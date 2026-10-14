//
//  BackedLabelTests.swift
//  PhysicsPlaygroundTests
//
//  The dark plate behind an in-room number: it must wrap the glyphs (a
//  backing narrower than its text is worse than none) and must never be
//  a target. Assertions read the scene graph, not the inputs.
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

    // MARK: The rollout

    /// The Callout's plate must sit on the glyph run, not at
    /// pivot-minus-centre.
    func testCalloutBackingSitsOnTheGlyphRun() throws {
        let callout = Callout(color: .white)
        callout.setText("12.5 µT")

        let pivot = try XCTUnwrap(callout.root.children.first {
            $0.components[BillboardComponent.self] != nil
        }, "the callout lost its billboarded label pivot")
        let models = pivot.children.compactMap { $0 as? ModelEntity }
        XCTAssertEqual(models.count, 2, "a backed callout is a plate and its glyphs")
        guard models.count == 2 else { return }
        let plate = models[0]
        let glyphs = models[1]

        let bounds = try XCTUnwrap(glyphs.model).mesh.bounds
        // The glyph run's centre, in pivot space, must be the pivot…
        XCTAssertEqual(glyphs.position.x + (bounds.min.x + bounds.max.x) / 2, 0,
                       accuracy: 1e-5)
        XCTAssertEqual(glyphs.position.y + (bounds.min.y + bounds.max.y) / 2, 0,
                       accuracy: 1e-5)
        // …and the plate must sit exactly there, not off by the shift.
        XCTAssertEqual(plate.position.x, 0, accuracy: 1e-5,
                       "the plate is off the text by the centring shift — "
                       + "it was parented to the shifted glyph model again")
        XCTAssertEqual(plate.position.y, 0, accuracy: 1e-5)
    }


    // MARK: The 8 Hz limit

    /// Clearing is never rate-limited: an empty string means the subject is
    /// gone, and a throttled clear leaves a reading describing nothing.
    func testClearingACalloutIsNotRateLimited() {
        let callout = Callout(color: .white)
        // Measured against the callout's own empty state rather than
        // zero: the root also carries a leader line, which is furniture
        // and is not what "cleared" is about.
        let empty = countModelEntities(under: callout.root)

        callout.setText("12.5 µT")
        let labelled = countModelEntities(under: callout.root)
        XCTAssertGreaterThan(labelled, empty,
                             "nothing was built, so the clear proves nothing")

        // Immediately — well inside the 125 ms window.
        callout.setText("")
        XCTAssertEqual(countModelEntities(under: callout.root), empty,
                       "a callout whose subject vanished kept describing it")
    }

    private func countModelEntities(under entity: Entity) -> Int {
        var count = entity is ModelEntity && (entity as? ModelEntity)?.model != nil
            ? 1 : 0
        for child in entity.children {
            count += countModelEntities(under: child)
        }
        return count
    }

    private final class ValueBox {
        var value: Double = 20
    }
}
