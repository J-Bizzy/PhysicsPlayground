//
//  OpeningTests.swift
//  PhysicsPlaygroundTests
//
//  What the home reads of its opening: where the labs stand, and how they,
//  their names and the wordmark arrive. The opening's physics — "Birth of
//  a System" since 2026-10-20 — is `OpeningPlanTests`; the particle field
//  it replaced, and its tests, are in the git history.
//

import XCTest
import simd
@testable import PhysicsPlayground

final class OpeningTests: XCTestCase {

    private let portals = PortalLayout.portals(count: 7)

    // MARK: The portals

    /// Seven portals on one arc, each facing the wearer, no two plinths
    /// within 20 cm of touching.
    func testThePortalsFaceTheWearerAndDoNotTouch() {
        XCTAssertEqual(portals.count, 7)
        for portal in portals {
            // The face's normal (+z rotated by yaw) points at the wearer.
            let normal = SIMD3(sin(portal.yaw), 0, cos(portal.yaw))
            let toWearer = simd_normalize(SIMD3(-portal.position.x, 0, -portal.position.z))
            XCTAssertEqual(simd_dot(normal, toWearer), 1, accuracy: 1e-9)
            XCTAssertEqual(simd_dot(portal.toward, toWearer), 1, accuracy: 1e-9)
        }
        for (a, b) in zip(portals, portals.dropFirst()) {
            XCTAssertGreaterThan(simd_distance(a.position, b.position),
                                 2 * PortalLayout.plinthRadius + 0.2)
        }
    }

    /// Every plinth's top centre stands the same drop below its portal.
    func testEveryPlinthStandsAtOneHeight() {
        for portal in portals {
            XCTAssertEqual(PortalLayout.plinthCentre(of: portal).y,
                           PortalLayout.height - PortalLayout.plinthDrop, accuracy: 1e-12)
        }
    }

    // MARK: Arriving

    /// The labs fade up as their worlds land and are fully there before the
    /// opening ends.
    func testTheLabsComeUpAsTheWorldsLand() {
        XCTAssertEqual(Opening.portalOpacity(at: Opening.landingTime - 0.5), 0)
        XCTAssertGreaterThan(Opening.portalOpacity(at: Opening.landingTime), 0)
        XCTAssertEqual(Opening.portalOpacity(at: Opening.duration), 1, accuracy: 1e-6)
    }

    /// A lab grows out of its world into place — smaller before,
    /// monotonically larger, and exactly full size by the time the opening
    /// hands over (or finishing it would snap them).
    func testTheLabsGrowIntoPlaceAndFinishFullSize() {
        XCTAssertEqual(Opening.portalScale(at: 0), 1 - OpeningPlan.labGrowth, accuracy: 1e-6)
        var previous: Float = 0
        for step in 0...400 {
            let t = Opening.duration * Double(step) / 400
            let scale = Opening.portalScale(at: t)
            XCTAssertGreaterThanOrEqual(scale, previous - 1e-6, "a lab shrank at \(t) s")
            XCTAssertLessThanOrEqual(scale, 1 + 1e-6, "a lab overshot at \(t) s")
            previous = scale
        }
        XCTAssertEqual(Opening.portalScale(at: Opening.duration), 1, accuracy: 1e-6)
    }

    /// The wordmark rises into place as it fades up, and is exactly in
    /// place when the opening ends.
    func testTheWordmarkRisesIntoPlace() {
        XCTAssertEqual(Opening.titleOffset(at: 0), -OpeningPlan.titleRise, accuracy: 1e-6)
        var previous = -Float.infinity
        for step in 0...400 {
            let t = Opening.duration * Double(step) / 400
            let offset = Opening.titleOffset(at: t)
            XCTAssertGreaterThanOrEqual(offset, previous - 1e-6)
            XCTAssertLessThanOrEqual(offset, 1e-6, "the wordmark rose past its place")
            previous = offset
        }
        XCTAssertEqual(Opening.titleOffset(at: Opening.duration), 0, accuracy: 1e-6)
    }

    /// The labels come last, from the landing on.
    func testTheNamesComeLast() {
        XCTAssertEqual(Opening.labelOpacity(at: Opening.landingTime - 0.01), 0)
        XCTAssertEqual(Opening.labelOpacity(at: Opening.duration), 1, accuracy: 1e-6)
        XCTAssertTrue(Opening.isFinished(at: Opening.duration))
        XCTAssertFalse(Opening.isFinished(at: Opening.duration - 0.01))
    }
}
