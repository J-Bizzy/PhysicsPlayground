//
//  Catenary.swift
//  PhysicsCore — Circuits
//
//  The shape a flexible cable takes when it hangs under its own
//  weight: y = a·cosh(x/a), the catenary. Not a parabola, and not a
//  quadratic Bézier that looks about right — this module's whole
//  argument is that its pictures are physics, and a hanging cable is
//  one of the few things in a room that has a closed-form shape a
//  student can check.
//
//  THE PARAMETER IS SOLVED, NOT CHOSEN. Given a span L and a total arc
//  length S > L, the shape parameter `a` is the root of
//
//      2·sinh(a·L/2)/a = S            (with a = 1/catenary parameter)
//
//  which has no elementary inverse, so it comes out of a few Newton
//  steps. Five is plenty here: the function is smooth and convex in
//  the region of interest and the initial guess below is close.
//
//  The curve is computed in a 2-D frame — horizontal distance along
//  the chord, and vertical — then lifted back into the room, so an
//  arbitrarily oriented span sags DOWNWARD rather than sideways.
//  A near-vertical span has no meaningful horizontal frame, and
//  degrades to the straight chord rather than inventing one.
//

import Foundation
import simd

public enum Catenary {

    /// Points along a cable of arc length `chord + slack` hung between
    /// two points, from `from` to `to` inclusive.
    ///
    /// `slack` is the EXTRA length beyond the straight-line distance —
    /// zero gives the chord exactly, which is what a snapped joint
    /// wants and what keeps this from being a special case at the
    /// call site.
    public static func points(from: SIMD3<Double>, to: SIMD3<Double>,
                              slack: Double, samples: Int = 12) -> [SIMD3<Double>] {
        let count = max(samples, 2)
        let delta = to - from
        let chord = simd_length(delta)
        // Nothing to hang, or nothing to hang it on.
        guard chord > 1e-6, slack > 1e-6 else { return straight(from: from, to: to, count: count) }

        // The horizontal frame. A vertical span has none — every
        // direction is equally "sideways" — so it stays straight.
        let horizontal = SIMD3(delta.x, 0, delta.z)
        let horizontalLength = simd_length(horizontal)
        guard horizontalLength > 1e-4 else { return straight(from: from, to: to, count: count) }
        let alongChord = horizontal / horizontalLength
        let rise = delta.y

        let arc = chord + slack
        guard let a = solveParameter(span: horizontalLength, arc: arc, rise: rise) else {
            return straight(from: from, to: to, count: count)
        }

        // Hang a symmetric catenary across the horizontal span and add
        // the endpoints' height difference linearly. This is exact for
        // a level span and a very good approximation for the shallow
        // rises a bench produces; a fully asymmetric solve would buy
        // nothing an eye could see at these scales.
        let halfSpan = horizontalLength / 2
        let sagAtEnd = cosh(a * halfSpan)
        var result: [SIMD3<Double>] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let t = Double(index) / Double(count - 1)
            let x = (t - 0.5) * horizontalLength
            // Measured DOWN from the chord: zero at both ends.
            let drop = (sagAtEnd - cosh(a * x)) / a
            result.append(from
                + alongChord * (t * horizontalLength)
                + SIMD3(0, rise * t - drop, 0))
        }
        return result
    }

    /// The arc length of that same curve — what a charge actually
    /// travels along, as opposed to the distance between the ends.
    public static func arcLength(from: SIMD3<Double>, to: SIMD3<Double>,
                                 slack: Double, samples: Int = 12) -> Double {
        let curve = points(from: from, to: to, slack: slack, samples: samples)
        var total = 0.0
        for index in 1..<curve.count {
            total += simd_distance(curve[index - 1], curve[index])
        }
        return total
    }

    // MARK: -

    private static func straight(from: SIMD3<Double>, to: SIMD3<Double>,
                                 count: Int) -> [SIMD3<Double>] {
        (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            return from + (to - from) * t
        }
    }

    /// Newton on `2·sinh(a·L/2)/a = S′`, where S′ is the arc length
    /// the horizontal span has to carry.
    ///
    /// Returns nil when the requested arc is not longer than the span
    /// it must cross — there is no catenary shorter than its own
    /// chord, and the caller draws a straight line.
    private static func solveParameter(span: Double, arc: Double, rise: Double) -> Double? {
        // The horizontal span carries the arc net of the rise it also
        // has to climb.
        let target = sqrt(max(arc * arc - rise * rise, 0))
        guard target > span * (1 + 1e-9) else { return nil }

        // A good opening guess from the small-sag expansion
        // S ≈ L·(1 + (a·L)²/24), inverted.
        let ratio = target / span
        var a = sqrt(24 * (ratio - 1)) / span
        guard a.isFinite, a > 0 else { return nil }

        for _ in 0..<5 {
            let half = a * span / 2
            let value = 2 * sinh(half) / a - target
            // d/da [2·sinh(aL/2)/a] = L·cosh(aL/2)/a − 2·sinh(aL/2)/a²
            let derivative = span * cosh(half) / a - 2 * sinh(half) / (a * a)
            guard abs(derivative) > 1e-12 else { break }
            let next = a - value / derivative
            guard next.isFinite, next > 0 else { break }
            a = next
        }
        return a.isFinite && a > 0 ? a : nil
    }
}
