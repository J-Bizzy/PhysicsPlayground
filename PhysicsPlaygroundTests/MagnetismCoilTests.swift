//
//  MagnetismCoilTests.swift
//  PhysicsPlaygroundTests
//
//  The pickup coil in the lab as built: a magnet carried through it at a
//  brisk hand's speed lights the LED, red going in and green coming out
//  (or the other way round); a still magnet, or a slow one, does not; a
//  magnet carried by hand induces even with the glide frozen; and reset,
//  the Time Capsule and the coil's own edits behave.
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
    /// side to 0.6 m the other, recording the coil's current each frame.
    private func pass(speed: Double) throws -> [Double] {
        let (model, coil, magnet) = try bench()
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

    func testASlowPassStaysBelowTheLEDsThreshold() throws {
        let currents = try pass(speed: 0.2)
        XCTAssertLessThan(currents.map(abs).max() ?? 1, 1e-4)
    }

    func testAStillMagnetInducesNothing() throws {
        let (model, coil, magnet) = try bench()
        model.move(id: magnet.id, to: coil.position)
        model.step(dt: dt)
        for _ in 0..<30 { model.step(dt: dt) }
        XCTAssertEqual(model.coils[0].emf, 0, accuracy: 1e-12)
    }

    /// More turns, more EMF: the same pass through 4000 turns gives four
    /// times what it gives through 1000.
    func testTheEMFGoesAsTheTurns() throws {
        let (model, coil, magnet) = try bench()
        model.cycleTurns(id: coil.id)   // 4000 → 1000
        XCTAssertEqual(model.coils[0].turns, 1000)
        model.move(id: magnet.id, to: coil.position - coil.axis * 0.10)
        model.step(dt: dt)
        model.move(id: magnet.id, to: coil.position - coil.axis * 0.09)
        model.step(dt: dt)
        let few = model.coils[0].emf
        model.cycleTurns(id: coil.id)   // 2000
        model.cycleTurns(id: coil.id)   // 4000
        model.move(id: magnet.id, to: coil.position - coil.axis * 0.10)
        model.step(dt: dt)
        model.move(id: magnet.id, to: coil.position - coil.axis * 0.09)
        model.step(dt: dt)
        XCTAssertEqual(model.coils[0].emf / few, 4, accuracy: 1e-9)
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
