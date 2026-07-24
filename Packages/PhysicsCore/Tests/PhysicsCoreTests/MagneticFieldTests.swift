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
}
