//
//  FieldEquipotentialTests.swift
//  PhysicsPlaygroundTests
//
//  Electric Fields' equipotential shells as the lab draws them: off in the
//  opening room; equal steps of potential on a 1-2-5 ladder, four each side
//  of every sign present and the 0 V surface between opposite charges; and
//  the opening dipole's nine surfaces meshed whole within the renderer's
//  triangle budget at the renderer's resolution.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class FieldEquipotentialTests: XCTestCase {

    func testTheShellsAreOffInTheOpeningRoom() {
        XCTAssertFalse(FieldModel().showEquipotentials, "shells in the opening room are clutter")
    }

    func testTheStepIsTheLargestOneTwoFiveNotAboveTheValue() {
        XCTAssertEqual(FieldModel.roundStep(28_090), 20_000)
        XCTAssertEqual(FieldModel.roundStep(56_000), 50_000)
        XCTAssertEqual(FieldModel.roundStep(19_999), 10_000)
        XCTAssertEqual(FieldModel.roundStep(1), 1)
        XCTAssertEqual(FieldModel.roundStep(0.7), 0.5)
        XCTAssertEqual(FieldModel.roundStep(0), 0)
    }

    /// The opening dipole: four surfaces round each charge and the 0 V plane
    /// between them, all at whole multiples of one step.
    func testTheOpeningDipoleGetsFourShellsEachSideAndZeroVolts() {
        let model = FieldModel()
        let ladder = FieldModel.equipotentialLevels(model.charges)
        XCTAssertEqual(ladder.levels.count, 9)
        XCTAssertTrue(ladder.levels.contains(0))
        XCTAssertEqual(ladder.levels.filter { $0 > 0 }.count, 4)
        XCTAssertEqual(ladder.levels.filter { $0 < 0 }.count, 4)
        for level in ladder.levels {
            let multiple = level / ladder.step
            XCTAssertEqual(multiple, multiple.rounded(), accuracy: 1e-12)
        }
        // The innermost surface round the strongest charge stands clear of
        // its drawn sphere, about 8 cm out or more.
        let strongest = model.charges.map { abs($0.charge) }.max() ?? 0
        let innermost = ElectricField.k * strongest / (ladder.levels.map(abs).max() ?? 1)
        XCTAssertGreaterThanOrEqual(innermost, 0.08)
    }

    /// Like charges have no zero surface at a finite distance.
    func testLikeChargesHaveNoZeroSurface() {
        let charges = [PointCharge(position: SIMD3(0, 1.3, -0.9), charge: 1e-6),
                       PointCharge(position: SIMD3(0.3, 1.3, -0.9), charge: 2e-6)]
        let ladder = FieldModel.equipotentialLevels(charges)
        XCTAssertFalse(ladder.levels.contains(0))
        XCTAssertTrue(ladder.levels.allSatisfy { $0 > 0 })
        XCTAssertTrue(FieldModel.equipotentialLevels([]).levels.isEmpty)
    }

    /// What the renderer meshes for the opening room: the four closed
    /// shells round each charge, within the budget, and NOT the 0 V plane
    /// between them — infinite for equal and opposite charges, so the box
    /// would cut it into a flat pane.
    func testTheOpeningDipoleDrawsItsEightShellsAndNoPane() {
        let model = FieldModel()
        let meshes = FieldRenderer.shellMeshes(model.charges, region: model.samplingRegion)
        XCTAssertEqual(meshes.count, 8, "a shell was dropped, or the cut 0 V plane drawn")
        XCTAssertFalse(meshes.contains { $0.level == 0 })
        XCTAssertLessThanOrEqual(meshes.count, FieldRenderer.shellBudget)
        XCTAssertLessThanOrEqual(meshes.map(\.triangleCount).reduce(0, +),
                                 FieldRenderer.shellTriangleBudget)
    }

    /// Unequal and opposite: the 0 V surface closes, a sphere round the
    /// weaker charge (Apollonius'), radius d·q₁q₂/(q₂² − q₁²), and it is drawn.
    func testUnequalChargesDrawTheirClosedZeroVoltSphere() throws {
        let weak = PointCharge(position: SIMD3(-0.13, 1.35, -0.9), charge: 1e-6)
        let strong = PointCharge(position: SIMD3(0.13, 1.35, -0.9), charge: -3e-6)
        let region = FieldModel.SamplingRegion(center: SIMD3(0, 1.35, -0.9), extents: SIMD3(repeating: 1.3))
        let zero = try XCTUnwrap(FieldRenderer.shellMeshes([weak, strong], region: region)
            .first { $0.level == 0 })
        let d = 0.26, q1 = 1.0, q2 = 3.0
        let radius = d * q1 * q2 / (q2 * q2 - q1 * q1)
        // Its centre lies beyond the weaker charge, away from the stronger.
        let centre = weak.position + SIMD3(-d * q1 * q1 / (q2 * q2 - q1 * q1), 0, 0)
        for position in zero.positions {
            XCTAssertEqual(simd_length(SIMD3<Double>(position) - centre), radius, accuracy: 1e-5)
        }
    }
}
