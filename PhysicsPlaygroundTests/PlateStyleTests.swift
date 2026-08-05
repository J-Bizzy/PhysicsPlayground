//
//  PlateStyleTests.swift
//  PhysicsPlaygroundTests
//
//  The two banks share one plate silhouette by construction now
//  (`PlateStyle`, 2026-08-05) — the corner radius was deliberately
//  matched from the start, but the depths had drifted (0.007 vs 0.009
//  thick) because each file typed its own numbers on a different day.
//  Asserting `PlateStyle.depth == 0.009` would be vacuous; what matters
//  is what the banks BUILD, so this reads the constructed plate meshes
//  — the scene graph, not the constants they were supposed to come from.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class PlateStyleTests: XCTestCase {

    func testBothBanksBuildTheSamePlateSilhouette() throws {
        let layerBank = SpatialLayerBank(
            accent: .white,
            layers: [LayerSwitch(id: "grid", label: "Grid",
                                 isOn: { true }, toggle: {})])
        let actionBank = SpatialActionBank(
            accent: .white,
            actions: [.init(id: "clear", label: "Clear", symbol: "trash.slash",
                            isAvailable: { true }, confirms: false, fire: {})])
        for _ in 0..<40 {
            layerBank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0)
            actionBank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1.0 / 90.0)
        }

        let layerPlate = try XCTUnwrap(
            layerBank.root.children.first { $0.name == "layer-grid" } as? ModelEntity)
        let actionPlate = try XCTUnwrap(
            actionBank.root.children.first { $0.name == "action-clear" } as? ModelEntity)

        let layerExtents = try XCTUnwrap(layerPlate.model).mesh.bounds.extents
        let actionExtents = try XCTUnwrap(actionPlate.model).mesh.bounds.extents

        XCTAssertEqual(layerExtents.x, actionExtents.x, accuracy: 1e-5,
                       "the two banks' plates differ in width")
        XCTAssertEqual(layerExtents.y, actionExtents.y, accuracy: 1e-5,
                       "the two banks' plates differ in height")
        XCTAssertEqual(layerExtents.z, actionExtents.z, accuracy: 1e-5,
                       "the two banks' plates differ in thickness — the exact "
                       + "drift PlateStyle exists to close")
    }
}
