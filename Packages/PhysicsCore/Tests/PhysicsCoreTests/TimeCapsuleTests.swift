//
//  TimeCapsuleTests.swift
//  PhysicsCoreTests
//
//  The ring buffer behind the Time Capsule scrubber. Two claims the
//  feature stands on are proved here rather than assumed: memory is
//  bounded (by time window and by a hard frame cap), and a lookup always
//  returns an exactly-recorded frame — clamped at the ends, never
//  interpolated, never fabricated.
//

import XCTest
@testable import PhysicsCore

final class TimeCapsuleTests: XCTestCase {

    /// Frames older than the window are evicted as recording advances.
    func testEvictsByTimeWindow() {
        var capsule = TimeCapsule<Int>(window: 1.0, expectedRate: 100)
        for i in 0...200 {
            capsule.record(i, at: Double(i) * 0.01)
        }
        let span = try! XCTUnwrap(capsule.span)
        XCTAssertEqual(span.upperBound, 2.0, accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(span.lowerBound, 1.0 - 1e-12)
        // The whole kept window is still there, not just its ends.
        XCTAssertGreaterThanOrEqual(capsule.count, 99)
    }

    /// Recording faster than expectedRate can never exceed the frame cap —
    /// the hard memory guarantee.
    func testHardCapacityBound() {
        var capsule = TimeCapsule<Int>(window: 1.0, expectedRate: 50)
        XCTAssertEqual(capsule.capacity, 50)
        // 1000 frames inside one window: time eviction never fires.
        for i in 0..<1000 {
            capsule.record(i, at: Double(i) * 0.0001)
            XCTAssertLessThanOrEqual(capsule.count, 50)
        }
        XCTAssertEqual(capsule.count, 50)
        XCTAssertEqual(capsule.newest()?.snapshot, 999)
        // The survivors are the newest 50, in order.
        XCTAssertEqual(capsule.frame(at: 0.0)?.snapshot, 950)
    }

    /// After wrapping the circular storage several times over, ordering
    /// and lookup still hold.
    func testLookupSurvivesWraparound() {
        var capsule = TimeCapsule<Int>(window: 0.5, expectedRate: 60)
        for i in 0..<500 {
            capsule.record(i, at: Double(i) * 0.01)
        }
        let span = try! XCTUnwrap(capsule.span)
        XCTAssertEqual(span.upperBound, 4.99, accuracy: 1e-12)
        XCTAssertEqual(capsule.newest()?.snapshot, 499)
        // An interior lookup lands on the exact recorded frame.
        let frame = try! XCTUnwrap(capsule.frame(at: 4.755))
        XCTAssertEqual(frame.snapshot, 475)
        XCTAssertEqual(frame.time, 4.75, accuracy: 1e-12)
        // Times are strictly increasing across the whole buffer.
        let all = capsule.frames(in: span)
        for pair in zip(all, all.dropFirst()) {
            XCTAssertLessThan(pair.0.time, pair.1.time)
        }
    }

    /// A lookup between two recorded frames returns the earlier one —
    /// never an interpolation, which for stepped simulations would be a
    /// state that never happened.
    func testLookupLandsOnRecordedFramesOnly() {
        var capsule = TimeCapsule<Int>(window: 10)
        capsule.record(0, at: 0.0)
        capsule.record(1, at: 0.1)
        capsule.record(2, at: 0.2)
        XCTAssertEqual(capsule.frame(at: 0.1999)?.snapshot, 1)
        XCTAssertEqual(capsule.frame(at: 0.1)?.snapshot, 1)
        // Before the span clamps to oldest, after it to newest.
        XCTAssertEqual(capsule.frame(at: -5)?.snapshot, 0)
        XCTAssertEqual(capsule.frame(at: 99)?.snapshot, 2)
        XCTAssertNil(TimeCapsule<Int>(window: 10).frame(at: 0))
    }

    /// Resume-from-scrubbed-instant: everything after the scrub point is
    /// discarded, and recording continues cleanly from there.
    func testTruncateThenContinueRecording() {
        var capsule = TimeCapsule<Int>(window: 10)
        for i in 0..<100 {
            capsule.record(i, at: Double(i) * 0.1)
        }
        capsule.truncate(after: 4.55)
        XCTAssertEqual(capsule.newest()?.snapshot, 45)
        XCTAssertEqual(capsule.span?.upperBound ?? -1, 4.5, accuracy: 1e-12)
        capsule.record(999, at: 4.6)
        XCTAssertEqual(capsule.newest()?.snapshot, 999)
        XCTAssertEqual(capsule.count, 47)
    }

    /// Frame-stepping clamps at both ends of the recording instead of
    /// running off it.
    func testFrameStepClampsAtEdges() {
        var capsule = TimeCapsule<Int>(window: 10)
        for i in 0..<5 {
            capsule.record(i, at: Double(i))
        }
        XCTAssertEqual(capsule.frame(steppedFrom: 2, by: -1)?.snapshot, 1)
        XCTAssertEqual(capsule.frame(steppedFrom: 2, by: 2)?.snapshot, 4)
        XCTAssertEqual(capsule.frame(steppedFrom: 0, by: -3)?.snapshot, 0)
        XCTAssertEqual(capsule.frame(steppedFrom: 4, by: 10)?.snapshot, 4)
        // Stepping from a between-frames time steps from the frame a
        // lookup at that time would land on.
        XCTAssertEqual(capsule.frame(steppedFrom: 2.7, by: 1)?.snapshot, 3)
    }

    /// A rewound or stalled clock must not corrupt ordering: recording at
    /// a time the buffer has already passed drops the frames it overtakes.
    func testNonMonotonicTimeIsDefendedAgainst() {
        var capsule = TimeCapsule<Int>(window: 10)
        capsule.record(0, at: 0.0)
        capsule.record(1, at: 0.1)
        capsule.record(2, at: 0.2)
        // Same time as newest: replaces it rather than duplicating it.
        capsule.record(3, at: 0.2)
        XCTAssertEqual(capsule.count, 3)
        XCTAssertEqual(capsule.newest()?.snapshot, 3)
        // Earlier than newest: overtaken frames go, ordering survives.
        capsule.record(4, at: 0.05)
        XCTAssertEqual(capsule.count, 2)
        XCTAssertEqual(capsule.newest()?.snapshot, 4)
        let span = try! XCTUnwrap(capsule.span)
        XCTAssertLessThan(span.lowerBound, span.upperBound)
    }

    /// Strided extraction keeps both endpoints — a path drawn from these
    /// vertices starts and finishes where the recording does.
    func testStridedFramesKeepEndpoints() {
        var capsule = TimeCapsule<Int>(window: 10)
        for i in 0..<10 {
            capsule.record(i, at: Double(i) * 0.1)
        }
        let strided = capsule.frames(in: 0.0...0.9, stride: 4)
        XCTAssertEqual(strided.map(\.snapshot), [0, 4, 8, 9])
        let all = capsule.frames(in: 0.15...0.65)
        XCTAssertEqual(all.map(\.snapshot), [2, 3, 4, 5, 6])
        XCTAssertEqual(capsule.frames(in: 5.0...6.0), [])
    }

    func testRemoveAllEmptiesAndRecordingRestarts() {
        var capsule = TimeCapsule<Int>(window: 10)
        for i in 0..<20 {
            capsule.record(i, at: Double(i) * 0.1)
        }
        capsule.removeAll()
        XCTAssertTrue(capsule.isEmpty)
        XCTAssertNil(capsule.span)
        XCTAssertNil(capsule.newest())
        capsule.record(7, at: 0.0)
        XCTAssertEqual(capsule.count, 1)
        XCTAssertEqual(capsule.newest()?.snapshot, 7)
    }
}
