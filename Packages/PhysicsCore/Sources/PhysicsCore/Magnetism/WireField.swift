//
//  WireField.swift
//  PhysicsCore
//
//  The magnetic field of a FINITE straight current-carrying segment,
//  in closed form.
//
//  This is what a circuit's own field is made of: a bench of wires is a
//  chain of straight segments, and superposition does the rest. It is
//  deliberately not a numerical Biot–Savart integral — the integral has
//  an elementary antiderivative for a straight segment, so integrating it
//  numerically would be choosing to be approximately right about
//  something we can be exactly right about.
//
//  THE DERIVATION, because the sign conventions are where this goes
//  wrong and a reader should be able to check it rather than trust it.
//  For a segment from `a` to `b` carrying current I along L̂ = (b−a)/|b−a|,
//  and a field point p, write r₁ = p − a and r₂ = p − b. Parameterise the
//  wire by s ∈ [0, |L|]:
//
//      dl × r = L̂ ds × (r₁ − s L̂) = (L̂ × r₁) ds
//
//  because L̂ × L̂ = 0 — so the DIRECTION is constant along the segment
//  and comes straight out of the integral. With d the perpendicular
//  distance from p to the segment's line, |L̂ × r₁| = d, and writing
//  u = s − (r₁·L̂):
//
//      B = (μ₀I/4π)(L̂ × r₁) ∫ du / (d² + u²)^{3/2}
//        = (μ₀I/4πd) φ̂ [ u/√(d²+u²) ]
//        = (μ₀I/4πd) (cos θ₁ − cos θ₂) φ̂
//
//  with cos θᵢ = (rᵢ·L̂)/|rᵢ| and φ̂ = normalize(L̂ × r₁). The endpoints
//  fall out because √(d² + u²) at each limit is just |r₁| and |r₂|.
//
//  Two limits worth knowing, both pinned by tests: a very long segment
//  recovers the infinite-wire law μ₀I/2πd, and the field on the axis of a
//  polygon approximates a circular loop's μ₀I/2R as the polygon's side
//  count rises.
//

import Foundation
import simd

public enum WireField {

    /// The magnetic constant μ₀, T·m/A. Exact by the pre-2019 definition
    /// and still correct to ten significant figures after it.
    public static let mu0 = Constants.vacuumPermeability

    /// Field at `point` from a straight segment `a`→`b` carrying `current`
    /// amps, in tesla.
    ///
    /// Returns zero for a degenerate segment, and — deliberately — for a
    /// point ON the wire's axis, where the exact solution diverges. That
    /// is not a fudge: 1/d has no finite value at d = 0, a real wire has
    /// a radius that this idealisation does not, and a renderer sampling
    /// a grid will land exactly on a wire eventually. Returning zero
    /// there is a visible, checkable choice; returning `.infinity` would
    /// propagate a NaN into a transform and freeze the scene.
    public static func field(at point: SIMD3<Double>,
                             from a: SIMD3<Double>,
                             to b: SIMD3<Double>,
                             current: Double) -> SIMD3<Double> {
        let along = b - a
        let length = simd_length(along)
        guard length > 1e-12, current != 0 else { return .zero }
        let unit = along / length

        let r1 = point - a
        let r2 = point - b
        let n1 = simd_length(r1)
        let n2 = simd_length(r2)
        guard n1 > 1e-12, n2 > 1e-12 else { return .zero }

        // The azimuthal direction, and the perpendicular distance, from
        // the same cross product — |L̂ × r₁| IS d.
        let cross = simd_cross(unit, r1)
        let d = simd_length(cross)
        guard d > 1e-9 else { return .zero }   // on the axis: see above
        let phi = cross / d

        let cosTheta1 = simd_dot(r1, unit) / n1
        let cosTheta2 = simd_dot(r2, unit) / n2
        return phi * (mu0 * current / (4 * .pi * d)) * (cosTheta1 - cosTheta2)
    }

    /// One polyline carrying one current — a wire, as a renderer has it.
    public struct Segment: Sendable, Equatable {
        public var a: SIMD3<Double>
        public var b: SIMD3<Double>
        /// Amps, signed: the sign is the direction of flow along a→b.
        public var current: Double

        public init(a: SIMD3<Double>, b: SIMD3<Double>, current: Double) {
            self.a = a
            self.b = b
            self.current = current
        }
    }

    /// Superposition over a whole bench. Maxwell's equations are linear
    /// in the sources, so this really is just a sum.
    public static func field(at point: SIMD3<Double>,
                             segments: [Segment]) -> SIMD3<Double> {
        var total = SIMD3<Double>.zero
        for segment in segments {
            total += field(at: point, from: segment.a, to: segment.b,
                           current: segment.current)
        }
        return total
    }

    /// The infinite straight wire, μ₀I/2πd — kept as a named function
    /// because it is the touchstone every reader already knows, and the
    /// thing `field(at:from:to:)` is checked against in the long-segment
    /// limit.
    public static func infiniteWireMagnitude(current: Double,
                                             distance: Double) -> Double {
        guard distance > 1e-12 else { return 0 }
        return mu0 * abs(current) / (2 * .pi * distance)
    }
}
