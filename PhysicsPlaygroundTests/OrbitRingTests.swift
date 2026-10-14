//
//  OrbitRingTests.swift
//  PhysicsPlaygroundTests
//
//  The ring's drawn thickness is a room measurement, not a function of the
//  orbit's size or the zoom; its mesh follows the exact eccentricity and is
//  rebuilt only when that changes enough to see.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

final class OrbitRingTests: XCTestCase {

    /// Mercury's ring at 1× and Neptune's at 9× come out the same thickness
    /// in the room — the old canonical radius scaled with p, so Neptune's
    /// ring was a 13 cm hose and Mercury's a hairline.
    func testRingThicknessIsConstantInTheRoom() {
        let cases: [(p: Float, rig: Float)] = [(0.185, 1), (0.5, 1), (2.6, 4), (15.0, 9), (0.29, 0.4)]
        for (p, rig) in cases {
            let radii = OrbitRing.canonicalRadii(pDisplay: p, rigScale: rig)
            let roomCore = radii.core * p * rig
            XCTAssertEqual(roomCore, OrbitRing.roomCoreRadius, accuracy: OrbitRing.roomCoreRadius * 0.12,
                           "p \(p) m at \(rig)× draws a \(roomCore) m core")
            XCTAssertGreaterThan(radii.casing, radii.core, "the casing must wrap the core")
        }
    }

    /// The buckets hold still under a jitter smaller than themselves, so an
    /// evolving orbit does not ask for a mesh every frame.
    func testRadiiAreBucketedAgainstJitter() {
        let a = OrbitRing.canonicalRadii(pDisplay: 0.500, rigScale: 1.00)
        let b = OrbitRing.canonicalRadii(pDisplay: 0.503, rigScale: 1.02)
        XCTAssertEqual(a.core, b.core)
        XCTAssertEqual(a.casing, b.casing)
    }

    func testRebuildTriggersOnlyPastTheEccentricityThreshold() {
        let radii = OrbitRing.canonicalRadii(pDisplay: 0.5, rigScale: 1)
        let applied = OrbitRing.RingKey(eccentricity: 0.100, radii: radii)
        XCTAssertTrue(OrbitRing.needsRebuild(applied: nil, next: applied), "the first mesh is always built")
        XCTAssertFalse(OrbitRing.needsRebuild(
            applied: applied, next: .init(eccentricity: 0.1015, radii: radii)),
            "a hair of eccentricity rebuilt the ring")
        XCTAssertTrue(OrbitRing.needsRebuild(
            applied: applied, next: .init(eccentricity: 0.1030, radii: radii)))
        XCTAssertTrue(OrbitRing.needsRebuild(
            applied: applied,
            next: .init(eccentricity: 0.100, radii: OrbitRing.canonicalRadii(pDisplay: 0.5, rigScale: 2))),
            "a zoom that changes the tube's canonical radius must rebuild")
        XCTAssertTrue(OrbitRing.needsRebuild(
            applied: .init(eccentricity: 0.999, radii: radii), next: .init(eccentricity: 1.0005, radii: radii)),
            "crossing parabolic changes the curve's kind")
    }

    /// The canonical conic at the exact eccentricity: periapsis at 1/(1+e),
    /// apoapsis at 1/(1−e), none past parabolic.
    func testTheCanonicalConicFollowsTheExactEccentricity() {
        let ellipse = OrbitRing.canonicalFrame(eccentricity: 0.25)
        XCTAssertEqual(ellipse.periapsisRadius, 0.8, accuracy: 1e-12)
        XCTAssertEqual(ellipse.apoapsisRadius, 1 / 0.75, accuracy: 1e-12)
        XCTAssertEqual(ellipse.eccentricity, 0.25, accuracy: 1e-12)
        let hyperbola = OrbitRing.canonicalFrame(eccentricity: 1.6)
        XCTAssertFalse(hyperbola.hasApoapsis)
        XCTAssertEqual(hyperbola.eccentricity, 1.6, accuracy: 1e-9)
    }
}
