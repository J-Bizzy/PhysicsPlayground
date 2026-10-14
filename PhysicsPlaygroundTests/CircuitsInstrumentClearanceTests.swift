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

    /// The bench furniture, by name, at the sizes each primitive occupies
    /// including labels. The meter is absent: it is carried, so any
    /// clearance computed for it is fiction the moment a hand moves it.
    /// Since 2026-10-14 the shelf is the only standing furniture: the
    /// Views tab, the Clear plate and the Presets tab moved into More.
    private var standingFurniture: [(name: String, box: StationBox)] {
        [
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



}
