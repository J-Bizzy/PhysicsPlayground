//
//  StellarPhotometryTests.swift
//  Magnitudes are logarithmic and the drawing keeps their order: brighter
//  is bigger and brighter, the faintest is never under 4.5′, Sirius about
//  15.6′, and the atlas cells round-trip.
//

import XCTest
@testable import PhysicsCore

final class StellarPhotometryTests: XCTestCase {

    private let arcminute = Double.pi / (180 * 60)

    func testFiveMagnitudesIsAHundredfold() {
        XCTAssertEqual(StellarPhotometry.relativeFlux(magnitude: 6.5), 1, accuracy: 1e-12)
        XCTAssertEqual(StellarPhotometry.relativeFlux(magnitude: 1.5), 100, accuracy: 1e-9)
    }

    func testBrighterIsBiggerAndBrighterWithinTheBounds() {
        var lastSize = 0.0, lastPeak = 0.0
        for m in stride(from: 8.0, through: -1.5, by: -0.25) {
            let size = StellarPhotometry.angularSize(magnitude: m)
            let peak = StellarPhotometry.peakBrightness(magnitude: m)
            XCTAssertGreaterThanOrEqual(size, lastSize)
            XCTAssertGreaterThanOrEqual(peak, lastPeak)
            XCTAssertGreaterThanOrEqual(size, StellarPhotometry.minimumSize)
            XCTAssertLessThanOrEqual(size, StellarPhotometry.maximumSize)
            XCTAssertTrue((0.2...1).contains(peak))
            lastSize = size
            lastPeak = peak
        }
        XCTAssertEqual(StellarPhotometry.angularSize(magnitude: 6.5), 4.5 * arcminute, accuracy: 1e-12)
        XCTAssertEqual(StellarPhotometry.angularSize(magnitude: -1.46), 15.6 * arcminute,
                       accuracy: 0.1 * arcminute, "Sirius")
    }

    func testTheAtlasCellsRoundTrip() {
        for column in 0..<StellarPhotometry.temperatureColumns {
            XCTAssertEqual(StellarPhotometry.column(
                temperature: StellarPhotometry.temperature(column: column)), column)
        }
        for row in 0..<StellarPhotometry.brightnessRows {
            XCTAssertEqual(StellarPhotometry.row(brightness: StellarPhotometry.brightness(row: row)), row)
        }
        XCTAssertEqual(StellarPhotometry.temperature(column: 0), StellarPhotometry.hottest, accuracy: 1e-6)
        XCTAssertEqual(StellarPhotometry.temperature(column: 15), StellarPhotometry.coolest, accuracy: 1e-6)
        XCTAssertLessThan(StellarPhotometry.column(temperature: 11_000),
                          StellarPhotometry.column(temperature: 3_600), "hot to the left")
    }
}
