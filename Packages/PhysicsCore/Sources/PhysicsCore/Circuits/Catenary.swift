//
//  Catenary.swift
//  Exact hanging-cable shape y = a·cosh(x/a) (SI, meters); parameter solved by Newton on 2·sinh(a·L/2)/a = S; near-vertical spans fall to the chord.
//

import Foundation
import simd

public enum Catenary {

    /// Points along a cable of arc length `chord + slack` hung from `from` to `to` inclusive;
    /// slack is EXTRA length beyond the chord — zero gives the chord exactly (a snapped joint).
    public static func points(from: SIMD3<Double>, to: SIMD3<Double>,
                              slack: Double, samples: Int = 12) -> [SIMD3<Double>] {
        let count = max(samples, 2)
        let delta = to - from
        let chord = simd_length(delta)
        guard chord > 1e-6, slack > 1e-6 else { return straight(from: from, to: to, count: count) }

        // Horizontal-frame test is RELATIVE, not absolute: below a fifth of the chord the span is a
        // drop and stays straight — Newton from the small-sag guess diverges there (1e23 m mid-span drops).
        let horizontal = SIMD3(delta.x, 0, delta.z)
        let horizontalLength = simd_length(horizontal)
        guard horizontalLength > 0.2 * chord else {
            return straight(from: from, to: to, count: count)
        }
        let alongChord = horizontal / horizontalLength
        let rise = delta.y

        let arc = chord + slack
        guard let a = solveParameter(span: horizontalLength, arc: arc, rise: rise) else {
            return straight(from: from, to: to, count: count)
        }

        // Symmetric catenary across the horizontal span, rise added linearly — exact for a level
        // span, visually indistinguishable for shallow bench rises.
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

    /// Arc length of that same curve (meters) — what a charge actually travels along.
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

    /// Newton on `2·sinh(a·L/2)/a = S′` (S′ = arc net of the rise). nil when the arc is not longer
    /// than the span — no catenary is shorter than its chord — and the caller draws the straight line.
    private static func solveParameter(span: Double, arc: Double, rise: Double) -> Double? {
        let target = sqrt(max(arc * arc - rise * rise, 0))
        guard target > span * (1 + 1e-9) else { return nil }

        // Opening guess: small-sag expansion S ≈ L·(1 + (a·L)²/24), inverted.
        let ratio = target / span
        var a = sqrt(24 * (ratio - 1)) / span
        guard a.isFinite, a > 0 else { return nil }

        for _ in 0..<8 {
            let half = a * span / 2
            let value = 2 * sinh(half) / a - target
            // d/da [2·sinh(aL/2)/a] = L·cosh(aL/2)/a − 2·sinh(aL/2)/a²
            let derivative = span * cosh(half) / a - 2 * sinh(half) / (a * a)
            guard abs(derivative) > 1e-12 else { break }
            let next = a - value / derivative
            guard next.isFinite, next > 0 else { break }
            a = next
        }

        // Residual is CHECKED: an unconverged `a` draws a kilometres-deep curve, so nil → chord
        // (wrong by centimetres) is the honest fallback.
        guard a.isFinite, a > 0 else { return nil }
        let achieved = 2 * sinh(a * span / 2) / a
        guard achieved.isFinite,
              abs(achieved - target) <= max(target * 1e-3, 1e-9) else { return nil }
        return a
    }
}
