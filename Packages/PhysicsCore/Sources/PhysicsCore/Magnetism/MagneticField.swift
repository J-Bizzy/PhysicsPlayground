//  MagneticField.swift — exact ideal-dipole field, force and torque; pure functions, SI.
//  B(r) = (μ₀/4π)[3(m·r̂)r̂ − m]/r³;  τ = m × B;
//  F = (3μ₀/4π r⁴)[(m₁·r̂)m₂ + (m₂·r̂)m₁ + (m₁·m₂)r̂ − 5(m₁·r̂)(m₂·r̂)r̂]

import Foundation
import simd

public enum MagneticField {
    /// μ₀/4π in T·m/A.
    public static let mu0over4pi = Constants.permeabilityOver4Pi
    /// Separations below this (m) are "at the dipole", where 1/r³ is singular — return zero, let the renderer hide it.
    public static let singularityRadius = 1e-4

    // MARK: Field

    /// B at `point` from a single dipole.
    public static func vector(at point: SIMD3<Double>, dueTo magnet: BarMagnet) -> SIMD3<Double> {
        let r = point - magnet.position
        let d2 = simd_length_squared(r)
        guard d2 > singularityRadius * singularityRadius else { return .zero }
        let d = d2.squareRoot()
        let rHat = r / d
        let m = magnet.moment
        return mu0over4pi * (3 * simd_dot(m, rHat) * rHat - m) / (d2 * d)
    }

    /// B at `point` from any number of magnets, by superposition.
    public static func vector(at point: SIMD3<Double>, dueTo magnets: [BarMagnet]) -> SIMD3<Double> {
        magnets.reduce(.zero) { $0 + vector(at: point, dueTo: $1) }
    }

    /// Field strength |B| in tesla — a convenience for display.
    public static func magnitude(at point: SIMD3<Double>, dueTo magnets: [BarMagnet]) -> Double {
        simd_length(vector(at: point, dueTo: magnets))
    }

    // MARK: Every magnet but one
    // Allocation-free "skip index i" forms — the enumerated/filter/map spelling allocates
    // two arrays per magnet per substep. Same arithmetic; MagneticFieldTests pins it.

    /// B at `point` from every magnet except the one at `index`.
    public static func vector(at point: SIMD3<Double>,
                              dueTo magnets: [BarMagnet],
                              excluding index: Int) -> SIMD3<Double> {
        var sum = SIMD3<Double>.zero
        for i in magnets.indices where i != index {
            sum += vector(at: point, dueTo: magnets[i])
        }
        return sum
    }

    /// Net force on `magnets[index]` from every other magnet.
    public static func netForce(on magnets: [BarMagnet],
                                at index: Int) -> SIMD3<Double> {
        var sum = SIMD3<Double>.zero
        let subject = magnets[index]
        for i in magnets.indices where i != index {
            sum += force(on: subject, dueTo: magnets[i])
        }
        return sum
    }

    // MARK: The finite bar
    // A point dipole is not a bar magnet within ~one bar length — exactly where the field
    // line tracer samples. A uniformly magnetised bar ≡ two poles q = |m|/L at its ends:
    // B(r) = (μ₀/4π) q [(r−r₊)/|r−r₊|³ − (r−r₋)/|r−r₋|³], exact for that object and
    // converging to the point dipole as r/L grows (tested).

    /// Pole-pair field of a bar of length `length` — exact for a uniformly magnetised bar.
    public static func barVector(at point: SIMD3<Double>,
                                 dueTo magnet: BarMagnet,
                                 length: Double) -> SIMD3<Double> {
        let strength = magnet.strength
        guard strength > 1e-18, length > singularityRadius else {
            return vector(at: point, dueTo: magnet)
        }
        // Pole strength q_m in A·m: the moment spread over the bar.
        let q = strength / length
        let axis = magnet.axis
        var field = SIMD3<Double>.zero
        for (sign, pole) in [(1.0, magnet.position + 0.5 * length * axis),
                             (-1.0, magnet.position - 0.5 * length * axis)] {
            let r = point - pole
            let d2 = simd_length_squared(r)
            // A pole is a 1/r² singularity — clamped inside the core rather than allowed to dominate.
            let clamped = max(d2, poleCoreRadius * poleCoreRadius)
            let d = clamped.squareRoot()
            field += sign * mu0over4pi * q * r / (clamped * d)
        }
        return field
    }

    /// Superposition of finite bars.
    public static func barVector(at point: SIMD3<Double>,
                                 dueTo magnets: [BarMagnet],
                                 length: Double) -> SIMD3<Double> {
        magnets.reduce(.zero) { $0 + barVector(at: point, dueTo: $1, length: length) }
    }

    /// How close to a pole the pole-pair field stops growing, metres.
    public static let poleCoreRadius = 0.012

    // MARK: Force & torque

    /// Force on dipole `b` from dipole `a`'s field. Obeys Newton's third
    /// law: force(on: b, dueTo: a) == −force(on: a, dueTo: b).
    public static func force(on b: BarMagnet, dueTo a: BarMagnet) -> SIMD3<Double> {
        let r = b.position - a.position
        let d2 = simd_length_squared(r)
        guard d2 > singularityRadius * singularityRadius else { return .zero }
        let d = d2.squareRoot()
        let rHat = r / d
        let m1 = a.moment, m2 = b.moment
        let m1r = simd_dot(m1, rHat), m2r = simd_dot(m2, rHat), m1m2 = simd_dot(m1, m2)
        let coeff = 3 * mu0over4pi / (d2 * d2)
        return coeff * (m1r * m2 + m2r * m1 + m1m2 * rHat - 5 * m1r * m2r * rHat)
    }

    /// Net force on `b` as POINT DIPOLES — badly wrong nearer than a few bar lengths; a bench of real bars should use `barForce`.
    public static func netForce(on b: BarMagnet, from others: [BarMagnet]) -> SIMD3<Double> {
        others.reduce(.zero) { $0 + force(on: b, dueTo: $1) }
    }

    // MARK: The finite bar, again — this time for the force
    // Pole-pair force = q·B(north) − q·B(south), q = |m|/L. The dipole force is 50% low at
    // r/L = 0.92 (Magnetism's contactDistance), 2% at r/L = 5. A sum of central pole-pole
    // forces, so Newton's third law holds exactly; converges on the dipole answer far away
    // (pinned by testBarForceMeetsTheDipoleForceFarAway).

    /// Force on bar `b` from bar `a`, both treated as pole pairs.
    public static func barForce(on b: BarMagnet, dueTo a: BarMagnet,
                                length: Double) -> SIMD3<Double> {
        let moment = simd_length(b.moment)
        guard length > 1e-9, moment > 1e-30 else { return .zero }
        let axis = b.moment / moment
        let pole = moment / length
        let north = b.position + axis * (length / 2)
        let south = b.position - axis * (length / 2)
        return pole * (barVector(at: north, dueTo: a, length: length)
                       - barVector(at: south, dueTo: a, length: length))
    }

    /// Net pole-pair force on `b` from all the `others`.
    public static func netBarForce(on b: BarMagnet, from others: [BarMagnet],
                                   length: Double) -> SIMD3<Double> {
        others.reduce(.zero) { $0 + barForce(on: b, dueTo: $1, length: length) }
    }

    /// Torque on `b` in the combined field of the `others`: τ = m × B.
    /// It's zero when the moment is parallel to the local field and
    /// maximal when perpendicular — the drive that aligns a compass.
    public static func torque(on b: BarMagnet, inFieldOf others: [BarMagnet]) -> SIMD3<Double> {
        simd_cross(b.moment, vector(at: b.position, dueTo: others))
    }

    /// Interaction energy of dipole `b` in dipole `a`'s field: U = −m_b·B_a.
    /// Lowest (most negative) when they attract head-to-tail.
    public static func potentialEnergy(of b: BarMagnet, in a: BarMagnet) -> Double {
        -simd_dot(b.moment, vector(at: b.position, dueTo: a))
    }
}
