//
//  StellarColourTests.swift
//  A star's colour is a blackbody's: Ballesteros puts the Sun at 5,778 K,
//  Planck's law against the CIE functions lands the standard illuminants'
//  chromaticities, and a redder index draws a redder star.
//

import XCTest
import simd
@testable import PhysicsCore

final class StellarColourTests: XCTestCase {

    func testTheSunsIndexIsTheSunsTemperature() {
        XCTAssertEqual(StellarColour.temperature(bMinusV: 0.65), 5778, accuracy: 25)
        XCTAssertGreaterThan(StellarColour.temperature(bMinusV: -0.03),
                             StellarColour.temperature(bMinusV: 1.85))
    }

    /// CIE Illuminant A is a 2856 K blackbody; D65's nearest blackbody is
    /// about 6504 K.
    func testBlackbodiesLandTheStandardChromaticities() {
        let a = StellarColour.chromaticity(temperature: 2856)
        XCTAssertEqual(a.x, 0.4476, accuracy: 0.003)
        XCTAssertEqual(a.y, 0.4074, accuracy: 0.003)
        let d = StellarColour.chromaticity(temperature: 6504)
        XCTAssertEqual(d.x, 0.3135, accuracy: 0.003)
        XCTAssertEqual(d.y, 0.3236, accuracy: 0.003)
    }

    /// Wien: the spectrum peaks at b/T.
    func testPlanckPeaksAtWiensWavelength() {
        let t = 5778.0
        var best = (lambda: 0.0, value: 0.0)
        for nm in stride(from: 300.0, through: 900.0, by: 0.5) {
            let value = StellarColour.planck(wavelength: nm * 1e-9, temperature: t)
            if value > best.value { best = (nm * 1e-9, value) }
        }
        XCTAssertEqual(best.lambda, 2.897771955e-3 / t, accuracy: 1e-9)
    }

    /// Betelgeuse (B−V 1.85) is drawn redder than Rigel (−0.03), and both
    /// are still mostly white — the stated chroma.
    func testARedderIndexDrawsARedderStarAndStarsStayPale() {
        let betelgeuse = StellarColour.displayColour(
            temperature: StellarColour.temperature(bMinusV: 1.85))
        let rigel = StellarColour.displayColour(
            temperature: StellarColour.temperature(bMinusV: -0.03))
        XCTAssertGreaterThan(betelgeuse.x / betelgeuse.z, rigel.x / rigel.z)
        XCTAssertGreaterThan(rigel.z, rigel.x, "Rigel is blue-white")
        for colour in [betelgeuse, rigel] {
            XCTAssertEqual(colour.max(), 1, accuracy: 1e-9)
            XCTAssertGreaterThan(colour.min(), 0.6, "a star is a pale colour, not a lamp")
        }
    }
}
