//
//  StellarPhotometryTests.swift
//  Magnitudes are logarithmic and the drawing keeps their order: brighter
//  is brighter and never smaller. A faint star is a dim point — a
//  twentieth of white, 4′ — the peak reaches white at magnitude 1.5, and
//  only the stars past that widen much: Sirius is 12.8′ in a glare 1.25°
//  out. The sky's range is kept, not flattened, and the atlas cells
//  round-trip.
//

import XCTest
@testable import PhysicsCore

final class StellarPhotometryTests: XCTestCase {

    private let arcminute = Double.pi / (180 * 60)
    private let degree = Double.pi / 180

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
            XCTAssertTrue((StellarPhotometry.faintestPeak...1).contains(peak))
            lastSize = size
            lastPeak = peak
        }
        XCTAssertEqual(StellarPhotometry.angularSize(magnitude: 6.5), 4 * arcminute, accuracy: 1e-12)
        XCTAssertEqual(StellarPhotometry.angularSize(magnitude: -1.46), 12.8 * arcminute,
                       accuracy: 0.1 * arcminute, "Sirius")
    }

    /// The peak is 0.05 at the limit and exactly white at magnitude 1.5,
    /// along one power of the flux between.
    func testThePeakRunsFromATwentiethToWhite() {
        XCTAssertEqual(StellarPhotometry.peakBrightness(magnitude: 6.5), 0.05, accuracy: 1e-12)
        XCTAssertEqual(StellarPhotometry.peakBrightness(magnitude: 1.5), 1, accuracy: 1e-9)
        XCTAssertEqual(StellarPhotometry.peakBrightness(magnitude: -1.46), 1, "Sirius is white, not more")
        XCTAssertEqual(StellarPhotometry.peakExponent, 0.6505, accuracy: 0.0005)
        // Half way in magnitude is half way in the logarithm of the peak.
        let middle = StellarPhotometry.peakBrightness(magnitude: 4.0)
        XCTAssertEqual(middle, (0.05 * 1.0).squareRoot(), accuracy: 1e-9)
    }

    /// The range is kept. The old mapping drew a magnitude-1.5 star with
    /// 24 times the light of a limiting one (peak × area) against a true
    /// 100, and Sirius with 60 against 1,528: a sky of equal dots.
    func testTheSkysRangeIsNotFlattened() {
        func light(_ m: Double) -> Double {
            let size = StellarPhotometry.angularSize(magnitude: m)
            return StellarPhotometry.peakBrightness(magnitude: m) * size * size
        }
        XCTAssertGreaterThan(light(1.5) / light(6.5), 35)
        XCTAssertGreaterThan(light(-1.46) / light(6.5), 200)
        // And a limiting star is no longer mid-grey.
        XCTAssertLessThan(StellarPhotometry.peakBrightness(magnitude: 6.5), 0.1)
    }

    /// Only a bright star shows the eye's glare, and its reach goes as the
    /// square root of the flux — what a 1/θ² veil gives.
    func testGlareReachesAsTheSquareRootOfTheFlux() throws {
        XCTAssertNil(StellarPhotometry.glare(magnitude: 3.01))
        let faintest = try XCTUnwrap(StellarPhotometry.glare(magnitude: 3.0))
        XCTAssertEqual(faintest.radius, 0.16 * degree, accuracy: 1e-9)
        XCTAssertEqual(faintest.level, 0.05, accuracy: 1e-9)
        // Five magnitudes brighter: a hundred times the flux, ten times the reach.
        let bright = try XCTUnwrap(StellarPhotometry.glare(magnitude: -2.0))
        XCTAssertEqual(bright.radius / faintest.radius, 10, accuracy: 1e-6)
        let sirius = try XCTUnwrap(StellarPhotometry.glare(magnitude: -1.46))
        XCTAssertEqual(sirius.radius, 1.25 * degree, accuracy: 0.01 * degree)
        // A veil, never a disc: always dimmer than the star it surrounds.
        var last = 0.0
        for m in stride(from: 3.0, through: -1.5, by: -0.25) {
            let glare = try XCTUnwrap(StellarPhotometry.glare(magnitude: m))
            XCTAssertGreaterThanOrEqual(glare.level, last)
            XCTAssertLessThanOrEqual(glare.level, StellarPhotometry.brightestGlareLevel)
            XCTAssertLessThan(glare.level, StellarPhotometry.peakBrightness(magnitude: m))
            XCTAssertGreaterThan(glare.radius, StellarPhotometry.angularSize(magnitude: m))
            last = glare.level
        }
    }

    func testTheAtlasCellsRoundTrip() {
        for column in 0..<StellarPhotometry.temperatureColumns {
            XCTAssertEqual(StellarPhotometry.column(
                temperature: StellarPhotometry.temperature(column: column)), column)
        }
        for row in 0..<StellarPhotometry.brightnessRows {
            XCTAssertEqual(StellarPhotometry.row(brightness: StellarPhotometry.brightness(row: row)), row)
        }
        for row in 0..<StellarPhotometry.glareRows {
            XCTAssertEqual(StellarPhotometry.glareRow(level: StellarPhotometry.glareLevel(row: row)), row)
        }
        XCTAssertEqual(StellarPhotometry.brightness(row: 0), StellarPhotometry.faintestPeak, accuracy: 1e-12)
        XCTAssertEqual(StellarPhotometry.brightness(row: StellarPhotometry.brightnessRows - 1), 1,
                       accuracy: 1e-12)
        XCTAssertEqual(StellarPhotometry.temperature(column: 0), StellarPhotometry.hottest, accuracy: 1e-6)
        XCTAssertEqual(StellarPhotometry.temperature(column: 15), StellarPhotometry.coolest, accuracy: 1e-6)
        XCTAssertLessThan(StellarPhotometry.column(temperature: 11_000),
                          StellarPhotometry.column(temperature: 3_600), "hot to the left")
    }

    /// The rows are equal ratios, so no star is drawn far from its own
    /// brightness: within 11 % anywhere in the range.
    func testNoStarIsDrawnFarFromItsOwnBrightness() {
        for m in stride(from: 6.5, through: 1.5, by: -0.05) {
            let peak = StellarPhotometry.peakBrightness(magnitude: m)
            let drawn = StellarPhotometry.brightness(row: StellarPhotometry.row(brightness: peak))
            XCTAssertEqual(drawn / peak, 1, accuracy: 0.11, "magnitude \(m)")
        }
    }
}
