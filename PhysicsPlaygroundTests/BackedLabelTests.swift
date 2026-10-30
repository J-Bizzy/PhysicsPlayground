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

    /// A backed label is a plate and a glyph run (`GlyphRun`, since
    /// 2026-10-20: one line set from cached glyphs, not a mesh per string).
    private func parts(of label: BackedLabel) -> (plate: ModelEntity, run: Entity)? {
        let children = label.root.children
        guard children.count == 2,
              let plate = children.first(where: { ($0 as? ModelEntity)?.model != nil }) as? ModelEntity,
              let run = children.first(where: { $0 !== plate }) else { return nil }
        return (plate, run)
    }

    func testThePlateWrapsTheGlyphs() throws {
        let label = BackedLabel(size: 0.02)
        label.setText("12.5 V", color: .white)

        let (plate, run) = try XCTUnwrap(parts(of: label), "a backed label is a plate and its glyphs")
        let plateExtents = plate.visualBounds(relativeTo: label.root).extents
        let glyphBounds = run.visualBounds(relativeTo: label.root)
        XCTAssertGreaterThan(plateExtents.x, glyphBounds.extents.x,
                             "the plate must be wider than the text it carries")
        XCTAssertGreaterThan(plateExtents.y, glyphBounds.extents.y,
                             "the plate must be taller than the text it carries")
        XCTAssertLessThan(plate.position.z, glyphBounds.min.z,
                          "darkness sits behind the light, never over it")
    }

    /// A new reading moves glyphs: nothing is generated for it, and the
    /// run and the plate are the same entities before and after.
    func testANewReadingReusesItsGlyphsAndPlate() throws {
        let label = BackedLabel(size: 0.02)
        label.setText("12.5 V", color: .white)
        let before = try XCTUnwrap(parts(of: label))
        // Past the 8 Hz limit, as a live reading would be.
        Thread.sleep(forTimeInterval: 0.13)
        label.setText("12.8 V", color: .white)
        let after = try XCTUnwrap(parts(of: label))
        XCTAssertTrue(before.plate === after.plate)
        XCTAssertTrue(before.run === after.run)
    }

    /// A reading whose width moves by a digit keeps the plate it has — a
    /// new width was a mesh generated on the main thread, eight times a
    /// second — and one that outgrows it gets a wider one, never a plate
    /// narrower than its text.
    func testALiveReadingKeepsItsPlateUntilItOutgrowsIt() throws {
        let label = BackedLabel(size: 0.02)
        label.setText("7.4 m/s", color: .white)
        let first = try XCTUnwrap(parts(of: label)?.plate.model?.mesh)
        Thread.sleep(forTimeInterval: 0.13)
        label.setText("7.1 m/s", color: .white)
        XCTAssertTrue(parts(of: label)?.plate.model?.mesh === first,
                      "a digit's change of width made a new plate")
        Thread.sleep(forTimeInterval: 0.13)
        label.setText("17.1 m/s · 32°", color: .white)
        let (plate, run) = try XCTUnwrap(parts(of: label))
        XCTAssertFalse(plate.model?.mesh === first)
        XCTAssertGreaterThan(plate.visualBounds(relativeTo: label.root).extents.x,
                             run.visualBounds(relativeTo: label.root).extents.x)
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
        XCTAssertEqual(pivot.children.count, 2, "a backed callout is a plate and its glyphs")
        let plate = try XCTUnwrap(pivot.children.first { ($0 as? ModelEntity)?.model != nil })
        let run = try XCTUnwrap(pivot.children.first { $0 !== plate })

        let bounds = run.visualBounds(relativeTo: pivot)
        // The glyph run's centre, in pivot space, must be the pivot…
        XCTAssertEqual((bounds.min.x + bounds.max.x) / 2, 0, accuracy: 1e-5)
        XCTAssertEqual((bounds.min.y + bounds.max.y) / 2, 0, accuracy: 1e-5)
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

    /// A readout with line breaks stands its lines one over another, as
    /// the whole-string mesh did — not run together on one line.
    func testALineBreakStartsANewLine() {
        let oneLine = GlyphRun(size: 0.02, color: .white).set("Caught 2.31 m/s")
        let twoLines = GlyphRun(size: 0.02, color: .white).set("Caught\n2.31 m/s")
        XCTAssertGreaterThan(twoLines.extents.y, oneLine.extents.y * 1.6,
                             "the second line stands under the first")
        XCTAssertLessThan(twoLines.extents.x, oneLine.extents.x * 0.75,
                          "two short lines are narrower than one long one")
        XCTAssertEqual(twoLines.center.x, 0, accuracy: 1e-4, "centred on the run")
    }

    private final class ValueBox {
        var value: Double = 20
    }
}
