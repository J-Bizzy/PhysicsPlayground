//
//  ExcludingOverloadTests.swift
//  PhysicsCoreTests
//
//  The `excluding:` overloads sum in place instead of materialising a
//  filtered array per call inside a substep loop. A performance rewrite
//  of a physics kernel is still a physics change, so each test computes
//  the answer both ways and compares. Relative at 1e-12, not bit-equal:
//  floating-point addition is not associative, and a loop that skips one
//  element sums in a different order than `reduce` does. The boundaries
//  are the interesting cases: first element, last element, and a single
//  element whose answer is zero.
//

import XCTest
import simd
@testable import PhysicsCore

final class ExcludingOverloadTests: XCTestCase {

    // MARK: Fixtures

    /// Deliberately asymmetric — equal, evenly spaced charges would
    /// cancel and hide an off-by-one.
    private let charges = [
        PointCharge(position: SIMD3(-0.30, 1.35, -0.90), charge: 2.0e-6),
        PointCharge(position: SIMD3(0.12, 1.41, -0.83), charge: -3.5e-6),
        PointCharge(position: SIMD3(0.26, 1.22, -1.04), charge: 1.25e-6),
        PointCharge(position: SIMD3(-0.05, 1.50, -0.71), charge: -0.75e-6),
    ]

    private let magnets = [
        BarMagnet(position: SIMD3(-0.22, 1.35, -0.70), moment: SIMD3(0.8, 0, 0)),
        BarMagnet(position: SIMD3(0.16, 1.30, -0.66), moment: SIMD3(0, 0.55, 0.2)),
        BarMagnet(position: SIMD3(0.04, 1.44, -0.88), moment: SIMD3(-0.3, 0.1, 0.6)),
    ]

    /// The spelling the modules used before the overloads landed.
    private func allBut<T>(_ index: Int, of items: [T]) -> [T] {
        items.enumerated().filter { $0.offset != index }.map(\.element)
    }

    /// Agreement as a fraction of the quantity being compared, so one
    /// bar holds for a 2e5 N/C field and a 1e-9 N force alike.
    private func assertAgree(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>,
                             _ message: String,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        let magnitude = max(simd_length(lhs), simd_length(rhs))
        guard magnitude > 0 else { return }
        XCTAssertLessThan(simd_length(lhs - rhs) / magnitude, 1e-12,
                          message, file: file, line: line)
    }

    // MARK: Electric

    func testExcludingMatchesTheMaterialisedFormAtEveryIndex() {
        let point = SIMD3<Double>(0.02, 1.33, -0.88)
        for index in charges.indices {
            let materialised = ElectricField.vector(
                at: point, dueTo: allBut(index, of: charges))
            let inPlace = ElectricField.vector(
                at: point, dueTo: charges, excluding: index)
            assertAgree(inPlace, materialised, "index \(index) differs")
        }
    }

    func testExcludingActuallyOmitsThatCharge() {
        // The whole point: the answer must not equal the all-charges sum.
        // A skip that silently skips nothing passes every test above.
        let point = SIMD3<Double>(0.02, 1.33, -0.88)
        let all = ElectricField.vector(at: point, dueTo: charges)
        for index in charges.indices {
            let without = ElectricField.vector(
                at: point, dueTo: charges, excluding: index)
            let contribution = ElectricField.vector(
                at: point, dueTo: charges[index])
            XCTAssertGreaterThan(simd_length(contribution), 1e-9,
                                 "fixture \(index) contributes nothing — bad test")
            assertAgree(all - without, contribution,
                        "index \(index): removing it did not remove its field")
        }
    }

    func testASingleChargeExcludedLeavesNoField() {
        let one = [charges[0]]
        let field = ElectricField.vector(
            at: SIMD3(0, 1.4, -0.8), dueTo: one, excluding: 0)
        XCTAssertEqual(simd_length(field), 0,
                       "excluding the only charge must leave zero, not itself")
    }

    // MARK: Magnetic

    func testMagneticVectorExcludingMatchesTheMaterialisedForm() {
        let point = SIMD3<Double>(-0.02, 1.38, -0.75)
        for index in magnets.indices {
            let materialised = MagneticField.vector(
                at: point, dueTo: allBut(index, of: magnets))
            let inPlace = MagneticField.vector(
                at: point, dueTo: magnets, excluding: index)
            assertAgree(inPlace, materialised, "index \(index) differs")
        }
    }

    func testNetForceAtIndexMatchesTheMaterialisedForm() {
        for index in magnets.indices {
            let materialised = MagneticField.netForce(
                on: magnets[index], from: allBut(index, of: magnets))
            let inPlace = MagneticField.netForce(on: magnets, at: index)
            assertAgree(inPlace, materialised, "index \(index) differs")
        }
    }

    func testASingleMagnetFeelsNoForceFromItself() {
        let one = [magnets[0]]
        XCTAssertEqual(simd_length(MagneticField.netForce(on: one, at: 0)), 0)
        XCTAssertEqual(
            simd_length(MagneticField.vector(
                at: SIMD3(0, 1.4, -0.7), dueTo: one, excluding: 0)),
            0)
    }
}
