//
//  CatenaryTests.swift
//  PhysicsCoreTests
//
//  A hanging cable is a catenary, not a parabola and not a Bézier
//  that looks about right. The shape parameter comes out of a Newton
//  solve, so the thing worth testing is that the curve it produces
//  actually has the ARC LENGTH it was asked for — that is the claim
//  the solve makes, and a wrong root still draws a plausible-looking
//  droop.
//

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

    /// The endpoints are the endpoints, always — a curve that misses
    /// its own terminals would leave a visible gap at every joint.
    func testTheCurveStartsAndEndsWhereItWasTold() {
        for slack in [0.0, 0.01, 0.1, 0.5] {
            let curve = Catenary.points(from: a, to: b, slack: slack)
            XCTAssertEqual(simd_distance(curve.first!, a), 0, accuracy: 1e-12)
            XCTAssertEqual(simd_distance(curve.last!, b), 0, accuracy: 1e-12)
        }
    }

    /// THE CLAIM THE SOLVE MAKES: the curve is as long as it was asked
    /// to be. Sampled arc length underestimates a smooth curve
    /// slightly, so this is checked to a part in a thousand rather
    /// than exactly — but a wrong root misses by percent, not
    /// per-mille.
    func testArcLengthMatchesTheRequestedSlack() {
        for slack in [0.02, 0.05, 0.1, 0.3] {
            let requested = simd_distance(a, b) + slack
            let measured = Catenary.arcLength(from: a, to: b, slack: slack, samples: 64)
            XCTAssertEqual(measured, requested, accuracy: requested * 1e-3,
                           "slack \(slack): asked for \(requested), got \(measured)")
        }
    }

    /// It hangs DOWN, and its lowest point is below both ends.
    func testTheLowestPointIsBelowBothEnds() {
        let curve = Catenary.points(from: a, to: b, slack: 0.1)
        let lowest = curve.map(\.y).min()!
        XCTAssertLessThan(lowest, a.y - 1e-4)
        XCTAssertLessThan(lowest, b.y - 1e-4)
    }

    /// A level span sags symmetrically about its midpoint.
    func testTheCurveIsSymmetricAboutMidSpan() {
        let curve = Catenary.points(from: a, to: b, slack: 0.12, samples: 21)
        for index in 0..<curve.count {
            let mirror = curve.count - 1 - index
            XCTAssertEqual(curve[index].y, curve[mirror].y, accuracy: 1e-9,
                           "sample \(index) does not mirror \(mirror)")
        }
    }

    /// More slack, more sag — monotonically.
    func testMoreSlackSagsFurther() {
        var previous = a.y
        for slack in [0.02, 0.05, 0.12, 0.3] {
            let lowest = Catenary.points(from: a, to: b, slack: slack).map(\.y).min()!
            XCTAssertLessThan(lowest, previous, "slack \(slack) sagged no further than the last")
            previous = lowest
        }
    }

    /// A vertical span has no horizontal frame to sag across — every
    /// direction is equally sideways — so it degrades to the chord
    /// rather than inventing one.
    func testAVerticalSpanDegradesToTheChord() {
        let top = SIMD3<Double>(0, 1.6, -0.9)
        let bottom = SIMD3<Double>(0, 1.2, -0.9)
        let curve = Catenary.points(from: top, to: bottom, slack: 0.1)
        XCTAssertEqual(length(curve), simd_distance(top, bottom), accuracy: 1e-12)
    }

    /// A sloped span still hangs, and still lands on both ends.
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

    /// A zero-length span does not divide by zero, and neither does a
    /// pair of coincident points — which a snapped joint produces on
    /// purpose.
    func testDegenerateSpansAreSafe() {
        let curve = Catenary.points(from: a, to: a, slack: 0.1)
        XCTAssertFalse(curve.contains { $0.x.isNaN || $0.y.isNaN || $0.z.isNaN })
        for point in curve {
            XCTAssertEqual(simd_distance(point, a), 0, accuracy: 1e-12)
        }
    }

    /// Nothing produces a NaN, over a wide sweep of spans and slacks.
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

    /// NEAR-VERTICAL, NOT JUST VERTICAL — the case the first version
    /// of this file got catastrophically wrong.
    ///
    /// The degeneracy guard was an ABSOLUTE 1e-4 on the horizontal
    /// run, so a span 0.2 mm across and 0.4 m tall went to the Newton
    /// solve, which was asked to hang 4 cm of slack across 0.2 mm of
    /// horizontal distance. Five iterations from a small-sag guess do
    /// not reach that root, and the unconverged value produced
    /// mid-span drops of 10^23 metres — numbers that reach a vertex
    /// buffer as infinities. `testAVerticalSpanDegradesToTheChord`
    /// missed it because it used an offset of EXACTLY zero, and
    /// `testNothingProducesANaN` missed it because its sweep never
    /// went near vertical.
    func testNearVerticalSpansStayBounded() {
        let top = SIMD3<Double>(0, 1.6, -0.9)
        for offset in [1e-6, 1e-5, 1e-4, 5e-4, 1e-3, 2e-3, 5e-3, 0.01, 0.05, 0.1] {
            let bottom = SIMD3<Double>(offset, 1.2, -0.9)
            let curve = Catenary.points(from: top, to: bottom, slack: 0.04)
            let chord = simd_distance(top, bottom)
            for point in curve {
                XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite,
                              "offset \(offset) produced \(point)")
                // Nothing may end up further from an endpoint than the
                // cable is long. A curve that cannot honour its slack
                // must fall back to the chord, not run away.
                XCTAssertLessThan(simd_distance(point, top), chord + 0.05 + 1e-9,
                                  "offset \(offset) flung a point \(simd_distance(point, top)) m away")
            }
        }
    }

    /// The same claim as a property, over every direction: no sampled
    /// point is ever further from an end than the arc length.
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

    /// The sample count is honoured — the renderer sizes a tube from
    /// it.
    func testTheSampleCountIsHonoured() {
        XCTAssertEqual(Catenary.points(from: a, to: b, slack: 0.1, samples: 5).count, 5)
        XCTAssertEqual(Catenary.points(from: a, to: b, slack: 0, samples: 9).count, 9)
        // Never fewer than the two endpoints, whatever it is asked.
        XCTAssertEqual(Catenary.points(from: a, to: b, slack: 0.1, samples: 0).count, 2)
    }
}
