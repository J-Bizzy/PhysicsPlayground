//
//  CircuitsInstrumentClearanceTests.swift
//  PhysicsPlaygroundTests
//
//  THE SECOND MODULE TO GET THE CLEARANCE CHECKS, which is the whole
//  point of having moved them out of Electric Fields.
//
//  `InstrumentClearance` was `FieldInstrumentLayout`'s private
//  arithmetic until 2026-08-08 — four rules that are true of any
//  instrument in any lab, available to exactly one of six modules. This
//  is the first new furniture placed anywhere else since, and it is
//  placed against the rules rather than against a screenshot.
//
//  WHY THAT MATTERS HERE SPECIFICALLY. Circuits' own comments record two
//  placements that a screenshot had to kill: the Clear plate went beside
//  the tray first and landed INSIDE a slab 0.93 m wide, with the slab's
//  own glass between the plate and the reader, and then half out of the
//  bottom of the frame. Both are arithmetic errors that arithmetic can
//  catch. The presets tab is the first thing in this module that did not
//  need a screenshot to find its spot.
//
//  Coordinates here are the module's own — Float offsets from
//  `CircuitsRenderer.benchPivot` — converted to the Double boxes the
//  shared checker speaks. The conversion is the test's job because the
//  module's placement predates the checker by a year and rewriting it
//  is not what this commit is for.
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

    /// The bench furniture, by name, at the sizes each primitive
    /// actually occupies including labels.
    ///
    /// The METER IS ABSENT and that is deliberate: it is a carried
    /// instrument, so it has no fixed place to be spaced against — the
    /// moment a hand moves it, any clearance computed here is fiction.
    /// The ΔV rail in Electric Fields is left out of that module's list
    /// for the same reason and says so.
    private var standingFurniture: [(name: String, box: StationBox)] {
        // Five plates at 0.066 pitch is 0.264 of column plus a plate's own
        // 0.05 — a 0.157 half-extent. Guessing 0.10 here is what made the
        // first placement look like it fitted.
        let fiveHigh = SIMD3<Double>(0.15, 0.157, 0.05)
        return [
            ("layers bank", box([-0.62, -0.06, 0.16], fiveHigh)),
            // Sized on the ARMED label — "Tap again" — because a
            // confirming plate grows when armed.
            ("clear plate", box([-1.02, -0.02, 0.10], SIMD3(0.13, 0.06, 0.08))),
            // The presets tab folded: one plate plus the summary line
            // hanging under it.
            ("presets tab", box([-1.02, 0.15, 0.10], SIMD3(0.09, 0.05, 0.05))),
            ("presets column", box([-1.02, 0.39, 0.10], fiveHigh)),
            // THE PARTS BLOCK. World coordinates, not bench-relative —
            // `CircuitsPartsLayout.rightSlot` places these absolutely, so
            // the box is built from the real slots rather than from an
            // offset that would drift if the bench moved.
            ("parts block", partsBlock),
        ]
    }

    /// Every well mouth as one box, measured from the layout itself.
    private var partsBlock: StationBox {
        // THE WINDOW, NOT THE WHOLE RACK. Only six slots are on screen
        // at once and the rack slides so the window stays put, so the
        // occupied volume is six rows however many parts exist. Measuring
        // all twelve would reserve half a metre of room nothing stands
        // in — and would fail the working-band check for furniture that
        // is never visible there.
        let slots = (0..<CircuitsPartsLayout.rightVisibleRows)
            .map { CircuitsPartsLayout.rightSlot(index: $0) }
        var lo = SIMD3<Double>(Double(slots[0].x), Double(slots[0].y),
                               Double(slots[0].z))
        var hi = lo
        for slot in slots {
            let p = SIMD3<Double>(Double(slot.x), Double(slot.y), Double(slot.z))
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        // Each mouth's own half-extents, as `Well` measures them.
        let mouth = SIMD3<Double>(0.06, 0.055, 0.06)
        return StationBox(center: (lo + hi) / 2,
                          halfExtents: (hi - lo) / 2 + mouth)
    }

    /// The bench's build volume — where a part can legally be dragged to,
    /// which is what furniture must not stand inside.
    private var buildVolume: StationBox {
        StationBox(center: CircuitsModel.buildCenter,
                   halfExtents: CircuitsModel.buildHalfExtents)
    }

    /// The four shared rules, over the bench's own furniture.
    ///
    /// MARGIN 0 RATHER THAN 0.12, and the reason is the interesting part.
    /// `stationMargin`'s default is Electric Fields'
    /// `resolveCharge(fallbackRadius:)`: there, a pinch on empty air
    /// within 12 cm of a charge grabs that charge, so an instrument any
    /// closer could be pinched at a point that is also a grab. Circuit
    /// Workshop has no such fallback — `nearestTerminal` only runs during
    /// a wire drag already in progress — so the number does not transfer
    /// even though the rule does. What remains true here is the weaker
    /// and still worth checking claim: furniture must not stand INSIDE
    /// the volume parts can be dragged into.
    ///
    /// The presets tab and its column are both listed even though the
    /// column only exists while the tab is open. A folded instrument that
    /// would overlap something when unfolded is still a bug; it just
    /// waits for a pinch. Same reasoning as sizing the Clear plate on its
    /// armed label.
    func testTheFurniturePlacedWithTheCheckerObeysIt() {
        let violations = InstrumentClearance.violations(
            instruments: standingFurniture, station: buildVolume, margin: 0)
        // The furniture ADDED with the checker in hand answers for
        // itself; the layers bank predates it — see
        // `testTheOlderBenchFurnitureStandsInsideTheBuildVolume`.
        //
        let mine = violations.filter {
            ($0.contains("presets") || $0.contains("parts block"))

        }
        XCTAssertTrue(mine.isEmpty, """
            The presets furniture breaks \(mine.count) of the shared rules:
            \(mine.joined(separator: "\n"))
            """)
    }

    /// The specific thing that was got wrong three times.
    ///
    /// First the tab sat INSIDE its own column, because a bank centres
    /// its plates on its anchor rather than stacking down from it. Then,
    /// moved above the layers bank, five plates over five plates pushed
    /// the tab past the 1.80 ceiling. Then the column was flipped to
    /// unfold UPWARD — grouping the tab with the Clear plate, after a
    /// screenshot showed the old height reading "on its own" — and this
    /// test failed, because it asserted the tab was ABOVE its column.
    ///
    /// DIRECTION IS NOT THE CLAIM. What must be true is that the tab and
    /// the column do not occupy each other, and that neither leaves the
    /// working band; which way the column opens is a layout decision the
    /// test has no business pinning. It said "above" only because that
    /// is how the first version happened to work.
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

    /// A FINDING, NOT A REGRESSION — recorded as a passing assertion of
    /// what is currently TRUE, so the number is on the record and moving
    /// the furniture will be a deliberate act rather than a surprise.
    ///
    /// The very first run of the shared checker against this module said
    /// the layers bank stands inside the bench's build volume, and it is
    /// right: `buildHalfExtents.x` is 0.70, so a part can be dragged to
    /// x = −0.70, while the bank spans −0.77…−0.47. A component parked at
    /// the bench's left edge is behind the bank's plates, and the plates
    /// carry colliders — which is the shielding failure this whole family
    /// of rules exists to prevent, sitting in the module all along.
    ///
    /// Not fixed here. Moving the layers bank is a visual change to a
    /// module the owner has not seen since, and it wants a screenshot,
    /// not a commit that also adds a feature.
    func testTheOlderBenchFurnitureStandsInsideTheBuildVolume() throws {
        let bank = try XCTUnwrap(
            standingFurniture.first { $0.name == "layers bank" }).box
        XCTAssertLessThan(bank.separation(from: buildVolume), 0, """
            The layers bank no longer overlaps the build volume. If that was \
            deliberate, delete this test — it exists only to keep a known \
            overlap on the record.
            """)
        // The presets column, placed with the checker, does NOT.
        let column = try XCTUnwrap(
            standingFurniture.first { $0.name == "presets column" }).box
        XCTAssertGreaterThan(column.separation(from: buildVolume), 0,
                             "the new furniture repeated the old mistake")
    }
}
