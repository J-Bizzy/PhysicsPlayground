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

    // MARK: The 2026-08-06 rollout

    /// The Callout's plate must sit ON the glyph run. The first wiring
    /// parented the plate to the CENTRE-SHIFTED glyph model, so it
    /// landed at pivot-minus-centre — off the text by exactly the
    /// centring shift. Latent while the flag was off; pinned here the
    /// day the default flipped.
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

    /// The rail's value plate is replaced across value changes, never
    /// accumulated — a rail that is dragged all day must not stack a
    /// hundred plates behind its number.
    func testRailValuePlateIsReplacedNotAccumulated() {
        let box = ValueBox()
        let track = SpatialTrackControl(
            name: "Test", center: .zero, normal: [0, 0, 1], accent: .white,
            range: 0...100, layout: TrackLayout(length: 0.26),
            read: { box.value }, write: { box.value = $0 },
            format: { String(format: "%.0f", $0) })

        func plateCount() -> Int {
            var count = 0
            func walk(_ entity: Entity) {
                if let model = entity as? ModelEntity,
                   model.model?.mesh.bounds.extents.z ?? 1 < 0.001,
                   model.components[CollisionComponent.self] == nil,
                   entity.name.isEmpty {
                    count += 1
                }
                entity.children.forEach(walk)
            }
            walk(track.root)
            return count
        }

        track.refresh()
        let first = plateCount()
        XCTAssertGreaterThan(first, 0, "the rail's number never got its plate")
        for value in [10.0, 55.0, 90.0] {
            box.value = value
            track.refresh()
        }
        XCTAssertEqual(plateCount(), first,
                       "value changes accumulated plates instead of replacing one")
    }

    private final class ValueBox {
        var value: Double = 20
    }
}
