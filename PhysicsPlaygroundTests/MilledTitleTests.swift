//
//  MilledTitleTests.swift
//  Physics Playground — app tests
//
//  The home's three display texts are milled in Blender now
//  (`Tools/hubtitles.py`) and loaded as assets. `HubTitleStyle.milled`
//  falls back to the generated line whenever anything is wrong, which
//  is the right behaviour in the room and a menace in a test suite:
//  EVERY EXISTING TEST IN `HubTitleStyleTests` DRIVES THE FALLBACK.
//  Delete all six assets and that file still passes, the app still
//  builds, the home still shows a wordmark, and the only symptom is
//  that the letters quietly have square edges again — which since the
//  casing was removed on 2026-08-11 is also the only thing holding
//  them against a bright wall.
//
//  So this file exists to assert the thing a green suite otherwise
//  cannot: that the assets are IN THE BUNDLE, that they LOAD, and that
//  the milled path is the one actually answering. It is the same lesson
//  the screenshot loop taught — a passing test proves the fallback
//  works, never that the feature does.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

final class MilledTitleTests: XCTestCase {

    /// Every line the home speaks, and the words are the lookup key —
    /// a baked asset only knows the words it was baked with, so a
    /// renamed door sign silently drops back to generated type.
    private static let lines = ["Physics", "Playground",
                                "Electricity", "& Magnetism",
                                "Mechanics", "& Energy"]

    /// THE LOAD-BEARING TEST. Every one of the six resolves to an
    /// asset, so nothing in the home is falling back.
    @MainActor
    func testEveryLineIsActuallyMilled() {
        for text in Self.lines {
            XCTAssertNotNil(
                HubTitleStyle.milled(text, size: 0.17, accent: nil),
                """
                "\(text)" fell back to generated type. Either the asset \
                is missing from the bundle, or its meshes are not named \
                Letters and Rim — an asset from before the diamond-cut \
                split fails on purpose. Rebuild with Tools/hubtitles.py.
                """)
        }
    }

    /// The diamond cut survived the USD round-trip: the chamfer band is
    /// genuinely a SECOND part, because the whole legibility argument —
    /// dark anodised face, bright alloy rim — rests on the two being
    /// paintable separately. One combined mesh would anodise the rim
    /// dark along with the face and the silhouette would go with it.
    @MainActor
    func testTheChamferRimIsItsOwnPart() {
        for text in Self.lines {
            guard let built = HubTitleStyle.milled(text, size: 0.17,
                                                   accent: nil) else {
                continue    // reported by testEveryLineIsActuallyMilled
            }
            var names: [String] = []
            func walk(_ entity: Entity) {
                names.append(entity.name)
                for child in entity.children { walk(child) }
            }
            walk(built.entity)
            XCTAssertTrue(names.contains { $0.contains("Letters") },
                          "\(text): no Letters part")
            XCTAssertTrue(names.contains { $0.contains("Rim") },
                          "\(text): the chamfer rim is not its own part")
        }
    }

    /// Real, positive extents — the flush-width lockup divides by the
    /// width, so a zero scales a line to infinity and hangs the sign
    /// across the room. The generated builder is held to this in
    /// `HubTitleStyleTests`; the milled one has to earn it separately,
    /// because it gets its numbers from a file rather than from a font.
    @MainActor
    func testTheMilledLineMeasuresRealExtents() {
        for text in Self.lines {
            guard let built = HubTitleStyle.milled(text, size: 0.17,
                                                   accent: nil) else {
                continue    // reported by testEveryLineIsActuallyMilled
            }
            XCTAssertGreaterThan(built.extents.x, 0.05, "\(text): no width")
            XCTAssertGreaterThan(built.extents.y, 0.02, "\(text): no height")
            XCTAssertGreaterThan(built.extents.z, 0, "\(text): no depth")
        }
    }

    /// Centred on its own origin — the contract `line` also offers,
    /// and the one the two-line lockups above depend on.
    /// An asset centred on its baseline instead would stack correctly
    /// in the maths and hang wrong in the room.
    @MainActor
    func testTheMilledLineIsCentredOnItsOwnOrigin() {
        guard let built = HubTitleStyle.milled("Playground", size: 0.17,
                                               accent: nil) else {
            return XCTFail("no asset for Playground")
        }
        let centre = built.entity.visualBounds(relativeTo: nil).center
        XCTAssertEqual(centre.x, 0, accuracy: 1e-3, "not centred on X")
        XCTAssertEqual(centre.y, 0, accuracy: 1e-3, "not centred on Y")
    }

    /// `size` IS the scale, because the asset is built at a nominal
    /// point size of 1 — which is what makes `milled` a drop-in for
    /// the generated line, whose extents the lockup divides into a
    /// common width. If this stopped being linear the two lines of a lockup
    /// would be set at different weights.
    @MainActor
    func testSizeScalesTheMilledLine() {
        guard let small = HubTitleStyle.milled("Mechanics", size: 0.10,
                                               accent: nil),
              let large = HubTitleStyle.milled("Mechanics", size: 0.20,
                                               accent: nil) else {
            return XCTFail("no asset for Mechanics")
        }
        XCTAssertEqual(large.extents.x, small.extents.x * 2,
                       accuracy: small.extents.x * 0.02,
                       "doubling the size should double the width")
    }

    /// THE BUG THIS FILE EXISTS FOR, SECOND EDITION.
    ///
    /// Both lockups finish by ASSIGNING the entity's scale:
    ///
    ///     item.entity.scale = SIMD3(repeating: scale)
    ///
    /// The generated line survives that because its size lives in its
    /// geometry.
    /// The first milled build put `size` on the returned entity itself,
    /// so the assignment threw it away, the asset reverted to its
    /// nominal point size of one METRE, and the wordmark came up six
    /// times too big and filled the room.
    ///
    /// Every test still passed. They checked what `milled` returned,
    /// and what it returned was right — the defect only appeared once a
    /// caller composed with it. So this pins the composition: a line
    /// must survive having its scale assigned, which it can only do if
    /// it kept its own transform free.
    @MainActor
    func testAssigningScaleDoesNotResizeTheLine() {
        guard let built = HubTitleStyle.milled("Physics", size: 0.17,
                                               accent: nil) else {
            return XCTFail("no asset for Physics")
        }
        XCTAssertEqual(built.entity.scale, SIMD3<Float>(repeating: 1),
                       "the wrapper's transform must stay free for the "
                       + "lockup to assign, or size is silently lost")

        // Do exactly what the lockup does, then measure the room.
        let width: Float = 0.60          // HubSpaceView.titleWidth
        built.entity.scale = SIMD3(repeating: width / built.extents.x)
        let set = built.entity.visualBounds(relativeTo: nil).extents.x
        XCTAssertEqual(set, width, accuracy: 0.01,
                       "a line scaled to the lockup width should BE that "
                       + "wide — got \(set) m")
    }

    /// The words the home does NOT say get generated type, not a crash
    /// and not a wrong sign. This is the fallback working on purpose.
    @MainActor
    func testAnUnbakedLineFallsBack() {
        XCTAssertNil(HubTitleStyle.milled("Thermodynamics", size: 0.17,
                                          accent: nil),
                     "an unbaked line must fall through to generated type")
    }

    // MARK: The rake

    /// It actually moves, and it comes back — a turn, not a drift.
    func testTheRakeTurnsAndReturns() {
        let rest = HubTitleStyle.rake(time: 0, phase: 0)
        var sawADifference = false
        for step in 1...40 {
            let turned = HubTitleStyle.rake(time: Double(step) * 0.4, phase: 0)
            if turned.angle > rest.angle + 0.005 { sawADifference = true }
        }
        XCTAssertTrue(sawADifference, "the rake never turned the line")
    }

    /// SMALL. The point is that the highlight moves, not that the sign
    /// does — a reader who catches the sign turning is watching the
    /// animation instead of reading the words. Two degrees is the
    /// ceiling.
    func testTheRakeStaysSubtle() {
        for step in 0...200 {
            let turn = HubTitleStyle.rake(time: Double(step) * 0.31, phase: 0.7)
            XCTAssertLessThan(turn.angle, 0.035,
                              "the rake swung \(turn.angle) rad — too far to "
                              + "read as light rather than as movement")
        }
    }

    /// THE DEPTH CUE IS THE WHOLE REASON THESE ARE ASSETS. A milled
    /// line is a deep solid — flatten it and the chamfer has no side to
    /// run along, which is the difference between a machined plaque and
    /// a sticker. Held as a fraction of point size, the same way
    /// `extrusionFactor` is.
    @MainActor
    func testTheMilledLineIsDeeplyExtruded() {
        guard let built = HubTitleStyle.milled("Electricity", size: 0.12,
                                               accent: nil) else {
            return XCTFail("no asset for Electricity")
        }
        XCTAssertGreaterThan(built.extents.z, 0.12 * 0.4,
                             "the plaque should be milled deep")
    }
}
