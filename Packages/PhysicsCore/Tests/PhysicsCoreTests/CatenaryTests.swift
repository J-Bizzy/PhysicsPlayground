//  CatenaryTests.swift
//  True catenary for hanging cables — the load-bearing claim is that the Newton solve's curve has the requested arc length.

import XCTest
import simd
@testable import PhysicsCore

final class CatenaryTests: XCTestCase {

    private let a = SIMD3<Double>(-0.3, 1.3, -0.9)
    private let b = SIMD3<Double>(0.3, 1.3, -0.9)

    private func length(_ curve: [SIMD3<Double>]) -> Double {
        (1..<curve.count).reduce(0) { $0 + simd_distance(curve[$1 - 1], curve[$1]) }
    }

    /// No slack, no sag: the chord, exactly.
    func testZeroSlackIsStraight() {
        let curve = Catenary.points(from: a, to: b, slack: 0)
        XCTAssertEqual(length(curve), simd_distance(a, b), accuracy: 1e-12)
        for point in curve {
            XCTAssertEqual(point.y, a.y, accuracy: 1e-12, "a slack-free cable must not sag")
        }
    }

    func testTheCurveStartsAndEndsWhereItWasTold() {
        for slack in [0.0, 0.01, 0.1, 0.5] {
            let curve = Catenary.points(from: a, to: b, slack: slack)
            XCTAssertEqual(simd_distance(curve.first!, a), 0, accuracy: 1e-12)
            XCTAssertEqual(simd_distance(curve.last!, b), 0, accuracy: 1e-12)
        }
    }

    /// The solve's claim: arc length equals the request. Tolerance 1e-3 relative because
    /// sampling underestimates a smooth curve slightly; a wrong root misses by percent.
    func testArcLengthMatchesTheRequestedSlack() {
        for slack in [0.02, 0.05, 0.1, 0.3] {
            let requested = simd_distance(a, b) + slack
            let measured = Catenary.arcLength(from: a, to: b, slack: slack, samples: 64)
            XCTAssertEqual(measured, requested, accuracy: requested * 1e-3,
                           "slack \(slack): asked for \(requested), got \(measured)")
        }
    }

    func testTheLowestPointIsBelowBothEnds() {
        let curve = Catenary.points(from: a, to: b, slack: 0.1)
        let lowest = curve.map(\.y).min()!
        XCTAssertLessThan(lowest, a.y - 1e-4)
        XCTAssertLessThan(lowest, b.y - 1e-4)
    }

    func testTheCurveIsSymmetricAboutMidSpan() {
        let curve = Catenary.points(from: a, to: b, slack: 0.12, samples: 21)
        for index in 0..<curve.count {
            let mirror = curve.count - 1 - index
            XCTAssertEqual(curve[index].y, curve[mirror].y, accuracy: 1e-9,
                           "sample \(index) does not mirror \(mirror)")
        }
    }

    func testMoreSlackSagsFurther() {
        var previous = a.y
        for slack in [0.02, 0.05, 0.12, 0.3] {
            let lowest = Catenary.points(from: a, to: b, slack: slack).map(\.y).min()!
            XCTAssertLessThan(lowest, previous, "slack \(slack) sagged no further than the last")
            previous = lowest
        }
    }

    /// A vertical span has no horizontal frame to sag across, so it degrades to the chord.
    func testAVerticalSpanDegradesToTheChord() {
        let top = SIMD3<Double>(0, 1.6, -0.9)
        let bottom = SIMD3<Double>(0, 1.2, -0.9)
        let curve = Catenary.points(from: top, to: bottom, slack: 0.1)
        XCTAssertEqual(length(curve), simd_distance(top, bottom), accuracy: 1e-12)
    }

    func testASlopedSpanHangsAndStillMeetsItsEnds() {
        let low = SIMD3<Double>(-0.3, 1.15, -0.9)
        let high = SIMD3<Double>(0.3, 1.45, -0.9)
        let curve = Catenary.points(from: low, to: high, slack: 0.08)
        XCTAssertEqual(simd_distance(curve.first!, low), 0, accuracy: 1e-12)
        XCTAssertEqual(simd_distance(curve.last!, high), 0, accuracy: 1e-12)
        // It must dip below the straight line somewhere.
        let midpoint = (low + high) / 2
        let nearestToMid = curve.min {
            abs(simd_length(SIMD3($0.x, 0, $0.z) - SIMD3(midpoint.x, 0, midpoint.z)))
                < abs(simd_length(SIMD3($1.x, 0, $1.z) - SIMD3(midpoint.x, 0, midpoint.z)))
        }!
        XCTAssertLessThan(nearestToMid.y, midpoint.y)
    }

    /// Coincident endpoints — which a snapped joint produces on purpose — must not divide by zero.
    func testDegenerateSpansAreSafe() {
        let curve = Catenary.points(from: a, to: a, slack: 0.1)
        XCTAssertFalse(curve.contains { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN })
        for point in curve {
            XCTAssertEqual(simd_distance(point, a), 0, accuracy: 1e-12)
        }
    }

    /// A single NaN in a vertex buffer takes the whole mesh with it.
    func testNothingProducesANaN() {
        for spanIndex in 0...20 {
            for slackIndex in 0...20 {
                let span = Double(spanIndex) * 0.1
                let slack = Double(slackIndex) * 0.05
                let curve = Catenary.points(
                    from: a, to: a + SIMD3(span, span * 0.2, 0), slack: slack)
                for point in curve {
                    XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite,
                                  "span \(span), slack \(slack) produced \(point)")
                }
            }
        }
    }

    /// Regression: an absolute 1e-4 horizontal-run guard sent near-vertical spans to an
    /// unconverged Newton solve (mid-span drops of 1e23 m); exactly-vertical tests miss this.
    func testNearVerticalSpansStayBounded() {
        let top = SIMD3<Double>(0, 1.6, -0.9)
        for offset in [1e-6, 1e-5, 1e-4, 5e-4, 1e-3, 2e-3, 5e-3, 0.01, 0.05, 0.1] {
            let bottom = SIMD3<Double>(offset, 1.2, -0.9)
            let curve = Catenary.points(from: top, to: bottom, slack: 0.04)
            let chord = simd_distance(top, bottom)
            for point in curve {
                XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite,
                              "offset \(offset) produced \(point)")
                // A curve that cannot honour its slack must fall back to the chord, not run away.
                XCTAssertLessThan(simd_distance(point, top), chord + 0.05 + 1e-9,
                                  "offset \(offset) flung a point \(simd_distance(point, top)) m away")
            }
        }
    }

    /// Property form over random spans: no sampled point further from an end than the arc length.
    func testNoPointEverExceedsTheCableLength() {
        var seed: UInt64 = 99
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        for _ in 0..<3000 {
            let to = a + SIMD3((random() * 2 - 1) * 1.5,
                               (random() * 2 - 1) * 1.5,
                               (random() * 2 - 1) * 1.5)
            let slack = random() * 0.6
            let bound = simd_distance(a, to) + slack + 1e-6
            for point in Catenary.points(from: a, to: to, slack: slack) {
                XCTAssertLessThanOrEqual(simd_distance(point, a), bound,
                                         "to \(to), slack \(slack): point \(point)")
            }
        }
    }

    /// The renderer sizes a tube from the sample count.
    func testTheSampleCountIsHonoured() {
        XCTAssertEqual(Catenary.points(from: a, to: b, slack: 0.1, samples: 5).count, 5)
        XCTAssertEqual(Catenary.points(from: a, to: b, slack: 0, samples: 9).count, 9)
        // Never fewer than the two endpoints, whatever it is asked.
        XCTAssertEqual(Catenary.points(from: a, to: b, slack: 0.1, samples: 0).count, 2)
    }
}
