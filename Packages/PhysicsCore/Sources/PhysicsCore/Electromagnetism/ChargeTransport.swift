//
//  ChargeTransport.swift
//  PhysicsCore
//
//  The most counter-intuitive true fact in elementary circuits, and
//  the one no flat diagram has ever taught well: the electrons in a
//  wire crawl. In a millimetre-radius copper wire carrying an amp,
//  each conduction electron drifts at about 23 MICROMETRES per second
//  — slower than a growing fingernail, hours to travel a metre. Yet
//  the bulb lights the instant you close the switch, because what
//  travels is not the electrons but the FIELD that pushes them, at a
//  good fraction of light speed.
//
//  Thirteen orders of magnitude separate those two numbers. A student
//  who has watched dots march around a circuit diagram has been taught
//  the opposite of this.
//
//    v_drift = I / (n · A · e)
//
//  with n the free-electron number density (copper: one conduction
//  electron per atom, 8.5×10²⁸ per cubic metre), A the cross-section,
//  e the elementary charge.
//

import Foundation

public enum ChargeTransport {
    /// Coulombs.
    public static let elementaryCharge = Constants.elementaryCharge
    /// Free conduction electrons per cubic metre in copper — one per
    /// atom, from its density and molar mass.
    public static let copperElectronDensity = 8.5e28
    /// Metres per second.
    public static let speedOfLight = Constants.speedOfLight

    /// Drift speed of the charge carriers, m/s. The honest answer to
    /// "how fast do the electrons go".
    public static func driftSpeed(current: Double,
                                  wireRadius: Double,
                                  carrierDensity: Double = copperElectronDensity) -> Double {
        let area = Double.pi * wireRadius * wireRadius
        guard area > 0, carrierDensity > 0 else { return 0 }
        return abs(current) / (carrierDensity * area * elementaryCharge)
    }

    /// How fast the SIGNAL travels — the electromagnetic disturbance
    /// that tells the whole circuit to start conducting. Typically
    /// 50–99% of c depending on the geometry and dielectric; two
    /// thirds is the standard figure for ordinary wiring.
    public static func signalSpeed(velocityFactor: Double = 0.66) -> Double {
        speedOfLight * velocityFactor
    }

    /// Seconds to cross `length` at `speed`; .infinity when stopped.
    public static func traversalTime(length: Double, speed: Double) -> Double {
        guard speed > 0 else { return .infinity }
        return length / speed
    }

    /// How many times faster the signal is than the carriers. This
    /// number — around ten trillion for ordinary wiring — IS the
    /// lesson.
    public static func signalToDriftRatio(current: Double,
                                          wireRadius: Double,
                                          carrierDensity: Double = copperElectronDensity,
                                          velocityFactor: Double = 0.66) -> Double {
        let drift = driftSpeed(current: current, wireRadius: wireRadius,
                               carrierDensity: carrierDensity)
        guard drift > 0 else { return .infinity }
        return signalSpeed(velocityFactor: velocityFactor) / drift
    }
}
