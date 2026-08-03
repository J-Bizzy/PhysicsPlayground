//
//  PhysicsFormatTests.swift
//  PhysicsPlaygroundTests
//
//  THE QUANTISATION CONTRACT, which is the reason `PhysicsFormat` grew
//  from two functions into the app's number canon.
//
//  An in-room readout is a RealityKit attachment or a text mesh, and what
//  costs is how often the RENDERED OUTPUT changes — not how often `body`
//  runs. A live value formatted straight from the model produces a
//  different string every frame and rebuilds its texture every frame.
//
//  Four files remembered that and hand-rolled `(x * 100).rounded() / 100`
//  before formatting; the rest did not. These tests are what makes it a
//  property of the formatter rather than a habit: **a value perturbed by
//  less than its own displayed precision must produce the SAME STRING.**
//  Break that and the app quietly gets slower in the modules that show
//  the most numbers.
//

import XCTest
@testable import PhysicsPlayground

final class PhysicsFormatTests: XCTestCase {

    // MARK: The contract

    /// A jitter far below the last displayed digit must not change the
    /// text. This is the whole point.
    ///
    /// **EXCEPT AT A ROUNDING BOUNDARY**, and that exception is real
    /// rather than a weakness. Exactly on a half-step — 42.5 at zero
    /// decimals — an arbitrarily small nudge flips 42 to 43, and no
    /// quantiser can do otherwise; that is what a boundary IS. It costs
    /// nothing in practice because it happens once per step of the
    /// displayed value, not once per frame. The first version of this
    /// test used 42.5 as a base and failed against a perfectly correct
    /// formatter.
    ///
    /// So the bases below deliberately sit away from half-steps, and the
    /// boundary gets its own test underneath.
    func testAValuePerturbedBelowItsPrecisionFormatsIdentically() {
        for decimals in 0...4 {
            let step = pow(10.0, Double(-decimals))
            for base in [0.0, 1.0, 3.14159, 42.31, 9.81, 1234.5678] {
                let reference = PhysicsFormat.fixed(base, decimals: decimals)
                // A thousandth of the last displayed digit, either way.
                for jitter in [step / 1000, -step / 1000, step / 5000] {
                    XCTAssertEqual(
                        PhysicsFormat.fixed(base + jitter, decimals: decimals),
                        reference,
                        """
                        \(base) and \(base + jitter) format differently at \
                        \(decimals) decimals. A readout built on this \
                        re-rasterises every frame.
                        """)
                }
            }
        }
    }

    /// The boundary behaves the way rounding behaves, stated so nobody
    /// reads the test above as a stronger promise than it is.
    func testTheOnlyPlaceAJitterShowsIsARoundingBoundary() {
        XCTAssertEqual(PhysicsFormat.fixed(42.5, decimals: 0), "43")
        XCTAssertEqual(PhysicsFormat.fixed(42.499, decimals: 0), "42")
        // One step of the displayed value, one change of the string. That
        // is a redraw per increment, which is what quantising is for.
    }

    /// …and a change AT the displayed precision must come through. A
    /// formatter that never changed its output would pass the test above
    /// perfectly.
    func testAValueChangedAtItsPrecisionFormatsDifferently() {
        for decimals in 0...4 {
            let step = pow(10.0, Double(-decimals))
            let base = 5.0
            XCTAssertNotEqual(PhysicsFormat.fixed(base, decimals: decimals),
                              PhysicsFormat.fixed(base + step, decimals: decimals),
                              "A full step at \(decimals) decimals must show.")
        }
    }

    /// `quantise` must return the number the string represents, so a
    /// caller can compare or cache on it and get the same answer the eye
    /// gets.
    func testQuantiseAgreesWithWhatIsPrinted() {
        for value in [1.0 / 3, 2.675, -0.004, 9.9999, 1e-9] {
            for decimals in 0...4 {
                let quantised = PhysicsFormat.quantise(value, decimals: decimals)
                XCTAssertEqual(PhysicsFormat.fixed(value, decimals: decimals),
                               PhysicsFormat.fixed(quantised, decimals: decimals))
            }
        }
    }

    /// `-0.00` is a real thing `%f` prints and it reads as a defect.
    func testATinyNegativeDoesNotPrintAsNegativeZero() {
        XCTAssertEqual(PhysicsFormat.fixed(-0.0001, decimals: 2), "0.00")
        XCTAssertEqual(PhysicsFormat.fixed(-0.0, decimals: 2), "0.00")
    }

    /// Non-finite values must not reach a readout as "nan" or "inf".
    func testNonFiniteValuesReadAsADash() {
        XCTAssertEqual(PhysicsFormat.fixed(.nan), "—")
        XCTAssertEqual(PhysicsFormat.fixed(.infinity), "—")
        XCTAssertTrue(PhysicsFormat.metric(.nan, "T").hasPrefix("—"))
    }

    // MARK: SI prefixes

    /// The prefix is chosen so the mantissa reads in the 1…999 band.
    /// This is what the app was spelling four separate ways.
    func testTheMetricPrefixKeepsTheMantissaReadable() {
        XCTAssertEqual(PhysicsFormat.metric(4.7e-5, "T", decimals: 1), "47.0 µT")
        XCTAssertEqual(PhysicsFormat.metric(0.0025, "A", decimals: 1), "2.5 mA")
        XCTAssertEqual(PhysicsFormat.metric(1500, "V", decimals: 1), "1.5 kV")
        XCTAssertEqual(PhysicsFormat.metric(12, "W", decimals: 1), "12.0 W")
        XCTAssertEqual(PhysicsFormat.metric(0, "T"), "0 T")
    }

    /// The band boundary: 999 stays plain, 1000 steps up. An
    /// off-by-one here is how a readout ends up saying "0.9 kV" and
    /// "1000.0 V" a frame apart.
    func testThePrefixStepsAtTheDecadeAndNotBefore() {
        XCTAssertEqual(PhysicsFormat.metric(999, "V", decimals: 0), "999 V")
        XCTAssertEqual(PhysicsFormat.metric(1000, "V", decimals: 0), "1 kV")
    }

    /// Negative values keep their sign and their prefix.
    func testANegativeValueKeepsItsSignAndPrefix() {
        XCTAssertEqual(PhysicsFormat.metric(-0.0025, "A", decimals: 1), "-2.5 mA")
    }

    // MARK: One spelling per fact

    /// The notebook had three spellings of a switched state — "on/off",
    /// "free/frozen", "yes/no — unbound" — depending on which room wrote
    /// the row. A notebook is a comparison surface; that is the one thing
    /// it must not do.
    func testASwitchedStateHasOneSpelling() {
        XCTAssertEqual(PhysicsFormat.state(true), "on")
        XCTAssertEqual(PhysicsFormat.state(false), "off")
    }

    /// Scientific notation keeps true superscripts and falls back to
    /// plain digits where an exponent would be noise.
    func testScientificNotationAndItsPlainBand() {
        XCTAssertEqual(PhysicsFormat.scientific(0), "0")
        XCTAssertEqual(PhysicsFormat.scientific(42.5), "42.50")
        XCTAssertTrue(PhysicsFormat.scientific(2.4e5).contains("× 10⁵"))
        XCTAssertTrue(PhysicsFormat.scientific(1e-7).contains("⁻"))
    }

    /// An angle closes the degree symbol up against the number, and takes
    /// the house precision — a tenth, which is already past what a hand
    /// can set and what a spinning planet lets you read.
    func testAnAngleIsWrittenOneWay() {
        XCTAssertEqual(PhysicsFormat.angle(37.44), "37.4°")
        XCTAssertEqual(PhysicsFormat.angle(-0.02), "0.0°")
    }
}
