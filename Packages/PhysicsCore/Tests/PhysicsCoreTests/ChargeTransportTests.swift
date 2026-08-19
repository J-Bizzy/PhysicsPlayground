//  ChargeTransportTests.swift
//  Drift-speed textbook case and scaling laws.

import XCTest
@testable import PhysicsCore

final class ChargeTransportTests: XCTestCase {

    func testTheTextbookCase() {
        // Canonical case: 1 A through a 1 mm-radius copper wire drifts at ≈ 23 µm/s.
        let v = ChargeTransport.driftSpeed(current: 1, wireRadius: 1e-3)
        XCTAssertEqual(v, 2.34e-5, accuracy: 0.05e-5)
        XCTAssertLessThan(v * 60, 1.5e-3)
    }

    func testAnElectronTakesHoursToCrossAMetre() {
        let v = ChargeTransport.driftSpeed(current: 1, wireRadius: 1e-3)
        let hours = ChargeTransport.traversalTime(length: 1, speed: v) / 3600
        XCTAssertEqual(hours, 11.9, accuracy: 0.5)
    }

    func testSignalCrossesTheSameMetreInNanoseconds() {
        let t = ChargeTransport.traversalTime(
            length: 1, speed: ChargeTransport.signalSpeed())
        XCTAssertEqual(t * 1e9, 5.05, accuracy: 0.1)
    }

    func testTheRatioIsAboutTenTrillion() {
        let ratio = ChargeTransport.signalToDriftRatio(current: 1, wireRadius: 1e-3)
        XCTAssertGreaterThan(ratio, 1e12)
        XCTAssertLessThan(ratio, 1e13)
    }

    func testDriftScalesLinearlyWithCurrent() {
        let one = ChargeTransport.driftSpeed(current: 1, wireRadius: 1e-3)
        let three = ChargeTransport.driftSpeed(current: 3, wireRadius: 1e-3)
        XCTAssertEqual(three / one, 3, accuracy: 1e-9)
    }

    func testDriftScalesInverselyWithArea() {
        // Halving the radius quarters the area, so quadruples the speed.
        let fat = ChargeTransport.driftSpeed(current: 1, wireRadius: 1e-3)
        let thin = ChargeTransport.driftSpeed(current: 1, wireRadius: 0.5e-3)
        XCTAssertEqual(thin / fat, 4, accuracy: 1e-9)
    }

    func testZeroCurrentIsZeroDriftAndInfiniteCrossing() {
        XCTAssertEqual(ChargeTransport.driftSpeed(current: 0, wireRadius: 1e-3), 0)
        XCTAssertEqual(ChargeTransport.traversalTime(length: 1, speed: 0), .infinity)
    }
}
