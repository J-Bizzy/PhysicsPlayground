//
//  PickupCoil.swift
//  PhysicsCore — Magnetism
//
//  A coil of N turns and a bicolour LED across it: push a magnet through
//  and the LED lights, red one way and green the other. Faraday's law,
//  ε = −dΛ/dt, with Λ the flux linkage.
//
//  The flux is the loop integral of the vector potential, Φ = ∮ A · dl,
//  with a point dipole's A = (μ₀/4π) m × r / r³. That is exact for a
//  dipole anywhere but on the wire itself — including in the loop's own
//  plane, as a magnet passing through the coil must be. Sampling B over
//  the disc (`Induction.flux(throughDiscAt:)`) cannot be used there: the
//  dipole's field is singular at the dipole, and the samples straddle it.
//  The integrand is smooth and periodic in the loop angle, so the
//  trapezoid rule converges exponentially.
//
//  The coil is resistive. Its own inductance is millihenries against
//  hundreds of ohms, a time constant of microseconds, so the current
//  follows the EMF within a frame and L dI/dt is negligible. The LED pair
//  is two Shockley diodes back to back, solved with the coil's resistance
//  in series.
//
//  SI units.
//

import Foundation
import simd

extension Induction {
    /// μ₀/4π, T·m/A.
    static let mu0Over4Pi = 1e-7

    /// The flux of the magnets' dipole fields through a circular loop,
    /// Wb, positive along `normal`: ∮ A · dl. Exact except within
    /// `nearest` of the wire, where the field of a point dipole is not.
    public static func flux(throughLoopAt center: SIMD3<Double>,
                            normal: SIMD3<Double>,
                            radius: Double,
                            magnets: [BarMagnet],
                            samples: Int = 96,
                            nearest: Double = 0.004) -> Double {
        guard radius > 0, !magnets.isEmpty, samples >= 8 else { return 0 }
        let n = simd_normalize(normal)
        let seed = abs(n.x) < 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
        let u = simd_normalize(simd_cross(n, seed))
        let v = simd_cross(n, u)
        let step = 2 * Double.pi / Double(samples)
        var total = 0.0
        for index in 0..<samples {
            let angle = Double(index) * step
            let point = center + radius * (cos(angle) * u + sin(angle) * v)
            // dl runs anticlockwise about n, so the flux is positive along n.
            let tangent = radius * step * (-sin(angle) * u + cos(angle) * v)
            for magnet in magnets {
                let r = point - magnet.position
                let distance = max(simd_length(r), nearest)
                let potential = mu0Over4Pi * simd_cross(magnet.moment, r)
                    / (distance * distance * distance)
                total += simd_dot(potential, tangent)
            }
        }
        return total
    }
}

/// A cylindrical coil wound uniformly along its axis.
public struct PickupCoil: Sendable, Equatable {
    public var center: SIMD3<Double>
    /// Unit vector along the bore; the flux is counted positive along it.
    public var axis: SIMD3<Double>
    /// The winding's mean radius, m.
    public var radius: Double
    /// The winding's length along the axis, m.
    public var length: Double
    public var turns: Int
    /// The copper wire's diameter, m.
    public var wireDiameter: Double

    public init(center: SIMD3<Double>, axis: SIMD3<Double>, radius: Double,
                length: Double, turns: Int, wireDiameter: Double) {
        self.center = center
        self.axis = simd_normalize(axis)
        self.radius = radius
        self.length = length
        self.turns = turns
        self.wireDiameter = wireDiameter
    }

    /// How many loops stand in for the winding: the turns are spread
    /// evenly along the coil, and each loop speaks for N/M of them.
    public static let loops = 12

    /// The flux linkage Λ = Σ Φ over every turn, Wb·turns.
    public func linkage(magnets: [BarMagnet]) -> Double {
        let count = Self.loops
        var total = 0.0
        for index in 0..<count {
            let offset = length * ((Double(index) + 0.5) / Double(count) - 0.5)
            total += Induction.flux(throughLoopAt: center + axis * offset, normal: axis,
                                    radius: radius, magnets: magnets)
        }
        return total * Double(turns) / Double(count)
    }

    /// The copper's resistance: ρL/A, with L the wire's whole length.
    public var resistance: Double {
        let resistivity = 1.68e-8   // copper at 20 °C, Ω·m
        let wire = Double(turns) * 2 * .pi * radius
        let area = .pi * wireDiameter * wireDiameter / 4
        return resistivity * wire / area
    }
}

/// Two LEDs back to back across the coil, a red and a green: whichever
/// way the current runs, one of them lights.
public enum BicolourLED {
    /// One LED by the Shockley equation, I = I_s (e^{V/(nV_T)} − 1),
    /// characterised by its forward voltage at a reference current.
    public struct Diode: Sendable, Equatable {
        /// n·V_T, V: the ideality factor times the thermal voltage.
        public var thermal: Double
        public var saturation: Double

        /// A diode that drops `forwardVoltage` at `atCurrent`.
        public init(forwardVoltage: Double, atCurrent: Double, ideality: Double = 2) {
            thermal = ideality * 0.025852   // kT/q at 300 K
            saturation = atCurrent / (exp(forwardVoltage / thermal) - 1)
        }

        public func voltage(current: Double) -> Double {
            thermal * log(1 + max(current, 0) / saturation)
        }
    }

    /// A red LED: 1.8 V at 10 mA. Positive current lights it.
    public static let red = Diode(forwardVoltage: 1.8, atCurrent: 0.010)
    /// A green LED: 2.1 V at 10 mA. Negative current lights it.
    public static let green = Diode(forwardVoltage: 2.1, atCurrent: 0.010)

    /// The current, A (positive through the red LED), that an EMF drives
    /// through the coil's `resistance` and the LED pair: the root of
    /// ε = I R + V_LED(I), found by bisection on the bracket [0, ε/R].
    public static func current(emf: Double, resistance: Double) -> Double {
        guard abs(emf) > 0, resistance > 0 else { return 0 }
        let diode = emf > 0 ? red : green
        let drive = abs(emf)
        var low = 0.0, high = drive / resistance
        for _ in 0..<80 {
            let middle = (low + high) / 2
            if middle * resistance + diode.voltage(current: middle) > drive {
                high = middle
            } else {
                low = middle
            }
        }
        let current = (low + high) / 2
        return emf > 0 ? current : -current
    }

    /// What Kirchhoff's voltage law leaves over for a current: zero when
    /// the current is right.
    public static func residual(emf: Double, resistance: Double, current: Double) -> Double {
        let diode = current >= 0 ? red : green
        let sign: Double = current >= 0 ? 1 : -1
        return emf - sign * (abs(current) * resistance + diode.voltage(current: abs(current)))
    }
}
