//
//  MilkyWayTests.swift
//  The model's shape: brightest on the centre, falling away from the
//  plane, darkened along the Great Rift, dimmer toward the anticentre, and
//  the Large Magellanic Cloud a glow of its own.
//

import XCTest
@testable import PhysicsCore

final class MilkyWayTests: XCTestCase {

    private let degree = Double.pi / 180

    private func glow(_ l: Double, _ b: Double) -> Double {
        MilkyWay.brightness(longitude: l * degree, latitude: b * degree)
    }

    func testTheCentreIsTheBrightestAndThePlaneFallsAway() {
        let centre = glow(0, -3)
        for l in stride(from: -180.0, through: 180, by: 15) {
            for b in stride(from: -60.0, through: 60, by: 10) {
                XCTAssertLessThanOrEqual(glow(l, b), centre + 1e-9, "(\(l), \(b))")
            }
        }
        XCTAssertGreaterThan(glow(60, 0), glow(60, 10))
        XCTAssertGreaterThan(glow(60, 10), glow(60, 30))
        XCTAssertGreaterThan(glow(30, -3), glow(180, -3), "the anticentre is dimmer")
    }

    func testTheGreatRiftDarkensTheBandFromCygnusToSagittarius() {
        XCTAssertLessThan(glow(30, 0.8), glow(30, -2.5))
        XCTAssertEqual(glow(150, 0.8) / glow(150, -0.8), 1, accuracy: 0.25, "no rift in Perseus")
    }

    func testTheLargeMagellanicCloudGlowsWhereItIs() {
        XCTAssertGreaterThan(glow(280.47, -32.89), 3 * glow(250, -32.89))
    }
}
