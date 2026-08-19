//
//  ChargeTransport.swift
//  Electron drift vs signal speed in a wire: v_drift = I/(n·A·e) (SI; copper n = 8.5×10²⁸ m⁻³), signal at a fraction of c.
//

import Foundation

public enum ChargeTransport {
    /// Coulombs.
    public static let elementaryCharge = Constants.elementaryCharge
    /// Free conduction electrons per m³ in copper (one per atom).
    public static let copperElectronDensity = 8.5e28
    /// Metres per second.
    public static let speedOfLight = Constants.speedOfLight

    /// Drift speed of the charge carriers, m/s: v = I/(n·A·e).
    public static func driftSpeed(current: Double,
                                  wireRadius: Double,
                                  carrierDensity: Double = copperElectronDensity) -> Double {
        let area = Double.pi * wireRadius * wireRadius
        guard area > 0, carrierDensity > 0 else { return 0 }
        return abs(current) / (carrierDensity * area * elementaryCharge)
    }

    /// Signal (EM disturbance) speed, m/s — velocity factor × c; 0.66 is the standard figure for ordinary wiring.
    public static func signalSpeed(velocityFactor: Double = 0.66) -> Double {
        speedOfLight * velocityFactor
    }

    /// Seconds to cross `length` at `speed`; .infinity when stopped.
    public static func traversalTime(length: Double, speed: Double) -> Double {
        guard speed > 0 else { return .infinity }
        return length / speed
    }

    /// Signal speed over drift speed — around ten trillion for ordinary wiring.
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
