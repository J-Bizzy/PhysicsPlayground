//
//  PhysicsFormat.swift
//  Physics Playground — Core kernel
//
//  Number formatting for stats panels across all simulations: physics
//  values span many orders of magnitude, so the house style is readable
//  scientific notation with true superscripts ("2.4 × 10⁵").
//

import Foundation

nonisolated enum PhysicsFormat {
    /// "2.4 × 10⁵" — scientific notation for values spanning many orders of
    /// magnitude; small exponents read better as plain numbers.
    static func scientific(_ value: Double) -> String {
        guard value.isFinite, value != 0 else { return "0" }
        let exponent = Int(floor(log10(abs(value))))
        guard abs(exponent) >= 3 else { return String(format: "%.2f", value) }
        let mantissa = value / pow(10, Double(exponent))
        return String(format: "%.2f × 10%@", mantissa, superscript(exponent))
    }

    static func fixed(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.2f", value)
    }

    private static func superscript(_ exponent: Int) -> String {
        let digits: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻",
        ]
        return String(String(exponent).compactMap { digits[$0] })
    }
}
