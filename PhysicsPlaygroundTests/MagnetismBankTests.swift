//
//  MagnetismBankTests.swift
//  PhysicsPlaygroundTests
//
//  The four states the switch bank shows, and the one that used to
//  escape a reset.
//
//  Written the same day as Pendulums' equivalent, and for the same
//  reason: the moment a model flag gets a lamp standing in the room, the
//  lamp starts making a claim about it every frame. A flag that quietly
//  survived `reset()` was invisible while it was a toggle in a collapsed
//  card nobody opened twice; it is a visible lie once a plate is lit
//  over it.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class MagnetismBankTests: XCTestCase {

    /// `dynamicsOn` was the fourth switch and the one reset forgot — so
    /// freezing the magnets and pressing Reset left them frozen while
    /// every other layer came back. The other three were already
    /// restored; this pins all four together so the next one added
    /// cannot slip through the same gap.
    func testResetRestoresEverySwitchTheBankShows() {
        let model = MagnetismModel()
        model.dynamicsOn = false
        model.showFieldLines = false
        model.showCompasses = false
        model.compassOn = false
        model.earthFieldOn = false

        model.reset()

        XCTAssertTrue(model.dynamicsOn, "the magnets were left frozen")
        XCTAssertTrue(model.showFieldLines)
        XCTAssertTrue(model.showCompasses)
        XCTAssertTrue(model.compassOn)
        XCTAssertTrue(model.earthFieldOn, "the planet went missing")
    }

    /// The top plate is not a display layer, and this is the difference:
    /// switching it off has to stop the physics, not hide a drawing. A
    /// frozen magnet stays exactly where it was put even with another
    /// magnet close enough to pull hard on it.
    func testFreezingTheMagnetsStopsThemMoving() {
        let model = MagnetismModel()
        // A second magnet close by, so there is a real force to resist.
        let partner = MagnetismModel.regionCenter + SIMD3(0.34, 0, 0)
        XCTAssertNotNil(model.addMagnet(at: partner))

        model.dynamicsOn = false
        let frozen = model.magnets.map(\.position)
        for _ in 0..<120 { model.step(dt: 1.0 / 90.0) }
        XCTAssertEqual(model.magnets.map(\.position), frozen,
                       "frozen means frozen, however hard they pull")

        model.dynamicsOn = true
        for _ in 0..<120 { model.step(dt: 1.0 / 90.0) }
        XCTAssertNotEqual(model.magnets.map(\.position), frozen,
                          "free again, they should be closing on each other")
    }

    /// The three display switches must not touch the physics — a field
    /// line you cannot see still exists, and hiding it must not move a
    /// magnet. This is the converse of the test above, and together they
    /// say why the top plate needed a label of its own.
    func testHidingTheDrawnLayersLeavesThePhysicsAlone() {
        func positionsAfterAStep(drawing: Bool) -> [SIMD3<Double>] {
            let model = MagnetismModel()
            _ = model.addMagnet(at: MagnetismModel.regionCenter + SIMD3(0.34, 0, 0))
            model.showFieldLines = drawing
            model.showCompasses = drawing
            model.compassOn = drawing
            for _ in 0..<120 { model.step(dt: 1.0 / 90.0) }
            return model.magnets.map(\.position)
        }
        let shown = positionsAfterAStep(drawing: true)
        let hidden = positionsAfterAStep(drawing: false)
        XCTAssertEqual(shown.count, hidden.count)
        for (a, b) in zip(shown, hidden) {
            XCTAssertEqual(simd_distance(a, b), 0, accuracy: 1e-12,
                           "what is drawn changed where a magnet went")
        }
    }
}

/// Carrying things: the model must actually move when a hand drags.
///
/// The renderer half of this bug cannot be reached from a test — nothing
/// automated can touch a RealityKit entity — so what is pinned here is
/// the model contract the renderer depends on: a drag writes a new
/// position, unconditionally. The renderer's matching duty (sync the
/// entity from the model EVERY frame, held or not) is stated at
/// `syncHandCompass` and checked by hand.
@MainActor
final class MagnetismCarryTests: XCTestCase {

    func testMovingTheCompassWritesItsPosition() {
        let model = MagnetismModel()
        let start = model.compassPosition
        let target = start + SIMD3(0.30, 0.10, -0.20)
        model.moveCompass(to: target)
        XCTAssertNotEqual(model.compassPosition, start)
        XCTAssertEqual(simd_distance(model.compassPosition, target), 0,
                       accuracy: 1e-9)
    }

    /// …and it cannot be dragged through the floor.
    func testTheCompassStopsAtTheFloor() {
        let model = MagnetismModel()
        model.moveCompass(to: SIMD3(0, -5, -0.7))
        XCTAssertGreaterThan(model.compassPosition.y, -5,
                             "the compass went through the floor")
    }

    /// The compass reads the field where it IS, so moving it has to
    /// change what the needle is given. If a drag failed to write the
    /// position, this is the number that would silently stop moving.
    func testTheFieldFollowsTheCompassAsItMoves() {
        let model = MagnetismModel()
        model.moveCompass(to: MagnetismModel.regionCenter + SIMD3(0.18, 0, 0))
        let near = simd_length(model.compassField)
        model.moveCompass(to: MagnetismModel.regionCenter + SIMD3(0.90, 0, 0))
        let far = simd_length(model.compassField)
        XCTAssertGreaterThan(near, far * 2,
                             "the field did not weaken with distance")
    }
}

/// Two magnets that have come together must be STILL — in both degrees
/// of freedom.
///
/// The translational half of this was fixed once (`softenedAtContact`,
/// against a limit cycle where each magnet drove 8 mm inward every frame
/// and the separation projected it straight back). The ROTATIONAL half
/// was left, and it is what the owner saw as residual jitter: the torque
/// at contact saturates the angular speed cap, a fixed step overshoots
/// alignment, the torque reverses, and the pair buzzes forever at the
/// frame rate while apparently at rest.
@MainActor
final class MagnetismSettlingTests: XCTestCase {

    /// Runs a pair together and returns how much they still move per
    /// frame once they have had plenty of time to settle.
    private func residualMotion(
        steps: Int = 1_200
    ) -> (drift: Double, turn: Double) {
        let model = MagnetismModel()
        // SIDE BY SIDE, not end to end. Both magnets are born with their
        // moment along +x, so a second one placed along +x is already at
        // its equilibrium orientation and never rotates — which would
        // test the settling of a pair that had nothing to settle. Offset
        // in z and the two parallel dipoles have real work to do.
        _ = model.addMagnet(at: MagnetismModel.regionCenter + SIMD3(0.04, 0.02, 0.30))
        for _ in 0..<steps { model.step(dt: 1.0 / 90.0) }

        let before = model.magnets
        var drift = 0.0
        var turn = 0.0
        // Sample over many frames: a limit cycle can return to where it
        // started, so a single before/after pair can read as still.
        for _ in 0..<120 {
            let previous = model.magnets
            model.step(dt: 1.0 / 90.0)
            for (a, b) in zip(previous, model.magnets) {
                drift = max(drift, simd_distance(a.position, b.position))
                let ma = simd_normalize(a.moment), mb = simd_normalize(b.moment)
                turn = max(turn, acos(min(max(simd_dot(ma, mb), -1), 1)))
            }
        }
        XCTAssertEqual(before.count, model.magnets.count)
        return (drift, turn)
    }

    func testASettledPairDoesNotJitter() {
        let (drift, turn) = residualMotion()
        // Per frame, once settled. A tenth of a millimetre and a
        // thousandth of a radian are both far below anything visible;
        // the rotational figure used to sit at the 3 rad/s cap × the
        // frame time, i.e. about 0.033 rad every frame, forever.
        XCTAssertLessThan(drift, 1e-4, "the pair is still sliding")
        XCTAssertLessThan(turn, 1e-3, "the pair is still twitching")
    }

    /// The clamp must not stop them ALIGNING — a fix that froze the
    /// rotation early would pass the jitter test and break the module.
    func testTheyStillSwingIntoAlignmentFirst() {
        let model = MagnetismModel()
        // Side by side, so the two parallel moments are NOT already at
        // equilibrium and there is a real rotation to perform.
        _ = model.addMagnet(at: MagnetismModel.regionCenter + SIMD3(0.04, 0, 0.34))
        let startTurn = model.magnets.map { simd_normalize($0.moment) }

        for _ in 0..<1_200 { model.step(dt: 1.0 / 90.0) }

        // At least one of them should have turned on the way.
        let moved = zip(startTurn, model.magnets).contains { start, now in
            simd_dot(start, simd_normalize(now.moment)) < 0.999
        }
        XCTAssertTrue(moved, "nothing rotated — the clamp froze the torque")
    }
}

/// Earth's field: the compasses feel it, the magnets do not.
@MainActor
final class MagnetismEarthFieldTests: XCTestCase {

    func testTheCompassReadsEarthWhenCarriedClearOfTheBench() {
        let model = MagnetismModel()
        // Right on top of the magnet: the bench wins outright.
        model.moveCompass(to: MagnetismModel.regionCenter + SIMD3(0.16, 0, 0))
        XCTAssertFalse(model.compassIsReadingEarth)

        // An arm's length away: the planet takes over.
        model.moveCompass(to: MagnetismModel.regionCenter + SIMD3(0.85, 0, 0))
        XCTAssertTrue(model.compassIsReadingEarth)
        XCTAssertEqual(simd_length(model.compassField),
                       GeomagneticField.referenceMagnitude,
                       accuracy: GeomagneticField.referenceMagnitude * 0.35)
    }

    /// Far from every magnet the needle must settle to north-and-DOWN —
    /// not north-and-level. This is the whole reason the compass became
    /// a sphere.
    func testFarFromTheBenchTheNeedleTipsIntoTheGround() {
        let model = MagnetismModel()
        model.moveCompass(to: MagnetismModel.regionCenter + SIMD3(0, 0.80, 0.90))
        let field = simd_normalize(model.compassField)
        XCTAssertLessThan(simd_dot(field, GeomagneticField.up), -0.5,
                          "the needle settled level instead of dipping")
    }

    func testSwitchingEarthOffLeavesOnlyTheBench() {
        let model = MagnetismModel()
        model.moveCompass(to: MagnetismModel.regionCenter + SIMD3(0.85, 0, 0))
        let withEarth = simd_length(model.compassField)

        model.earthFieldOn = false
        XCTAssertEqual(model.earthField, .zero)
        XCTAssertLessThan(simd_length(model.compassField), withEarth / 5,
                          "the planet is still in the reading")
        XCTAssertFalse(model.compassIsReadingEarth)
    }

    /// The Delete petal must work all the way down to an empty room —
    /// a guard used to keep the last magnet alive, so the tap did
    /// nothing and the petal's swell read as a glitch (2026-08-03).
    func testTheLastMagnetCanBeDeletedAndTheRoomRefilled() {
        let model = MagnetismModel()
        XCTAssertEqual(model.magnets.count, 1)
        let last = model.magnets[0].id

        model.removeMagnet(id: last)
        XCTAssertTrue(model.magnets.isEmpty,
                      "the last magnet refused to delete")
        XCTAssertNil(model.selectedID)

        // An empty bench must still step and still take a new magnet.
        for _ in 0..<90 { model.step(dt: 1.0 / 90.0) }
        XCTAssertNotNil(model.addMagnet(at: MagnetismModel.regionCenter))
        XCTAssertEqual(model.magnets.count, 1)
    }

    /// COMPASSES ONLY. A lone magnet must not creep round to north —
    /// that was the owner's call, and it is the difference between this
    /// sandbox and a different one.
    func testEarthDoesNotTurnTheBarMagnets() {
        let model = MagnetismModel()
        XCTAssertTrue(model.earthFieldOn)
        // One magnet, alone, well clear of anything else.
        XCTAssertEqual(model.magnets.count, 1)
        let before = model.magnets[0].moment

        for _ in 0..<1_800 { model.step(dt: 1.0 / 90.0) }

        let after = model.magnets[0].moment
        XCTAssertEqual(simd_dot(simd_normalize(before), simd_normalize(after)), 1,
                       accuracy: 1e-9,
                       "a lone magnet swung toward north — Earth reached the bench")
    }
}
