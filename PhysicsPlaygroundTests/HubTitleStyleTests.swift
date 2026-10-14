//
//  HubTitleStyleTests.swift
//  Physics Playground — app tests
//
//  The engine behind the home's three display texts: real measured
//  extents, a buildable line, capitals, and one solid.
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

    /// Milled from stock: the letters' own extruded sides are the depth
    /// cue, which is why `line` can get away with a single pass.
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

    /// One solid, not a stack: a dark copy has to sit further back than the
    /// extrusion is deep, and any offset small enough to read as a shadow
    /// punched through the faces.
    @MainActor
    func testTheLineIsASingleSolid() {
        let line = HubTitleStyle.line("MECHANICS", size: 0.12,
                                      accent: .systemOrange)
        XCTAssertEqual(line.children.count, 1,
                       "the plaque grew a second pass — its own extruded "
                       + "sides are the depth cue, and a stacked copy will "
                       + "interpenetrate them")
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
