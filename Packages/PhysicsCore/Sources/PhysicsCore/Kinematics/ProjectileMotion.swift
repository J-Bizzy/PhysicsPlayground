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

    /// Integrates a launch from `start` until the flight ends: at the
    /// first ground contact when `maxBounces` is 0, otherwise bouncing
    /// with `restitution` until the bounce budget or the energy runs out.
    /// Ground crossings are linearly interpolated inside the step, so
    /// range and flight time don't quantize to the step size.
    ///
    /// `radius` IS NOT OPTIONAL DECORATION — pass the ball's. This
    /// function draws Projectiles' predicted arc, and "predicted arc,
    /// bounces included" is that module's central claim, so any way in
    /// which it disagrees with the live flight is a white line promising
    /// something the ball then fails to do. It disagreed in three ways
    /// until 2026-08-07, all of them from treating the projectile as a
    /// point:
    ///
    /// · it struck walls with `radius: 0`, so the arc cornered at the
    ///   wall plane while a basketball (r = 0.121 m) turns 12 cm short
    ///   of it;
    /// · it bounced the ball's CENTRE off y = 0 rather than its surface,
    ///   so every floor contact was drawn 12 cm too low;
    /// · it discarded `hit.t`, so the remainder of the frame after a
    ///   bounce was never spent — the exact defect `RoomWalls.Hit.t`'s
    ///   own doc says "deadened every fast bounce", fixed in the live
    ///   model on 2026-08-06 and not here.
    ///
    /// Each error compounds into the next segment, so by the second
    /// bounce the arc and the ball are visibly different curves.
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

            // Touched the ground going down — the ball's SURFACE, so a
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
