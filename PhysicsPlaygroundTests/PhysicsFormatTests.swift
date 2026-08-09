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
    ///
    /// The literal here was "-2.5 mA" with an ASCII hyphen until
    /// 2026-08-08. That was this test recording what the code did rather
    /// than what it should do — the claim in its own name is about the
    /// SIGN surviving, not about which character draws it.
    func testANegativeValueKeepsItsSignAndPrefix() {
        XCTAssertEqual(PhysicsFormat.metric(-0.0025, "A", decimals: 1), "\u{2212}2.5 mA")
    }

    // MARK: One minus sign

    /// EVERY NUMBER THIS APP SHOWS USES U+2212, because eight authored
    /// labels already do and `printf` does not.
    ///
    /// The Time Capsule's scrub reads "−1.50 s" with a typographic minus
    /// typed into the format string, in front of a number whose own sign
    /// would have been a hyphen. So two glyphs for one idea, at two
    /// widths, a few centimetres apart. A hyphen is a word-joiner drawn
    /// short and high to sit between letters; a minus is drawn to the
    /// width and height of the digits.
    func testEveryNegativeReadingUsesTheTypographicMinus() {
        let readings = [
            PhysicsFormat.fixed(-1.5, decimals: 2),
            PhysicsFormat.measurement(-9.81, "m/s²"),
            PhysicsFormat.angle(-45),
            PhysicsFormat.metric(-4.7e-5, "T"),
            PhysicsFormat.scientific(-2.4e5),
        ]
        for reading in readings {
            XCTAssertFalse(reading.contains("-"), """
                "\(reading)" uses a hyphen where the rest of the app uses \
                U+2212. Route it through `PhysicsFormat.typographic`.
                """)
            XCTAssertTrue(reading.contains("\u{2212}"),
                          "\"\(reading)\" lost its sign entirely")
        }
    }

    /// …and a positive reading must not grow one.
    func testAPositiveReadingHasNoSign() {
        XCTAssertEqual(PhysicsFormat.fixed(1.5, decimals: 2), "1.50")
        XCTAssertFalse(PhysicsFormat.measurement(9.81, "m/s²").contains("\u{2212}"))
    }

    /// ROUNDING MUST NOT PUSH THE MANTISSA OUT OF ITS BAND.
    ///
    /// The prefix is chosen from the unrounded magnitude and the mantissa
    /// is then rounded, so a value just under a decade picked the smaller
    /// prefix and printed a four-digit mantissa — the exact "1000.0 V"
    /// the test above exists to forbid, arrived at from the other side.
    func testRoundingUpAcrossADecadeStepsThePrefix() {
        XCTAssertEqual(PhysicsFormat.metric(999.97, "V", decimals: 1), "1.0 kV")
        XCTAssertEqual(PhysicsFormat.metric(999.4, "V", decimals: 1), "999.4 V")
        // And at the very top of the table there is nowhere to step to,
        // so it must not run off the end of the prefix list.
        XCTAssertFalse(PhysicsFormat.metric(9.9999e14, "W", decimals: 1).isEmpty)
    }

    // MARK: The canon is not optional

    /// NO MODULE FORMATS A NUMBER BY HAND.
    ///
    /// `PhysicsFormat` existed and was bypassed at 57 call sites under
    /// `Modules/`, which is how the same quantity came to be spelled two
    /// ways in one module: `CircuitsModel` printed "0 mF" at the bottom
    /// of the capacitor's own rail while the bench label beside it said
    /// "100 µF", and four separate files hand-rolled SI prefixes with
    /// four separate sets of bands.
    ///
    /// A BAN RATHER THAN A COUNT. "Fewer than N" is a ratchet somebody
    /// loosens; zero is a rule. And it has to be enforced by a test
    /// rather than by review, because a raw `String(format:)` is exactly
    /// what a hurried call site reaches for — it is shorter than the
    /// correct thing.
    ///
    /// WHAT THIS BUYS, concretely: quantisation (so a live readout does
    /// not rebuild its text mesh every frame for a number that reads the
    /// same), the typographic minus, and one answer to "how many
    /// decimals does a length get".
    func testNoModuleFormatsANumberByHand() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PhysicsPlayground/Modules")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path,
                                             isDirectory: &isDirectory),
              isDirectory.boolValue else {
            XCTFail("""
                Modules/ is not reachable from \(root.path) — this check would \
                pass without reading anything. Fix the path; do not let it skip.
                """)
            throw XCTSkip("source tree not reachable")
        }

        let files = FileManager.default.enumerator(at: root,
                                                   includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 20,
                             "found \(files.count) module files — the scan is "
                             + "looking in the wrong place")

        var offenders: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }
            for (number, line) in text.split(separator: "\n",
                                             omittingEmptySubsequences: false)
                .enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Comments may name it — several explain why it went.
                guard !trimmed.hasPrefix("//") else { continue }
                if line.contains("String(format:") {
                    offenders.append("\(file.lastPathComponent):\(number + 1)")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) module call site(s) format a number by hand \
            instead of through `PhysicsFormat`:
            \(offenders.joined(separator: "\n"))
            Use `measurement`, `metric`, `angle`, `fixed` or `scientific`. If a \
            reading genuinely needs a shape none of those make, add it THERE — \
            a fifth hand-rolled SI prefixer is what this ban exists to stop.
            """)
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
