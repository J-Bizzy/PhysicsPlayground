//
//  OpeningTests.swift
//  PhysicsPlaygroundTests
//
//  The home's arrival (`Opening`), on numbers: where the labs stand, and
//  how they, their names and the wordmark come up — one after another,
//  left to right, rising into place with no overshoot and no jump, all of
//  it exactly in place when it is over. "Birth of a System", which this
//  replaced on 2026-10-21, and its tests are in the git history.
//

import XCTest
import simd
@testable import PhysicsPlayground

final class OpeningTests: XCTestCase {

    private let portals = PortalLayout.portals(count: 7)
    private let frame = 1.0 / 90.0

    // MARK: The portals

    /// Seven portals on one arc, each facing the wearer, no two footprints
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
                                 2 * PortalLayout.footprintRadius + 0.2)
        }
    }

    /// Every lab's footprint stands the same drop below its portal.
    func testEveryFootprintStandsAtOneHeight() {
        for portal in portals {
            XCTAssertEqual(PortalLayout.footprintCentre(of: portal).y,
                           PortalLayout.height - PortalLayout.footprintDrop, accuracy: 1e-12)
        }
    }

    // MARK: The labs

    /// Short: the last lab is in place in about a second, and everything
    /// within a second and a half.
    func testItIsShort() {
        XCTAssertEqual(Opening.labCount, portals.count)
        XCTAssertLessThanOrEqual(Opening.labsArrived, 1.3)
        XCTAssertLessThanOrEqual(Opening.duration, 1.6)
    }

    /// Left to right: each lab starts after the one on its left, and none
    /// shows before it starts.
    func testTheLabsComeUpLeftToRight() {
        for index in 1..<Opening.labCount {
            let start = Double(index) * Opening.stagger
            XCTAssertEqual(Opening.labOpacity(index, at: start - frame), 0)
            XCTAssertGreaterThan(Opening.labOpacity(index - 1, at: start + frame),
                                 Opening.labOpacity(index, at: start + frame))
        }
    }

    /// Each rises into its place and grows to its size without passing
    /// either — monotonic, never above its place or over its size — and is
    /// exactly there from its arrival on.
    func testEachRisesIntoPlaceWithNoOvershoot() {
        for index in 0..<Opening.labCount {
            XCTAssertEqual(Opening.labLift(index, at: 0), -Opening.riseHeight, accuracy: 1e-7)
            XCTAssertEqual(Opening.labScale(index, at: 0), Opening.startScale, accuracy: 1e-6)
            var lift = -Float.infinity, scale: Float = 0, light: Float = 0
            for step in 0...Int(Opening.duration / frame) + 1 {
                let t = Double(step) * frame
                let nextLift = Opening.labLift(index, at: t)
                let nextScale = Opening.labScale(index, at: t)
                let nextLight = Opening.labOpacity(index, at: t)
                XCTAssertGreaterThanOrEqual(nextLift, lift - 1e-7, "lab \(index) sank at \(t) s")
                XCTAssertLessThanOrEqual(nextLift, 1e-7, "lab \(index) rose past its place")
                XCTAssertGreaterThanOrEqual(nextScale, scale - 1e-7)
                XCTAssertLessThanOrEqual(nextScale, 1 + 1e-6, "lab \(index) grew past its size")
                XCTAssertGreaterThanOrEqual(nextLight, light - 1e-7)
                (lift, scale, light) = (nextLift, nextScale, nextLight)
            }
            let done = Double(index) * Opening.stagger + Opening.rise
            XCTAssertEqual(Opening.labLift(index, at: done), 0, accuracy: 1e-7)
            XCTAssertEqual(Opening.labScale(index, at: done), 1, accuracy: 1e-7)
            XCTAssertEqual(Opening.labOpacity(index, at: done), 1, accuracy: 1e-7)
        }
    }

    /// Smooth: no frame moves a lab more than a few millimetres, and it
    /// comes to rest at its place rather than stopping short — the last
    /// frame's step is smaller than the first moving one's.
    func testTheRiseIsSmoothAndComesToRest() {
        var steps: [Float] = []
        var previous = Opening.labLift(0, at: 0)
        for step in 1...Int(Opening.rise / frame) {
            let lift = Opening.labLift(0, at: Double(step) * frame)
            steps.append(lift - previous)
            previous = lift
        }
        XCTAssertLessThan(steps.max() ?? 1, 0.004, "a frame jumped")
        XCTAssertLessThan(steps.last ?? 1, (steps.first ?? 0) / 20, "it stopped short instead of settling")
    }

    // MARK: The names, the More, the tone and the wordmark

    /// A lab's name comes up only once its lab is mostly in, and all are
    /// up, with the More, when the arrival ends.
    func testTheNamesFollowTheirLabs() {
        for index in 0..<Opening.labCount {
            let start = Double(index) * Opening.stagger
            XCTAssertEqual(Opening.nameOpacity(index, at: start + Opening.rise / 2 - frame), 0)
            XCTAssertGreaterThan(Opening.progress(ofLab: index, at: start + Opening.rise / 2), 0.8)
            XCTAssertEqual(Opening.nameOpacity(index, at: Opening.duration), 1, accuracy: 1e-6)
        }
        XCTAssertEqual(Opening.moreOpacity(at: 0), 0)
        XCTAssertEqual(Opening.moreOpacity(at: Opening.duration), 1, accuracy: 1e-6)
        XCTAssertTrue(Opening.isFinished(at: Opening.duration))
        XCTAssertFalse(Opening.isFinished(at: Opening.duration - 0.01))
    }

    /// The one tone sounds as the last lab comes to rest, not before the
    /// labs are most of the way in.
    func testTheToneSoundsAsTheLastLabSettles() {
        XCTAssertLessThan(Opening.toneTime, Opening.labsArrived)
        XCTAssertGreaterThan(Opening.progress(ofLab: Opening.labCount - 1, at: Opening.toneTime), 0.9)
    }

    /// The machined wordmark, when it stands in, rises into place and is
    /// exactly there when the labs are.
    func testTheWordmarkRisesIntoPlace() {
        XCTAssertEqual(Opening.titleOffset(at: 0), -Opening.titleRise, accuracy: 1e-6)
        var previous = -Float.infinity
        for step in 0...400 {
            let t = Opening.duration * Double(step) / 400
            let offset = Opening.titleOffset(at: t)
            XCTAssertGreaterThanOrEqual(offset, previous - 1e-6)
            XCTAssertLessThanOrEqual(offset, 1e-6, "the wordmark rose past its place")
            previous = offset
        }
        XCTAssertEqual(Opening.titleOffset(at: Opening.labsArrived), 0, accuracy: 1e-6)
    }
}
