//
//  Formula.swift
//  Physics Playground — Shell
//
//  A reading's equation, typeset. Unicode has subscript digits and a few
//  letters (₁ ᵢ ᵣ), so most of a formula is plain text; the rest — the
//  D of a drag coefficient, the c of a critical angle, the LED of a diode
//  drop — is marked `_x` for one character or `_{xy}` for several, and set
//  smaller and lowered here. (Unicode's own ᵢ and ᵣ come from a fallback
//  font and sit apart from their letter, so they are marked too.)
//
//  It breaks only where a reader would: at the comma between two clauses,
//  or just before the "=" where a law's numbers begin. Every other space
//  holds, so "− 60°" never lands alone on a line.
//

import Foundation
import SwiftUI

enum Formula {
    /// One run of a formula: normal text, or a subscript.
    struct Run: Equatable {
        var text: String
        var isSubscript: Bool
    }

    /// Splits `formula` at its subscript marks. An underscore with nothing
    /// after it, or an unclosed brace, is kept as text rather than lost.
    static func runs(_ formula: String) -> [Run] {
        var runs: [Run] = []
        var plain = ""
        var index = formula.startIndex
        func flush() {
            if !plain.isEmpty { runs.append(Run(text: plain, isSubscript: false)) }
            plain = ""
        }
        while index < formula.endIndex {
            let character = formula[index]
            let next = formula.index(after: index)
            guard character == "_", next < formula.endIndex else {
                plain.append(character)
                index = next
                continue
            }
            if formula[next] == "{" {
                guard let close = formula[next...].firstIndex(of: "}") else {
                    plain.append(character)
                    index = next
                    continue
                }
                flush()
                runs.append(Run(text: String(formula[formula.index(after: next)..<close]),
                                isSubscript: true))
                index = formula.index(after: close)
            } else {
                flush()
                runs.append(Run(text: String(formula[next]), isSubscript: true))
                index = formula.index(after: next)
            }
        }
        flush()
        return runs
    }

    /// The formula with every space made unbreakable except the comma
    /// between clauses and the space before a clause's second "=".
    static func breakable(_ formula: String) -> String {
        let glue = { (text: String) in text.replacingOccurrences(of: " ", with: "\u{00A0}") }
        return formula.components(separatedBy: ", ").map { clause in
            let sides = clause.components(separatedBy: " = ")
            guard sides.count > 1 else { return glue(clause) }
            return glue(sides[0]) + "\u{00A0}=\u{00A0}" + glue(sides[1])
                + sides.dropFirst(2).map { " =\u{00A0}" + glue($0) }.joined()
        }.joined(separator: ", ")
    }

    /// The formula as text, its subscripts set small and lowered.
    static func attributed(_ formula: String) -> AttributedString {
        var result = AttributedString()
        for run in runs(breakable(formula)) {
            var piece = AttributedString(run.text)
            if run.isSubscript {
                piece.font = .caption2
                piece.baselineOffset = -2.5
            }
            result += piece
        }
        return result
    }

    /// The formula with its marks taken out, for VoiceOver and for search.
    static func plain(_ formula: String) -> String {
        runs(formula).map(\.text).joined()
    }
}
