//
//  PodPlacementTests.swift
//  PhysicsPlaygroundTests
//
//  "Pods must open where the user can see them" used to be a lesson
//  written in a notes file and violated by most modules. Here it is an
//  invariant with a test.
//

import XCTest
import simd
@testable import PhysicsPlayground

@MainActor
final class PodPlacementTests: XCTestCase {

    func testClampingIsIdempotent() {
        for position in [SIMD3<Float>(1.5, 1.42, -0.25),
                         SIMD3(-1.62, 0.82, -0.1),
                         SIMD3(0, 3, -5),
                         SIMD3(0, 0, 0)] {
            let once = PodPlacement.clamped(position)
            let twice = PodPlacement.clamped(once)
            XCTAssertLessThan(simd_distance(once, twice), 1e-5,
                              "a clamped position must already be comfortable")
            XCTAssertTrue(PodPlacement.isComfortable(once))
        }
    }

    /// The exact failure seen in the screenshots: a pod at x = ±1.5,
    /// z = −0.25 sits almost beside the user and clipped off-frame.
    func testPodBesideTheUserIsPulledIntoView() {
        let clamped = PodPlacement.clamped(SIMD3(1.5, 1.42, -0.25))
        XCTAssertLessThan(clamped.z, PodPlacement.eye.z,
                          "a pod must end up in FRONT of the user")
        let planar = simd_length(SIMD2(clamped.x - PodPlacement.eye.x,
                                       clamped.z - PodPlacement.eye.z))
        XCTAssertLessThanOrEqual(planar, PodPlacement.maximumDistance + 1e-4)
        XCTAssertGreaterThanOrEqual(planar, PodPlacement.minimumDistance - 1e-4)
    }

    func testPodBehindTheUserIsBroughtRoundToTheFront() {
        let clamped = PodPlacement.clamped(SIMD3(0, 1.4, 1.2))
        XCTAssertLessThan(clamped.z, PodPlacement.eye.z)
    }

    func testHeightsAreHeldBetweenHipAndBrow() {
        XCTAssertGreaterThanOrEqual(PodPlacement.clamped(SIMD3(0, 0.2, -1)).y,
                                    PodPlacement.minimumHeight - 1e-5)
        XCTAssertLessThanOrEqual(PodPlacement.clamped(SIMD3(0, 2.6, -1)).y,
                                 PodPlacement.maximumHeight + 1e-5)
    }

    /// Clamping preserves which SIDE the module asked for, so a pod
    /// meant to sit beside the fan doesn't jump across the room.
    func testClampingKeepsTheRequestedSide() {
        XCTAssertGreaterThan(PodPlacement.clamped(SIMD3(1.9, 1.4, -0.4)).x, 0)
        XCTAssertLessThan(PodPlacement.clamped(SIMD3(-1.9, 1.4, -0.4)).x, 0)
    }

    /// The whole point: every module's own default pod positions are
    /// comfortable after clamping, so no module can regress by writing
    /// a convenient-looking number into its space view.
    func testEveryShellPodDefaultIsComfortable() {
        let shellDefaults: [SIMD3<Float>] = [
            [1.5, 1.42, -0.25],    // Controls
            [-1.5, 1.42, -0.25],   // Experiments
            [-1.62, 0.82, -0.1],   // Legend
        ]
        for position in shellDefaults {
            XCTAssertTrue(PodPlacement.isComfortable(PodPlacement.clamped(position)))
        }
    }
}
