//  GeomagneticField.swift — Earth's field, so a distant compass points north. Real numbers,
//  nothing tuned: a 6 A·m² bar beats Earth's 25–65 µT inside ~30 cm, Earth wins beyond.
//  The field is not horizontal — it dips ~65° into the ground at mid-northern latitudes.
//  Only north's direction in the room is a convention (visionOS exposes no true heading).

import Foundation
import simd

public enum GeomagneticField: Sendable {

    /// Earth's surface field strength, T: 50 µT, the round middle of the real 25–65 µT range.
    public static let referenceMagnitude = 50e-6

    /// Inclination, degrees below horizontal (positive = downward, northern hemisphere);
    /// ~65° across the continental US and much of Europe.
    public static let referenceDipDegrees = 65.0

    /// North in the lab — **a convention, not a measurement** (−z, straight ahead as you
    /// enter): visionOS gives no true heading. Callers showing it to a user must say so.
    public static let north = SIMD3<Double>(0, 0, -1)
    public static let up = SIMD3<Double>(0, 1, 0)

    /// The field vector, T — north and down by the dip angle.
    public static func vector(magnitude: Double = referenceMagnitude,
                              dipDegrees: Double = referenceDipDegrees)
    -> SIMD3<Double> {
        let dip = dipDegrees * .pi / 180
        return magnitude * (cos(dip) * north - sin(dip) * up)
    }

    /// Geocentric-dipole dip at a latitude: **tan I = 2 tan φ**. Earth's real field departs
    /// by a few degrees (not a perfect centred dipole) — a caller quoting it should say "about".
    public static func dipDegrees(atLatitude latitudeDegrees: Double) -> Double {
        let phi = latitudeDegrees * .pi / 180
        return atan(2 * tan(phi)) * 180 / .pi
    }

    /// On-axis distance at which a magnet's field equals Earth's — where a compass changes
    /// its mind. B_axis = (μ₀/4π)·2m/r³, so r = ∛(2·(μ₀/4π)·m / B).
    public static func crossoverDistance(momentMagnitude: Double,
                                         earth: Double = referenceMagnitude)
    -> Double {
        guard momentMagnitude > 0, earth > 0 else { return 0 }
        return cbrt(2 * 1e-7 * momentMagnitude / earth)
    }
}
