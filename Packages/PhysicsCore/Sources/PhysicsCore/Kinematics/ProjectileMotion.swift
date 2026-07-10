//
//  ProjectileMotion.swift
//  PhysicsCore — Kinematics
//
//  Projectile flight under uniform gravity, with optional quadratic air
//  drag F = ½ρ·Cd·A·v² opposing the velocity — the physically correct
//  model at sports-ball speeds.
//
//  Two faces, deliberately kept together so they can check each other:
//    · closed-form drag-free formulas (range, apex, flight time) — the
//      textbook results, used for live stats and as test oracles;
//    · RK4 simulation from launch to landing — the only correct option
//      once drag (velocity-dependent!) is on.
//  With drag off the simulation must reproduce the formulas; the unit
//  tests hold it to that.
//
//  Conventions: launch point is the origin, +y is up, the ground is the
//  y = 0 plane, all units SI.
//

import Foundation
import simd

public enum ProjectileMotion {
    /// kg/m³ at sea level, 15 °C.
    public static let seaLevelAirDensity = 1.225

    /// The drag half of the model; nil everywhere means "in a vacuum".
    public struct Drag: Equatable, Sendable {
        public var projectile: Projectile
        public var airDensity: Double

        public init(projectile: Projectile, airDensity: Double = ProjectileMotion.seaLevelAirDensity) {
            self.projectile = projectile
            self.airDensity = airDensity
        }
    }

    // MARK: Closed forms (drag-free; angles in radians)

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

    // MARK: Acceleration

    /// a = (0, −g, 0) − (ρ·Cd·A / 2m)·|v|·v
    public static func acceleration(
        velocity: SIMD3<Double>,
        gravity: Double,
        drag: Drag?
    ) -> SIMD3<Double> {
        var a = SIMD3<Double>(0, -gravity, 0)
        if let drag {
            let speed = simd_length(velocity)
            if speed > 0 {
                let k = 0.5 * drag.airDensity * drag.projectile.dragCoefficient
                    * drag.projectile.crossSectionalArea / drag.projectile.mass
                a -= (k * speed) * velocity
            }
        }
        return a
    }

    /// Speed at which drag balances weight for a falling projectile:
    /// v_t = √(2mg / ρ·Cd·A).
    public static func terminalSpeed(projectile: Projectile, gravity: Double,
                                     airDensity: Double = seaLevelAirDensity) -> Double {
        (2 * projectile.mass * gravity
            / (airDensity * projectile.dragCoefficient * projectile.crossSectionalArea)).squareRoot()
    }

    // MARK: Simulation

    public struct Trajectory: Sendable {
        /// Sampled flight path from launch to (interpolated) landing.
        public var points: [SIMD3<Double>]
        /// Seconds aloft. If the projectile never landed within
        /// `maxDuration`, this is the simulated span and `landed` is false.
        public var flightTime: Double
        /// Horizontal distance from launch to landing (or to the last
        /// simulated point).
        public var range: Double
        /// Greatest height above the launch point.
        public var apexHeight: Double
        public var landed: Bool
    }

    /// Integrates a launch from the origin until it crosses back through
    /// y = 0 (the landing point is linearly interpolated inside the final
    /// step, so range/flightTime don't quantize to the step size).
    public static func simulate(
        launchVelocity: SIMD3<Double>,
        gravity: Double,
        drag: Drag? = nil,
        timeStep: Double = 1.0 / 240.0,
        maxDuration: Double = 30,
        pointStride: Int = 4
    ) -> Trajectory {
        var state = ParticleDynamics.State(position: .zero, velocity: launchVelocity)
        var points = [state.position]
        var apex = 0.0
        var time = 0.0
        var step = 0

        while time < maxDuration {
            let previous = state
            state = Integrators.rk4Step(state, dt: timeStep) { _, v in
                acceleration(velocity: v, gravity: gravity, drag: drag)
            }
            time += timeStep
            step += 1
            apex = max(apex, state.position.y)

            // Crossed the ground going down: interpolate the landing.
            if state.position.y < 0, state.velocity.y < 0 {
                let dip = previous.position.y - state.position.y
                let fraction = dip > 0 ? previous.position.y / dip : 0
                let landing = previous.position + fraction * (state.position - previous.position)
                points.append(landing)
                return Trajectory(
                    points: points,
                    flightTime: time - timeStep + fraction * timeStep,
                    range: simd_length(SIMD2(landing.x, landing.z)),
                    apexHeight: apex,
                    landed: true
                )
            }

            if step % pointStride == 0 {
                points.append(state.position)
            }
        }

        // Ran out the clock (e.g. lunar gravity with a hard throw).
        points.append(state.position)
        return Trajectory(
            points: points,
            flightTime: time,
            range: simd_length(SIMD2(state.position.x, state.position.z)),
            apexHeight: apex,
            landed: false
        )
    }
}
