//
//  HubTitleStyleTests.swift
//  Physics Playground — app tests
//
//  The style engine behind the home's three display texts. Whatever
//  voice is on, the lockup math depends on the same properties: real
//  measured extents, a buildable line, and the plaque actually
//  speaking in capitals.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

final class HubTitleStyleTests: XCTestCase {

    /// Every voice measures real, positive extents — the flush-width
    /// lockup divides by these, so a zero would scale a line to
    /// infinity and hang the sign across the room.
    func testEveryStyleMeasuresRealExtents() {
        for style in HubTitleStyle.allCases {
            let extents = style.extents("Magnetism", size: 0.12)
            XCTAssertGreaterThan(extents.x, 0.1, "\(style) has no width")
            XCTAssertGreaterThan(extents.y, 0.03, "\(style) has no height")
            XCTAssertGreaterThan(extents.z, 0, "\(style) has no depth at all")
        }
    }

    /// The depths genuinely differ — the styles are three materials AND
    /// three geometries, not one mesh painted three ways.
    func testTheVoicesDifferInDepth() {
        let size: CGFloat = 0.12
        let plaque = HubTitleStyle.plaque.extents("Energy", size: size).z
        let poster = HubTitleStyle.poster.extents("Energy", size: size).z
        XCTAssertGreaterThan(plaque, poster * 3,
                             "the plaque should be milled deep and the "
                             + "poster near-flat; they measure alike")
    }

    /// The plaque speaks in capitals; nobody else does.
    func testOnlyThePlaqueUppercases() {
        XCTAssertEqual(HubTitleStyle.plaque.display("& Magnetism"), "& MAGNETISM")
        for style in HubTitleStyle.allCases where style != .plaque {
            XCTAssertEqual(style.display("& Magnetism"), "& Magnetism",
                           "\(style) should leave case alone")
        }
    }

    /// Every voice builds a line, in both roles — neutral wordmark and
    /// accented door sign — and every line has at least the letter pass.
    @MainActor
    func testEveryStyleBuildsBothRoles() {
        for style in HubTitleStyle.allCases {
            for accent in [nil, UIColor.systemGreen] {
                let line = style.line("Mechanics", size: 0.12, accent: accent)
                XCTAssertFalse(line.children.isEmpty,
                               "\(style) built an empty line")
                let width = line.visualBounds(relativeTo: line).extents.x
                XCTAssertGreaterThan(width, 0.1,
                                     "\(style)'s line has no visible width")
            }
        }
    }

    /// The home ships in ONE voice, pinned in code. It used to come
    /// out of Settings, with a sentinel that hung a specimen wall and a
    /// fallback for stale raw values; both went on 2026-07-31, when the
    /// choice stopped being a choice. If this constant ever moves, the
    /// wordmark and both door signs move with it — they all read
    /// `HubTitleStyle.current`, which the hub sets from this.
    func testTheHomeShipsInThePlaque() {
        XCTAssertEqual(HubTitleStyle.shipping, .plaque)
    }

    /// The plaque is ONE solid, not a stack. Two meshes sharing a
    /// volume is what made the letters look doubled and the lines look
    /// collided: a dark copy has to sit further back than the extrusion
    /// is deep, and this is the deepest voice in the set, so any offset
    /// small enough to read as a shadow punched through the faces.
    @MainActor
    func testThePlaqueIsASingleSolid() {
        let line = HubTitleStyle.plaque.line("MECHANICS", size: 0.12,
                                             accent: .systemOrange)
        XCTAssertEqual(line.children.count, 1,
                       "the plaque grew a second pass — its own extruded "
                       + "sides are the depth cue, and a stacked copy will "
                       + "interpenetrate them")
    }
}
