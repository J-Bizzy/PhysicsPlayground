//
//  TimeLapseTests.swift
//  A playback clock that varies smoothly: the rate continuous with zero
//  slope at every knot, simulated time its exact integral and never
//  decreasing, and the inverse finding the wall time back.
//

import XCTest
@testable import PhysicsCore

final class TimeLapseTests: XCTestCase {

    private let clock = TimeLapse(knots: [
        .init(time: 0, rate: 1), .init(time: 2.9, rate: 1),
        .init(time: 4.3, rate: 8), .init(time: 5.2, rate: 0),
    ])

    func testTheRateIsContinuousAndFlatAtEveryKnot() {
        for knot in clock.knots {
            let h = 1e-6
            XCTAssertEqual(clock.rate(at: knot.time - h), knot.rate, accuracy: 1e-5)
            XCTAssertEqual(clock.rate(at: knot.time + h), knot.rate, accuracy: 1e-5)
            let slopeBefore = (clock.rate(at: knot.time) - clock.rate(at: knot.time - h)) / h
            let slopeAfter = (clock.rate(at: knot.time + h) - clock.rate(at: knot.time)) / h
            XCTAssertEqual(slopeBefore, 0, accuracy: 1e-3)
            XCTAssertEqual(slopeAfter, 0, accuracy: 1e-3)
        }
        XCTAssertEqual(clock.rate(at: 6), 0, "stopped after the landing")
    }

    func testSimulatedTimeIsTheExactIntegralAndNeverFallsBack() {
        var numeric = 0.0
        let n = 52_000
        let dt = 5.2 / Double(n)
        for i in 0..<n {
            let t = Double(i) * dt
            // Simpson over each step.
            numeric += dt / 6 * (clock.rate(at: t) + 4 * clock.rate(at: t + dt / 2) + clock.rate(at: t + dt))
        }
        XCTAssertEqual(clock.simTime(at: 5.2), numeric, accuracy: 1e-9)
        var last = -Double.infinity
        for t in stride(from: -0.5, through: 6.5, by: 0.01) {
            let tau = clock.simTime(at: t)
            XCTAssertGreaterThanOrEqual(tau, last)
            last = tau
        }
        XCTAssertEqual(clock.simTime(at: 6.5), clock.simTime(at: 5.2), accuracy: 1e-12)
    }

    func testTheInverseFindsTheWallTimeBack() throws {
        for t in stride(from: 0.1, through: 5.1, by: 0.25) {
            let found = try XCTUnwrap(clock.wallTime(reaching: clock.simTime(at: t)))
            XCTAssertEqual(found, t, accuracy: 1e-9)
        }
        XCTAssertNil(clock.wallTime(reaching: clock.simTime(at: 5.2) + 1), "it stops; past that never comes")
    }
}
