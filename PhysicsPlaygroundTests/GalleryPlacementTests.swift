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

    // MARK: The facing rescue
    //
    // The relaunch promise above is kept, and one pathological case is
    // rescued: a saved yaw is relative to where the wearer stood LAST
    // launch, so relaunching from another chair can open the gallery
    // behind them. Pure arithmetic, because the headset cannot be asked
    // to relaunch four times in a unit test.

    func testAFacingCloseToTheWearerIsLeftAlone() {
        // A deliberate quarter-turn is a placement, not a mistake.
        XCTAssertEqual(GalleryPlacement.reFacedYaw(saved: 0.5, lookYaw: 0.9),
                       0.5, accuracy: 1e-6)
    }

    func testAFacingBehindTheWearerAdoptsTheLook() {
        XCTAssertEqual(GalleryPlacement.reFacedYaw(saved: 0, lookYaw: .pi),
                       .pi, accuracy: 1e-6)
    }

    /// THE CASE A NAIVE `abs(a - b)` GETS WRONG. These two facings are 20°
    /// apart, but straddle ±π — subtracting them reads 340° and would spin
    /// a correctly-placed gallery to face a wearer it already faced.
    func testTheComparisonWrapsAcrossPi() {
        let saved: Float = .pi - 0.17
        let look: Float = -.pi + 0.17
        XCTAssertEqual(GalleryPlacement.reFacedYaw(saved: saved, lookYaw: look),
                       saved, accuracy: 1e-6)
    }

    /// The rescue turns the gallery and never moves it — an offset the
    /// user dragged is theirs, and is not what put it behind them.
    func testTheRescueKeepsTheOffset() {
        let placement = GalleryPlacement()
        placement.move(to: SIMD3(1.2, 0, -0.4))
        placement.turn(to: 0)

        placement.refaceIfBehind(lookYaw: .pi)
        XCTAssertEqual(placement.offset, SIMD3(1.2, 0, -0.4))
        XCTAssertEqual(placement.yaw, .pi, accuracy: 1e-6)
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
