//
//  AccentAuthorityTests.swift
//  PhysicsPlaygroundTests
//
//  One authority for the accent hues: module accents own their values
//  in `DesignTokens.Palette`, and `HubDomain.color` reads them.
//  Source-reading, scoped to the two authority files.
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

    /// Every stock colour SwiftUI and UIKit hand out by name. The list
    /// closes the class rather than the three instances that were wrong on
    /// the day the test was written.
    private static let stockColorNames = [
        "black", "blue", "brown", "clear", "cyan", "gray", "grey", "green",
        "indigo", "mint", "orange", "pink", "purple", "red", "teal",
        "white", "yellow",
    ]

    /// The palette defines accents as owned values, never stock colours — a
    /// stock colour is not even a fixed hue across platforms.
    func testThePaletteOwnsItsAccentHues() throws {
        let lines = try source("PhysicsPlayground/DesignSystem/DesignTokens.swift")
        XCTAssertFalse(lines.isEmpty, "DesignTokens.swift unreadable — scanning nothing")

        var accentLinesScanned = 0
        for (number, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
            // Only the hue definitions. A `Color(uiColor:)` twin or a
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

    /// CIE76 ΔE in Lab; enough to ask "are these obviously different".
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

    /// How far apart two colours in the same view must be: 20 is
    /// "different colour", not "different shade", for two arrows seen
    /// through passthrough.
    private let minimumSeparation = 20.0

    /// An accent may not collide with a vector colour: an arrow the colour
    /// of the bank behind it cannot be followed.
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

    /// One collision that predates this test, asserted at its current
    /// distance so it cannot quietly worsen: `kinematicsAccent` sits ΔE
    /// 13.5 from the acceleration arrow. The search for a replacement was
    /// run and there is no winner (every bright warm colour near orange is
    /// orange; the unconstrained winners are greens, the E&M door), so the
    /// owner kept #FF9F0A.
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

    /// The vector colours must differ from each other: a component of a sum
    /// has to be distinguishable from the sum.
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

    /// A lab's field lines are its accent, derived from it, so the
    /// furniture and the centrepiece are one colour.
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

    /// Every module accent, by name — one per lab.
    private static let moduleAccents: [(String, UIColor)] = [
        ("electrostaticsAccent", UIColor(DesignTokens.Palette.electrostaticsAccent)),
        ("magnetismAccent", UIColor(DesignTokens.Palette.magnetismAccent)),
        ("gravityAccent", UIColor(DesignTokens.Palette.gravityAccent)),
        ("kinematicsAccent", UIColor(DesignTokens.Palette.kinematicsAccent)),
        ("circuitsAccent", UIColor(DesignTokens.Palette.circuitsAccent)),
        ("pendulumsAccent", UIColor(DesignTokens.Palette.pendulumsAccent)),
        ("opticsAccent", UIColor(DesignTokens.Palette.opticsAccent)),
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

    // MARK: The bodies' colours

    private static let namedBodies = ["Mercury", "Venus", "Earth", "Moon", "Mars", "Jupiter",
                                      "Saturn", "Uranus", "Neptune", "Asteroid", "Comet"]

    /// Every body wears its own colour on its sphere and its path: no two
    /// named bodies share one (four of ten used to be the same teal), and
    /// none can be mistaken for the ring's accent or a vector arrow.
    func testCelestialColoursAreDistinctAndClearTheAccentAndVectors() {
        let colours = Self.namedBodies.map { ($0, DesignTokens.Palette.celestialUI($0)) }
        for (i, a) in colours.enumerated() {
            for b in colours.dropFirst(i + 1) {
                let distance = deltaE(a.1, b.1)
                XCTAssertGreaterThanOrEqual(distance, 12,
                                            "\(a.0) and \(b.0) are ΔE \(distance) apart")
            }
            for (name, other) in [("the ring's accent", UIColor(DesignTokens.Palette.gravityAccent)),
                                  ("the velocity arrow", VectorPalette.velocity),
                                  ("the acceleration arrow", VectorPalette.acceleration),
                                  ("the force arrow", VectorPalette.force)] {
                let distance = deltaE(a.1, other)
                XCTAssertGreaterThanOrEqual(distance, 12,
                                            "\(a.0) is ΔE \(distance) from \(name)")
            }
        }
    }

    /// Worlds from the well take hues from the golden angle: ten in a row are all different.
    func testSpawnedWorldsGetDistinctColours() {
        let worlds = (1...10).map { DesignTokens.Palette.celestialUI("World \($0)") }
        for (i, a) in worlds.enumerated() {
            for (j, b) in worlds.enumerated() where j > i {
                XCTAssertGreaterThanOrEqual(deltaE(a, b), 10,
                                            "World \(i + 1) and World \(j + 1) look alike")
            }
        }
    }
}
