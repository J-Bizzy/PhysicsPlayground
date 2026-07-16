//
//  CircuitsModelTests.swift
//  PhysicsPlaygroundTests
//
//  Tests for the circuit-lab app state: the opening loop lights its
//  bulb with the exact Ohm's-law current, the switch gates it, tap-tap
//  wiring behaves, capacitors charge through time, and edits stay
//  consistent. Solver math itself is covered in PhysicsCore's
//  CircuitSolverTests.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsModelTests: XCTestCase {

    /// The opening battery–switch–bulb loop carries exactly
    /// V / (R_bulb + r_internal + R_switch).
    func testOpeningLoopLightsTheBulb() {
        let model = CircuitsModel()
        XCTAssertEqual(model.components.count, 3)
        XCTAssertEqual(model.wires.count, 3)

        let bulb = model.components.first { $0.kind == .bulb }!
        let readout = try! XCTUnwrap(model.readouts[bulb.id])
        let expected = 9.0 / (24 + CircuitsModel.batteryInternalResistance
                              + CircuitSolver.switchResistance)
        XCTAssertEqual(abs(readout.amps), expected, accuracy: expected * 1e-3)
        XCTAssertEqual(abs(readout.watts), expected * expected * 24,
                       accuracy: 0.05)
        XCTAssertGreaterThan(model.totalSourcePower, 3)
    }

    /// Pinching the switch open stops everything.
    func testOpeningTheSwitchKillsTheCurrent() {
        let model = CircuitsModel()
        let toggle = model.components.first { $0.kind == .switcher }!
        model.toggleSwitch(id: toggle.id)
        model.step(dt: 1.0 / 90.0)

        let bulb = model.components.first { $0.kind == .bulb }!
        XCTAssertEqual(abs(model.readouts[bulb.id]?.amps ?? 1), 0, accuracy: 1e-6)
        XCTAssertEqual(model.totalSourcePower, 0, accuracy: 1e-6)
    }

    /// Tap–tap wiring: first tap arms, second connects, tapping the same
    /// terminal cancels, duplicates are refused.
    func testTapTapWiring() {
        let model = CircuitsModel()
        model.add(.resistor)
        let resistor = model.components.last!
        let battery = model.components.first { $0.kind == .battery }!
        let a = CircuitsModel.Terminal(componentID: resistor.id, end: 0)
        let b = CircuitsModel.Terminal(componentID: battery.id, end: 0)
        let wiresBefore = model.wires.count

        model.tapTerminal(a)
        XCTAssertEqual(model.pendingTerminal, a)
        model.tapTerminal(b)
        XCTAssertNil(model.pendingTerminal)
        XCTAssertEqual(model.wires.count, wiresBefore + 1)

        // Duplicate refused (in either direction).
        model.tapTerminal(b)
        model.tapTerminal(a)
        XCTAssertEqual(model.wires.count, wiresBefore + 1)

        // Same-terminal tap cancels.
        model.tapTerminal(a)
        model.tapTerminal(a)
        XCTAssertNil(model.pendingTerminal)
        XCTAssertEqual(model.wires.count, wiresBefore + 1)
    }

    /// Removing a component takes its wires with it.
    func testRemovingComponentRemovesItsWires() {
        let model = CircuitsModel()
        let bulb = model.components.first { $0.kind == .bulb }!
        model.select(id: bulb.id)
        model.removeSelected()
        XCTAssertEqual(model.components.count, 2)
        XCTAssertEqual(model.wires.count, 1,
                       "only the battery–switch wire survives")
        XCTAssertFalse(model.wires.contains {
            $0.from.componentID == bulb.id || $0.to.componentID == bulb.id
        })
    }

    /// A capacitor wired across the battery charges toward the source
    /// voltage through time — and pause freezes it mid-charge.
    func testCapacitorChargesAndPauseFreezesIt() {
        let model = CircuitsModel()
        model.add(.capacitor)
        let capacitor = model.components.last!
        let battery = model.components.first { $0.kind == .battery }!

        // Wire it straight across the battery (through a fresh resistor
        // for a visible time constant).
        model.add(.resistor)
        let resistor = model.components.last!
        model.tapTerminal(.init(componentID: battery.id, end: 0))
        model.tapTerminal(.init(componentID: resistor.id, end: 0))
        model.tapTerminal(.init(componentID: resistor.id, end: 1))
        model.tapTerminal(.init(componentID: capacitor.id, end: 0))
        model.tapTerminal(.init(componentID: capacitor.id, end: 1))
        model.tapTerminal(.init(componentID: battery.id, end: 1))

        for _ in 0..<300 {
            model.step(dt: 1.0 / 90.0)
        }
        let charged = model.components.first { $0.id == capacitor.id }!.capacitorVoltage
        XCTAssertGreaterThan(charged, 1.0, "the capacitor must be charging")

        model.isPaused = true
        for _ in 0..<100 {
            model.step(dt: 1.0 / 90.0)
        }
        let frozen = model.components.first { $0.id == capacitor.id }!.capacitorVoltage
        XCTAssertEqual(frozen, charged, accuracy: 1e-12,
                       "pause must freeze the capacitor's state")
    }

    func testBudgetsAndClamping() {
        let model = CircuitsModel()
        for _ in 0..<30 {
            model.add(.resistor)
        }
        XCTAssertEqual(model.components.count, CircuitsModel.componentBudget)

        let id = model.components.last!.id
        model.move(id: id, to: SIMD3(50, -50, 50))
        let position = model.components.last!.position
        XCTAssertLessThanOrEqual(
            simd_distance(position, CircuitsModel.buildCenter),
            CircuitsModel.buildRadius + 1e-9)
        XCTAssertGreaterThanOrEqual(position.y, CircuitsModel.floorMargin - 1e-9)
    }

    func testResetRestoresTheLitLoop() {
        let model = CircuitsModel()
        model.add(.capacitor)
        model.showElectronFlow = false
        model.isPaused = true

        model.reset()

        XCTAssertEqual(model.components.count, 3)
        XCTAssertEqual(model.wires.count, 3)
        XCTAssertTrue(model.showElectronFlow)
        XCTAssertFalse(model.isPaused)
        XCTAssertNil(model.pendingTerminal)
        XCTAssertGreaterThan(model.totalSourcePower, 3, "the loop starts lit")
    }
}
