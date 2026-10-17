//
//  FieldEquipotentialTests.swift
//  PhysicsPlaygroundTests
//
//  Electric Fields' equipotential shells as the lab draws them: off in the
//  opening room; equal steps of potential on a 1-2-5 ladder, the three inner
//  surfaces round every sign present and the 0 V surface between opposite
//  charges; the coarse grid while charges move and the fine one once they
//  are still, both exact where they have vertices; and the in-place mesh
//  that draws them, which drops whole shells, never parts of one.
//

import XCTest
import PhysicsCore
import RealityKit
import RenderKit
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

    /// The opening dipole: three surfaces round each charge — two, three and
    /// four steps out — and the 0 V plane between them, all at whole
    /// multiples of one step.
    func testTheOpeningDipoleGetsThreeShellsEachSideAndZeroVolts() {
        let model = FieldModel()
        let ladder = FieldModel.equipotentialLevels(model.charges)
        XCTAssertEqual(ladder.levels.count, 7)
        XCTAssertTrue(ladder.levels.contains(0))
        XCTAssertEqual(ladder.levels.filter { $0 > 0 }.sorted(), [2, 3, 4].map { $0 * ladder.step })
        XCTAssertEqual(ladder.levels.filter { $0 < 0 }.count, 3)
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

    /// What the renderer meshes for the opening room: the three closed
    /// shells round each charge, within the budget, and NOT the 0 V plane
    /// between them — infinite for equal and opposite charges, so the box
    /// would cut it into a flat pane.
    func testTheOpeningDipoleDrawsItsSixShellsAndNoPane() {
        let model = FieldModel()
        let meshes = FieldRenderer.shellMeshes(model.charges, region: model.samplingRegion)
        XCTAssertEqual(meshes.count, 6, "a shell was dropped, or the cut 0 V plane drawn")
        XCTAssertFalse(meshes.contains { $0.level == 0 })
        XCTAssertLessThanOrEqual(meshes.map(\.triangleCount).reduce(0, +),
                                 FieldRenderer.shellTriangleBudget)
    }

    // MARK: Cheap while moving, fine when still

    /// The coarse grid the moment the charges move, the fine one once they
    /// have been still a quarter of a second, nothing while they rest
    /// meshed, and the fine one at once when the shells are switched on.
    func testTheShellsMeshCoarseWhileMovingAndFineWhenStill() {
        let fine = FieldRenderer.shellResolution, coarse = FieldRenderer.movingShellResolution
        XCTAssertLessThan(coarse, fine)
        XCTAssertEqual(FieldRenderer.shellResolution(changed: false, firstShow: true,
                                                     stillFor: 0, fineDone: false), fine)
        XCTAssertEqual(FieldRenderer.shellResolution(changed: true, firstShow: false,
                                                     stillFor: 0, fineDone: true), coarse)
        XCTAssertNil(FieldRenderer.shellResolution(changed: false, firstShow: false,
                                                   stillFor: 0.1, fineDone: false),
                     "re-meshed fine while the hand was still moving")
        XCTAssertEqual(FieldRenderer.shellResolution(changed: false, firstShow: false,
                                                     stillFor: 0.3, fineDone: false), fine)
        XCTAssertNil(FieldRenderer.shellResolution(changed: false, firstShow: false,
                                                   stillFor: 5, fineDone: true),
                     "re-meshed a still room")
    }

    /// The coarse grid a drag shows is coarser between vertices, not wrong
    /// at them: every vertex still on its sphere r = kq/V. The charge sits
    /// exactly on a grid node here, which is what found the 0 V a charge
    /// reads at itself.
    func testACoarseShellIsStillExactAtItsVertices() {
        let charge = PointCharge(position: SIMD3(0, 1.35, -0.9), charge: 1e-6)
        let region = FieldModel.SamplingRegion(center: charge.position, extents: SIMD3(repeating: 1.3))
        let meshes = FieldRenderer.shellMeshes([charge], region: region,
                                               resolution: FieldRenderer.movingShellResolution)
        XCTAssertFalse(meshes.isEmpty)
        for mesh in meshes {
            let radius = ElectricField.k * charge.charge / mesh.level
            for position in mesh.positions {
                XCTAssertEqual(simd_length(SIMD3<Double>(position) - charge.position), radius,
                               accuracy: 1e-5)
            }
        }
    }

    /// At a charge the shells' potential is that charge's ceiling, not the
    /// 0 V `ElectricField` answers there.
    func testAChargeReadsItsCeilingAtItself() {
        let plus = PointCharge(position: SIMD3(0, 1, 0), charge: 1e-6)
        let minus = PointCharge(position: SIMD3(0.3, 1, 0), charge: -1e-6)
        XCTAssertEqual(FieldRenderer.shellPotential(at: plus.position, charges: [plus, minus], ceiling: 5), 5)
        XCTAssertEqual(FieldRenderer.shellPotential(at: minus.position, charges: [plus, minus], ceiling: 5), -5)
    }

    // MARK: The mesh they are drawn from

    /// One in-place mesh, a part per shell wearing its rank's material; a set
    /// that would overflow it keeps the shells that fit, whole.
    func testTheSurfaceMeshDropsWholeShellsNeverPartsOfOne() throws {
        let triangle = SurfaceMesh.Surface(positions: [[0, 0, 0], [1, 0, 0], [0, 1, 0]],
                                           normals: Array(repeating: [0, 0, 1], count: 3),
                                           indices: [0, 1, 2], material: 2)
        let surface = try XCTUnwrap(SurfaceMesh(vertexCapacity: 7, indexCapacity: 9,
                                                materials: [UnlitMaterial(), UnlitMaterial(), UnlitMaterial()]))
        surface.update([triangle, triangle])
        XCTAssertEqual(surface.drawn, 2)
        XCTAssertTrue(surface.entity.isEnabled)
        surface.update([triangle, triangle, triangle])
        XCTAssertEqual(surface.drawn, 2, "a third shell overflows the vertices; it goes whole")
        surface.update([])
        XCTAssertEqual(surface.drawn, 0)
        XCTAssertFalse(surface.entity.isEnabled)
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
