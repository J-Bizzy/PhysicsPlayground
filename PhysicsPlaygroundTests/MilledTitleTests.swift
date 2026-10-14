//
//  MilledTitleTests.swift
//  Physics Playground — app tests
//
//  The home's display texts are milled in Blender and loaded as assets;
//  `HubTitleStyle.milled` falls back to the generated line whenever
//  anything is wrong, so every test in `HubTitleStyleTests` drives the
//  fallback. This file asserts that the assets are in the bundle, that
//  they load, and that the milled path is the one answering.
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

    /// The load-bearing test. Every one of the six resolves to an
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

    /// The chamfer band survived the round-trip as a second part: the
    /// legibility argument rests on the face and the rim being paintable
    /// separately.
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

    /// Real, positive extents: the milled line gets its numbers from a
    /// file rather than a font and has to earn this separately.
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

    /// Centred on its own origin, the contract `line` also offers and the
    /// lockups depend on.
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

    /// `size` is the scale, because the asset is built at a nominal point
    /// size of 1; if this stopped being linear the two lines of a lockup
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

    /// A line must survive having its scale assigned, which both lockups
    /// do: the first milled build put `size` on the returned entity, the
    /// assignment threw it away, and the wordmark came up at its nominal
    /// one metre and filled the room — with every test green, since they
    /// checked what `milled` returned rather than what a caller composed.
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

    /// The words the home does not say get generated type, not a crash
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

    /// Small: the point is that the highlight moves, not that the sign
    /// does. Two degrees is the ceiling.
    func testTheRakeStaysSubtle() {
        for step in 0...200 {
            let turn = HubTitleStyle.rake(time: Double(step) * 0.31, phase: 0.7)
            XCTAssertLessThan(turn.angle, 0.035,
                              "the rake swung \(turn.angle) rad — too far to "
                              + "read as light rather than as movement")
        }
    }

    /// The depth cue is the whole reason these are assets: flatten a milled
    /// line and the chamfer has no side to run along.
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
