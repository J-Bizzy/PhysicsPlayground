//
//  PhysicsFormat.swift
//  Physics Playground — Design system
//
//  How a number is written, once, for the whole app.
//
//  This was 35 lines with two functions and 21 call sites in two modules,
//  against 107 hand-rolled `String(format:)` calls everywhere else — the
//  shape `Materials.swift` was convicted of on 2026-07-30. A canon with
//  one recipe is a default, not a canon, and the tell is a grep for
//  hand-typed values: each one marks a call site the shared layer failed
//  to serve.
//
//  What the scattering cost was not hypothetical. The same physical
//  quantity was written to different precision in different rooms —
//  gravity `%.2f` in Projectiles against `%.3f` in Pendulums, a length
//  `%.3f` against `%.4f`, and a fifth style `%.4g` in Electric Fields —
//  and a boolean reading came out as "on/off", "free/frozen" and
//  "yes/no — unbound" depending on which module wrote it. A lab notebook
//  is a comparison surface; three spellings of the same fact is the one
//  thing it must not do.
//
//  ── THE QUANTISATION RULE IS THE REAL REASON THIS FILE GREW ──
//
//  An in-room readout is a RealityKit attachment or a text mesh, and
//  what costs is how often the RENDERED OUTPUT changes, not how often
//  `body` runs. So every live value has to be quantised to the precision
//  it is displayed at, or the string differs every frame and the texture
//  is rebuilt every frame.
//
//  Four files remembered that and hand-rolled `(x * 100).rounded() / 100`
//  before formatting. The rest did not. Making it the formatter's job is
//  what turns a rule people remember into a rule the code enforces —
//  every function here returns a string that is stable under a
//  perturbation smaller than its own displayed precision, and
//  `PhysicsFormatTests` asserts exactly that.
//

import Foundation

nonisolated enum PhysicsFormat {

    // MARK: The house precisions
    //
    // Named rather than passed, so "how many decimals does a length get"
    // has one answer instead of one per call site.

    /// Metres, seconds, kilograms, m/s — the everyday quantities.
    /// Millimetre resolution is finer than anything in these rooms is
    /// placed to.
    static let standardDecimals = 3
    /// Angles in degrees, where a tenth is already past what a hand can
    /// set.
    static let angleDecimals = 1

    // MARK: Fixed-point

    /// A value at a stated number of decimals, quantised first.
    ///
    /// The quantisation is not decoration: `String(format:)` alone would
    /// round for display while the caller went on comparing unrounded
    /// values, and any caller caching "has the text changed" would see it
    /// change every frame.
    static func fixed(_ value: Double, decimals: Int = 2) -> String {
        guard value.isFinite else { return "—" }
        let quantised = quantise(value, decimals: decimals)
        // -0.00 is a real thing `%f` will print, and it reads as an error.
        let cleaned = quantised == 0 ? 0 : quantised
        return typographic(String(format: Self.fixedSpecifier(decimals), cleaned))
    }

    /// `"%.<n>f"` without building it each time.
    ///
    /// The interpolated form allocated a format String on every call —
    /// and this is called dozens of times a frame across the renderers
    /// (skyline labels, callouts, component labels, every readout row),
    /// so the app was allocating a throwaway String to describe how to
    /// build a String. Seven entries cover every precision the house
    /// uses; anything past them falls back to the old path rather than
    /// growing a table nobody reads.
    private static let fixedSpecifiers = [
        "%.0f", "%.1f", "%.2f", "%.3f", "%.4f", "%.5f", "%.6f",
    ]

    private static func fixedSpecifier(_ decimals: Int) -> String {
        let clamped = max(decimals, 0)
        return clamped < fixedSpecifiers.count
            ? fixedSpecifiers[clamped]
            : "%.\(clamped)f"
    }

    /// U+2212 MINUS SIGN, not the hyphen `%f` emits.
    ///
    /// THE APP ALREADY DECIDED THIS and only authored strings got the
    /// memo. Eight hand-written labels use `−`, including the Time
    /// Capsule's "−%.2f s" — which puts a typographic minus in front of
    /// a number whose OWN sign, when it has one, is a hyphen. So a
    /// negative potential renders "-12.00 V" a few centimetres from a
    /// scrub reading "−1.50 s", in two different glyphs, at two
    /// different widths, because one came from a keyboard and one from
    /// `printf`.
    ///
    /// A hyphen is also the wrong character: it is a word-joiner, drawn
    /// short and high to sit between letters. The minus sign is drawn to
    /// the width and height of the digits beside it.
    static func typographic(_ string: String) -> String {
        string.replacingOccurrences(of: "-", with: "\u{2212}")
    }

    /// The value a `fixed` string represents — what a caller should
    /// compare or cache on.
    static func quantise(_ value: Double, decimals: Int) -> Double {
        guard value.isFinite else { return value }
        let scale = pow(10.0, Double(max(decimals, 0)))
        return (value * scale).rounded() / scale
    }

    // MARK: Units

    /// A value and its unit, at the house precision for that unit.
    static func measurement(_ value: Double, _ unit: String,
                            decimals: Int = standardDecimals) -> String {
        "\(fixed(value, decimals: decimals)) \(unit)"
    }

    /// Degrees, with the symbol closed up against the number as typography
    /// wants.
    static func angle(_ degrees: Double, decimals: Int = angleDecimals) -> String {
        "\(fixed(degrees, decimals: decimals))°"
    }

    /// A quantity with an SI prefix chosen so the mantissa reads in the
    /// 1…999 band: 4.7e-5 T becomes "47.0 µT" rather than "0.0000470 T".
    ///
    /// This is what the app was spelling four different ways. Magnetism
    /// hand-wrote µT, Electric Fields hand-wrote mT and kT in separate
    /// places, and each carried its own multiply-and-round.
    static func metric(_ value: Double, _ unit: String,
                       decimals: Int = 1) -> String {
        guard value.isFinite else { return "— \(unit)" }
        guard value != 0 else { return "0 \(unit)" }

        let prefixes: [(exponent: Int, symbol: String)] = [
            (-15, "f"), (-12, "p"), (-9, "n"), (-6, "µ"), (-3, "m"),
            (0, ""), (3, "k"), (6, "M"), (9, "G"), (12, "T"),
        ]
        let magnitude = log10(abs(value))
        // Step DOWN to the prefix whose band this sits in, so 999 stays
        // 999 and 1000 becomes 1 k.
        var index = prefixes.lastIndex { Double($0.exponent) <= magnitude }
            ?? prefixes.startIndex
        // AND STEP UP AGAIN IF ROUNDING PUSHED IT OUT OF THE BAND. The
        // prefix is chosen from the unrounded magnitude, but what gets
        // shown is rounded — so 999.97 V at one decimal picked the empty
        // prefix and then printed "1000.0 V", which is the one string
        // this function exists to prevent. Nothing about it looks wrong
        // until you notice the app can also say "1.0 kV".
        if abs(quantise(value / pow(10, Double(prefixes[index].exponent)),
                        decimals: decimals)) >= 1000,
           index + 1 < prefixes.endIndex {
            index += 1
        }
        let chosen = prefixes[index]
        let scaled = value / pow(10, Double(chosen.exponent))
        return "\(fixed(scaled, decimals: decimals)) \(chosen.symbol)\(unit)"
    }

    // MARK: Scientific

    /// "2.4 × 10⁵" — for values spanning many orders of magnitude, where
    /// a prefix would run out. Small exponents read better plain.
    static func scientific(_ value: Double) -> String {
        guard value.isFinite, value != 0 else { return "0" }
        let exponent = Int(floor(log10(abs(value))))
        guard abs(exponent) >= 3 else { return fixed(value, decimals: 2) }
        // THROUGH `fixed`, not `String(format:)` directly. Building the
        // mantissa here bypassed both house rules this file exists to
        // enforce — the quantisation AND the minus sign — so a negative
        // value came out of the canon wearing a hyphen. Caught by
        // `testEveryNegativeReadingUsesTheTypographicMinus` on its first
        // run, which is the argument for asserting over every entry
        // point rather than the one being edited.
        //
        // (The superscript table already maps "-" to "⁻", so a negative
        // EXPONENT was always right. It was only the mantissa.)
        let mantissa = value / pow(10, Double(exponent))
        return "\(fixed(mantissa, decimals: 2)) × 10\(superscript(exponent))"
    }

    // MARK: States

    /// One spelling for a switched state, everywhere.
    ///
    /// The notebook had three: "on"/"off", "free"/"frozen" and
    /// "yes"/"no — unbound". A reader comparing two captured moments
    /// should not have to notice which room wrote them.
    static func state(_ isOn: Bool) -> String { isOn ? "on" : "off" }

    private static func superscript(_ exponent: Int) -> String {
        let digits: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻",
        ]
        return String(String(exponent).compactMap { digits[$0] })
    }
}
