//
//  GeomagneticField.swift
//  PhysicsCore — Magnetism
//
//  Earth's own field, so a compass carried away from the bar magnets
//  swings back to north instead of pointing at nothing.
//
//  IT DOES NOT NEED TO BE FAKED, which is the good news and the reason
//  this is worth having. A 6 A·m² bar magnet — this app's default —
//  produces about 356 µT at 15 cm, 77 µT at 25 cm, 19 µT at 40 cm and
//  5.6 µT at 60 cm. Earth's surface field is 25–65 µT. So the crossover
//  sits at roughly 30 cm, which is arm's length: hold the compass near a
//  magnet and the magnet wins outright, step back and Earth takes over.
//  The demonstration falls out of the real numbers with nothing tuned.
//
//  AND IT IS NOT HORIZONTAL. The one thing everybody knows about a
//  compass — that it lies flat and points north — is a fact about the
//  instrument, not about the field. Earth's field runs steeply INTO THE
//  GROUND across most of the inhabited world: about 65° below horizontal
//  at mid-northern latitudes, vertical at the magnetic poles, flat only
//  near the magnetic equator. A flat dial cannot show that, which is why
//  dip circles are separate instruments in a real lab and why almost
//  nobody has seen one. A spherical compass can.
//
//  The direction of north in the room is a CONVENTION and callers must
//  say so: visionOS exposes no true heading, so there is nothing to
//  measure it against. Everything else here is the real thing.
//

import Foundation
import simd

public enum GeomagneticField: Sendable {

    /// Earth's surface field strength, T.
    ///
    /// 50 µT is the round middle of the real 25–65 µT range and close to
    /// the value across most of North America and Europe.
    public static let referenceMagnitude = 50e-6

    /// Inclination — how far below horizontal the field points, degrees.
    ///
    /// About 65° across the continental United States and much of
    /// Europe. Positive means downward, which is the northern
    /// hemisphere; the field tips up out of the ground in the south.
    public static let referenceDipDegrees = 65.0

    /// Which way north lies in the lab, as a unit vector.
    ///
    /// **A convention, not a measurement.** Straight ahead as you enter
    /// (−z in immersive-space coordinates), because visionOS gives no
    /// true heading and there is nothing here to calibrate against. Any
    /// caller that shows this to a user has to say as much.
    public static let north = SIMD3<Double>(0, 0, -1)
    public static let up = SIMD3<Double>(0, 1, 0)

    /// The field vector, T — north and DOWN by the dip angle.
    public static func vector(magnitude: Double = referenceMagnitude,
                              dipDegrees: Double = referenceDipDegrees)
    -> SIMD3<Double> {
        let dip = dipDegrees * .pi / 180
        // Horizontal part along north, vertical part into the ground.
        return magnitude * (cos(dip) * north - sin(dip) * up)
    }

    /// The dip a geocentric dipole predicts at a given latitude:
    /// **tan I = 2 tan φ**.
    ///
    /// The classical result, and the reason dip is steep so much sooner
    /// than intuition suggests — at 45° of latitude the field already
    /// points 63° down. Earth's real field departs from this by a few
    /// degrees because it is not a perfect centred dipole, and a caller
    /// quoting it should say "about".
    public static func dipDegrees(atLatitude latitudeDegrees: Double) -> Double {
        let phi = latitudeDegrees * .pi / 180
        return atan(2 * tan(phi)) * 180 / .pi
    }

    /// How far a point is from where a magnet's own field would equal
    /// Earth's, on the magnet's axis — the distance at which a compass
    /// changes its mind.
    ///
    /// B_axis = (μ₀/4π)·2m/r³, so r = ∛(2·(μ₀/4π)·m / B).
    public static func crossoverDistance(momentMagnitude: Double,
                                         earth: Double = referenceMagnitude)
    -> Double {
        guard momentMagnitude > 0, earth > 0 else { return 0 }
        return cbrt(2 * 1e-7 * momentMagnitude / earth)
    }
}
