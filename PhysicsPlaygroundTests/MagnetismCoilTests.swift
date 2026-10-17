//
//  MagnetismCoilTests.swift
//  PhysicsPlaygroundTests
//
//  The pickup coil in the lab as built: a magnet carried through it at a
//  gentle hand's pace lights the LED, red going in and green coming out
//  (or the other way round); a still magnet, or a creeping one, does not; a
//  magnet carried by hand induces even with the glide frozen; a magnet
//  carried in crosswise is turned into line by the bore and lights it too;
//  and reset, the Time Capsule and the coil's own edits behave.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class MagnetismCoilTests: XCTestCase {

    private let dt = 1.0 / 90.0

    /// A bench with one coil and one magnet on its axis, far to one side,
    /// pointing along it, the glide frozen so only the hand moves it.
    private func bench() throws -> (MagnetismModel, MagnetismModel.Coil, BarMagnet) {
        let model = MagnetismModel()
        model.dynamicsOn = false
        for extra in model.magnets.dropFirst() { model.removeMagnet(id: extra.id) }
        let coilID = try XCTUnwrap(model.addCoil(at: SIMD3(0, 1.3, -0.6)))
        let coil = try XCTUnwrap(model.coils.first { $0.id == coilID })
        let magnet = try XCTUnwrap(model.magnets.first)
        model.setStrength(id: magnet.id, MagnetismModel.defaultStrength, along: coil.axis)
        model.move(id: magnet.id, to: coil.position - coil.axis * 0.6)
        model.step(dt: dt)
        return (model, coil, magnet)
    }

    /// Carries the magnet along the coil's axis at `speed` from 0.6 m one
    /// side to 0.6 m the other, recording the coil's current each frame —
    /// pointing along the bore, or across it when `crosswise`.
    private func pass(speed: Double, crosswise: Bool = false) throws -> [Double] {
        let (model, coil, magnet) = try bench()
        if crosswise {
            model.setStrength(id: magnet.id, MagnetismModel.defaultStrength, along: SIMD3(0, 0, 1))
        }
        model.grab(id: magnet.id)
        var currents: [Double] = []
        var offset = -0.6
        while offset < 0.6 {
            offset += speed * dt
            model.move(id: magnet.id, to: coil.position + coil.axis * offset)
            model.step(dt: dt)
            currents.append(model.coils[0].current)
        }
        return currents
    }

    func testABriskPassLightsTheLEDBothWays() throws {
        let currents = try pass(speed: 2.0)
        XCTAssertGreaterThan(currents.max() ?? 0, 0.002, "the red LED never lit")
        XCTAssertLessThan(currents.min() ?? 0, -0.002, "the green LED never lit")
        // In, then out: the colours come in that order, not mixed.
        let firstRed = try XCTUnwrap(currents.firstIndex { $0 > 0.001 })
        let firstGreen = try XCTUnwrap(currents.firstIndex { $0 < -0.001 })
        XCTAssertNotEqual(firstRed < firstGreen, firstGreen < firstRed)
    }

    /// The pace a hand guides a magnet into a coil at, a third of a metre a
    /// second, lights the full winding plainly. At 4000 turns it took more
    /// than twice this, and a careful push left the LED dark.
    func testAGentlePassLightsTheLED() throws {
        let currents = try pass(speed: 0.35)
        XCTAssertGreaterThan(currents.map(abs).max() ?? 0, 3e-4, "a gentle push left it dark")
    }

    func testACreepingPassStaysBelowTheLEDsThreshold() throws {
        let currents = try pass(speed: 0.15)
        XCTAssertLessThan(currents.map(abs).max() ?? 1, 5e-5)
    }

    // MARK: The bore is a sleeve

    /// A hand cannot turn what it holds, so a magnet carried in crosswise —
    /// which through the bore would induce nothing at all — is turned into
    /// line by the mouth, and the pass lights the LED both ways.
    func testACrosswiseMagnetIsTurnedIntoLineAndLightsIt() throws {
        let currents = try pass(speed: 0.5, crosswise: true)
        XCTAssertGreaterThan(currents.max() ?? 0, 3e-4, "the red LED never lit")
        XCTAssertLessThan(currents.min() ?? 0, -3e-4, "the green LED never lit")
    }

    func testTheMouthTurnsAMagnetAlongTheBoreKeepingItsLead() throws {
        let (model, coil, magnet) = try bench()
        // Mostly across the bore, a little against it.
        let aim = simd_normalize(SIMD3(-0.3, 0, 1.0))
        model.setStrength(id: magnet.id, MagnetismModel.defaultStrength, along: aim)
        model.grab(id: magnet.id)
        var offset = -0.6
        while offset < 0 {
            offset += 0.5 * dt
            model.move(id: magnet.id, to: coil.position + coil.axis * offset)
            model.step(dt: dt)
        }
        let moment = try XCTUnwrap(model.magnets.first { $0.id == magnet.id }).moment
        XCTAssertEqual(simd_length(moment), MagnetismModel.defaultStrength, accuracy: 1e-9)
        XCTAssertGreaterThan(simd_dot(simd_normalize(moment), -coil.axis), cos(0.5 * .pi / 180),
                             "not along the bore, or turned end for end")
    }

    func testAMagnetHeldBesideTheCoilKeepsItsAim() throws {
        let (model, coil, magnet) = try bench()
        let aim = SIMD3<Double>(0, 0, 1)
        model.setStrength(id: magnet.id, MagnetismModel.defaultStrength, along: aim)
        model.grab(id: magnet.id)
        let beside = coil.position + SIMD3(0, 0, 0.25)
        model.move(id: magnet.id, to: beside)
        for _ in 0..<90 { model.step(dt: dt) }
        let held = try XCTUnwrap(model.magnets.first { $0.id == magnet.id })
        XCTAssertEqual(simd_dot(simd_normalize(held.moment), aim), 1, accuracy: 1e-12)
        XCTAssertEqual(simd_distance(held.position, beside), 0, accuracy: 1e-12)
    }

    /// Inside the coil a magnet sits within the bore's centimetre of play
    /// however far off line the hand is; and the hand drawn steadily out
    /// sideways draws the magnet out steadily, never in a jump.
    func testTheBoreHoldsAMagnetOffItsWallsWithoutAJump() throws {
        let (_, coil, _) = try bench()
        let across = SIMD3<Double>(0, 0, 1)
        var last = 0.0
        var r = 0.0
        while r < 0.2 {
            let point = MagnetismModel.sleeved(coil.position + across * r, through: coil)
            let radius = simd_length(point - coil.position)
            XCTAssertEqual(simd_dot(point - coil.position, coil.axis), 0, accuracy: 1e-12)
            if r <= MagnetismModel.coilBoreRadius {
                XCTAssertLessThanOrEqual(radius, MagnetismModel.boreClearance + 1e-12)
            }
            XCTAssertGreaterThanOrEqual(radius, last - 1e-12, "the magnet moved back toward the axis")
            XCTAssertLessThan(radius - last, 0.006, "the magnet jumped at \(r) m off the axis")
            last = radius
            r += 0.001
        }
        // Clear of the flanges, and clear of the coil along its axis, the
        // magnet is wherever the hand is.
        let off = coil.position + across * 0.2
        XCTAssertEqual(simd_distance(MagnetismModel.sleeved(off, through: coil), off), 0, accuracy: 1e-12)
        let outside = coil.position + coil.axis * 0.2 + across * 0.03
        XCTAssertEqual(simd_distance(MagnetismModel.sleeved(outside, through: coil), outside), 0,
                       accuracy: 1e-12)
    }

    func testAStillMagnetInducesNothing() throws {
        let (model, coil, magnet) = try bench()
        model.move(id: magnet.id, to: coil.position)
        model.step(dt: dt)
        for _ in 0..<30 { model.step(dt: dt) }
        XCTAssertEqual(model.coils[0].emf, 0, accuracy: 1e-12)
    }

    /// More turns, more EMF: the same pass through 10 000 turns gives four
    /// times what it gives through 2500.
    func testTheEMFGoesAsTheTurns() throws {
        let (model, coil, magnet) = try bench()
        model.cycleTurns(id: coil.id)   // 10 000 → 2500
        XCTAssertEqual(model.coils[0].turns, 2500)
        model.move(id: magnet.id, to: coil.position - coil.axis * 0.10)
        model.step(dt: dt)
        model.move(id: magnet.id, to: coil.position - coil.axis * 0.09)
        model.step(dt: dt)
        let few = model.coils[0].emf
        model.cycleTurns(id: coil.id)   // 5000
        model.cycleTurns(id: coil.id)   // 10 000
        model.move(id: magnet.id, to: coil.position - coil.axis * 0.10)
        model.step(dt: dt)
        model.move(id: magnet.id, to: coil.position - coil.axis * 0.09)
        model.step(dt: dt)
        XCTAssertEqual(model.coils[0].emf / few, 4, accuracy: 1e-9)
    }

    /// Every winding is the same bobbin full of copper, drawn into a
    /// different wire: the copper's cross-section is the same, so the
    /// resistance goes as N² while the EMF goes as N.
    func testEveryWindingFillsTheBobbin() {
        let window = (MagnetismModel.windingOuter - MagnetismModel.windingInner) * MagnetismModel.coilLength
        XCTAssertEqual(MagnetismModel.coilRadius,
                       (MagnetismModel.windingOuter + MagnetismModel.windingInner) / 2, accuracy: 1e-12)
        for turns in MagnetismModel.turnOptions {
            let d = MagnetismModel.wireDiameter(turns: turns)
            XCTAssertEqual(Double(turns) * .pi * d * d / 4, MagnetismModel.copperFill * window,
                           accuracy: 1e-12)
        }
        XCTAssertEqual(MagnetismModel.wireDiameter(turns: MagnetismModel.defaultTurns), 0.25e-3,
                       accuracy: 0.005e-3, "the default winding is 0.25 mm wire")
        func resistance(_ turns: Int) -> Double {
            PickupCoil(center: .zero, axis: SIMD3(1, 0, 0), radius: MagnetismModel.coilRadius,
                       length: MagnetismModel.coilLength, turns: turns,
                       wireDiameter: MagnetismModel.wireDiameter(turns: turns)).resistance
        }
        XCTAssertEqual(resistance(10_000) / resistance(2500), 16, accuracy: 1e-9)
    }

    /// Changing the winding or turning the coil re-measures its linkage, so
    /// the edit itself is no jolt of EMF.
    func testEditingTheCoilIsNoJolt() throws {
        let (model, coil, magnet) = try bench()
        model.move(id: magnet.id, to: coil.position - coil.axis * 0.06)
        model.step(dt: dt)
        model.step(dt: dt)
        model.cycleTurns(id: coil.id)
        model.step(dt: dt)
        XCTAssertEqual(model.coils[0].emf, 0, accuracy: 1e-12)
        model.turnCoil(id: coil.id)
        model.step(dt: dt)
        XCTAssertEqual(model.coils[0].emf, 0, accuracy: 1e-12)
    }

    func testTheRoomOpensWithNoCoilAndResetClearsThem() throws {
        let model = MagnetismModel()
        XCTAssertTrue(model.coils.isEmpty, "a coil in the opening room is clutter")
        model.addCoil(at: SIMD3(0, 1.3, -0.6))
        model.reset()
        XCTAssertTrue(model.coils.isEmpty)
    }

    func testTheWellRefusesAThirdCoil() {
        let model = MagnetismModel()
        XCTAssertNotNil(model.addCoil(at: SIMD3(0, 1.3, -0.6)))
        XCTAssertNotNil(model.addCoil(at: SIMD3(0.3, 1.3, -0.6)))
        XCTAssertNil(model.addCoil(at: SIMD3(0.6, 1.3, -0.6)))
    }

    /// The Time Capsule brings the coil back with the linkage its next EMF
    /// differences from, so a restore does not flash the LED.
    func testTheCapsuleRestoresTheCoilWithoutAFlash() throws {
        let (model, coil, magnet) = try bench()
        model.move(id: magnet.id, to: coil.position - coil.axis * 0.05)
        model.step(dt: dt)
        model.step(dt: dt)
        let snapshot = model.captureCapsuleSnapshot()
        model.move(id: magnet.id, to: coil.position + coil.axis * 0.3)
        model.step(dt: dt)
        model.restoreCapsuleSnapshot(snapshot)
        XCTAssertEqual(model.coils, snapshot.coils)
        model.step(dt: dt)
        XCTAssertEqual(model.coils[0].emf, 0, accuracy: 1e-12)
    }

    func testTheLEDLevelFollowsTheCurrent() {
        XCTAssertEqual(MagnetismRenderer.ledLevel(current: 0), 0)
        XCTAssertEqual(MagnetismRenderer.ledLevel(current: 1e-6), 0)
        XCTAssertGreaterThan(MagnetismRenderer.ledLevel(current: 0.002), 0)
        XCTAssertLessThan(MagnetismRenderer.ledLevel(current: -0.002), 0)
        XCTAssertEqual(MagnetismRenderer.ledLevel(current: 0.010), 8)
        XCTAssertLessThan(MagnetismRenderer.ledLevel(current: 0.001),
                          MagnetismRenderer.ledLevel(current: 0.008))
    }
}
