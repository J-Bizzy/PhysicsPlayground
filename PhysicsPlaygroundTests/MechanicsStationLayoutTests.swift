//
//  MechanicsStationLayoutTests.swift
//  Physics Playground — app tests
//
//  The Mechanics world stands a launcher and a pendulum rig in one
//  room. As in the E&M world, everything that can go wrong with that is
//  geometry and all of it is silent — but this world has one failure
//  the other cannot have, and it is the first test here.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class MechanicsStationLayoutTests: XCTestCase {

    // MARK: The one that matters most

    /// THE PROJECTILE BENCH MAY NEVER BE OFFSET.
    ///
    /// Its physics space IS the user's room, one to one: the solver
    /// takes `room.collisionWalls` and `room.bounds` directly, and balls
    /// are caught at real `room.fingertips`. Translate the display and
    /// every ball bounces off a wall that is not where the bounce is
    /// drawn, and is caught by a hand that is not where the catch is
    /// shown — silently, in the one module whose whole claim is that
    /// the physics is happening in your actual room.
    ///
    /// This is why the pendulum rig is the station that moves.
    func testTheProjectileStationIsNeverOffset() {
        XCTAssertEqual(
            MechanicsStationLayout.offset(.projectile), .zero,
            "the projectile bench's physics space IS the room: balls "
            + "bounce off the user's real scanned walls and are caught by "
            + "real fingertips. A display offset makes every bounce a "
            + "fiction. Move the other bench instead.")
    }

    // MARK: The anchors and seats

    func testNativeAnchorsMatchTheModulesTheyDescribe() {
        XCTAssertEqual(
            simd_distance(MechanicsStationLayout.nativeAnchor(.projectile),
                          KinematicsModel.launcherHome), 0, accuracy: 1e-9,
            "projectile anchor drifted from KinematicsModel.launcherHome")
        XCTAssertEqual(
            simd_distance(MechanicsStationLayout.nativeAnchor(.pendulum),
                          PendulumsModel.defaultPivot), 0, accuracy: 1e-9,
            "pendulum anchor drifted from PendulumsModel.defaultPivot")
    }

    /// The offset is what actually moves the display root, so it has to
    /// be exactly the difference between the seat and the anchor — not
    /// a separately maintained number.
    func testOffsetCarriesTheNativeAnchorToItsSeat() {
        for station in MechanicsStation.allCases {
            let moved = MechanicsStationLayout.nativeAnchor(station)
                + SIMD3<Double>(MechanicsStationLayout.offset(station))
            XCTAssertEqual(
                simd_distance(moved, MechanicsStationLayout.seat(station)), 0,
                accuracy: 1e-9, "\(station.rawValue) offset misses its seat")
        }
    }

    /// Seat and volume are separate here — a pendulum hangs from a pivot
    /// at head height and swings down past your knees — but a station
    /// must at least occupy the place it is placed at.
    func testEveryStationContainsItsOwnSeat() {
        for station in MechanicsStation.allCases where station.isBuilt {
            XCTAssertTrue(
                MechanicsStationLayout.box(station)
                    .contains(MechanicsStationLayout.seat(station)),
                "\(station.rawValue) is seated outside its own volume")
        }
    }

    // MARK: Disjointness — arc stations only

    /// The ambient station is exempt by construction: an orrery fifteen
    /// metres across cannot be disjoint from anything in the room, which
    /// is exactly why it is held to a containment invariant instead
    /// (see the annulus test, which arrives with the station).
    func testEveryPairOfArcStationsIsDisjoint() {
        let arc = MechanicsStation.allCases.filter { $0.kind == .arc }
        for i in 0..<arc.count {
            for j in (i + 1)..<arc.count {
                XCTAssertTrue(
                    MechanicsStationLayout.areSeparated(arc[i], arc[j],
                                                        margin: 0.05),
                    "\(arc[i].rawValue) and \(arc[j].rawValue) overlap, or "
                    + "sit closer than the 5 cm clearance")
            }
        }
    }

    func testTheOrreryIsTheOnlyAmbientStation() {
        XCTAssertEqual(MechanicsStation.orbital.kind, .ambient)
        XCTAssertEqual(MechanicsStation.projectile.kind, .arc)
        XCTAssertEqual(MechanicsStation.pendulum.kind, .arc)
    }

    /// Every bench has to be worth walking to.
    func testEveryBuiltStationHasAFaceWithinOneStep() {
        let user = SIMD3<Double>(0, 1.5, 0)
        for station in MechanicsStation.allCases where station.isBuilt {
            let (near, _) = MechanicsStationLayout.box(station)
                .distanceRange(from: user)
            XCTAssertLessThanOrEqual(
                near, 1.25,
                "\(station.rawValue) is more than a step away — its nearest "
                + "face is \(String(format: "%.2f", near)) m from the user")
        }
    }

    // MARK: What each bench actually draws inside its box

    /// A pendulum is as tall as its pivot and as long as its cable, and
    /// both ends of that have to be inside the station.
    ///
    /// The box is the rig's RESTING volume, deliberately. A bob thrown
    /// hard sideways swings out past it, and that is allowed: apparatus
    /// volumes must stay apart, trajectories may cross freely. There is
    /// no test asserting a swinging bob stays inside, and there must
    /// not be one — it would be asserting that a pendulum cannot swing.
    func testTheLongestPendulumStaysInsideItsStation() {
        let box = MechanicsStationLayout.box(.pendulum)
        let offset = SIMD3<Double>(MechanicsStationLayout.offset(.pendulum))
        let pivot = PendulumsModel.defaultPivot + offset
        let lowestBob = pivot
            - SIMD3(0, PendulumsModel.lengthRange.upperBound
                        + PendulumsModel.bobRadiusRange.upperBound, 0)
        XCTAssertTrue(box.contains(pivot), "the pivot is outside its station")
        XCTAssertTrue(box.contains(lowestBob),
                      "a bob at full length hangs out of its station")
    }

    /// The launcher, the ball spawn and the hoop spawn are all authored
    /// as absolute points, and the projectile station cannot move to
    /// accommodate them — so the BOX has to be drawn around where they
    /// already are.
    func testTheProjectileApparatusStaysInsideItsStation() {
        let box = MechanicsStationLayout.box(.projectile)
        for (point, what) in [
            (KinematicsModel.launcherHome, "the launcher's home"),
            (KinematicsModel.ballSpawnPoint, "the ball spawn"),
            (KinematicsModel.ringSpawnPoint, "the hoop spawn"),
        ] {
            XCTAssertTrue(box.contains(point),
                          "\(what) is outside the projectile station")
        }
    }

    /// Side furniture hangs outboard, away from the other bench.
    func testThePendulumWellHangsAwayFromTheProjectileBench() {
        XCTAssertEqual(MechanicsStationLayout.outboard(.pendulum), -1,
                       "the rig sits left of centre, so its well hangs left")
    }
}
