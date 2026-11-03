//
//  TwoHandsTests.swift
//  PhysicsPlaygroundTests
//
//  One object in each hand (2026-11-02). A pinch cannot be synthesised, so
//  this holds the two halves a test can reach: `HandGrabs`, the per-pinch
//  table the labs share, fed reports by hand; and each lab's model holding
//  two things at once — both pinned to their hands, each let go on its own,
//  each thrown by its own hand.
//

import XCTest
import PhysicsCore
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class TwoHandsTests: XCTestCase {

    // MARK: The table

    private final class Log {
        var begun: [String] = []
        var moved: [String: SIMD3<Double>] = [:]
        var ended: [String] = []
    }

    /// A table whose `begin` takes any entity named "take-…" and turns the
    /// rest down, logging what each hand does.
    private func feed(_ table: HandGrabs<String>, _ log: Log, _ id: String, active: Bool,
                      on entity: Entity?, hand: SIMD3<Double>, at now: Double) {
        table.report(id, active: active, on: entity, hand: active ? hand : nil, now: now,
                     begin: { entity, _ in
                         guard let name = entity?.name, name.hasPrefix("take-") else { return nil }
                         log.begun.append(name)
                         return (name, .zero)
                     },
                     move: { target, position in log.moved[target] = position },
                     end: { session in log.ended.append(session.target) })
    }

    private func named(_ name: String) -> Entity {
        let entity = Entity()
        entity.name = name
        return entity
    }

    func testEachHandHoldsItsOwnObject() {
        let table = HandGrabs<String>(), log = Log()
        let a = named("take-a"), b = named("take-b")
        feed(table, log, "left", active: true, on: a, hand: [0, 0, 0], at: 0)
        feed(table, log, "right", active: true, on: b, hand: [1, 0, 0], at: 0.3)
        XCTAssertEqual(table.count, 2)

        feed(table, log, "left", active: true, on: a, hand: [0, 0.1, 0], at: 0.4)
        feed(table, log, "right", active: true, on: b, hand: [1.2, 0, 0], at: 0.4)
        XCTAssertEqual(simd_distance(log.moved["take-a"] ?? [9, 9, 9], [0, 0.1, 0]), 0,
                       accuracy: 1e-12, "the left hand's object did not follow it")
        XCTAssertEqual(simd_distance(log.moved["take-b"] ?? [9, 9, 9], [0.2, 0, 0]), 0,
                       accuracy: 1e-12, "the right hand's object did not follow it")

        feed(table, log, "left", active: false, on: nil, hand: .zero, at: 0.5)
        XCTAssertEqual(log.ended, ["take-a"], "letting go with one hand dropped the other's too")
        XCTAssertEqual(table.count, 1)
    }

    func testAPinchIsJudgedOnceWhereItClosed() {
        let table = HandGrabs<String>(), log = Log()
        feed(table, log, "right", active: true, on: named("well"), hand: .zero, at: 0)
        // Later reports of the same pinch name something it may take: it was
        // turned down where it closed, and stays turned down.
        feed(table, log, "right", active: true, on: named("take-a"), hand: .zero, at: 0.1)
        XCTAssertTrue(log.begun.isEmpty, "a declined pinch took something mid-pinch")
        XCTAssertTrue(table.isEmpty)
        // A fresh pinch is judged afresh.
        feed(table, log, "right", active: false, on: nil, hand: .zero, at: 0.2)
        feed(table, log, "right", active: true, on: named("take-a"), hand: .zero, at: 0.3)
        XCTAssertEqual(log.begun, ["take-a"])
    }

    func testAHandThatVanishesLetsGo() {
        let table = HandGrabs<String>(), log = Log()
        feed(table, log, "left", active: true, on: named("take-a"), hand: .zero, at: 0)
        feed(table, log, "right", active: true, on: named("take-b"), hand: .zero, at: 0)
        // Only the right hand keeps reporting; the left left the tracking volume.
        for t in stride(from: 0.1, through: 0.7, by: 0.1) {
            feed(table, log, "right", active: true, on: named("take-b"), hand: .zero, at: t)
        }
        table.expire(now: 0.7) { log.ended.append($0.target) }
        XCTAssertEqual(log.ended, ["take-a"])
        XCTAssertEqual(table.count, 1)
    }

    func testReleaseAllLetsGoOfEverything() {
        let table = HandGrabs<String>(), log = Log()
        feed(table, log, "left", active: true, on: named("take-a"), hand: .zero, at: 0)
        feed(table, log, "right", active: true, on: named("take-b"), hand: .zero, at: 0)
        table.releaseAll { log.ended.append($0.target) }
        XCTAssertEqual(Set(log.ended), ["take-a", "take-b"])
        XCTAssertTrue(table.isEmpty)
    }

    // MARK: Electric Fields

    func testTwoHeldChargesStayInTheirHandsWhileAThirdResponds() {
        let model = FieldModel()
        model.removeAllCharges()
        model.addCharge(positive: true)
        model.addCharge(positive: true)
        model.addCharge(positive: false)
        model.chargesRespond = true
        let held = [model.charges[0], model.charges[1]]
        model.heldChargeIDs = Set(held.map(\.id))
        let free = model.charges[2].position
        for _ in 0..<120 { model.stepFreeCharges(dt: 1.0 / 60.0) }
        for charge in held {
            XCTAssertEqual(simd_distance(model.charges.first { $0.id == charge.id }!.position,
                                         charge.position), 0, "a held charge drifted out of its hand")
        }
        XCTAssertGreaterThan(simd_distance(model.charges[2].position, free), 0.01)

        model.removeCharge(id: held[0].id)
        XCTAssertEqual(model.heldChargeIDs, [held[1].id], "a deleted charge stayed held")
    }

    // MARK: Pendulums

    func testTwoBobsHeldAtOnceAreLetGoEachOnItsOwn() throws {
        let model = PendulumsModel()
        let first = try XCTUnwrap(model.pendulums.first)
        let second = try XCTUnwrap(model.pendulums.last)
        XCTAssertNotEqual(first.id, second.id)
        model.beginGrab(id: first.id)
        model.beginGrab(id: second.id)
        let pulled = first.pivot + SIMD3(0.2, -first.length * 0.9, 0)
        model.moveGrabbed(id: first.id, toWorld: pulled)
        for _ in 0..<30 { model.step(dt: 1.0 / 90.0) }
        let held = try XCTUnwrap(model.pendulums.first { $0.id == first.id })
        XCTAssertTrue(held.isGrabbed && model.pendulums.first { $0.id == second.id }!.isGrabbed)
        let restWhileHeld = held.bobWorld

        model.release(id: second.id, handVelocity: .zero)
        for _ in 0..<30 { model.step(dt: 1.0 / 90.0) }
        let still = try XCTUnwrap(model.pendulums.first { $0.id == first.id })
        XCTAssertTrue(still.isGrabbed, "letting go of one bob let go of the other")
        XCTAssertEqual(simd_distance(still.bobWorld, restWhileHeld), 0, accuracy: 1e-9)
    }

    // MARK: Orbital Mechanics

    func testTwoHeldBodiesAreBothFrozenAndThrownEachByItsOwnHand() throws {
        let model = OrbitalMechanicsModel()
        let earth = try XCTUnwrap(model.bodies.first { $0.body.name == "Earth" })
        let mars = try XCTUnwrap(model.bodies.first { $0.body.name == "Mars" })
        let earthAt = earth.body.position * model.simToDisplay
        let marsAt = mars.body.position * model.simToDisplay
        model.grab(id: earth.id, at: earthAt, timestamp: 10)
        model.grab(id: mars.id, at: marsAt, timestamp: 10)
        XCTAssertEqual(model.heldBodyIDs, [earth.id, mars.id])
        XCTAssertEqual(model.heldBodyID, mars.id, "the preview is for the body taken last")

        // The left hand moves Earth; the right hand keeps Mars where it took it.
        for step in 1...6 {
            model.hold(id: earth.id, at: earthAt + SIMD3(0.01 * Double(step), 0, 0),
                       timestamp: 10 + Double(step) * 0.02)
            model.step(dt: 1.0 / 90.0)
        }
        let marsHeld = try XCTUnwrap(model.bodies.first { $0.id == mars.id }).body.position
        XCTAssertEqual(simd_distance(marsHeld, marsAt * model.displayToSim), 0,
                       accuracy: 1e-9 * simd_length(marsHeld),
                       "a body in a still hand moved: the integrator froze only one")
        XCTAssertGreaterThan(simd_length(model.currentHandVelocity(of: earth.id, timestamp: 10.12)), 0)
        XCTAssertEqual(simd_length(model.currentHandVelocity(of: mars.id, timestamp: 10.12)), 0,
                       "the still hand's body would leave with the moving hand's throw")

        model.release(id: earth.id, timestamp: 10.13)
        XCTAssertEqual(model.heldBodyIDs, [mars.id], "letting go of Earth let go of Mars")
        XCTAssertEqual(model.heldBodyID, mars.id)
        model.release(id: mars.id, timestamp: 10.13)
        XCTAssertTrue(model.heldBodyIDs.isEmpty)
        XCTAssertNil(model.heldBodyID)
    }

    // MARK: Projectiles

    func testABallInEachHandIsThrownByItsOwnHand() throws {
        let model = KinematicsModel()
        model.clearFlights()
        let left = model.spawnBall(at: SIMD3(-0.3, 1.2, -0.6))
        let right = model.spawnBall(at: SIMD3(0.3, 1.2, -0.6))
        model.grabBall(id: left)
        model.grabBall(id: right)
        for step in 0...10 {
            let t = 1 + Double(step) * 0.01
            // Left throws forward and up; right only lifts slowly.
            model.holdBall(id: left, at: SIMD3(-0.3, 1.2 + 0.03 * Double(step), -0.6 - 0.06 * Double(step)),
                           timestamp: t)
            model.holdBall(id: right, at: SIMD3(0.3, 1.2 + 0.005 * Double(step), -0.6), timestamp: t)
        }
        model.releaseBall(id: left, timestamp: 1.1)
        let leftFlight = try XCTUnwrap(model.flights.first { $0.id == left })
        let rightFlight = try XCTUnwrap(model.flights.first { $0.id == right })
        XCTAssertEqual(leftFlight.status, .flying)
        XCTAssertEqual(rightFlight.status, .held, "throwing the left ball let go of the right")
        model.releaseBall(id: right, timestamp: 1.1)
        let rightThrown = try XCTUnwrap(model.flights.first { $0.id == right })
        XCTAssertGreaterThan(-leftFlight.state.velocity.z, 3 * abs(rightThrown.state.velocity.z),
                             "the right ball left with the left hand's throw")
    }

    // MARK: Circuits

    func testTwoCarriedPartsBothLiftAndSettleEachOnItsOwn() throws {
        let model = CircuitsModel()
        guard model.components.count > 1 else { return XCTFail("need two parts") }
        let a = model.components[0].id, b = model.components[1].id
        let renderer = CircuitsRenderer()
        renderer.tick(dt: 1 / 90, model: model)
        let holderA = try XCTUnwrap(renderer.root.findEntity(named: a.uuidString))
        let holderB = try XCTUnwrap(renderer.root.findEntity(named: b.uuidString))

        renderer.flashPickup(id: a)
        renderer.flashPickup(id: b)
        for _ in 0..<60 { renderer.tick(dt: 1 / 90, model: model) }
        func lift(_ holder: Entity, _ id: UUID) -> Float {
            holder.position.y - Float(model.components.first { $0.id == id }!.position.y)
        }
        XCTAssertEqual(lift(holderA, a), CircuitsRenderer.liftHeight, accuracy: 1e-4)
        XCTAssertEqual(lift(holderB, b), CircuitsRenderer.liftHeight, accuracy: 1e-4,
                       "the second part taken did not lift")
        XCTAssertTrue(LiveGlow.isLive(holderA) && LiveGlow.isLive(holderB))

        renderer.flashRelease(id: a)
        for _ in 0..<60 { renderer.tick(dt: 1 / 90, model: model) }
        XCTAssertEqual(lift(holderA, a), 0, accuracy: 1e-4)
        XCTAssertEqual(lift(holderB, b), CircuitsRenderer.liftHeight, accuracy: 1e-4,
                       "letting go of one part set the other down")
        XCTAssertTrue(LiveGlow.isLive(holderB))
    }
}
