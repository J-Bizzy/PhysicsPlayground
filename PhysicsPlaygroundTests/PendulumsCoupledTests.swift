//
//  PendulumsCoupledTests.swift
//  PhysicsPlaygroundTests
//
//  Coupled pendulums in the lab as built: the ready pair trades its swing
//  as the beat says, a spring couples only free simple pendulums within a
//  spring's reach, deleting a bob takes its spring, the pair never touches
//  the cradle beside it, and a Time Capsule restore brings the spring back.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class PendulumsCoupledTests: XCTestCase {

    private let dt = 1.0 / 90.0

    private func pair(_ model: PendulumsModel) throws -> (PendulumsModel.Pendulum, PendulumsModel.Pendulum) {
        let spring = try XCTUnwrap(model.springs.first)
        let a = try XCTUnwrap(model.pendulums.first { $0.id == spring.a })
        let b = try XCTUnwrap(model.pendulums.first { $0.id == spring.b })
        return (a, b)
    }

    /// The cradle beside the pair goes on exactly as if the pair were not
    /// there: they are independent rigs and never touch.
    func testTheCoupledPairDoesNotDisturbTheCradle() {
        let plain = PendulumsModel()
        let coupled = PendulumsModel()
        XCTAssertTrue(coupled.addCoupledPair())
        for _ in 0..<Int(20 / dt) {
            plain.step(dt: dt)
            coupled.step(dt: dt)
        }
        for (a, b) in zip(plain.pendulums.prefix(5), coupled.pendulums.prefix(5)) {
            XCTAssertEqual(simd_distance(a.bobWorld, b.bobWorld), 0, accuracy: 1e-9,
                           "the pair changed the cradle")
        }
    }

    /// Released from one bob, the pair hands its swing to the other within
    /// half a beat (plus a swing either side).
    func testTheReadyPairTradesItsSwing() throws {
        let model = PendulumsModel()
        model.frictionOn = false
        XCTAssertTrue(model.addCoupledPair())
        let (a, b) = try pair(model)
        // Whichever bob was pulled back; the other starts at rest.
        let pulled = abs(a.state.position.x) > abs(b.state.position.x) ? a : b
        let still = pulled.id == a.id ? b.id : a.id
        let beat = CoupledPendulums.beatPeriod(length: a.length, mass: a.mass,
                                               stiffness: model.springStiffness,
                                               gravity: model.gravity)
        var largest = 0.0
        for _ in 0..<Int((beat / 2 + 2) / dt) {
            model.step(dt: dt)
            let bob = try XCTUnwrap(model.pendulums.first { $0.id == still })
            largest = max(largest, abs(bob.state.position.x))
        }
        XCTAssertGreaterThan(largest, 0.9 * abs(pulled.state.position.x),
                             "the swing never reached the other bob")
    }

    func testCouplingNeedsTwoFreeSimplePendulumsWithinReach() throws {
        let model = PendulumsModel()
        // No two of the cradle's bobs are far enough apart for a spring that
        // would not run through the others.
        for bob in model.pendulums {
            XCTAssertNil(model.couplingCandidate(for: bob.id))
        }
        for bob in model.pendulums { model.removePendulum(id: bob.id) }
        let far = try XCTUnwrap(model.addPendulum(at: SIMD3(-1.5, 1.6, -1.1)))
        XCTAssertNil(model.couplingCandidate(for: far))
        let near = try XCTUnwrap(model.addPendulum(at: SIMD3(-1.0, 1.6, -1.1)))
        XCTAssertEqual(model.couplingCandidate(for: far), near)
        XCTAssertTrue(model.couple(id: far))
        XCTAssertEqual(model.partner(of: near), far)
        // A pendulum on a spring is not free for a second one.
        XCTAssertNil(model.couplingCandidate(for: far))
        let double = try XCTUnwrap(model.addDoublePendulum(at: SIMD3(-0.6, 1.8, -1.1)))
        XCTAssertNil(model.couplingCandidate(for: double))
    }

    /// The ready pair is coupled to itself, never to the cradle beside it.
    func testTheReadyPairIsCoupledToItself() throws {
        let model = PendulumsModel()
        let cradle = Set(model.pendulums.map(\.id))
        XCTAssertTrue(model.addCoupledPair())
        let (a, b) = try pair(model)
        XCTAssertFalse(cradle.contains(a.id))
        XCTAssertFalse(cradle.contains(b.id))
    }

    func testDeletingABobTakesItsSpring() throws {
        let model = PendulumsModel()
        XCTAssertTrue(model.addCoupledPair())
        let (a, b) = try pair(model)
        model.removePendulum(id: a.id)
        XCTAssertTrue(model.springs.isEmpty)
        XCTAssertNil(model.partner(of: b.id))
    }

    /// Hanging still, the spring is at its natural length: a coupled pair at
    /// rest pulls on nothing, and each cable holds just its bob.
    func testAPairAtRestIsUnstretched() throws {
        let model = PendulumsModel()
        let left = try XCTUnwrap(model.addPendulum(angle: 0, at: SIMD3(-1.0, 1.6, -1.1)))
        let right = try XCTUnwrap(model.addPendulum(angle: 0, at: SIMD3(-0.6, 1.6, -1.1)))
        XCTAssertTrue(model.couple(id: left))
        let bob = try XCTUnwrap(model.pendulums.first { $0.id == right })
        let forces = model.forces(on: bob)
        XCTAssertEqual(simd_length(forces.spring), 0, accuracy: 1e-12)
        XCTAssertEqual(simd_length(forces.net), 0, accuracy: 1e-9)
    }

    func testTheCapsuleBringsTheSpringBack() throws {
        let model = PendulumsModel()
        XCTAssertTrue(model.addCoupledPair())
        for _ in 0..<30 { model.step(dt: dt) }
        let snapshot = model.captureCapsuleSnapshot()
        let (a, _) = try pair(model)
        model.uncouple(id: a.id)
        model.setSpringStiffness(6)
        model.restoreCapsuleSnapshot(snapshot)
        XCTAssertEqual(model.springs, snapshot.springs)
        XCTAssertEqual(model.springStiffness, PendulumsModel.defaultStiffness)
    }

    func testResetRemovesEverySpring() {
        let model = PendulumsModel()
        model.addCoupledPair()
        model.setSpringStiffness(5)
        model.reset()
        XCTAssertTrue(model.springs.isEmpty)
        XCTAssertEqual(model.springStiffness, PendulumsModel.defaultStiffness)
    }
}
