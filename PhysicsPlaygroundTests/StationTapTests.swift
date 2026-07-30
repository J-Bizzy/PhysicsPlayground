//
//  StationTapTests.swift
//  Physics Playground — app tests
//
//  Tap handling, driven directly.
//
//  The simulator cannot synthesise a pinch — `simctl` has no tap verb,
//  and XCUITest has no API for RealityKit entities — so every gesture
//  in this app has historically been checked by eye in a headset, or
//  bypassed entirely by a debug argument that SETS the state a tap
//  would have produced (`-magRing 1` opens a ring without ever tapping
//  anything). That verifies the renderer and proves nothing about the
//  handler.
//
//  But `handleTap` takes an `Entity`, and an `Entity` is just an object.
//  The whole tap grammar — resolve what was hit by walking up the
//  hierarchy, toggle its ring, fold everything away on a miss — is
//  ordinary code that can be called and asserted on. These are the
//  bugs that class of test catches: the wrong thing resolved, a ring
//  that opens but never closes, a phantom ring on an id that is not
//  really there.
//

import XCTest
import PhysicsCore
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class StationTapTests: XCTestCase {

    /// The coil annex, with a magnet on it, and that magnet's id.
    private func makeStation() throws -> (EMFieldStation, UUID) {
        let model = MagnetismModel()
        let id = try XCTUnwrap(model.magnets.first?.id,
                               "a fresh magnetic field should open with magnets")
        return (EMFieldStation(model: model, offset: .zero), id)
    }

    /// How the renderer names a magnet's entity: its UUID string. The
    /// handler resolves by parsing that back, so the two are one
    /// contract — this test is also what catches the naming convention
    /// changing out from under the resolver.
    private func entity(named name: String) -> Entity {
        let entity = Entity()
        entity.name = name
        return entity
    }

    // MARK: The ring toggle

    func testTappingAMagnetOpensItsRing() throws {
        let (station, id) = try makeStation()
        XCTAssertNil(station.openRingID, "nothing is open before a tap")

        XCTAssertTrue(station.handleTap(entity(named: id.uuidString)))
        XCTAssertEqual(station.openRingID, id)
    }

    /// Tapping the same magnet again closes it. The ring is a toggle,
    /// and a toggle that only opens is the failure mode that leaves a
    /// control ring stuck over an apparatus for the rest of a session.
    func testTappingTheSameMagnetAgainClosesItsRing() throws {
        let (station, id) = try makeStation()
        let magnet = entity(named: id.uuidString)

        station.handleTap(magnet)
        XCTAssertEqual(station.openRingID, id)
        station.handleTap(magnet)
        XCTAssertNil(station.openRingID, "the ring should have folded away")
    }

    /// A pinch rarely lands on the entity that carries the name — it
    /// lands on a child mesh, a pole cap, a collider. The handler walks
    /// UP to find the owner, and this is the test that keeps it walking.
    func testTappingAChildOfAMagnetStillResolvesTheMagnet() throws {
        let (station, id) = try makeStation()
        let magnet = entity(named: id.uuidString)
        let pole = entity(named: "north-cap")
        let glyph = entity(named: "N")
        pole.addChild(glyph)
        magnet.addChild(pole)

        // Two levels down from the named entity.
        station.handleTap(glyph)
        XCTAssertEqual(station.openRingID, id,
                       "the ancestry walk stopped short — a pinch on a pole "
                       + "cap must still be a pinch on its magnet")
    }

    /// Tapping the room, the cable, or anything anonymous folds the
    /// ring away. "You tapped elsewhere" is the only way a user closes
    /// a ring without hitting the same magnet twice.
    func testTappingElsewhereFoldsTheRingAway() throws {
        let (station, id) = try makeStation()
        station.handleTap(entity(named: id.uuidString))
        XCTAssertEqual(station.openRingID, id)

        station.handleTap(entity(named: "some-other-thing"))
        XCTAssertNil(station.openRingID)
    }

    /// A well-formed UUID that belongs to no magnet must not open a
    /// ring on nothing. The resolver checks membership, not just that
    /// the name parses — a deleted magnet's entity lingering one frame
    /// is exactly this case.
    func testAUUIDThatIsNotAMagnetOpensNoRing() throws {
        let (station, _) = try makeStation()
        station.handleTap(entity(named: UUID().uuidString))
        XCTAssertNil(station.openRingID,
                     "a ring opened on an id with no magnet behind it")
    }

    /// A ring open on a magnet that is then deleted must not survive.
    /// The render loop clears it, but the state should never claim a
    /// magnet that is gone.
    func testTappingAMagnetThenAnotherMovesTheRing() throws {
        let model = MagnetismModel()
        let first = try XCTUnwrap(model.magnets.first?.id)
        model.addMagnet()
        let second = try XCTUnwrap(
            model.magnets.last(where: { $0.id != first })?.id,
            "adding a magnet should give a second id")
        let station = EMFieldStation(model: model, offset: .zero)

        station.handleTap(entity(named: first.uuidString))
        XCTAssertEqual(station.openRingID, first)
        station.handleTap(entity(named: second.uuidString))
        XCTAssertEqual(station.openRingID, second,
                       "the ring should move to the newly tapped magnet, "
                       + "not stay on the old one or close")
    }

    // MARK: Routing — which apparatus owns a hit

    /// Circuit Workshop routes gestures by walking the hit entity up to
    /// the coil annex's root; anything not under it belongs to the
    /// bench. That check is `isDescendant(of:)`, and it is the whole
    /// reason a pinch on a magnet does not zoom the circuit bench.
    func testAnnexOwnsOnlyItsOwnDescendants() throws {
        let (station, _) = try makeStation()

        let magnetPart = Entity()
        station.root.addChild(magnetPart)
        XCTAssertTrue(magnetPart.isDescendant(of: station.root))

        let benchPart = Entity()
        let benchRoot = Entity()
        benchRoot.addChild(benchPart)
        XCTAssertFalse(benchPart.isDescendant(of: station.root),
                       "a bench entity resolved to the annex — a two-hand "
                       + "pinch there would zoom the wrong apparatus")
    }

    /// The annex declares a scale rig, and Circuit Workshop's routing
    /// hands two-handed pinches to it. A nil rig would silently send
    /// them to the bench instead.
    func testTheAnnexOffersAScaleRig() throws {
        let (station, _) = try makeStation()
        XCTAssertNotNil(station.scaleRig)
    }
}
