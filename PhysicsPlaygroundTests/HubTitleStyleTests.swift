//
//  HubTitleStyleTests.swift
//  Physics Playground — app tests
//
//  The engine behind the home's three display texts. There used to be
//  four voices and half of these tests existed to prove they really
//  differed; the three losers are gone, and what is left to pin is the
//  contract the lockup math actually leans on: real measured extents, a
//  buildable line, capitals, and ONE solid.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

final class HubTitleStyleTests: XCTestCase {

    /// Real, positive extents on every axis — the flush-width lockup
    /// divides by the width, so a zero would scale a line to infinity
    /// and hang the sign across the room.
    func testTheVoiceMeasuresRealExtents() {
        let extents = HubTitleStyle.extents("Magnetism", size: 0.12)
        XCTAssertGreaterThan(extents.x, 0.1, "no width")
        XCTAssertGreaterThan(extents.y, 0.03, "no height")
        XCTAssertGreaterThan(extents.z, 0, "no depth at all")
    }

    /// Milled from stock, and the depth is not incidental: the letters'
    /// own extruded sides ARE the depth cue, which is why `line` can get
    /// away with a single pass. Flatten this and the type loses the only
    /// shadow it has.
    func testTheTypeIsDeeplyExtruded() {
        let extents = HubTitleStyle.extents("Energy", size: 0.12)
        XCTAssertGreaterThan(extents.z, 0.12 * 0.4,
                             "the plaque should be milled deep")
    }

    /// The plaque speaks in capitals.
    func testTheVoiceUppercases() {
        XCTAssertEqual(HubTitleStyle.display("& Magnetism"), "& MAGNETISM")
    }

    /// It builds a line in both roles — neutral wordmark and accented
    /// door sign — and both have visible width.
    @MainActor
    func testItBuildsBothRoles() {
        for accent in [nil, UIColor.systemGreen] {
            let line = HubTitleStyle.line("Mechanics", size: 0.12, accent: accent)
            XCTAssertFalse(line.children.isEmpty, "built an empty line")
            let width = line.visualBounds(relativeTo: line).extents.x
            XCTAssertGreaterThan(width, 0.1, "the line has no visible width")
        }
    }

    /// ONE solid, not a stack. Two meshes sharing a volume is what made
    /// the letters look doubled and the lines look collided: a dark copy
    /// has to sit further back than the extrusion is deep, and this type
    /// is deep, so any offset small enough to read as a shadow punched
    /// through the faces.
    @MainActor
    func testTheLineIsASingleSolid() {
        let line = HubTitleStyle.line("MECHANICS", size: 0.12,
                                      accent: .systemOrange)
        XCTAssertEqual(line.children.count, 1,
                       "the plaque grew a second pass — its own extruded "
                       + "sides are the depth cue, and a stacked copy will "
                       + "interpenetrate them")
    }

    // MARK: The keyline

    /// EVERY GLYPH GETS A SHELL. The keyline is what the wordmark is
    /// read against on a bright wall; one letter without it is one
    /// letter that disappears at the worst moment.
    @MainActor
    func testEveryGlyphIsKeylined() {
        let word = "PHYSICS"
        let built = HubTitleStyle.keylined(word, size: 0.17, accent: nil)
        XCTAssertEqual(built.entity.children.count, word.count * 2, """
            \(built.entity.children.count) parts for \(word.count) letters. \
            Each glyph is a letter plus its casing, so this should be twice \
            the letter count — anything less is a letter with no keyline.
            """)
    }

    /// THE SHELL IS BEHIND THE LETTER, and this is the assertion that
    /// catches the whole thing rendering as a dark blob. The casing is
    /// swollen and deeper than what it backs; if its face ever comes
    /// forward of the letter's, the wordmark is a black slab with the
    /// shape of some words.
    @MainActor
    func testTheKeylineSitsBehindTheLetterItBacks() {
        let word = "PLAY"
        let built = HubTitleStyle.keylined(word, size: 0.17, accent: nil)
        let parts = built.entity.children.map {
            $0.visualBounds(relativeTo: built.entity)
        }
        XCTAssertEqual(parts.count, word.count * 2, "unexpected part count")

        for index in stride(from: 0, to: parts.count, by: 2) {
            let letter = parts[index], casing = parts[index + 1]
            XCTAssertLessThan(casing.max.z, letter.max.z, """
                a casing's face reaches z \(casing.max.z) against its \
                letter's \(letter.max.z) — level with or in front of the type \
                it is supposed to sit behind, which draws the wordmark as a \
                dark blob shaped like some words.
                """)
            XCTAssertLessThan(casing.min.z, letter.min.z, """
                the casing does not run deeper than its letter, so the letter \
                is not contained by it — that is two solids sharing a volume, \
                which is the doubling this builder exists to avoid.
                """)
        }
    }

    /// SHELL AND LETTER SHARE A CENTRE. This is the failure `namePlate`
    /// documents and this builder exists to avoid: scale a whole string
    /// and every glyph moves outward from the string's centre, so the
    /// casing letters land between their own neighbours and the word
    /// reads as if printed twice. Built per glyph, the two cannot
    /// separate — unless someone reintroduces a string-wide scale, which
    /// is what this catches.
    @MainActor
    func testEachCasingIsCentredOnItsOwnGlyph() {
        let word = "PLAYGROUND"
        let built = HubTitleStyle.keylined(word, size: 0.17, accent: nil)
        let parts = built.entity.children.map {
            $0.visualBounds(relativeTo: built.entity)
        }
        // The builder adds each glyph as a letter followed by its
        // casing, so the pairing is positional.
        XCTAssertEqual(parts.count, word.count * 2, "unexpected part count")

        for index in stride(from: 0, to: parts.count, by: 2) {
            let letter = parts[index], casing = parts[index + 1]
            XCTAssertEqual(casing.center.x, letter.center.x, accuracy: 0.002, """
                a casing centred at x \(casing.center.x) backs a letter at \
                \(letter.center.x). Off-centre casings are the printed-twice \
                failure returning.
                """)
            XCTAssertEqual(casing.center.y, letter.center.y, accuracy: 0.002,
                           "the casing is not vertically centred on its letter")
            XCTAssertGreaterThan(casing.extents.x, letter.extents.x, """
                the casing is no wider than the letter it backs, so there is \
                no keyline to see.
                """)
        }
    }

    /// THE PER-GLYPH LAYOUT AGREES WITH THE FONT'S OWN.
    ///
    /// The builder lays the line out itself — right edge of glyph i is
    /// the right edge of the prefix ending at glyph i — rather than
    /// letting `generateText` set one string. That is the only part of
    /// this that could silently drift: if the placement accumulated
    /// error, letters would space out or crowd together and nothing
    /// would fail. So the built width is compared against what the font
    /// produces for the same word in one pass, which is the layout being
    /// imitated.
    @MainActor
    func testTheKeylinedLineIsAsWideAsTheFontWouldSetIt() {
        for word in ["PHYSICS", "PLAYGROUND"] {
            let single = HubTitleStyle.extents(word, size: 0.17).x
            let built = HubTitleStyle.keylined(word, size: 0.17, accent: nil).extents.x
            // The casing swells past the outermost letters on both
            // sides, so the keylined line is legitimately a little
            // wider — but only by about that swell.
            let allowed = single * (1 + HubTitleStyle.keylineSwell)
            XCTAssertGreaterThan(built, single * 0.98, """
                \(word) sets \(built) m keylined against \(single) m in one \
                pass — narrower, so the per-glyph placement is crowding the \
                letters together.
                """)
            XCTAssertLessThan(built, allowed + 0.01, """
                \(word) sets \(built) m keylined against \(single) m in one \
                pass. The casing explains a few per cent; this is the \
                placement spacing the letters out.
                """)
        }
    }

    /// ONE BASELINE. Each glyph is generated separately, so the one way
    /// to get this wrong is to re-centre every letter on its own ink —
    /// which drops "O" and "S", the letters that overshoot the cap line,
    /// below their neighbours.
    @MainActor
    func testEveryGlyphSitsOnTheSameBaseline() {
        let built = HubTitleStyle.keylined("PLAYGROUND", size: 0.17, accent: nil)
        let feet = built.entity.children.map {
            $0.visualBounds(relativeTo: built.entity).min.y
        }
        let lowest = feet.min() ?? 0, highest = feet.max() ?? 0
        let capHeight = built.extents.y
        XCTAssertLessThan(highest - lowest, capHeight * 0.12, """
            the glyphs' feet span \(highest - lowest) m against a cap height \
            of \(capHeight) m — they are not standing on one line. Round \
            letters overshoot by a per cent or two; this is more than that.
            """)
    }

    /// An accented sign is tinted toward the stock alloy rather than
    /// printed in the raw domain hue: the signage is metal, and metal
    /// takes a colour by being anodised, not by being painted.
    func testAnAccentIsPulledTowardTheAlloy() {
        let raw = UIColor.systemGreen
        let stock = HubTitleStyle.blend(raw, toward: UIColor(white: 0.72, alpha: 1),
                                        by: 0.30)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        raw.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        stock.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        XCTAssertGreaterThan(r2, r1, "the alloy should lift the dark channels")
        XCTAssertLessThan(g2, g1, "and pull the saturated one back")
        XCTAssertEqual(a2, a1, accuracy: 0.001, "alpha should survive a blend")
    }
}
