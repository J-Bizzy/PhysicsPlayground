//
//  ExcludingOverloadTests.swift
//  PhysicsCoreTests
//
//  `ElectricField.vector(at:dueTo:excluding:)`,
//  `MagneticField.vector(at:dueTo:excluding:)` and
//  `MagneticField.netForce(on:at:)` exist for one reason: the callers
//  were spelling "every one but this one" as
//  `xs.enumerated().filter { $0.offset != i }.map(\.element)`, which
//  allocates two arrays per call — inside a substep loop, inside a
//  per-frame `step`. The overloads sum in place instead.
//
//  A PERFORMANCE REWRITE OF A PHYSICS KERNEL IS STILL A PHYSICS CHANGE
//  until something says the numbers did not move. So each test computes
//  the answer BOTH ways — the materialising form the modules used to
//  use, and the overload they use now — and compares.
//
//  RELATIVE, NOT BIT-EQUAL, and the first draft of this file got that
//  wrong. Demanding bit-equality looks like the stricter test and is
//  really a misunderstanding: floating-point addition is not
//  associative, `reduce` sums in array order, and an index loop that
//  skips one element sums in a different order. The residual it found
//  was 1.2e-10 on a field of 2e5 N/C — six parts in ten quadrillion,
//  which is double precision working correctly, not a bug.
//
//  So the bar is relative agreement at 1e-12, roughly ten thousand
//  times tighter than anything the physics is measured to and far
//  looser than reordering noise. A skip that omits the wrong element
//  misses by whole percent; nothing here can pass by luck.
//
//  The interesting cases are the boundaries, and they are the ones a
//  hand-rolled index loop gets wrong: excluding the first element,
//  excluding the last, and a single-element array where the answer is
//  zero rather than "the one element".
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

    /// Agreement as a FRACTION of the quantity being compared, so one
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
        // The whole point: the answer must NOT equal the all-charges sum.
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
