//
//  PhysicsFormatTests.swift
//  PhysicsPlaygroundTests
//
//  The quantisation contract: an in-room readout is rasterised, so what
//  costs is how often the rendered output changes, and a value perturbed
//  by less than its displayed precision must produce the same string.
//

import XCTest
@testable import PhysicsPlayground

final class PhysicsFormatTests: XCTestCase {

    // MARK: The contract

    /// A jitter far below the last displayed digit must not change the
    /// text — except at a rounding boundary, where no quantiser can do
    /// otherwise; the bases below sit away from half-steps.
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

    /// …and a change at the displayed precision must come through. A
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

    /// Negative values keep their sign and their prefix; the claim is about
    /// the sign surviving, not which character draws it.
    func testANegativeValueKeepsItsSignAndPrefix() {
        XCTAssertEqual(PhysicsFormat.metric(-0.0025, "A", decimals: 1), "\u{2212}2.5 mA")
    }

    // MARK: One minus sign

    /// Every number this app shows uses U+2212: a hyphen is a word-joiner
    /// drawn short and high, a minus is drawn to the digits' width.
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

    /// Rounding must not push the mantissa out of its band: a value just
    /// under a decade must not print a four-digit mantissa.
    func testRoundingUpAcrossADecadeStepsThePrefix() {
        XCTAssertEqual(PhysicsFormat.metric(999.97, "V", decimals: 1), "1.0 kV")
        XCTAssertEqual(PhysicsFormat.metric(999.4, "V", decimals: 1), "999.4 V")
        // And at the very top of the table there is nowhere to step to,
        // so it must not run off the end of the prefix list.
        XCTAssertFalse(PhysicsFormat.metric(9.9999e14, "W", decimals: 1).isEmpty)
    }

    // MARK: The canon is not optional

    /// No module formats a number by hand: `PhysicsFormat` was bypassed at
    /// dozens of call sites, which is how one quantity came to be spelled
    /// two ways in one module. A ban rather than a count, enforced by a
    /// test because a raw `String(format:)` is shorter than the right thing.
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

    /// The noun agrees with the number the wearer reads: Orbital Mechanics'
    /// mass grip said "1 Earths" and "1.00 Suns" until 2026-10-14.
    func testACountAgreesWithTheNumberShown() {
        XCTAssertEqual(PhysicsFormat.count(1, singular: "Earth", plural: "Earths"), "1 Earth")
        XCTAssertEqual(PhysicsFormat.count(1.3, singular: "Earth", plural: "Earths"), "1 Earth")
        XCTAssertEqual(PhysicsFormat.count(2, singular: "Earth", plural: "Earths"), "2 Earths")
        XCTAssertEqual(PhysicsFormat.count(0.5, singular: "Earth", plural: "Earths",
                                           decimals: 2), "0.50 Earths")
        XCTAssertEqual(PhysicsFormat.count(1.004, singular: "Sun", plural: "Suns",
                                           decimals: 2), "1.00 Sun")
    }

    /// A reversed clock reads with the room's minus, not a hyphen.
    func testAMultiplierUsesATrueMinus() {
        XCTAssertEqual(PhysicsFormat.multiplier(20), "20×")
        XCTAssertEqual(PhysicsFormat.multiplier(-20), "\u{2212}20×")
    }
}
