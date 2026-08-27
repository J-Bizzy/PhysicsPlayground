//
//  AccentAuthorityTests.swift
//  PhysicsPlaygroundTests
//
//  One authority for the accent hues, as an assertion (2026-08-06).
//
//  The app shipped for weeks with two greens (#30D158 on the E&M door,
//  stock `Color.green` on Circuits) and two oranges (#FF9F0A / stock
//  `.orange`) defined in different files — near enough to read as the
//  same colour badly printed, far enough to be two colours. The fix is
//  structural: module accents own the values in `DesignTokens.Palette`,
//  and `HubDomain.color` READS them. These tests keep both halves true,
//  in the house source-reading style, scoped to the two authority
//  files — a `.orange` warning triangle in a banner is a semantic
//  system colour and none of this test's business.
//

import XCTest
import RenderKit
import SwiftUI
@testable import PhysicsPlayground

final class AccentAuthorityTests: XCTestCase {

    private func projectRoot() throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile.deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> [Substring] {
        let url = try projectRoot().appendingPathComponent(relativePath)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// Every stock colour SwiftUI and UIKit hand out by name.
    ///
    /// THE LIST IS THE POINT. This test used to check three spellings —
    /// `Color.yellow`, `Color.green`, `Color.orange` — because those
    /// were the three that were wrong on the day it was written. It
    /// therefore passed for months over `gravityAccent = Color.indigo`
    /// and `pendulumsAccent = Color.purple`, which are the same defect
    /// in a hue the author had not thought of. A criterion that lists
    /// the instances somebody already found is the same act of
    /// attention that missed the others; this one closes the class.
    private static let stockColorNames = [
        "black", "blue", "brown", "clear", "cyan", "gray", "grey", "green",
        "indigo", "mint", "orange", "pink", "purple", "red", "teal",
        "white", "yellow",
    ]

    /// The palette defines accents as owned values, never as stock
    /// SwiftUI colours — a stock colour is an unowned hue that happens
    /// to be near a door. It is also not a fixed hue: `Color.indigo`
    /// resolves differently on visionOS than the iOS value its name
    /// suggests, so "stock" does not even mean "the same colour".
    func testThePaletteOwnsItsAccentHues() throws {
        let lines = try source("PhysicsPlayground/DesignSystem/DesignTokens.swift")
        XCTAssertFalse(lines.isEmpty, "DesignTokens.swift unreadable — scanning nothing")

        var accentLinesScanned = 0
        for (number, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
            // Only the hue DEFINITIONS. A `Color(uiColor:)` twin or a
            // `UIColor(someAccent)` derivation is not a stock colour.
            guard trimmed.contains("Accent"), trimmed.contains("=") else { continue }
            accentLinesScanned += 1

            for stock in Self.stockColorNames {
                for spelling in ["Color.\(stock)", "UIColor.\(stock)",
                                 "UIColor.system\(stock.capitalized)"] {
                    XCTAssertFalse(trimmed.contains(spelling), """
                        DesignTokens.swift:\(number + 1) defines an accent as \
                        `\(spelling)`.

                        An accent is an OWNED value (the door hues #30D158 / \
                        #FF9F0A are the precedent); a stock colour beside them \
                        recreates the two-greens drift this test closed — and a \
                        stock colour is not even a fixed number across platforms.

                        If you want that exact hue, MEASURE it and write the \
                        literal, the way gravityAccent and pendulumsAccent were \
                        owned on 2026-08-09.
                        """)
                }
            }
        }
        // A negative criterion over lines it never matched passes
        // vacuously — the same guard `SellingCopyCriterionTests` uses.
        XCTAssertGreaterThanOrEqual(accentLinesScanned, 6, """
            only \(accentLinesScanned) accent definitions were scanned, and the \
            app has six modules. The line shape this test recognises has \
            changed and it is now checking almost nothing.
            """)
    }

    // MARK: Distance, not just ownership

    /// CIE76 ΔE in Lab. Crude next to ΔE2000 and entirely sufficient
    /// here: the question is "are these two obviously different", not
    /// "how different, to two decimals".
    private func deltaE(_ a: UIColor, _ b: UIColor) -> Double {
        func lab(_ colour: UIColor) -> (Double, Double, Double) {
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, alpha: CGFloat = 0
            colour.getRed(&r, green: &g, blue: &bl, alpha: &alpha)
            func linear(_ c: CGFloat) -> Double {
                let v = Double(c)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            let rl = linear(r), gl = linear(g), bll = linear(bl)
            let x = (rl * 0.4124 + gl * 0.3576 + bll * 0.1805) / 0.95047
            let y = rl * 0.2126 + gl * 0.7152 + bll * 0.0722
            let z = (rl * 0.0193 + gl * 0.1192 + bll * 0.9505) / 1.08883
            func f(_ t: Double) -> Double {
                t > pow(6.0 / 29, 3) ? pow(t, 1.0 / 3) : t / (3 * pow(6.0 / 29, 2)) + 4.0 / 29
            }
            let fx = f(x), fy = f(y), fz = f(z)
            return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
        }
        let (l1, a1, b1) = lab(a), (l2, a2, b2) = lab(b)
        return ((l1 - l2) * (l1 - l2) + (a1 - a2) * (a1 - a2)
                + (b1 - b2) * (b1 - b2)).squareRoot()
    }

    /// How far apart two colours that appear in the same view have to be.
    ///
    /// 20 is a judgement and this is the argument for it: 2.3 is the
    /// textbook just-noticeable difference for two swatches touching
    /// under lab conditions, which is nowhere near enough for two arrows
    /// on opposite sides of a room, seen through passthrough, at
    /// whatever the wall behind them is doing. 20 is "different colour",
    /// not "different shade".
    private let minimumSeparation = 20.0

    /// `testNoModuleAccentCollidesWithCompletionGold` STOOD HERE and was
    /// deleted on 2026-08-09 with the experiments system.
    ///
    /// It was a real catch in its day: `electrostaticsAccent` was #FFD60A
    /// against gold's #FFD640 — same red, same green, ΔE 11.6 — and every
    /// plate, well and label in Electric Fields wore it, so the lab read
    /// as an award. The accent was moved and stayed moved.
    ///
    /// There is nothing left to collide with. Gold was the colour of a
    /// completed experiment and nothing draws it now, so the assertion
    /// would be reserving a hue against a claim the app no longer makes.
    /// The `VectorPalette` test below is the live half of the same rule.

    /// …and nor may an accent collide with a VECTOR colour, which is the
    /// same failure one layer down: the arrows and the furniture are in
    /// the same view, and an arrow the colour of the bank behind it is
    /// an arrow you cannot follow.
    func testNoModuleAccentCollidesWithAVectorColour() {
        let vectors: [(String, UIColor)] = [
            ("velocity", VectorPalette.velocity),
            ("acceleration", VectorPalette.acceleration),
            ("force", VectorPalette.force),
            ("gravity", VectorPalette.gravity),
        ]
        for (name, accent) in Self.moduleAccents {
            for (vectorName, vector) in vectors {
                guard !Self.recordedCollisions.contains(where: {
                    $0.accent == name && $0.vector == vectorName
                }) else { continue }
                let distance = deltaE(accent, vector)
                XCTAssertGreaterThanOrEqual(distance, minimumSeparation, """
                    \(name) is ΔE \(String(format: "%.1f", distance)) from the \
                    \(vectorName) arrow — an arrow drawn over furniture its own \
                    colour cannot be followed.
                    """)
            }
        }
    }

    /// ONE COLLISION THAT PREDATES THIS TEST, recorded rather than
    /// excused, and asserted at its CURRENT distance so it cannot
    /// quietly get worse.
    ///
    /// `kinematicsAccent` #FF9F0A is the Mechanics door and sits ΔE 13.5
    /// from the acceleration arrow — under the bar, and both appear in
    /// Projectiles at once. Fixing it means changing a domain's identity
    /// hue or a vector colour used in all six labs, which is a decision
    /// about what the app looks like rather than a defect to sweep. This
    /// file's job is to make the number visible, not to make it.
    ///
    /// MEASURED IN SWIFT, NOT ESTIMATED. I first recorded this pair at
    /// 5.1 and a `gravityAccent`/velocity pair at 19.5, both from
    /// hand-typed approximations of `.systemOrange`, `.systemBlue` and
    /// `.indigo`. The real figures are 13.5 and 23.8 — so the second
    /// pair is not a collision at all and was about to be written into
    /// this file as one. UIKit's system colours are not the RGB triples
    /// they look like.
    ///
    /// THE SEARCH WAS RUN, AND THERE IS NO WINNER (2026-08-26). Brute
    /// force over the RGB cube in this file's own ΔE, scored by the worst
    /// separation from all four `VectorPalette` entries and all five other
    /// module accents, keeping only bright saturated candidates (L 62–92,
    /// chroma > 60 — without a chroma floor the search "wins" by going
    /// grey, which is far from everything and reads as nothing):
    ///
    /// · Warm band (r ≥ g ≥ b, still amber/gold): the best is #A3991E at
    ///   worst-ΔE 42.6 — but it is a dark olive. Every bright warm colour
    ///   near orange IS orange; that is what 13.5 is measuring.
    /// · Unconstrained: the winners are all bright greens (#A3FF00,
    ///   worst-ΔE 44.5). Numerically fine, conceptually wrong — green is
    ///   the E&M door, and Mechanics cannot wear it.
    /// · Yellow is `electrostaticsAccent` #FFEA05 already.
    ///
    /// So the choice is: a muddy door, a door that duplicates another
    /// domain, or moving `acceleration` — a vector colour used in all six
    /// labs — to fix one lab's furniture. The owner's call was to keep
    /// #FF9F0A and keep the number visible. Recorded here so the next
    /// person does not run the search again.
    func testTheKnownAccentCollisionHasNotWorsened() {
        let distance = deltaE(UIColor(DesignTokens.Palette.kinematicsAccent),
                              VectorPalette.acceleration)
        XCTAssertEqual(distance, 13.5, accuracy: 0.6, """
            kinematicsAccent vs acceleration is now ΔE \
            \(String(format: "%.1f", distance)), recorded as 13.5. If this got \
            better, tighten the literal; if worse, something moved a door \
            colour toward an arrow.
            """)
    }

    /// The pair above, by name, so the general test skips exactly it and
    /// nothing else.
    private static let recordedCollisions: [(accent: String, vector: String)] = [
        (accent: "kinematicsAccent", vector: "acceleration"),
    ]

    /// THE VECTOR COLOURS MUST DIFFER FROM EACH OTHER, which is where
    /// Pendulums went wrong: it drew gravity and the NET force in the
    /// identical red while its legend promised "purple gravity". A
    /// component of a sum has to be distinguishable from the sum.
    func testTheVectorColoursAreDistinguishableFromEachOther() {
        let vectors: [(String, UIColor)] = [
            ("velocity", VectorPalette.velocity),
            ("acceleration", VectorPalette.acceleration),
            ("force", VectorPalette.force),
            ("gravity", VectorPalette.gravity),
        ]
        for i in vectors.indices {
            for j in (i + 1)..<vectors.count {
                let distance = deltaE(vectors[i].1, vectors[j].1)
                XCTAssertGreaterThanOrEqual(distance, minimumSeparation, """
                    the \(vectors[i].0) and \(vectors[j].0) arrows are ΔE \
                    \(String(format: "%.1f", distance)) apart — drawn from the \
                    same object, they would read as one quantity.
                    """)
            }
        }
    }

    /// A LAB'S FIELD LINES ARE ITS ACCENT.
    ///
    /// The two modules that draw a field filling the room both derive the
    /// line colour from the module accent, so the furniture and the
    /// centrepiece move together and a lab is one colour.
    ///
    /// Electric Fields did this from the start; Magnetism carried a
    /// hardcoded lavender until 2026-08-26 — ΔE 46 from the pink accent
    /// on every plate around it. Deriving is not a tidiness preference
    /// here: the lavender was also the closest thing in the room to the
    /// S pole's blue, so the exception cost pole legibility too.
    func testAFieldLineIsItsModulesAccent() {
        let pairs: [(String, UIColor, UIColor)] = [
            ("Electric Fields",
             DesignTokens.Palette.fieldLineUI,
             UIColor(DesignTokens.Palette.electrostaticsAccent)),
            ("Magnetism",
             DesignTokens.Palette.magnetismLineUI,
             UIColor(DesignTokens.Palette.magnetismAccent)),
        ]
        for (lab, line, accent) in pairs {
            XCTAssertEqual(deltaE(line, accent), 0, accuracy: 0.5, """
                \(lab)'s field lines are ΔE \
                \(String(format: "%.1f", deltaE(line, accent))) from its own \
                accent — the lab is two colours, and the one filling the room \
                is not the one on the plates.
                """)
        }
    }

    /// …and the lines still have to clear the pole colours they are drawn
    /// between, which is the constraint deriving them could have broken.
    func testFieldLinesClearThePoleColours() {
        let lines: [(String, UIColor)] = [
            ("Electric Fields", DesignTokens.Palette.fieldLineUI),
            ("Magnetism", DesignTokens.Palette.magnetismLineUI),
        ]
        let poles: [(String, UIColor)] = [
            ("positive/N", DesignTokens.Palette.positiveUI),
            ("negative/S", DesignTokens.Palette.negativeUI),
        ]
        for (lab, line) in lines {
            for (poleName, pole) in poles {
                let distance = deltaE(line, pole)
                XCTAssertGreaterThanOrEqual(distance, minimumSeparation, """
                    \(lab)'s field lines are ΔE \
                    \(String(format: "%.1f", distance)) from the \(poleName) \
                    pole — the lines and the thing they come out of read as \
                    one object.
                    """)
            }
        }
    }

    /// Every module accent, by name. A LIST, and the only one in this
    /// file — the palette is a fixed set of six doors, so there is
    /// nothing to reflect over and nothing that grows without somebody
    /// editing `DesignTokens` in the same breath.
    private static let moduleAccents: [(String, UIColor)] = [
        ("electrostaticsAccent", UIColor(DesignTokens.Palette.electrostaticsAccent)),
        ("magnetismAccent", UIColor(DesignTokens.Palette.magnetismAccent)),
        ("gravityAccent", UIColor(DesignTokens.Palette.gravityAccent)),
        ("kinematicsAccent", UIColor(DesignTokens.Palette.kinematicsAccent)),
        ("circuitsAccent", UIColor(DesignTokens.Palette.circuitsAccent)),
        ("pendulumsAccent", UIColor(DesignTokens.Palette.pendulumsAccent)),
    ]

    /// The domain doors read the palette, never a literal of their own.
    func testTheDomainDoorsReadThePalette() throws {
        let lines = try source("PhysicsPlayground/Hub/HubDomains.swift")
        XCTAssertFalse(lines.isEmpty, "HubDomains.swift unreadable — scanning nothing")
        var readsTokens = false
        for (number, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
            XCTAssertFalse(trimmed.contains("Color(red:"), """
                HubDomains.swift:\(number + 1) holds a colour literal. The \
                door hues live in DesignTokens.Palette; a second copy here \
                is the drift the 2026-08-06 unification removed.
                """)
            if trimmed.contains("DesignTokens.Palette.") { readsTokens = true }
        }
        XCTAssertTrue(readsTokens,
                      "HubDomain no longer reads DesignTokens.Palette — the "
                      + "one-authority rule has come unwired")
    }
}
