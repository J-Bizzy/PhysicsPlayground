//
//  ElectricFieldTests.swift
//  PhysicsCoreTests
//
//  Unit tests for the physics layer. These exercise Coulomb's Law and
//  superposition directly — no RealityKit, no rendering — which is exactly
//  why the physics code lives in its own dependency-free layer.
//

import XCTest
import simd
@testable import PhysicsCore

final class ElectricFieldTests: XCTestCase {

    // MARK: Coulomb's Law fundamentals

    /// A 1 C charge produces a field of exactly k N/C at 1 m.
    func testUnitChargeAtUnitDistanceGivesCoulombConstant() {
        let charge = PointCharge(position: .zero, charge: 1.0)
        let field = ElectricField.vector(at: SIMD3(1, 0, 0), dueTo: charge)
        XCTAssertEqual(simd_length(field), ElectricField.k, accuracy: ElectricField.k * 1e-12)
    }

    /// Hand-computed reference: 1 µC at 0.1 m →
    /// E = (8.9875517923e9 × 1e-6) / 0.1² = 898755.17923 N/C.
    func testMicrocoulombFieldMatchesHandCalculation() {
        let charge = PointCharge(position: .zero, charge: 1e-6)
        let field = ElectricField.vector(at: SIMD3(0, 0.1, 0), dueTo: charge)
        XCTAssertEqual(simd_length(field), 898755.17923, accuracy: 1e-3)
    }

    /// Doubling the distance quarters the field (inverse-square law).
    func testInverseSquareFalloff() {
        let charge = PointCharge(position: .zero, charge: 2e-6)
        let near = simd_length(ElectricField.vector(at: SIMD3(0.5, 0, 0), dueTo: charge))
        let far = simd_length(ElectricField.vector(at: SIMD3(1.0, 0, 0), dueTo: charge))
        XCTAssertEqual(near / far, 4.0, accuracy: 1e-9)
    }

    // MARK: Direction

    func testFieldPointsAwayFromPositiveCharge() {
        let charge = PointCharge(position: SIMD3(1, 2, 3), charge: 1e-6)
        let point = SIMD3<Double>(2, 3, 5)
        let field = ElectricField.vector(at: point, dueTo: charge)
        let outward = simd_normalize(point - charge.position)
        XCTAssertEqual(simd_dot(simd_normalize(field), outward), 1.0, accuracy: 1e-12)
    }

    func testFieldPointsTowardNegativeCharge() {
        let charge = PointCharge(position: .zero, charge: -1e-6)
        let field = ElectricField.vector(at: SIMD3(0, 0, 1), dueTo: charge)
        let inward = SIMD3<Double>(0, 0, -1)
        XCTAssertEqual(simd_dot(simd_normalize(field), inward), 1.0, accuracy: 1e-12)
    }

    // MARK: Superposition

    /// Midway between two equal positive charges the fields cancel exactly.
    func testEqualChargesCancelAtMidpoint() {
        let charges = [
            PointCharge(position: SIMD3(-1, 0, 0), charge: 3e-6),
            PointCharge(position: SIMD3(1, 0, 0), charge: 3e-6),
        ]
        let field = ElectricField.vector(at: .zero, dueTo: charges)
        XCTAssertEqual(simd_length(field), 0.0, accuracy: 1e-9)
    }

    /// The combined field equals the vector sum of the individual fields
    /// at an arbitrary off-axis point.
    func testSuperpositionIsVectorSum() {
        let a = PointCharge(position: SIMD3(0.2, -0.1, 0.4), charge: 2e-6)
        let b = PointCharge(position: SIMD3(-0.3, 0.5, -0.2), charge: -1.5e-6)
        let point = SIMD3<Double>(0.7, 0.7, 0.7)

        let combined = ElectricField.vector(at: point, dueTo: [a, b])
        let summed = ElectricField.vector(at: point, dueTo: a) + ElectricField.vector(at: point, dueTo: b)

        XCTAssertEqual(combined.x, summed.x, accuracy: abs(summed.x) * 1e-12)
        XCTAssertEqual(combined.y, summed.y, accuracy: abs(summed.y) * 1e-12)
        XCTAssertEqual(combined.z, summed.z, accuracy: abs(summed.z) * 1e-12)
    }

    /// On a dipole's perpendicular bisector, the field points from the
    /// positive toward the negative charge (axial components cancel).
    func testDipoleFieldOnPerpendicularBisector() {
        let charges = [
            PointCharge(position: SIMD3(-0.5, 0, 0), charge: 1e-6),   // +
            PointCharge(position: SIMD3(0.5, 0, 0), charge: -1e-6),   // −
        ]
        let field = ElectricField.vector(at: SIMD3(0, 1, 0), dueTo: charges)
        XCTAssertGreaterThan(field.x, 0)
        XCTAssertEqual(field.y, 0.0, accuracy: 1e-9)
        XCTAssertEqual(field.z, 0.0, accuracy: 1e-9)
    }

    // MARK: Edge cases

    /// At the charge's own location the field is singular; we define it as
    /// zero so callers never see infinities or NaNs.
    func testFieldIsZeroAtChargeLocation() {
        let charge = PointCharge(position: SIMD3(1, 1, 1), charge: 5e-6)
        let field = ElectricField.vector(at: SIMD3(1, 1, 1), dueTo: charge)
        XCTAssertEqual(field, .zero)
    }

    func testFieldOfNoChargesIsZero() {
        XCTAssertEqual(ElectricField.vector(at: SIMD3(1, 2, 3), dueTo: []), .zero)
    }

    /// Field scales linearly with charge magnitude.
    func testFieldScalesLinearlyWithCharge() {
        let point = SIMD3<Double>(0.3, 0.4, 0)
        let single = ElectricField.vector(at: point, dueTo: PointCharge(position: .zero, charge: 1e-6))
        let triple = ElectricField.vector(at: point, dueTo: PointCharge(position: .zero, charge: 3e-6))
        XCTAssertEqual(simd_length(triple), 3 * simd_length(single), accuracy: simd_length(single) * 1e-9)
    }

    // MARK: Potential

    /// Hand-computed reference: V = kq/r for 1 µC at 0.1 m →
    /// (8.9875517923e9 × 1e-6) / 0.1 = 89875.517923 V.
    func testPotentialMatchesHandCalculation() {
        let charge = PointCharge(position: .zero, charge: 1e-6)
        let potential = ElectricField.potential(at: SIMD3(0.1, 0, 0), dueTo: charge)
        XCTAssertEqual(potential, 89875.517923, accuracy: 1e-4)
    }

    func testPotentialIsNegativeForNegativeCharge() {
        let charge = PointCharge(position: .zero, charge: -1e-6)
        XCTAssertLessThan(ElectricField.potential(at: SIMD3(0, 0.2, 0), dueTo: charge), 0)
    }

    /// Potential superposes as a plain scalar sum.
    func testPotentialSuperposesAsScalarSum() {
        let a = PointCharge(position: SIMD3(0.1, 0, 0), charge: 2e-6)
        let b = PointCharge(position: SIMD3(-0.2, 0.3, 0), charge: -1e-6)
        let point = SIMD3<Double>(0.5, 0.5, 0.5)
        let combined = ElectricField.potential(at: point, dueTo: [a, b])
        let summed = ElectricField.potential(at: point, dueTo: a) + ElectricField.potential(at: point, dueTo: b)
        XCTAssertEqual(combined, summed, accuracy: abs(summed) * 1e-12)
    }

    /// A dipole's perpendicular bisector is the V = 0 surface.
    func testPotentialIsZeroOnDipoleBisector() {
        let charges = [
            PointCharge(position: SIMD3(-0.3, 0, 0), charge: 1e-6),
            PointCharge(position: SIMD3(0.3, 0, 0), charge: -1e-6),
        ]
        XCTAssertEqual(ElectricField.potential(at: SIMD3(0, 0.4, 0), dueTo: charges), 0, accuracy: 1e-9)
    }

    /// Same singularity guard as the field: defined zero at the charge itself.
    func testPotentialIsZeroAtChargeLocation() {
        let charge = PointCharge(position: SIMD3(1, 1, 1), charge: 5e-6)
        XCTAssertEqual(ElectricField.potential(at: SIMD3(1, 1, 1), dueTo: charge), 0)
    }
}
