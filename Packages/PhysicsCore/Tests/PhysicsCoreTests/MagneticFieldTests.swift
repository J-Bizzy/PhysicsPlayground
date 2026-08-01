//
//  MagneticFieldTests.swift
//  PhysicsCoreTests
//
//  The dipole pinned to the textbook: the on-axis field is exactly twice
//  the equatorial and points the opposite way; the dipole–dipole force
//  obeys Newton's third law and gives attract head-to-tail / repel
//  side-by-side; the torque aligns a magnet with the field; and field
//  lines close back on the magnet.
//

import XCTest
import simd
@testable import PhysicsCore

final class MagneticFieldTests: XCTestCase {

    private let k = MagneticField.mu0over4pi

    /// On the axis B = (μ₀/4π)(2m/r³) along m; on the equator it's half
    /// that, pointing opposite — the classic 2:1 dipole signature.
    func testAxialFieldIsTwiceEquatorialAndOpposite() {
        let m0 = 5.0, r = 0.3
        let magnet = BarMagnet(position: .zero, moment: SIMD3(m0, 0, 0))

        let axial = MagneticField.vector(at: SIMD3(r, 0, 0), dueTo: magnet)
        let equatorial = MagneticField.vector(at: SIMD3(0, r, 0), dueTo: magnet)

        XCTAssertEqual(axial.x, k * 2 * m0 / (r * r * r), accuracy: 1e-18)
        XCTAssertEqual(axial.y, 0, accuracy: 1e-20)
        // Equatorial points along −m and is half the magnitude.
        XCTAssertEqual(equatorial.x, -k * m0 / (r * r * r), accuracy: 1e-18)
        XCTAssertEqual(simd_length(axial), 2 * simd_length(equatorial), accuracy: 1e-18)
    }

    /// Newton's third law for two arbitrary dipoles.
    func testForceObeysNewtonsThirdLaw() {
        let a = BarMagnet(position: SIMD3(-0.1, 0.05, 0), moment: SIMD3(3, 1, -2))
        let b = BarMagnet(position: SIMD3(0.2, -0.1, 0.15), moment: SIMD3(-1, 2, 1))
        let fBA = MagneticField.force(on: b, dueTo: a)
        let fAB = MagneticField.force(on: a, dueTo: b)
        XCTAssertEqual(fBA.x, -fAB.x, accuracy: 1e-16)
        XCTAssertEqual(fBA.y, -fAB.y, accuracy: 1e-16)
        XCTAssertEqual(fBA.z, -fAB.z, accuracy: 1e-16)
    }

    /// Two magnets pointing the same way along their line of centres
    /// attract (N meets S); placed side by side they repel.
    func testAttractHeadToTailRepelSideBySide() {
        let a = BarMagnet(position: .zero, moment: SIMD3(5, 0, 0))
        let headToTail = BarMagnet(position: SIMD3(0.3, 0, 0), moment: SIMD3(5, 0, 0))
        let sideBySide = BarMagnet(position: SIMD3(0, 0.3, 0), moment: SIMD3(5, 0, 0))

        // Head-to-tail: pulled back toward a (−x).
        XCTAssertLessThan(MagneticField.force(on: headToTail, dueTo: a).x, 0)
        // Side-by-side parallel: pushed away (+y).
        XCTAssertGreaterThan(MagneticField.force(on: sideBySide, dueTo: a).y, 0)
    }

    /// Torque is zero when the moment lies along the local field and
    /// equals |m||B| when perpendicular — and it turns the magnet toward
    /// alignment (τ = m × B).
    func testTorqueAlignsWithField() {
        let source = BarMagnet(position: .zero, moment: SIMD3(5, 0, 0))
        let point = SIMD3(0.4, 0, 0)                 // on axis: B along +x
        let field = MagneticField.vector(at: point, dueTo: source)

        let aligned = BarMagnet(position: point, moment: SIMD3(2, 0, 0))
        XCTAssertEqual(simd_length(MagneticField.torque(on: aligned, inFieldOf: [source])),
                       0, accuracy: 1e-20)

        let perpendicular = BarMagnet(position: point, moment: SIMD3(0, 2, 0))
        let torque = MagneticField.torque(on: perpendicular, inFieldOf: [source])
        XCTAssertEqual(simd_length(torque), 2 * simd_length(field), accuracy: 1e-18)
        // m=+y, B=+x → τ = m×B along −z: rotating +y toward +x, i.e. into
        // alignment with the field.
        XCTAssertLessThan(torque.z, 0)
    }

    /// A single magnet's field lines are closed loops: a traced line
    /// starts and ends near the magnet it belongs to.
    func testFieldLinesCloseOnTheMagnet() {
        let magnet = BarMagnet(position: .zero, moment: SIMD3(0, 5, 0))
        var config = MagneticFieldLineTracer.Config()
        config.boundsRadius = 1.5
        let lines = MagneticFieldLineTracer.trace(magnets: [magnet], config: config)
        XCTAssertFalse(lines.isEmpty, "a magnet should radiate field lines")
        // At least one substantial loop returns near where it began.
        let loops = lines.filter { line in
            guard let first = line.first, let last = line.last, line.count > 8 else { return false }
            return simd_distance(first, magnet.position) < 0.12
                && simd_distance(last, magnet.position) < 0.12
        }
        XCTAssertFalse(loops.isEmpty, "field lines should loop back to the magnet")
    }

    // MARK: The finite bar

    /// The pole-pair bar carries the same total moment as the point
    /// dipole, so far away the two must agree — that convergence is the
    /// whole licence for using either. Checked at four bar-lengths and
    /// again at twenty, where the error has to have shrunk.
    func testTheFiniteBarConvergesToThePointDipoleFarAway() {
        let length = 0.16
        let magnet = BarMagnet(position: .zero, moment: SIMD3(0, 6, 0))

        func relativeError(at radius: Double) -> Double {
            // Off-axis, so the test is not fooled by an accidental
            // agreement on one symmetry axis.
            let point = SIMD3(radius * 0.6, radius * 0.8, 0)
            let ideal = MagneticField.vector(at: point, dueTo: magnet)
            let bar = MagneticField.barVector(at: point, dueTo: magnet, length: length)
            return simd_length(bar - ideal) / simd_length(ideal)
        }

        let near = relativeError(at: length * 4)
        let far = relativeError(at: length * 20)
        XCTAssertLessThan(near, 0.05,
                          "the bar has drifted off the dipole it is made of")
        XCTAssertLessThan(far, near / 10,
                          "the error is not falling with distance — the bar "
                          + "does not carry the moment it claims")
    }

    /// …and CLOSE to the bar the two genuinely disagree. If they did not,
    /// there would be no reason for the tracer to pay for the pole-pair
    /// model at all.
    func testTheFiniteBarDepartsFromThePointDipoleNearTheMagnet() {
        let length = 0.16
        let magnet = BarMagnet(position: .zero, moment: SIMD3(0, 6, 0))
        // Just off the bar's flank — where the field lines are seeded.
        let point = SIMD3(0.115, 0.02, 0)
        let ideal = MagneticField.vector(at: point, dueTo: magnet)
        let bar = MagneticField.barVector(at: point, dueTo: magnet, length: length)
        let error = simd_length(bar - ideal) / simd_length(ideal)
        XCTAssertGreaterThan(error, 0.10,
                             "at two-thirds of a bar-length the point dipole "
                             + "is supposed to be a poor model of a bar")
    }

    // MARK: Seeding

    /// Seeds are spread by equal slices of FLUX, not equal area. For a
    /// dipole the flux through a cap of half-angle θ goes as sin²θ, so
    /// the k-th of n seeds sits at sin²θ = (k + ½)/n. Checked against
    /// that closed form directly, in a tilted frame so the test cannot
    /// pass by accident on a coordinate axis.
    func testSeedsAreSpacedByEqualFlux() {
        let axis = simd_normalize(SIMD3<Double>(1, 2, -0.5))
        let n = 12
        let directions = MagneticFieldLineTracer.fluxSeedDirections(
            axis: axis, count: n)
        XCTAssertEqual(directions.count, n)
        for (k, direction) in directions.enumerated() {
            XCTAssertEqual(simd_length(direction), 1, accuracy: 1e-12,
                           "seed \(k) is not on the unit sphere")
            let cosTheta = simd_dot(direction, axis)
            let sin2 = 1 - cosTheta * cosTheta
            XCTAssertEqual(sin2, (Double(k) + 0.5) / Double(n), accuracy: 1e-12,
                           "seed \(k) does not carry its equal share of flux")
        }
    }

    /// Every seed is on the NORTH half. Both halves would be redundant:
    /// each seed is traced in both directions and comes back a closed
    /// loop that already crosses the south.
    func testSeedsStayOnTheNorthHalfOfTheSphere() {
        let axis = simd_normalize(SIMD3<Double>(0, -1, 0.3))
        for direction in MagneticFieldLineTracer.fluxSeedDirections(
            axis: axis, count: 20) {
            XCTAssertGreaterThanOrEqual(simd_dot(direction, axis), 0,
                                        "a seed crossed into the far hemisphere")
        }
    }

    // MARK: Density

    /// A stronger magnet draws more loops. This was the promise the
    /// module's strength bead made and could not keep: the tracer
    /// integrates the NORMALIZED field, so with a fixed seed count a
    /// magnet's loops were identical at every strength and pulling the
    /// bead rebuilt an unchanged mesh.
    func testAStrongerMagnetEarnsMoreLines() {
        var config = MagneticFieldLineTracer.Config()
        config.referenceStrength = 6
        config.seedsPerMagnet = 12
        XCTAssertEqual(config.seedCount(forStrength: 6), 12)
        XCTAssertEqual(config.seedCount(forStrength: 12), 24)
        XCTAssertEqual(config.seedCount(forStrength: 3), 6)
        // Bounded at both ends: one loop is not a field, and a maxed
        // magnet must not blow the frame budget.
        XCTAssertEqual(config.seedCount(forStrength: 0.01),
                       config.seedRange.lowerBound)
        XCTAssertEqual(config.seedCount(forStrength: 1e6),
                       config.seedRange.upperBound)
    }

    /// Lines are born and die OUTSIDE the bar they belong to. They used
    /// to be seeded 6 cm from the centre of a 16 cm magnet and to
    /// terminate at 5 cm — inside its body — so every loop emerged from
    /// the middle of a flank and vanished into it, with a dead sphere
    /// where the poles should have been.
    func testLinesAreSeededClearOfTheBarItself() {
        var config = MagneticFieldLineTracer.Config()
        config.magnetLength = 0.16
        let halfLength = config.magnetLength / 2
        XCTAssertGreaterThan(config.seedRadius, halfLength,
                             "lines start inside the magnet")
        XCTAssertGreaterThan(config.terminationRadius, halfLength,
                             "lines end inside the magnet")
        // …and the stop sphere is inside the seed sphere, or every line
        // terminates on the step it was born.
        XCTAssertLessThan(config.terminationRadius, config.seedRadius)
    }
}
