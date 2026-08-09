//
//  MagneticField.swift
//  PhysicsCore — Magnetism
//
//  The exact ideal-dipole field, and the dipole–dipole force and torque
//  that make two magnets attract, repel, and snap into alignment. Pure
//  functions the renderer and model only ever *ask* — physics lives here.
//
//  Dipole field:  B(r) = (μ₀/4π)[ 3(m·r̂)r̂ − m ] / r³
//  Torque:        τ = m × B          (turns a magnet to align with B)
//  Dipole force:  F = (3μ₀/4π r⁴)[ (m₁·r̂)m₂ + (m₂·r̂)m₁
//                                    + (m₁·m₂)r̂ − 5(m₁·r̂)(m₂·r̂)r̂ ]
//

import Foundation
import simd

public enum MagneticField {
    /// μ₀/4π in T·m/A.
    public static let mu0over4pi = Constants.permeabilityOver4Pi
    /// Separations below this (m) are treated as "at the dipole," where
    /// the 1/r³ field is singular — return zero and let the renderer hide it.
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
    //
    // A bench integrating itself asks, for each magnet, what the OTHERS
    // do to it. Spelled at the call site that is
    // `magnets.enumerated().filter { $0.offset != i }.map(\.element)`,
    // which allocates two arrays — the filter's tuples and the map's
    // elements — for every magnet, on every substep. Magnetism runs
    // four substeps a frame in the inertial mode, so eight magnets cost
    // sixty-four array allocations a frame to express "skip index i".
    //
    // These take the whole array and the index to leave out. Same
    // arithmetic, same results — `MagneticFieldTests` pins the numbers
    // against the materialising form.

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
    //
    // Everything above treats a magnet as a POINT dipole, which is exact
    // — for a point dipole. The expansion it comes from is the leading
    // term in L/r, so it is right to within a percent or so once you are
    // a few bar-lengths away, and it is simply not the field of a bar
    // magnet any nearer than that.
    //
    // Which would be an academic footnote if anything sampled B near a
    // magnet. Something does: the FIELD LINE TRACER. It seeds curves a
    // few centimetres off a 16 cm bar and integrates them right past its
    // flanks — the region where L/r is of order one and the expansion
    // has no claim at all. That is why the loops looked subtly wrong on
    // device: they were the correct picture of the wrong object, drawn
    // over the top of a bar they did not belong to.
    //
    // So the tracer asks for this instead. A uniformly magnetised bar is
    // equivalent to two magnetic poles of strength q = |m|/L at its
    // ends, and
    //
    //     B(r) = (μ₀/4π) q [ (r−r₊)/|r−r₊|³ − (r−r₋)/|r−r₋|³ ]
    //
    // is exact for THAT object. It carries the same total moment, so it
    // converges to the point dipole above as r/L grows — which is a
    // property worth testing, and MagneticFieldTests does.
    //
    // Force, torque and induction stay on the point dipole deliberately.
    // They are pinned by tests, they are what the module's numbers have
    // always meant, and unlike the tracer they are evaluated where a
    // dipole is a fair model of a magnet.

    /// The pole-pair field of a bar of length `length`, exact for a
    /// uniformly magnetised bar rather than for a point.
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
            // A pole is a 1/r² singularity. Inside the core the field is
            // meaningless and unbounded, so it is clamped rather than
            // allowed to dominate the superposition.
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

    /// Net force on `b` from all the `others`, as POINT DIPOLES.
    ///
    /// Correct a few bar-lengths out and badly wrong nearer than that —
    /// see `barForce`, which is what a bench of real bars should use.
    public static func netForce(on b: BarMagnet, from others: [BarMagnet]) -> SIMD3<Double> {
        others.reduce(.zero) { $0 + force(on: b, dueTo: $1) }
    }

    // MARK: The finite bar, again — this time for the force
    //
    // THE DYNAMICS WERE COMPUTED IN THE REGIME THIS FILE'S OWN HEADER
    // RULES OUT. The tracer was moved onto `barVector` because the point
    // dipole "is simply not the field of a bar magnet" close in; the
    // FORCE was left on the dipole expansion, and the force is what
    // decides where the magnets go. Measured, dipole against pole-pair,
    // head-to-tail on the axis:
    //
    //     r/L = 0.92   50.3 % low     ← `contactDistance`
    //     r/L = 1.5    21 %
    //     r/L = 3      5.5 %
    //     r/L = 5      2.0 %
    //
    // Magnetism's `contactDistance` is `magnetLength * 0.92`. So the
    // single most repeated interaction in the module — two magnets
    // snapping together — was driven by a field reporting HALF its real
    // value, while the loops drawn over the top were traced from the
    // right one. The picture and the motion disagreed, and the picture
    // was correct.
    //
    // A uniformly magnetised bar is two poles of strength q = |m|/L at
    // its ends, so the force on it is `q·B` at its north pole minus the
    // same at its south. That is a sum of pole-pole central forces, so
    // Newton's third law holds exactly rather than approximately, and it
    // converges on the dipole answer as the bars separate — which is the
    // property `testBarForceMeetsTheDipoleForceFarAway` pins.

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
