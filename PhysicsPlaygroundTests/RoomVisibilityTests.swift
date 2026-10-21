//
//  RoomVisibilityTests.swift
//  PhysicsPlaygroundTests
//
//  The room is out of reach in deep space (2026-10-20): one answer,
//  `RoomModel.tangible`, says what of the room a lab can touch, and in
//  space it is nothing — a ball flies on past where the walls were and
//  is retired far off, light finds no wall to land on, field lines are
//  clipped by nothing. The hands and the floor stay.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class RoomVisibilityTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "roomWall")
        UserDefaults.standard.removeObject(forKey: "settings.surroundings")
        super.tearDown()
    }

    // MARK: The one answer

    func testAnUnscannedRoomIsTheStandInBoxAndHiddenItIsOpenSpace() {
        let room = RoomModel()
        XCTAssertEqual(room.tangible, .unscanned)
        XCTAssertEqual(room.tangible.clipBox, .unscanned)
        room.isShown = false
        XCTAssertEqual(room.tangible, .openSpace)
        XCTAssertNil(room.tangible.clipBox, "field lines clipped to a room that is not there")
    }

    #if DEBUG
    /// Even a scanned room — the `-roomWall` debug wall — is out of reach
    /// once hidden, and back the moment it is shown.
    func testAHiddenScannedRoomIsOpenSpace() {
        UserDefaults.standard.set(2.6, forKey: "roomWall")
        let room = RoomModel()
        room.forceSensingForDebug()
        guard case .scanned(let walls, _) = room.tangible else {
            return XCTFail("the debug wall did not scan the room")
        }
        XCTAssertFalse(walls.isEmpty)
        room.isShown = false
        XCTAssertEqual(room.tangible, .openSpace)
        room.isShown = true
        if case .scanned = room.tangible {} else { XCTFail("the room did not come back") }
    }
    #endif

    /// The surroundings decide it: deep space hides the room, the room
    /// shows it, and Orbital Mechanics' own space hides it for its visit.
    func testTheSurroundingsHideAndShowTheRoom() {
        let app = AppModel()
        XCTAssertTrue(app.room.isShown)
        app.choose(.deepSpace)
        XCTAssertFalse(app.room.isShown)
        app.choose(.room)
        XCTAssertTrue(app.room.isShown)
        app.go(to: OrbitalMechanicsModule.id)
        XCTAssertFalse(app.room.isShown)
    }

    // MARK: Projectiles

    private func throwing(in tangible: RoomModel.Tangible,
                          velocity: SIMD3<Double>) -> (model: KinematicsModel, id: UUID) {
        let model = KinematicsModel()
        model.clearFlights()
        let fed = KinematicsSpaceView.roomFeed(tangible, placement: .zero)
        model.roomWalls = fed.walls
        model.roomBounds = fed.bounds
        #if DEBUG
        let id = model.stageThrow(from: SIMD3(0, 1.5, -0.5), velocity: velocity)
        #else
        let id = UUID()
        #endif
        return (model, id)
    }

    /// In space a hand-speed ball sails past where the stand-in box's wall
    /// stood (x = 1.9 m) without turning back; in the room it bounces.
    func testABallFliesOnPastWhereTheWallsWere() {
        let velocity = SIMD3<Double>(12, 2, 0)
        let (space, spaceID) = throwing(in: .openSpace, velocity: velocity)
        var passed = false
        for _ in 0..<45 {
            space.step(dt: 1.0 / 90.0)
            guard let flight = space.flights.first(where: { $0.id == spaceID }) else { break }
            XCTAssertGreaterThan(flight.state.velocity.x, 0, "it bounced off nothing")
            if flight.state.position.x > 2 { passed = true }
        }
        XCTAssertTrue(passed, "the ball never got past x = 2 m")

        let (room, roomID) = throwing(in: .unscanned, velocity: velocity)
        for _ in 0..<45 { room.step(dt: 1.0 / 90.0) }
        let kept = room.flights.first { $0.id == roomID }
        XCTAssertLessThan(kept?.state.position.x ?? 0, 1.95,
                          "the unscanned room's stand-in box stopped holding the ball")
    }

    /// With nothing to stop it, a ball is retired once it is beyond
    /// `escapeRadius` — it does not fly for ever.
    func testABallInSpaceIsRetiredFarOff() {
        let (model, id) = throwing(in: .openSpace, velocity: SIMD3(20, 15, 0))
        var retired = false
        for _ in 0..<(90 * 4) {
            model.step(dt: 1.0 / 90.0)
            if !model.flights.contains(where: { $0.id == id }) { retired = true; break }
            if let flight = model.flights.first(where: { $0.id == id }) {
                XCTAssertLessThanOrEqual(simd_length(flight.state.position),
                                         KinematicsModel.escapeRadius + 1)
            }
        }
        XCTAssertTrue(retired)
    }

    /// Nothing to bounce off: More's "Walls bounce" is greyed out in space.
    func testWallsBounceIsDisabledInSpace() throws {
        let model = KinematicsModel()
        var inReach = true
        let items = KinematicsModule.more(model, roomInReach: { inReach })
        let walls = try XCTUnwrap(items.first { $0.id == "walls" })
        guard case let .toggle(_, _, _, _, _, isEnabled) = walls else {
            return XCTFail("Walls bounce is not a toggle")
        }
        XCTAssertTrue(isEnabled())
        inReach = false
        XCTAssertFalse(isEnabled())
    }

    // MARK: Light & Optics

    /// Light lands on scanned walls in the room, on none in space — and on
    /// the floor in both.
    func testLightFindsNoWallInSpace() {
        let wall = RoomWalls.Wall(center: SIMD3(0, 1.5, -2.6), normal: SIMD3(0, 0, 1),
                                  uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 1, 0),
                                  halfU: 3, halfV: 1.5)
        let placement = SIMD3<Double>(0.3, 0, 0)
        let scanned = OpticsSpaceView.room(
            for: .scanned(walls: [wall], bounds: .unscanned), placement: placement)
        XCTAssertEqual(scanned.walls.count, 1)
        XCTAssertEqual(scanned.walls.first?.center.x ?? 0, -0.3, accuracy: 1e-12,
                       "the wall is not in the lab's coordinates")
        let space = OpticsSpaceView.room(for: .openSpace, placement: placement)
        XCTAssertTrue(space.walls.isEmpty)
        XCTAssertEqual(space.floorY, scanned.floorY, "the floor is the physics' own")
    }
}
