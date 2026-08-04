//
//  GalleryPlacementTests.swift
//  PhysicsPlaygroundTests
//
//  The gallery's grab bar promises one thing above all: the room opens
//  exactly where it was left. That is a UserDefaults round trip, which
//  a test can hold — the drag feel is the headset's job.
//

import XCTest
import simd
@testable import PhysicsPlayground

@MainActor
final class GalleryPlacementTests: XCTestCase {

    private let keys = ["hub.galleryOffset", "hub.galleryYaw"]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    func testAFreshGalleryStandsAtHome() {
        let placement = GalleryPlacement()
        XCTAssertEqual(placement.offset, .zero)
        XCTAssertEqual(placement.yaw, 0)
    }

    /// The promise itself: drag it somewhere, relaunch, and it is
    /// exactly there — same offset, same facing.
    func testThePlacementSurvivesRelaunch() {
        let placement = GalleryPlacement()
        placement.move(to: SIMD3(0.8, 0.2, -1.1))
        placement.turn(to: 0.6)

        let relaunched = GalleryPlacement()
        XCTAssertEqual(relaunched.offset, SIMD3(0.8, 0.2, -1.1))
        XCTAssertEqual(relaunched.yaw, 0.6, accuracy: 1e-6)
    }

    /// Generous but bounded: across the room yes, into next door no.
    func testTheOffsetIsClampedToTheRoomScaleBox() {
        let placement = GalleryPlacement()
        placement.move(to: SIMD3(50, -50, 50))
        XCTAssertEqual(placement.offset, SIMD3(3, -0.9, 3))
    }

    /// A tap on the bar: home, and facing the wearer when the room
    /// knows which way that is.
    func testRecentreGoesHomeAndFacesTheWearer() {
        let placement = GalleryPlacement()
        placement.move(to: SIMD3(1, 0, 1))
        placement.turn(to: 1.2)

        placement.recentre(facing: 0.4)
        XCTAssertEqual(placement.offset, .zero)
        XCTAssertEqual(placement.yaw, 0.4, accuracy: 1e-6)

        // Without a look ray the facing is kept, not zeroed — the
        // gallery goes home without spinning underfoot.
        placement.move(to: SIMD3(1, 0, 1))
        placement.recentre(facing: nil)
        XCTAssertEqual(placement.offset, .zero)
        XCTAssertEqual(placement.yaw, 0.4, accuracy: 1e-6)
    }
}
