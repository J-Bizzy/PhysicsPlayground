//
//  ProjectileMotion.swift
//  PhysicsCore — Kinematics
//
//  Projectile flight under uniform gravity, with optional quadratic air
//  drag F = ½ρ·Cd·A·|v−w|² opposing the air-relative velocity (w is the
//  wind) — the physically correct model at sports-ball speeds.
//
//  Two faces, deliberately kept together so they can check each other:
//    · closed-form drag-free formulas (range, apex, flight time) — the
//      textbook results, used for live stats and as test oracles;
//    · RK4 simulation from any launch point to landing, with optional
//      floor bounces — the only correct option once drag (velocity-
//      dependent!) is on.
//  With drag off and a ground-level launch the simulation must reproduce
//  the formulas; the unit tests hold it to that.
//
//  Conventions: +y is up, the ground is the y = 0 plane, all units SI.
//  Bounces reflect the vertical velocity scaled by the projectile's
//  restitution and keep `tangentialRetention` of the horizontal speed —
//  a simplification (no spin, no surface model) that still reproduces the
//  familiar e²-per-bounce decay of rebound heights.
//

import Foundation
import simd

public enum ProjectileMotion {
    /// kg/m³ at sea level, 15 °C.
    public static let seaLevelAirDensity = 1.225

    /// Horizontal speed kept through a bounce (rolling/skidding losses).
    public static let tangentialRetention = 0.8

    /// A bounce weaker than this vertical speed (m/s) is a landing.
    public static let restSpeed = 0.3

    /// The drag half of the model; nil everywhere means "in a vacuum".
    public struct Drag: Equatable, Sendable {
        public var projectile: Projectile
        public var airDensity: Double
        /// Wind velocity in m/s; drag opposes motion *through the air*.
        public var wind: SIMD3<Double>

        public init(projectile: Projectile,
                    airDensity: Double = ProjectileMotion.seaLevelAirDensity,
                    wind: SIMD3<Double> = .zero) {
            self.projectile = projectile
            self.airDensity = airDensity
            self.wind = wind
        }
    }

    // MARK: Closed forms (drag-free, launched from ground level; radians)

    /// R = v²·sin 2θ / g — horizontal distance back to launch height.
    public static func dragFreeRange(speed: Double, angle: Double, gravity: Double) -> Double {
        speed * speed * sin(2 * angle) / gravity
    }

    /// H = (v·sin θ)² / 2g — height gained above the launch point.
    public static func dragFreeApex(speed: Double, angle: Double, gravity: Double) -> Double {
        let vy = speed * sin(angle)
        return vy * vy / (2 * gravity)
    }

    /// T = 2·v·sin θ / g — time to return to launch height.
    public static func dragFreeFlightTime(speed: Double, angle: Double, gravity: Double) -> Double {
        2 * speed * sin(angle) / gravity
    }

    // MARK: Acceleration & bounce

    /// a = (0, −g, 0) − (ρ·Cd·A / 2m)·|v−w|·(v−w)
    public static func acceleration(
        velocity: SIMD3<Double>,
        gravity: Double,
        drag: Drag?
    ) -> SIMD3<Double> {
        var a = SIMD3<Double>(0, -gravity, 0)
        if let drag {
            let relative = velocity - drag.wind
            let speed = simd_length(relative)
            if speed > 0 {
                let k = 0.5 * drag.airDensity * drag.projectile.dragCoefficient
                    * drag.projectile.crossSectionalArea / drag.projectile.mass
                a -= (k * speed) * relative
            }
        }
        return a
    }

    /// Velocity after a floor bounce: vertical reflected and scaled by the
    /// restitution, horizontal scaled by `tangentialRetention`.
    public static func bounce(velocity: SIMD3<Double>, restitution: Double) -> SIMD3<Double> {
        SIMD3(
            velocity.x * tangentialRetention,
            -velocity.y * restitution,
            velocity.z * tangentialRetention
        )
    }

    /// Speed at which drag balances weight for a falling projectile:
    /// v_t = √(2mg / ρ·Cd·A).
    public static func terminalSpeed(projectile: Projectile, gravity: Double,
                                     airDensity: Double = seaLevelAirDensity) -> Double {
        guard gravity > 0 else { return 0 }
        return (2 * projectile.mass * gravity
            / (airDensity * projectile.dragCoefficient * projectile.crossSectionalArea)).squareRoot()
    }

    // MARK: Simulation

    public struct Trajectory: Sendable {
        /// Sampled path from launch through any bounces.
        public var points: [SIMD3<Double>]
        /// Seconds to *first* ground contact (the textbook flight time).
        /// If the projectile never landed within `maxDuration`, this is the
        /// simulated span and `landed` is false.
        public var flightTime: Double
        /// Horizontal distance from launch to first ground contact.
        public var range: Double
        /// Greatest height above the ground during the whole path.
        public var apexHeight: Double
        public var landed: Bool
        /// First ground contact, if any.
        public var landingPoint: SIMD3<Double>?
        /// Ground contacts that turned into bounces (excludes the final rest).
        public var bounceCount: Int
    }

    /// Integrates a launch from `start` until the flight ends: at the first
    /// ground contact when `maxBounces` is 0, otherwise bouncing with
    /// `restitution` until the bounce budget or the energy runs out. Ground
    /// crossings are interpolated inside the step. Pass the ball's `radius`:
    /// this draws Projectiles' predicted arc, and a point projectile corners
    /// short of walls, bounces its centre off the floor and drops the rest
    /// of the frame after a bounce, so the arc and the ball diverge.
    public static func simulate(
        from start: SIMD3<Double> = .zero,
        launchVelocity: SIMD3<Double>,
        gravity: Double,
        drag: Drag? = nil,
        restitution: Double = 0,
        maxBounces: Int = 0,
        walls: [RoomWalls.Wall] = [],
        radius: Double = 0,
        timeStep: Double = 1.0 / 240.0,
        maxDuration: Double = 30,
        pointStride: Int = 4
    ) -> Trajectory {
        var state = ParticleDynamics.State(position: start, velocity: launchVelocity)
        var points = [state.position]
        var apex = max(start.y, 0)
        var time = 0.0
        var step = 0
        var firstContact: (point: SIMD3<Double>, time: Double)?
        var bounces = 0

        while time < maxDuration {
            let previous = state
            state = Integrators.rk4Step(state, dt: timeStep) { _, v in
                acceleration(velocity: v, gravity: gravity, drag: drag)
            }
            time += timeStep
            step += 1
            apex = max(apex, state.position.y)

            // Struck a wall: reflect, and cut a crisp corner into the
            // polyline. Wall hits share the bounce budget so a ricochet
            // between close walls can't run forever.
            if !walls.isEmpty, bounces < maxBounces,
               let hit = RoomWalls.strike(
                   previous: previous.position, current: state.position,
                   velocity: state.velocity, radius: radius,
                   restitution: restitution, walls: walls) {
                bounces += 1
                points.append(hit.position)
                // Spend what is left of the step, as the live model
                // does. Dropping it leaves the ball at the contact point
                // for a whole frame, which reads as the bounce sticking.
                let remaining = timeStep * (1 - hit.t)
                state = ParticleDynamics.State(
                    position: hit.position + hit.velocity * remaining,
                    velocity: hit.velocity)
            }

            // Touched the ground going down — the ball's surface, so a
            // basketball rests on the floor rather than half through it.
            if state.position.y < radius, state.velocity.y < 0 {
                let dip = previous.position.y - state.position.y
                let fraction = dip > 0 ? (previous.position.y - radius) / dip : 0
                let clamped = min(max(fraction, 0), 1)
                let contact = previous.position
                    + clamped * (state.position - previous.position)
                let contactTime = time - timeStep + clamped * timeStep
                points.append(SIMD3(contact.x, radius, contact.z))
                if firstContact == nil {
                    firstContact = (contact, contactTime)
                }

                let reboundSpeed = -state.velocity.y * restitution
                if bounces < maxBounces, reboundSpeed > restSpeed {
                    bounces += 1
                    state = ParticleDynamics.State(
                        position: SIMD3(contact.x, radius, contact.z),
                        velocity: bounce(velocity: state.velocity, restitution: restitution)
                    )
                    continue
                }
                break
            }

            if step % pointStride == 0 {
                points.append(state.position)
            }
        }

        if let firstContact {
            return Trajectory(
                points: points,
                flightTime: firstContact.time,
                range: simd_length(SIMD2(firstContact.point.x - start.x,
                                         firstContact.point.z - start.z)),
                apexHeight: apex,
                landed: true,
                landingPoint: SIMD3(firstContact.point.x, 0, firstContact.point.z),
                bounceCount: bounces
            )
        }

        // Ran out the clock (zero-g, or lunar gravity with a hard throw).
        points.append(state.position)
        return Trajectory(
            points: points,
            flightTime: time,
            range: simd_length(SIMD2(state.position.x - start.x, state.position.z - start.z)),
            apexHeight: apex,
            landed: false,
            landingPoint: nil,
            bounceCount: bounces
        )
    }
}

// MARK: - Aiming at a point

/// The projectile problem solved the other way round: given where the
/// hoop is, which launch angles reach it? Two in a vacuum — the low
/// arc and the high arc — and the room draws both (Projectiles' "Aim
/// here").
public extension ProjectileMotion {
    /// Both drag-free launch angles, in radians above horizontal, that
    /// carry a projectile launched at `speed` through a point `x` metres
    /// away horizontally and `y` metres above the muzzle (negative for
    /// below). `low <= high`. Nil when the point is out of range at that
    /// speed — the discriminant of tan θ's quadratic is negative.
    ///
    ///     tan θ = (v² ± √(v⁴ − g(g·x² + 2·y·v²))) / (g·x)
    ///
    /// Two honest edge cases: in zero gravity the flight is a straight
    /// line and both angles are `atan2(y, x)`; straight above or below
    /// (x ≈ 0) the shot is vertical, reachable downward always and upward
    /// only while v² ≥ 2gy.
    static func launchAngles(toReachHorizontal x: Double, vertical y: Double,
                             speed v: Double, gravity g: Double)
    -> (low: Double, high: Double)? {
        guard v > 0, x >= 0 else { return nil }
        if g <= 1e-12 {
            let straight = atan2(y, x)
            return (straight, straight)
        }
        if x < 1e-9 {
            if y <= 0 { return (-.pi / 2, -.pi / 2) }
            return v * v >= 2 * g * y ? (.pi / 2, .pi / 2) : nil
        }
        let discriminant = v * v * v * v - g * (g * x * x + 2 * y * v * v)
        guard discriminant >= 0 else { return nil }
        let root = discriminant.squareRoot()
        let low = atan((v * v - root) / (g * x))
        let high = atan((v * v + root) / (g * x))
        return (min(low, high), max(low, high))
    }

    /// The horizontal distance, from the launch point, at which the
    /// launched shot passes through the target's range — i.e. `x` — and
    /// the height it has there, read off a simulated arc by linear
    /// interpolation between samples. Nil when the arc never gets that
    /// far (it fell short, or landed first).
    static func heightWhenReaching(horizontal x: Double,
                                   along trajectory: Trajectory,
                                   from start: SIMD3<Double>) -> Double? {
        var previous: SIMD3<Double>?
        for point in trajectory.points {
            let travelled = simd_length(SIMD2(point.x - start.x, point.z - start.z))
            if let p = previous, travelled >= x {
                let before = simd_length(SIMD2(p.x - start.x, p.z - start.z))
                let span = travelled - before
                let fraction = span > 1e-12 ? (x - before) / span : 0
                return p.y + fraction * (point.y - p.y)
            }
            previous = point
        }
        return nil
    }

    /// The same question with air in the way: no closed form, so the
    /// arc is shot numerically. Angles are scanned every 5° from −85° to
    /// 85° for sign changes of (height at the target's range − target
    /// height) and each bracket is bisected on the angle until it is
    /// narrower than `tolerance` (0.006° by default — the miss at the
    /// target is then well under a millimetre). Up to two roots come
    /// back, low first; a single root is returned as both. Nil when no
    /// angle reaches the point. The readout that shows these should say
    /// "with drag": they are found, not derived.
    ///
    /// The shot is simulated from a kilometre up so the floor in
    /// `simulate` (y = radius) cannot end an arc that is on its way to
    /// a target below the muzzle; heights come back relative to launch.
    static func launchAnglesWithDrag(toReachHorizontal x: Double, vertical y: Double,
                                     speed v: Double, gravity g: Double,
                                     drag: Drag, radius: Double,
                                     tolerance: Double = 1e-4)
    -> (low: Double, high: Double)? {
        guard v > 0, x > 1e-6 else { return nil }
        let start = SIMD3<Double>(0, 1000, 0)
        func miss(_ angle: Double) -> Double? {
            let velocity = SIMD3(v * cos(angle), v * sin(angle), 0)
            let arc = simulate(from: start, launchVelocity: velocity,
                               gravity: g, drag: drag, maxBounces: 0,
                               radius: radius, timeStep: 1.0 / 240.0,
                               maxDuration: 30, pointStride: 1)
            guard let height = heightWhenReaching(horizontal: x, along: arc,
                                                  from: start) else { return nil }
            return height - start.y - y
        }
        let step = 5.0 * .pi / 180
        var angle = -85.0 * .pi / 180
        var previousAngle = angle
        var previousMiss = miss(angle)
        var roots: [Double] = []
        while angle < 85.0 * .pi / 180 - 1e-9 {
            angle += step
            let current = miss(angle)
            if let a = previousMiss, let b = current, (a <= 0) != (b <= 0) {
                var lo = previousAngle, hi = angle
                var loMiss = a
                var iterations = 0
                while hi - lo > tolerance, iterations < 60 {
                    iterations += 1
                    let mid = (lo + hi) / 2
                    guard let m = miss(mid) else { break }
                    if (m <= 0) == (loMiss <= 0) { lo = mid; loMiss = m } else { hi = mid }
                }
                roots.append((lo + hi) / 2)
            }
            previousAngle = angle
            previousMiss = current
        }
        guard let first = roots.first, let last = roots.last else { return nil }
        return (first, last)
    }
}
