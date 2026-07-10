//
//  StreamlineTracer.swift
//  Physics Playground — Core kernel
//
//  Domain-agnostic streamline integration: traces curves that follow the
//  direction of any vector field F(r), by 4th-order Runge–Kutta on the
//  *normalized* field, dr/ds = F(r)/|F(r)|. Normalizing gives unit-speed
//  (arc-length) parametrization: every step advances ~stepSize meters along
//  the curve regardless of the field's magnitude, so integration neither
//  blows up near singularities nor crawls in weak regions.
//
//  Electric field lines, magnetic field lines, and flow visualizations are
//  all streamlines — each module supplies its own field closure, seeding
//  policy, and termination sites.
//

import Foundation
import simd

nonisolated enum StreamlineTracer {
    nonisolated struct Config {
        /// Arc length advanced per RK4 step, in meters.
        var stepSize = 0.008
        var maxSteps = 320
        /// A line ends when it comes this close to any of `stopCenters`
        /// (e.g. the charges field lines terminate on).
        var stopCenters: [SIMD3<Double>] = []
        var stopRadius = 0.04
        /// Lines also end when they wander this far from `boundsCenter`
        /// ("off to infinity" as far as the room is concerned).
        var boundsCenter: SIMD3<Double> = .zero
        var boundsRadius = 0.85
    }

    /// Integrates a single streamline from `seed`, following sign·F/|F|.
    /// Returns points spaced ~stepSize apart.
    static func streamline(
        from seed: SIMD3<Double>,
        sign: Double,
        field: (SIMD3<Double>) -> SIMD3<Double>,
        config: Config
    ) -> [SIMD3<Double>] {
        // Unit tangent of the streamline at a point; nil where the field
        // vanishes (equilibrium points, or a guarded singularity).
        func tangent(at point: SIMD3<Double>) -> SIMD3<Double>? {
            let value = field(point)
            let magnitude = simd_length(value)
            guard magnitude > 1e-12 else { return nil }
            return (sign / magnitude) * value
        }

        var points = [seed]
        var p = seed
        let h = config.stepSize
        let halfStep = h / 2

        for _ in 0..<config.maxSteps {
            // RK4: sample the direction at four staged points and blend.
            guard let k1 = tangent(at: p) else { break }
            guard let k2 = tangent(at: p + halfStep * k1) else { break }
            guard let k3 = tangent(at: p + halfStep * k2) else { break }
            guard let k4 = tangent(at: p + h * k3) else { break }
            var blended = k1 + k4
            blended += 2 * k2
            blended += 2 * k3
            p += (h / 6) * blended
            points.append(p)

            // Landed on a termination site or left the room.
            if config.stopCenters.contains(where: { simd_distance($0, p) < config.stopRadius }) {
                break
            }
            if simd_distance(p, config.boundsCenter) > config.boundsRadius {
                break
            }
        }
        return points
    }

    /// `count` directions spread nearly uniformly over a unit sphere
    /// (Fibonacci lattice — the standard trick for even spherical coverage).
    /// The usual seeding pattern for streamlines radiating from a point.
    static func fibonacciSphere(count: Int) -> [SIMD3<Double>] {
        let goldenAngle = Double.pi * (3 - 5.0.squareRoot())
        return (0..<count).map { i in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(count)
            let ringRadius = (1 - y * y).squareRoot()
            let phi = Double(i) * goldenAngle
            return SIMD3(ringRadius * cos(phi), y, ringRadius * sin(phi))
        }
    }
}
