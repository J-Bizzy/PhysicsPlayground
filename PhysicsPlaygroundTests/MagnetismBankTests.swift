//
//  MagnetismBankTests.swift
//  The four states the switch bank shows, and reset restoring every one.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class MagnetismBankTests: XCTestCase {

    /// All four switches pinned together so the next one added cannot slip out of `reset()`.
    func testResetRestoresEverySwitchTheBankShows() {
        let model = MagnetismModel()
        model.dynamicsOn = false
        model.showFieldLines = false
        model.compassOn = false
        model.earthFieldOn = false

        model.reset()

        XCTAssertTrue(model.dynamicsOn, "the magnets were left frozen")
        XCTAssertTrue(model.showFieldLines)
        XCTAssertTrue(model.compassOn)
        XCTAssertTrue(model.earthFieldOn, "the planet went missing")
    }

    /// Freezing is physics, not display: a frozen magnet stays put even under a strong pull.
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

    /// Converse of the above: display switches must not touch the physics — hiding a field line must not move a magnet.
    func testHidingTheDrawnLayersLeavesThePhysicsAlone() {
        func positionsAfterAStep(drawing: Bool) -> [SIMD3<Double>] {
            let model = MagnetismModel()
            _ = model.addMagnet(at: MagnetismModel.regionCenter + SIMD3(0.34, 0, 0))
            model.showFieldLines = drawing
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

/// A drag writes a new position, unconditionally. The renderer half cannot be reached
/// from a test (nothing automated touches a RealityKit entity); `syncHandCompass` is checked by hand.
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

    /// The compass reads the field where it IS — moving it must change the reading.
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

/// A pair in contact must be STILL in both degrees of freedom — the rotational limit
/// cycle (torque saturates the cap, a fixed step overshoots, torque reverses) buzzes at frame rate.
@MainActor
final class MagnetismSettlingTests: XCTestCase {

    /// Runs a pair together; returns per-frame residual motion after settling.
    private func residualMotion(
        steps: Int = 1_200
    ) -> (drift: Double, turn: Double) {
        let model = MagnetismModel()
        // SIDE BY SIDE, not end to end: a second magnet along +x is already at
        // equilibrium and never rotates — a fixture with nothing to settle.
        _ = model.addMagnet(at: MagnetismModel.regionCenter + SIMD3(0.04, 0.02, 0.30))
        for _ in 0..<steps { model.step(dt: 1.0 / 90.0) }

        let before = model.magnets
        var drift = 0.0
        var turn = 0.0
        // Sample many frames: a limit cycle can return to its start, so one before/after pair can read as still.
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
        // Per frame once settled: 1e-4 m and 1e-3 rad are far below visible;
        // the broken figure was the 3 rad/s cap × frame time ≈ 0.033 rad, forever.
        XCTAssertLessThan(drift, 1e-4, "the pair is still sliding")
        XCTAssertLessThan(turn, 1e-3, "the pair is still twitching")
    }

    /// The clamp must not stop them ALIGNING — freezing rotation early would pass the jitter test.
    func testTheyStillSwingIntoAlignmentFirst() {
        let model = MagnetismModel()
        // Side by side, so there is a real rotation to perform.
        _ = model.addMagnet(at: MagnetismModel.regionCenter + SIMD3(0.04, 0, 0.34))
        let startTurn = model.magnets.map { simd_normalize($0.moment) }

        for _ in 0..<1_200 { model.step(dt: 1.0 / 90.0) }

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

    /// Far from the bench the needle settles north-and-DOWN, not level.
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

    /// Two hands, two magnets: both pinned against the physics, and releasing
    /// one frees only that one. `heldIDs` is a set for exactly this.
    func testTwoMagnetsCanBeHeldAtOnceAndReleasedIndependently() {
        let model = MagnetismModel()
        guard let second = model.addMagnet(
            at: MagnetismModel.regionCenter + SIMD3(0.30, 0, 0)),
            let first = model.magnets.first?.id else {
            return XCTFail("could not stage two magnets")
        }

        model.grab(id: first)
        model.grab(id: second)
        XCTAssertEqual(model.heldIDs, [first, second])

        let held = model.magnets.map(\.position)
        for _ in 0..<180 { model.step(dt: 1.0 / 90.0) }
        XCTAssertEqual(model.magnets.map(\.position), held,
                       "a held magnet moved — the physics reclaimed a hand's magnet")

        // Let go of one: it glides toward the one still held.
        model.release(id: first)
        XCTAssertEqual(model.heldIDs, [second])
        for _ in 0..<180 { model.step(dt: 1.0 / 90.0) }
        let after = model.magnets
        XCTAssertNotEqual(after.first { $0.id == first }?.position, held[0],
                          "the released magnet stayed frozen")
        XCTAssertEqual(after.first { $0.id == second }?.position, held[1],
                       "releasing one hand dropped the other hand's magnet")
    }

    /// The strength bead must change the PICTURE: more strength, more loops — monotonic, never zero, never a flood.
    func testTheLineBudgetGrowsWithStrength() {
        let range = MagnetismModel.strengthRange
        let weak = MagnetismRenderer.lineBudget(forStrength: range.lowerBound)
        let stock = MagnetismRenderer.lineBudget(
            forStrength: MagnetismModel.defaultStrength)
        let strong = MagnetismRenderer.lineBudget(forStrength: range.upperBound)

        XCTAssertLessThan(weak, stock, "a weak magnet should draw fewer loops")
        XCTAssertLessThan(stock, strong, "a strong magnet should draw more loops")
        var previous = 0
        for strength in stride(from: range.lowerBound,
                               through: range.upperBound, by: 0.5) {
            let budget = MagnetismRenderer.lineBudget(forStrength: strength)
            XCTAssertGreaterThanOrEqual(budget, previous,
                                        "the budget is not monotonic in strength")
            XCTAssertGreaterThan(budget, 0)
            XCTAssertLessThanOrEqual(budget, 48)
            previous = budget
        }
    }

    /// The Delete petal works all the way down to an empty room, which must still step and refill.
    func testTheLastMagnetCanBeDeletedAndTheRoomRefilled() {
        let model = MagnetismModel()
        XCTAssertEqual(model.magnets.count, 1)
        let last = model.magnets[0].id

        model.removeMagnet(id: last)
        XCTAssertTrue(model.magnets.isEmpty,
                      "the last magnet refused to delete")
        XCTAssertNil(model.selectedID)

        for _ in 0..<90 { model.step(dt: 1.0 / 90.0) }
        XCTAssertNotNil(model.addMagnet(at: MagnetismModel.regionCenter))
        XCTAssertEqual(model.magnets.count, 1)
    }

    /// COMPASSES ONLY: Earth must not turn the bar magnets.
    func testEarthDoesNotTurnTheBarMagnets() {
        let model = MagnetismModel()
        XCTAssertTrue(model.earthFieldOn)
        XCTAssertEqual(model.magnets.count, 1)
        let before = model.magnets[0].moment

        for _ in 0..<1_800 { model.step(dt: 1.0 / 90.0) }

        let after = model.magnets[0].moment
        XCTAssertEqual(simd_dot(simd_normalize(before), simd_normalize(after)), 1,
                       accuracy: 1e-9,
                       "a lone magnet swung toward north — Earth reached the bench")
    }
}
