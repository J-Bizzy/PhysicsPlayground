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

    /// The palette defines accents as owned values, never as stock
    /// SwiftUI colours — a stock colour is an unowned hue that happens
    /// to be near a door.
    func testThePaletteOwnsItsAccentHues() throws {
        let lines = try source("PhysicsPlayground/DesignSystem/DesignTokens.swift")
        XCTAssertFalse(lines.isEmpty, "DesignTokens.swift unreadable — scanning nothing")
        for (number, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
            for stock in ["Color.yellow", "Color.green", "Color.orange"] {
                XCTAssertFalse(trimmed.contains(stock), """
                    DesignTokens.swift:\(number + 1) defines a hue as `\(stock)`. \
                    An accent is an OWNED value (the door hues #30D158 / \
                    #FF9F0A are the precedent); a stock colour beside them \
                    recreates the two-greens drift this test closed.
                    """)
            }
        }
    }

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
