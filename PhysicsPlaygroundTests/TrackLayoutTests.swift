//
//  TrackLayoutTests.swift
//  PhysicsPlaygroundTests
//
//  The track replaced the dial, so its arithmetic inherits the dial's
//  test burden — with one difference that is the whole point. A dial had
//  to be tested for ACCUMULATION (does a sequence of twists add up, does
//  the ±π seam behave). A track has nothing to accumulate: a hand position
//  maps to a value directly, every frame, from scratch. Most of the ways
//  the dial could go wrong cannot happen here, and the tests that remain
//  are about the mapping being honest at the ends and in the middle.
//

import XCTest
import simd
import RenderKit

final class TrackLayoutTests: XCTestCase {

    private let track = TrackLayout(length: 0.26)

    // MARK: The mapping

    /// Half way along the rail is half way through the range — the claim a
    /// user reads off the bead's position without being told.
    func testMidRailIsMidRange() {
        XCTAssertEqual(track.fraction(forHandInTrackSpace: .zero), 0.5,
                       accuracy: 1e-12)
        XCTAssertEqual(track.value(forFraction: 0.5, in: 0...100), 50,
                       accuracy: 1e-12)
    }

    func testRailEndsAreTheRangeEnds() {
        XCTAssertEqual(track.fraction(forHandInTrackSpace: SIMD3(-0.13, 0, 0)),
                       0, accuracy: 1e-12)
        XCTAssertEqual(track.fraction(forHandInTrackSpace: SIMD3(0.13, 0, 0)),
                       1, accuracy: 1e-12)
    }

    /// Reaching past an end pins to it rather than running off — a value
    /// cannot leave its range however far the arm goes.
    func testReachingPastAnEndClamps() {
        XCTAssertEqual(track.fraction(forHandInTrackSpace: SIMD3(-9, 0, 0)), 0)
        XCTAssertEqual(track.fraction(forHandInTrackSpace: SIMD3(9, 0, 0)), 1)
        XCTAssertEqual(track.value(forFraction: -4, in: 0.2...1.0), 0.2)
        XCTAssertEqual(track.value(forFraction: 7, in: 0.2...1.0), 1.0)
    }

    /// ONLY the along-rail component counts. A hand that drifts up or
    /// forward mid-drag — which every real hand does — must not change the
    /// value it is level with.
    func testOffAxisDriftDoesNotChangeTheValue() {
        let onAxis = track.fraction(forHandInTrackSpace: SIMD3(0.04, 0, 0))
        for drift in [SIMD3<Double>(0.04, 0.3, 0),
                      SIMD3<Double>(0.04, -0.2, 0.5),
                      SIMD3<Double>(0.04, 0, -0.9)] {
            XCTAssertEqual(track.fraction(forHandInTrackSpace: drift), onAxis,
                           accuracy: 1e-12, "drift \(drift) moved the value")
        }
    }

    /// Absolute, not relative: the same hand position always means the same
    /// value, no matter what happened before. This is the property the dial
    /// could not have, and the reason the bead's position can be trusted.
    func testTheSameHandPositionAlwaysMeansTheSameValue() {
        let hand = SIMD3<Double>(0.065, 0, 0)
        let first = track.fraction(forHandInTrackSpace: hand)
        // Wander all over the rail, then come back.
        for x in stride(from: -0.13, through: 0.13, by: 0.01) {
            _ = track.fraction(forHandInTrackSpace: SIMD3(x, 0, 0))
        }
        XCTAssertEqual(track.fraction(forHandInTrackSpace: hand), first,
                       accuracy: 1e-12)
    }

    // MARK: Round trips

    /// value → fraction → offset → fraction → value, for a real range.
    func testValueSurvivesARoundTrip() {
        let range = 0.2...2.0
        for value in stride(from: 0.2, through: 2.0, by: 0.1) {
            let fraction = track.fraction(forValue: value, in: range)
            let back = track.value(forFraction: fraction, in: range)
            XCTAssertEqual(back, value, accuracy: 1e-12)

            // And the bead's own position implies the same fraction.
            let offset = track.offset(forFraction: fraction)
            XCTAssertEqual(track.fraction(forHandInTrackSpace: offset),
                           fraction, accuracy: 1e-12)
        }
    }

    /// A range that spans zero — the cylinder's circulation is −1.5…1.5, so
    /// the middle of the rail must be no spin at all.
    func testRangeSpanningZeroPutsZeroInTheMiddle() {
        let range = -1.5...1.5
        XCTAssertEqual(track.fraction(forValue: 0, in: range), 0.5,
                       accuracy: 1e-12)
        XCTAssertEqual(track.value(forFraction: 0.5, in: range), 0,
                       accuracy: 1e-12)
        XCTAssertEqual(track.value(forFraction: 0, in: range), -1.5)
        XCTAssertEqual(track.value(forFraction: 1, in: range), 1.5)
    }

    /// The bead is centred on the anchor, so a caller can drop a track
    /// beside an apparatus without compensating for its length.
    func testBeadIsCentredOnTheAnchor() {
        XCTAssertEqual(track.offset(forFraction: 0.5).x, 0, accuracy: 1e-12)
        XCTAssertEqual(track.offset(forFraction: 0).x, -0.13, accuracy: 1e-12)
        XCTAssertEqual(track.offset(forFraction: 1).x, 0.13, accuracy: 1e-12)
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let offset = track.offset(forFraction: fraction)
            XCTAssertEqual(offset.y, 0)
            XCTAssertEqual(offset.z, 0)
        }
    }

    // MARK: Degenerate input

    /// A zero-length rail and a zero-width range are both finite rather
    /// than NaN — a divide by either would poison every transform
    /// downstream, which is the failure the fan layout taught.
    func testZeroLengthRailIsFiniteRatherThanNaN() {
        let degenerate = TrackLayout(length: 0)
        XCTAssertEqual(degenerate.fraction(forHandInTrackSpace: SIMD3(1, 0, 0)), 0)
        XCTAssertTrue(degenerate.offset(forFraction: 0.5).x.isFinite)
    }

    func testZeroWidthRangeIsFiniteRatherThanNaN() {
        XCTAssertEqual(track.fraction(forValue: 5, in: 5...5), 0)
        XCTAssertEqual(track.value(forFraction: 0.5, in: 5...5), 5)
    }
}
