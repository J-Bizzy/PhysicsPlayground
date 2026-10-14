//
//  CircuitsInstrumentClearanceTests.swift
//  PhysicsPlaygroundTests
//
//  The bench's furniture against the shared clearance rules
//  (`InstrumentClearance`), placed by arithmetic rather than by
//  screenshot. Coordinates are the module's own Float offsets from
//  `CircuitsRenderer.benchPivot`, converted to the checker's boxes.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsInstrumentClearanceTests: XCTestCase {

    private func box(_ offset: SIMD3<Float>,
                     _ halfExtents: SIMD3<Double>) -> StationBox {
        let world = CircuitsRenderer.benchPivot + offset
        return StationBox(center: SIMD3(Double(world.x), Double(world.y),
                                        Double(world.z)),
                          halfExtents: halfExtents)
    }

    /// The bench furniture, by name, at the sizes each primitive occupies
    /// including labels. The meter is absent: it is carried, so any
    /// clearance computed for it is fiction the moment a hand moves it.
    private var standingFurniture: [(name: String, box: StationBox)] {
        // Five plates at 0.066 pitch plus a plate's own height — a 0.157
        // half-extent.
        let fiveHigh = SIMD3<Double>(0.15, 0.157, 0.05)
        return [
            // The Views tab and the column it unfolds above itself, both from the
            // view's own constants, so a move there is a move here.
            ("views tab", StationBox(
                center: SIMD3<Double>(CircuitsSpaceView.bankAnchor),
                halfExtents: SIMD3(0.09, 0.05, 0.05))),
            ("views column", StationBox(
                center: SIMD3<Double>(CircuitsSpaceView.viewsColumnAnchor),
                halfExtents: fiveHigh)),
            // Sized on the armed label — "Tap again" — because a
            // confirming plate grows when armed.
            ("clear plate", box([-1.02, -0.02, 0.10], SIMD3(0.13, 0.06, 0.08))),
            // The presets tab folded: one plate plus the summary line
            // hanging under it.
            ("presets tab", box([-1.02, 0.15, 0.10], SIMD3(0.09, 0.05, 0.05))),
            ("presets column", box([-1.02, 0.39, 0.10], fiveHigh)),
            // The parts block, in world coordinates: `CircuitsPartsLayout.rightSlot`
            // places the slots absolutely.
            ("parts block", partsBlock),
        ]
    }

    /// Every well mouth as one box, measured from the layout itself.
    private var partsBlock: StationBox {
        // The window, not the whole shelf: only `rightVisibleRows` slots are on
        // screen and the strip slides so the window stays put.
        let slots = (0..<CircuitsPartsLayout.rightVisibleRows)
            .map { CircuitsPartsLayout.rightSlot(index: $0) }
        var lo = SIMD3<Double>(Double(slots[0].x), Double(slots[0].y),
                               Double(slots[0].z))
        var hi = lo
        // Each mouth's own half-extents, as `Well` measures them.
        let mouth = SIMD3<Double>(0.06, 0.055, 0.06)
        for slot in slots {
            let p = SIMD3<Double>(Double(slot.x), Double(slot.y), Double(slot.z))
            lo = simd_min(lo, p - mouth)
            hi = simd_max(hi, p + mouth)
        }
        // And the spine beside the column with the crown on it, faced at
        // the viewer as `CircuitsSpaceView` faces it.
        let track = Well.Rack.track(head: slots[0],
                                    pitch: CircuitsPartsLayout.rightRowPitch,
                                    visible: CircuitsPartsLayout.rightVisibleRows,
                                    facing: CircuitsPartsLayout.viewer)
        lo = simd_min(lo, SIMD3<Double>(track.center - track.halfExtents))
        hi = simd_max(hi, SIMD3<Double>(track.center + track.halfExtents))
        let crown = Well.Rack.crown(head: slots[0],
                                    pitch: CircuitsPartsLayout.rightRowPitch,
                                    visible: CircuitsPartsLayout.rightVisibleRows,
                                    facing: CircuitsPartsLayout.viewer)
        lo = simd_min(lo, SIMD3<Double>(crown.center - crown.halfExtents))
        hi = simd_max(hi, SIMD3<Double>(crown.center + crown.halfExtents))
        return StationBox(center: (lo + hi) / 2, halfExtents: (hi - lo) / 2)
    }

    /// The bench's build volume — where a part can legally be dragged to,
    /// which is what furniture must not stand inside.
    private var buildVolume: StationBox {
        StationBox(center: CircuitsModel.buildCenter,
                   halfExtents: CircuitsModel.buildHalfExtents)
    }

    /// The four shared rules over the bench's own furniture. Margin 0 rather
    /// than 0.12: Circuit Workshop has no proximity-fallback grab, so what
    /// remains is the weaker claim that furniture must not stand inside the
    /// volume parts can be dragged into. Folded columns are listed too: a
    /// folded instrument that would overlap something when unfolded is
    /// still a bug.
    func testTheFurniturePlacedWithTheCheckerObeysIt() {
        let violations = InstrumentClearance.violations(
            instruments: standingFurniture, station: buildVolume, margin: 0)
        // The furniture placed with the checker answers for itself; the Clear
        // plate predates it and stands 53.7° off axis by the owner's layout.
        let mine = violations.filter {
            $0.contains("presets") || $0.contains("parts block")
                || $0.contains("views")
        }
        XCTAssertTrue(mine.isEmpty, """
            The bench furniture breaks \(mine.count) of the shared rules:
            \(mine.joined(separator: "\n"))
            """)
    }

    /// The tab and its column must not occupy each other, and neither may
    /// leave the working band. Direction is not the claim: which way the
    /// column opens is a layout decision the test has no business pinning.
    func testThePresetsTabAndItsColumnDoNotOccupyEachOther() throws {
        let all = standingFurniture
        let tab = try XCTUnwrap(all.first { $0.name == "presets tab" }).box
        let column = try XCTUnwrap(all.first { $0.name == "presets column" }).box

        XCTAssertGreaterThanOrEqual(
            tab.separation(from: column), InstrumentClearance.separation,
            "the tab is inside the column it opens")
        for (name, box) in [("tab", tab), ("column", column)] {
            XCTAssertLessThan(box.maximum.y,
                              InstrumentClearance.workingHeight.upperBound,
                              "the presets \(name) is above a comfortable reach")
            XCTAssertGreaterThan(box.minimum.y,
                                 InstrumentClearance.workingHeight.lowerBound,
                                 "the presets \(name) hangs too low to use")
        }
    }

    /// And the column must clear the Clear plate it stands above.
    func testTheUnfoldedPresetsColumnClearsTheClearPlate() throws {
        let all = standingFurniture
        let column = try XCTUnwrap(all.first { $0.name == "presets column" }).box
        let clear = try XCTUnwrap(all.first { $0.name == "clear plate" }).box
        XCTAssertGreaterThanOrEqual(column.separation(from: clear),
                                    InstrumentClearance.separation)
    }

    /// The Views tab and its column stand clear of the build volume — the
    /// finding the old five-plate bank recorded as an overlap of 0.13 m,
    /// closed by folding the bank behind a tab.
    func testTheViewsFurnitureStandsClearOfTheBuildVolume() throws {
        let tab = try XCTUnwrap(
            standingFurniture.first { $0.name == "views tab" }).box
        let column = try XCTUnwrap(
            standingFurniture.first { $0.name == "views column" }).box
        XCTAssertGreaterThan(tab.separation(from: buildVolume), 0,
                             "the Views tab stands inside the build volume")
        XCTAssertGreaterThan(column.separation(from: buildVolume), 0,
                             "the unfolded Views column reaches into the build volume")
        XCTAssertGreaterThanOrEqual(
            tab.separation(from: column), InstrumentClearance.separation,
            "the Views tab is inside the column it opens")
        // Inside the frame, unlike the fore column: the rack's own rule.
        let degrees = atan2(abs(tab.center.x), -tab.center.z) * 180 / .pi
        XCTAssertLessThanOrEqual(degrees, Double(CircuitsPartsLayout.maximumOffAxisAngle),
                                 "the Views tab stands past the off-axis limit")
        // The presets column, placed with the checker, does not either.
        let presets = try XCTUnwrap(
            standingFurniture.first { $0.name == "presets column" }).box
        XCTAssertGreaterThan(presets.separation(from: buildVolume), 0,
                             "the new furniture repeated the old mistake")
    }
}
