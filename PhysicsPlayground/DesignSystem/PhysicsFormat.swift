//
//  PhysicsFormat.swift
//  Physics Playground — Design system
//
//  How a number is written, once, for the whole app. Every function returns
//  a string stable under a perturbation smaller than its displayed precision
//  (quantise before formatting), so per-frame readouts don't rebuild their
//  textures — `PhysicsFormatTests` asserts exactly that.
//

import Foundation

nonisolated enum PhysicsFormat {

    // MARK: The house precisions

    /// Metres, seconds, kilograms, m/s — millimetre resolution.
    static let standardDecimals = 3
    /// Angles in degrees — a tenth is past what a hand can set.
    static let angleDecimals = 1

    // MARK: Fixed-point

    /// A value at a stated number of decimals, quantised first — so a
    /// caller caching "has the text changed" doesn't see it change per frame.
    static func fixed(_ value: Double, decimals: Int = 2) -> String {
        guard value.isFinite else { return "—" }
        let quantised = quantise(value, decimals: decimals)
        // -0.00 is a real thing `%f` will print, and it reads as an error.
        let cleaned = quantised == 0 ? 0 : quantised
        return typographic(String(format: Self.fixedSpecifier(decimals), cleaned))
    }

    /// A round value as a tick mark carries it: as few decimals as it
    /// needs, up to three — "0.5", "1", "20", "0.05".
    static func compact(_ value: Double) -> String {
        for decimals in 0...3 where abs(quantise(value, decimals: decimals) - value)
            <= 1e-9 * max(abs(value), 1) {
            return fixed(value, decimals: decimals)
        }
        return fixed(value, decimals: 3)
    }

    /// `"%.<n>f"` without allocating a format String per call — this runs
    /// dozens of times a frame across the renderers.
    private static let fixedSpecifiers = [
        "%.0f", "%.1f", "%.2f", "%.3f", "%.4f", "%.5f", "%.6f",
    ]

    private static func fixedSpecifier(_ decimals: Int) -> String {
        let clamped = max(decimals, 0)
        return clamped < fixedSpecifiers.count
            ? fixedSpecifiers[clamped]
            : "%.\(clamped)f"
    }

    /// U+2212 minus sign, not the hyphen `%f` emits — matching the authored
    /// labels, and drawn to the width and height of the digits beside it.
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

    /// A count of things whose noun agrees with the number as shown:
    /// "1 Earth", "1.00 Sun", "2 Earths", "0.50 Earths". Decided on the
    /// quantised value, so 1.004 shown as "1.00" is singular too.
    static func count(_ value: Double, singular: String, plural: String,
                      decimals: Int = 0) -> String {
        let shown = quantise(value, decimals: decimals)
        return measurement(value, abs(shown) == 1 ? singular : plural,
                           decimals: decimals)
    }

    /// A speed multiplier, "20×" or "−20×" — a true minus, as every other
    /// signed number in the room.
    static func multiplier(_ value: Double, decimals: Int = 0) -> String {
        "\(fixed(value, decimals: decimals))×"
    }

    /// Degrees, with the symbol closed up against the number.
    static func angle(_ degrees: Double, decimals: Int = angleDecimals) -> String {
        "\(fixed(degrees, decimals: decimals))°"
    }

    /// A quantity with an SI prefix chosen so the mantissa reads in the
    /// 1…999 band: 4.7e-5 T becomes "47.0 µT" rather than "0.0000470 T".
    static func metric(_ value: Double, _ unit: String,
                       decimals: Int = 1) -> String {
        guard value.isFinite else { return "— \(unit)" }
        guard value != 0 else { return "0 \(unit)" }

        let prefixes: [(exponent: Int, symbol: String)] = [
            (-15, "f"), (-12, "p"), (-9, "n"), (-6, "µ"), (-3, "m"),
            (0, ""), (3, "k"), (6, "M"), (9, "G"), (12, "T"),
        ]
        let magnitude = log10(abs(value))
        // Step down to the prefix whose band this sits in: 999 stays 999,
        // 1000 becomes 1 k.
        var index = prefixes.lastIndex { Double($0.exponent) <= magnitude }
            ?? prefixes.startIndex
        // Step up again if rounding pushed it out of the band — otherwise
        // 999.97 V at one decimal prints "1000.0 V".
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
        // Through `fixed`, not `String(format:)` — it enforces both the
        // quantisation and the typographic minus for the mantissa.
        let mantissa = value / pow(10, Double(exponent))
        return "\(fixed(mantissa, decimals: 2)) × 10\(superscript(exponent))"
    }

    // MARK: Spoken

    /// What VoiceOver should say for a display string: "6.0 µC" as "6.0
    /// microcoulombs", "24 Ω" as "24 ohms", "3.5 × 10²²" as "3.5 times 10 to
    /// the 22". VoiceOver reads Ω as "omega", skips superscripts and says
    /// "m/s²" letter by letter; the screen keeps the symbols.
    static func spoken(_ display: String) -> String {
        guard !display.isEmpty else { return display }
        let tokens = display
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        var words: [String] = []
        for token in tokens {
            if let unit = spokenUnits[token] {
                words.append(unit)
                continue
            }
            switch token {
            case "×": words.append("times"); continue
            case "·": words.append(","); continue
            case "±": words.append("plus or minus"); continue
            default: break
            }
            words.append(spokenNumber(token))
        }
        return words.joined(separator: " ").replacingOccurrences(of: " ,", with: ",")
    }

    /// A number with its marks spoken: a leading minus, a superscript
    /// exponent ("10²²"), a trailing degree or percent sign.
    private static func spokenNumber(_ token: String) -> String {
        var text = token
        var suffix = ""
        if text.hasSuffix("°") { text.removeLast(); suffix = " degrees" }
        else if text.hasSuffix("%") { text.removeLast(); suffix = " percent" }
        let exponentDigits: [Character: Character] = [
            "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
            "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-",
        ]
        if let start = text.firstIndex(where: { exponentDigits[$0] != nil }) {
            let base = String(text[..<start])
            let exponent = String(text[start...].compactMap { exponentDigits[$0] })
            text = "\(base) to the \(exponent)"
        }
        if text.hasPrefix("-"), text.count > 1 {
            text = "minus " + text.dropFirst()
        }
        return text.replacingOccurrences(of: "to the -", with: "to the minus ") + suffix
    }

    /// Every unit symbol the app puts on screen, as words.
    private static let spokenUnits: [String: String] = [
        "Ω": "ohms", "kΩ": "kilohms", "MΩ": "megohms",
        "V": "volts", "mV": "millivolts", "kV": "kilovolts",
        "A": "amps", "mA": "milliamps", "µA": "microamps",
        "W": "watts", "mW": "milliwatts",
        "F": "farads", "mF": "millifarads", "µF": "microfarads", "nF": "nanofarads",
        "H": "henries", "mH": "millihenries",
        "C": "coulombs", "µC": "microcoulombs", "nC": "nanocoulombs",
        "Hz": "hertz", "J": "joules", "mJ": "millijoules", "µJ": "microjoules",
        "N": "newtons", "N/m": "newtons per metre", "N/C": "newtons per coulomb",
        "V/m": "volts per metre", "T": "tesla", "mT": "millitesla", "µT": "microtesla",
        "A·m²": "amp square metres",
        "m": "metres", "cm": "centimetres", "mm": "millimetres", "km": "kilometres",
        "AU": "astronomical units",
        "s": "seconds", "ms": "milliseconds", "µs": "microseconds", "min": "minutes",
        "m/s": "metres per second", "km/s": "kilometres per second",
        "m/s²": "metres per second squared", "rad/s": "radians per second",
        "kg": "kilograms", "g": "grams", "rpm": "revolutions per minute",
        "yr": "years", "days": "days",
        "nm": "nanometres", "°": "degrees", "%": "percent",
    ]

    // MARK: States

    /// One spelling for a switched state, everywhere.
    static func state(_ isOn: Bool) -> String { isOn ? "on" : "off" }

    private static func superscript(_ exponent: Int) -> String {
        let digits: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻",
        ]
        return String(String(exponent).compactMap { digits[$0] })
    }
}
