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

    /// The settings value picks the voice, and anything the enum does
    /// not recognise — the audition sentinel, or a stale raw value left
    /// by an older build — falls back to the original rather than
    /// leaving the home with no type at all.
    @MainActor
    func testTheSettingSelectsTheVoice() {
        let settings = AppSettings()
        defer { UserDefaults.standard.removeObject(forKey: "settings.titleStyle") }

        for expected in HubTitleStyle.allCases {
            settings.titleStyle = expected.rawValue
            XCTAssertEqual(HubTitleStyle.chosen(settings), expected)
        }

        settings.titleStyle = HubTitleStyle.audition
        XCTAssertEqual(HubTitleStyle.chosen(settings), .bubble,
                       "the audition sentinel is not a voice — the wall is "
                       + "hung by the hub, and the type still needs a face")

        settings.titleStyle = 99
        XCTAssertEqual(HubTitleStyle.chosen(settings), .bubble,
                       "a stale raw value must not leave the home mute")
    }

    /// A fresh install auditions rather than silently picking: the
    /// choice presents itself in the room instead of waiting to be
    /// found in a menu.
    @MainActor
    func testAFreshInstallOpensOnTheAudition() {
        UserDefaults.standard.removeObject(forKey: "settings.titleStyle")
        XCTAssertEqual(AppSettings().titleStyle, HubTitleStyle.audition)
    }
}
