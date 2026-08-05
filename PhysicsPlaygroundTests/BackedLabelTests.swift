//
//  BackedLabelTests.swift
//  PhysicsPlaygroundTests
//
//  The dark plate behind an in-room number (2026-08-05, staged into
//  Circuits first). Two claims worth pinning, both learned elsewhere:
//
//  · The plate must WRAP the glyphs — a backing narrower than its text
//    is worse than none, because the contrast edge lands mid-numeral.
//    The nameplate's padding arithmetic already failed once by being
//    fixed instead of scaling with the type; these read the built
//    meshes, not the formula.
//  · The backing is decoration and must never be a target — a readout
//    that intercepts a pinch is `SpatialScaleHandle` again.
//
//  Assertions read the scene graph, not the inputs it was built from
//  (the Multimeter's first probe test passed against the bug it was
//  written to catch by asserting on a variable).
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class BackedLabelTests: XCTestCase {

    func testThePlateWrapsTheGlyphs() {
        let label = BackedLabel(size: 0.02)
        label.setText("12.5 V", color: .white)

        let models = label.root.children.compactMap { $0 as? ModelEntity }
        XCTAssertEqual(models.count, 2, "a backed label is a plate and its glyphs")
        guard models.count == 2 else { return }
        let plate = models[0]
        let glyphs = models[1]

        let plateExtents = plate.model?.mesh.bounds.extents ?? .zero
        let glyphExtents = glyphs.model?.mesh.bounds.extents ?? .zero
        XCTAssertGreaterThan(plateExtents.x, glyphExtents.x,
                             "the plate must be wider than the text it carries")
        XCTAssertGreaterThan(plateExtents.y, glyphExtents.y,
                             "the plate must be taller than the text it carries")
        XCTAssertLessThan(plate.position.z, glyphs.position.z,
                          "darkness sits behind the light, never over it")
    }

    func testTheBackingIsNeverATarget() {
        let label = BackedLabel(size: 0.03)
        label.setText("3.3 V", color: .white)
        for entity in label.root.children {
            XCTAssertNil(entity.components[CollisionComponent.self],
                         "a readout that intercepts a pinch is SpatialScaleHandle again")
            XCTAssertNil(entity.components[InputTargetComponent.self])
        }
    }

    func testEmptyTextClearsTheLabelEntirely() {
        let label = BackedLabel(size: 0.02)
        label.setText("open", color: .white)
        XCTAssertFalse(label.root.children.isEmpty)
        label.setText("", color: .white)
        XCTAssertTrue(label.root.children.isEmpty,
                      "an empty reading leaves no orphaned plate floating in the room")
    }
}
