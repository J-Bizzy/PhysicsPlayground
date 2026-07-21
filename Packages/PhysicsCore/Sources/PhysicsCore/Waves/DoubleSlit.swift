//
//  DoubleSlit.swift
//  PhysicsCore — Waves
//
//  The double-slit screen pattern, exactly: two-slit interference
//  cos²(π·d·sinθ/λ) under the single-slit envelope sinc²(π·w·sinθ/λ).
//  The studio's floating fringe strip is painted with this; the
//  WALKABLE field between barrier and screen comes from WaveField
//  with the slits as Huygens sources — same physics, two views.
//

import Foundation

public enum DoubleSlit {
    /// Normalized intensity (0…1) at height `y` on a screen a distance
    /// `distance` past the barrier. Exact angles — no small-angle
    /// shortcut — so the strip stays honest even up close.
    public static func intensity(
        y: Double, distance: Double,
        separation: Double, slitWidth: Double, wavelength: Double
    ) -> Double {
        let sinTheta = y / (y * y + distance * distance).squareRoot()
        let twoSlit = cos(.pi * separation * sinTheta / wavelength)
        let envelopeArgument = .pi * slitWidth * sinTheta / wavelength
        let envelope = abs(envelopeArgument) < 1e-12
            ? 1.0
            : sin(envelopeArgument) / envelopeArgument
        return twoSlit * twoSlit * envelope * envelope
    }

    /// Small-angle fringe spacing Δy = λL/d — the number every intro
    /// lab measures.
    public static func fringeSpacing(
        distance: Double, separation: Double, wavelength: Double
    ) -> Double {
        wavelength * distance / separation
    }

    /// Screen heights of the first `count` bright fringes (m = 0, ±1, …),
    /// exact: y = L·tan(asin(mλ/d)). Orders past 90° don't exist and
    /// are skipped.
    public static func brightFringes(
        distance: Double, separation: Double, wavelength: Double, count: Int
    ) -> [Double] {
        var fringes: [Double] = [0]
        var order = 1
        while fringes.count < count {
            let sinTheta = Double(order) * wavelength / separation
            guard sinTheta < 1 else { break }
            let y = distance * tan(asin(sinTheta))
            fringes.append(y)
            fringes.append(-y)
            order += 1
        }
        return fringes.sorted()
    }
}
