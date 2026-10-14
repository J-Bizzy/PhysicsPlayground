//
//  PlacementDragTests.swift
//  PhysicsPlaygroundTests
//
//  The lab anchor and the gallery bar are the same interaction twice: a
//  `RelativeDrag` on a placement offset, with a press that never moves
//  folded into the same recogniser as a tap that recentres. Both once
//  measured travel against a reference the next line overwrote, so only
//  one frame's displacement was compared to the tap threshold and a
//  careful placement snapped home on release. These replay the real
//  frame loop at speeds a hand actually moves at.
//

import XCTest
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class PlacementDragTests: XCTestCase {

    /// A frame rate and the threshold both call sites use.
    private let frameRate = 90.0
    private let tapTravel: Float = 0.012

    /// Replays a press: `frames` frames of hand motion at `speed`,
    /// accumulating travel exactly as the gesture handlers do, and
    /// returns what they would test against the tap threshold.
    private func replay(speed: Double, frames: Int,
                        into placement: LabPlacement) -> Float {
        let start = SIMD3<Double>(0, 1.1, -0.8)
        let drag = RelativeDrag(name: "lab-anchor",
                                target: SIMD3<Double>(placement.offset),
                                hand: start)
        var travelled: Float = 0
        for frame in 1...frames {
            let hand = start + SIMD3(speed * Double(frame) / frameRate, 0, 0)
            let next = SIMD3<Float>(drag.position(forHand: hand))
            travelled = max(travelled, Float(drag.travel(forHand: hand)))
            placement.move(to: next)
        }
        return travelled
    }

    // MARK: The defect

    /// 0.3 m/s for two seconds must not read as a tap; the old arithmetic
    /// returned one frame's travel, a quarter of the threshold.
    func testANormalSpeedPlacementIsNotReadAsATap() {
        let placement = LabPlacement()
        placement.adopt(moduleID: "test-normal-speed")
        defer { UserDefaults.standard.removeObject(forKey: "labOffset.test-normal-speed") }

        let travelled = replay(speed: 0.3, frames: 180, into: placement)

        XCTAssertGreaterThan(
            travelled, tapTravel,
            "a 60 cm placement at 0.3 m/s measured \(travelled) m of travel — "
            + "under the \(tapTravel) m threshold this takes the tap branch "
            + "and recentres, discarding the drag")
        XCTAssertEqual(Double(travelled), 0.6, accuracy: 0.01,
                       "travel must be the DRAG's distance, not a frame's")
        XCTAssertEqual(Double(placement.offset.x), 0.6, accuracy: 0.01,
                       "the lab did not end up where it was carried")
    }

    /// Slower still. There is no lower speed at which a real drag may be
    /// mistaken for a press, because a press is defined by distance.
    func testEvenAVerySlowDragSurvives() {
        let placement = LabPlacement()
        placement.adopt(moduleID: "test-slow")
        defer { UserDefaults.standard.removeObject(forKey: "labOffset.test-slow") }

        // 5 cm/s for three seconds: 15 cm, nudging apparatus off a table.
        let travelled = replay(speed: 0.05, frames: 270, into: placement)
        XCTAssertGreaterThan(travelled, tapTravel)
        XCTAssertEqual(Double(placement.offset.x), 0.15, accuracy: 0.005)
    }

    // MARK: The verb the discriminator exists for

    /// A press that never moves is still a tap, and must stay one — the
    /// fix must not cost the recentre verb, which has no other door.
    func testAHeldStillPressIsStillATap() {
        let placement = LabPlacement()
        placement.adopt(moduleID: "test-still")
        defer { UserDefaults.standard.removeObject(forKey: "labOffset.test-still") }

        // A hand held still in mid-air drifts a few millimetres.
        let travelled = replay(speed: 0.004, frames: 90, into: placement)
        XCTAssertLessThan(travelled, tapTravel,
                          "a still hand read as a drag — recentre becomes "
                          + "unreachable")
    }

    /// A press that wanders out and comes back is a drag, not a tap: the
    /// user moved the thing and put it back, and recentring on top of
    /// that would throw away a deliberate act. This is why the
    /// accumulator is a running `max` rather than a final distance.
    func testAnOutAndBackDragIsNotATap() {
        let start = SIMD3<Double>.zero
        let drag = RelativeDrag(name: "lab-anchor", target: .zero, hand: start)
        var travelled: Float = 0
        for frame in 0...180 {
            let phase = Double(frame) / 180 * 2 * .pi
            let hand = start + SIMD3(0.25 * sin(phase), 0, 0)
            travelled = max(travelled, Float(drag.travel(forHand: hand)))
        }
        XCTAssertGreaterThan(travelled, tapTravel)
        XCTAssertEqual(Double(travelled), 0.25, accuracy: 0.01,
                       "the running max should hold the furthest point reached")
    }

    // MARK: The primitive

    /// `travel` is measured from where the drag picked the object up,
    /// which is the one reference in the loop that nothing rewrites.
    func testTravelIsMeasuredFromWhereTheDragStarted() {
        let drag = RelativeDrag(name: "x",
                                target: SIMD3(1, 2, 3),
                                hand: SIMD3(10, 10, 10))
        XCTAssertEqual(drag.travel(forHand: SIMD3(10, 10, 10)), 0, accuracy: 1e-12)
        XCTAssertEqual(drag.travel(forHand: SIMD3(10.4, 10, 10)), 0.4, accuracy: 1e-12)
        XCTAssertEqual(drag.travel(forHand: SIMD3(10, 10.3, 10.4)), 0.5, accuracy: 1e-12)
    }

    // MARK: Persistence

    private func saved(_ moduleID: String) -> [Double]? {
        UserDefaults.standard.array(forKey: "labOffset.\(moduleID)") as? [Double]
    }

    /// A drag is one write, not ninety a second: `move(to:)` runs once per
    /// frame, so the write is debounced and the drag's end flushes it.
    func testAWholeDragCollapsesIntoOneWriteAtTheEnd() {
        let id = "test-debounce"
        UserDefaults.standard.removeObject(forKey: "labOffset.\(id)")
        defer { UserDefaults.standard.removeObject(forKey: "labOffset.\(id)") }

        let placement = LabPlacement()
        placement.adopt(moduleID: id)

        _ = replay(speed: 0.3, frames: 180, into: placement)
        XCTAssertNil(saved(id),
                     "180 drag frames wrote the defaults database before the "
                     + "drag had even finished")

        placement.endMove()
        let written = try? XCTUnwrap(saved(id))
        XCTAssertEqual(written?.count, 3)
        XCTAssertEqual(written?[0] ?? 0, 0.6, accuracy: 0.01,
                       "the flush wrote something other than where the lab "
                       + "was actually carried to")
    }

    /// Recentring is a discrete act, so it writes immediately — a tap
    /// has no "end of drag" to flush it later.
    func testRecentreWritesStraightAway() {
        let id = "test-recentre"
        UserDefaults.standard.removeObject(forKey: "labOffset.\(id)")
        defer { UserDefaults.standard.removeObject(forKey: "labOffset.\(id)") }

        let placement = LabPlacement()
        placement.adopt(moduleID: id)
        _ = replay(speed: 0.3, frames: 60, into: placement)
        placement.recentre()

        XCTAssertEqual(saved(id) ?? [], [0, 0, 0])
    }

    /// Switching labs flushes the old one first: `persistNow` reads
    /// `moduleID` when it runs, so a pending write carried across a switch
    /// would file the old lab's offset under the new lab's key.
    func testSwitchingModulesFlushesThePreviousLabsPlacement() {
        let first = "test-switch-a", second = "test-switch-b"
        for id in [first, second] {
            UserDefaults.standard.removeObject(forKey: "labOffset.\(id)")
        }
        defer {
            for id in [first, second] {
                UserDefaults.standard.removeObject(forKey: "labOffset.\(id)")
            }
        }

        let placement = LabPlacement()
        placement.adopt(moduleID: first)
        _ = replay(speed: 0.3, frames: 180, into: placement)

        // Switch away mid-debounce, exactly as leaving a lab does.
        placement.adopt(moduleID: second)

        XCTAssertEqual((saved(first) ?? [0])[0], 0.6, accuracy: 0.01,
                       "the first lab's placement was lost on the way out")
        XCTAssertNil(saved(second),
                     "the first lab's offset was filed under the second "
                     + "lab's key")
        XCTAssertEqual(placement.offset, .zero,
                       "the second lab opened with the first one's offset")
    }
}
