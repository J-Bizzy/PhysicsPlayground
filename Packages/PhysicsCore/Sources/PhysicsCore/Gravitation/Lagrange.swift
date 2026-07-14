//
//  Lagrange.swift
//  PhysicsCore — Gravitation
//
//  The five Lagrange points of a circular two-body system: the places
//  where a small third body can co-rotate with the pair. L4 and L5 are
//  exactly the equilateral-triangle points (and are stable when the mass
//  ratio is extreme enough, as for Earth–Moon). L1, L2, L3 lie on the
//  line through both bodies and have no closed form — they are roots of
//  a quintic — so this solves the rotating-frame force balance
//
//      a_grav,axial(x) + ω²·x = 0,   ω² = G(m₁+m₂)/R³
//
//  by bisection in the three brackets that each contain one root
//  (origin at the barycenter, x along the primary→secondary axis).
//
//  Everything is exact for circular orbits; for the mildly eccentric
//  real Moon these are the standard instantaneous points.
//

import Foundation
import simd

public enum Lagrange {
    public struct Points: Sendable {
        public var l1: SIMD3<Double>
        public var l2: SIMD3<Double>
        public var l3: SIMD3<Double>
        public var l4: SIMD3<Double>
        public var l5: SIMD3<Double>

        public var all: [(name: String, position: SIMD3<Double>)] {
            [("L1", l1), ("L2", l2), ("L3", l3), ("L4", l4), ("L5", l5)]
        }
    }

    /// The five points for the pair's current geometry, in world
    /// coordinates. L4 leads the secondary along its motion; L5 trails.
    public static func points(
        primary: CelestialBody,
        secondary: CelestialBody,
        gravitationalConstant G: Double = NBody.gravitationalConstant
    ) -> Points {
        let m1 = primary.mass
        let m2 = secondary.mass
        let offset = secondary.position - primary.position
        let separation = simd_length(offset)
        let axis = offset / separation

        // In-plane direction of the secondary's motion (defines "leading").
        let relativeVelocity = secondary.velocity - primary.velocity
        var motion = relativeVelocity - simd_dot(relativeVelocity, axis) * axis
        if simd_length(motion) < 1e-9 {
            // Degenerate (no motion): fall back to the y-up orbital plane.
            motion = simd_cross(SIMD3(0, 1, 0), axis)
        }
        motion = simd_normalize(motion)

        let barycenter = (m1 * primary.position + m2 * secondary.position) / (m1 + m2)
        let alpha = m2 / (m1 + m2)
        let omegaSquared = G * (m1 + m2) / (separation * separation * separation)
        let x1 = -alpha * separation          // primary's axial coordinate
        let x2 = (1 - alpha) * separation     // secondary's

        // Net axial acceleration in the rotating frame; roots are L1/L2/L3.
        func residual(_ x: Double) -> Double {
            let d1 = x - x1
            let d2 = x - x2
            return -G * m1 * d1 / abs(d1 * d1 * d1)
                 - G * m2 * d2 / abs(d2 * d2 * d2)
                 + omegaSquared * x
        }

        func bisect(_ lower: Double, _ upper: Double) -> Double {
            var lo = lower, hi = upper
            var fLo = residual(lo)
            for _ in 0..<200 {
                let mid = (lo + hi) / 2
                let fMid = residual(mid)
                if fLo * fMid <= 0 { hi = mid } else { lo = mid; fLo = fMid }
            }
            return (lo + hi) / 2
        }

        let margin = 1e-5 * separation
        let l1x = bisect(x1 + margin, x2 - margin)
        let l2x = bisect(x2 + margin, x2 + separation)
        let l3x = bisect(x1 - 2 * separation, x1 - margin)

        func onAxis(_ x: Double) -> SIMD3<Double> { barycenter + x * axis }

        // L4/L5: equilateral with both bodies, leading/trailing the secondary.
        let l4 = primary.position + separation * (0.5 * axis + (3.0.squareRoot() / 2) * motion)
        let l5 = primary.position + separation * (0.5 * axis - (3.0.squareRoot() / 2) * motion)

        return Points(l1: onAxis(l1x), l2: onAxis(l2x), l3: onAxis(l3x), l4: l4, l5: l5)
    }

    /// The velocity a small body needs at `point` to co-rotate with the
    /// pair — the rotating frame made concrete: v = v_bary + ω × (r − r_bary),
    /// with ω taken from the pair's actual instantaneous rotation.
    public static func corotatingVelocity(
        at point: SIMD3<Double>,
        primary: CelestialBody,
        secondary: CelestialBody
    ) -> SIMD3<Double> {
        let totalMass = primary.mass + secondary.mass
        let barycenter = (primary.mass * primary.position + secondary.mass * secondary.position) / totalMass
        let barycenterVelocity = (primary.mass * primary.velocity + secondary.mass * secondary.velocity) / totalMass

        let r = secondary.position - primary.position
        let v = secondary.velocity - primary.velocity
        let omega = simd_cross(r, v) / simd_length_squared(r)
        return barycenterVelocity + simd_cross(omega, point - barycenter)
    }

    /// Earth and Moon on their real mutual circular orbit about the
    /// barycenter — the clean starting state for a Lagrange laboratory.
    public static func earthMoonSystem(
        gravitationalConstant G: Double = NBody.gravitationalConstant
    ) -> (earth: CelestialBody, moon: CelestialBody) {
        let separation = 3.844e8
        var earth = CelestialBody.earth
        var moon = CelestialBody.moon
        let totalMass = earth.mass + moon.mass
        let relativeSpeed = (G * totalMass / separation).squareRoot()

        // Positions/velocities about the barycenter so total momentum is zero.
        earth.position = SIMD3(-separation * moon.mass / totalMass, 0, 0)
        moon.position = SIMD3(separation * earth.mass / totalMass, 0, 0)
        earth.velocity = SIMD3(0, 0, relativeSpeed * moon.mass / totalMass)
        moon.velocity = SIMD3(0, 0, -relativeSpeed * earth.mass / totalMass)
        return (earth, moon)
    }
}
