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
    func testResetRestoresAllFourSwitchesTheBankShows() {
        let model = MagnetismModel()
        model.dynamicsOn = false
        model.showFieldLines = false
        model.showCompasses = false
        model.compassOn = false

        model.reset()

        XCTAssertTrue(model.dynamicsOn, "the magnets were left frozen")
        XCTAssertTrue(model.showFieldLines)
        XCTAssertTrue(model.showCompasses)
        XCTAssertTrue(model.compassOn)
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

    /// Magnetism opened alone must not inherit a coil left switched on by
    /// a Circuit Workshop session — the coil belongs to that room, and
    /// its current is that bench's inductor current. `reset()` is one of
    /// the two places that has to hold the line (the space view forces it
    /// again on entry).
    func testResetLeavesTheElectromagnetOff() {
        let model = MagnetismModel()
        model.electromagnetOn = true
        model.reset()
        XCTAssertFalse(model.electromagnetOn)
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

    func testMovingTheElectromagnetWritesItsPosition() {
        let model = MagnetismModel()
        let start = model.electromagnetPosition
        let target = start + SIMD3(-0.25, 0.05, 0.15)
        model.moveElectromagnet(to: target)
        XCTAssertNotEqual(model.electromagnetPosition, start)
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
