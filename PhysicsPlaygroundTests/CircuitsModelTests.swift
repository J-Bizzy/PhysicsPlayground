//
//  CircuitsModelTests.swift
//  PhysicsPlaygroundTests
//
//  Tests for the circuit-lab app state: the bench opens empty (parts
//  come off the tray), a hand-built battery–switch–bulb loop carries
//  the exact Ohm's-law current, the switch gates it, tap-tap wiring
//  behaves, capacitors charge through time, and edits stay consistent.
//  Solver math itself is covered in PhysicsCore's CircuitSolverTests.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsModelTests: XCTestCase {

    /// Builds the classic loop the way a user would: three parts off the
    /// tray, three tap-tap wires — battery → switch → bulb → battery.
    private func buildLoop(on model: CircuitsModel)
    -> (battery: CircuitsModel.Component, toggle: CircuitsModel.Component, bulb: CircuitsModel.Component) {
        model.add(.battery)
        model.add(.switcher)
        model.add(.bulb)
        let battery = model.components[0]
        let toggle = model.components[1]
        let bulb = model.components[2]

        model.tapTerminal(.init(componentID: battery.id, end: 1))
        model.tapTerminal(.init(componentID: toggle.id, end: 0))
        model.tapTerminal(.init(componentID: toggle.id, end: 1))
        model.tapTerminal(.init(componentID: bulb.id, end: 0))
        model.tapTerminal(.init(componentID: bulb.id, end: 1))
        model.tapTerminal(.init(componentID: battery.id, end: 0))

        model.step(dt: 1.0 / 90.0)
        return (battery, toggle, bulb)
    }

    /// The lab opens with nothing on the bench — parts come off the tray.
    func testOpensEmpty() {
        let model = CircuitsModel()
        XCTAssertTrue(model.components.isEmpty)
        XCTAssertTrue(model.wires.isEmpty)
        XCTAssertEqual(model.totalSourcePower, 0)
        XCTAssertNil(model.pendingTerminal)
    }

    /// A tray pickup drops the copy at the pinch point (clamped to the
    /// build sphere), not at some fixed spawn slot.
    func testAddAtPointSpawnsThere() {
        let model = CircuitsModel()
        let point = CircuitsModel.buildCenter + SIMD3(0.4, 0.2, -0.3)
        model.add(.resistor, at: point)
        XCTAssertEqual(model.components.count, 1)
        XCTAssertEqual(simd_distance(model.components[0].position, point), 0,
                       accuracy: 1e-12)
        XCTAssertEqual(model.selectedID, model.components[0].id,
                       "a fresh pickup is the selection")
    }

    /// The hand-built battery–switch–bulb loop carries exactly
    /// V / (R_bulb + r_internal + R_switch).
    func testBuiltLoopLightsTheBulb() {
        let model = CircuitsModel()
        let (_, _, bulb) = buildLoop(on: model)
        XCTAssertEqual(model.wires.count, 3)

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
        let (_, toggle, bulb) = buildLoop(on: model)
        model.toggleSwitch(id: toggle.id)
        model.step(dt: 1.0 / 90.0)

        XCTAssertEqual(abs(model.readouts[bulb.id]?.amps ?? 1), 0, accuracy: 1e-6)
        XCTAssertEqual(model.totalSourcePower, 0, accuracy: 1e-6)
    }

    /// The solver keeps running while a component is being carried — the
    /// circuit never freezes mid-move.
    func testCarryingAComponentKeepsTheCircuitLive() {
        let model = CircuitsModel()
        let (_, _, bulb) = buildLoop(on: model)

        // Drag the bulb across the room mid-simulation.
        model.move(id: bulb.id, to: CircuitsModel.buildCenter + SIMD3(0.8, 0.4, 0.2))
        model.step(dt: 1.0 / 90.0)

        let expected = 9.0 / (24 + CircuitsModel.batteryInternalResistance
                              + CircuitSolver.switchResistance)
        XCTAssertEqual(abs(model.readouts[bulb.id]?.amps ?? 0), expected,
                       accuracy: expected * 1e-3,
                       "moving a part must not interrupt the current")
    }

    /// Wire jumpers are honest copper: a battery–wire–bulb–wire loop
    /// carries V / (R_bulb + r_internal + 2·R_wire) with R = ρL/A.
    func testWireJumpersConductTheLoop() {
        let model = CircuitsModel()
        model.add(.battery)
        model.add(.wire)
        model.add(.bulb)
        model.add(.wire)
        let battery = model.components[0]
        let wireA = model.components[1]
        let bulb = model.components[2]
        let wireB = model.components[3]

        model.tapTerminal(.init(componentID: battery.id, end: 1))
        model.tapTerminal(.init(componentID: wireA.id, end: 0))
        model.tapTerminal(.init(componentID: wireA.id, end: 1))
        model.tapTerminal(.init(componentID: bulb.id, end: 0))
        model.tapTerminal(.init(componentID: bulb.id, end: 1))
        model.tapTerminal(.init(componentID: wireB.id, end: 0))
        model.tapTerminal(.init(componentID: wireB.id, end: 1))
        model.tapTerminal(.init(componentID: battery.id, end: 0))
        model.step(dt: 1.0 / 90.0)

        let wireOhms = CircuitsModel.wireResistance(
            length: CircuitsModel.ComponentKind.wire.defaultValue)
        let expected = 9.0 / (24 + CircuitsModel.batteryInternalResistance
                              + 2 * wireOhms)
        XCTAssertEqual(abs(model.readouts[bulb.id]?.amps ?? 0), expected,
                       accuracy: expected * 1e-3)
        // The jumper drops exactly I·R — a millivolt or so, not zero.
        XCTAssertEqual(abs(model.readouts[wireA.id]?.volts ?? 0),
                       expected * wireOhms,
                       accuracy: expected * wireOhms * 0.01)
    }

    /// A wire's length is adjustable: its terminals spread to span it
    /// and its resistance grows with it (R = ρL/A).
    func testWireLengthMovesTerminalsAndScalesResistance() {
        let model = CircuitsModel()
        model.add(.wire)
        let short = model.components[0]
        XCTAssertEqual(short.terminalPosition(1).x - short.terminalPosition(0).x,
                       short.value, accuracy: 1e-12,
                       "terminals span exactly the wire's length")

        model.select(id: short.id)
        model.selectedValue = 2.0
        let long = model.components[0]
        XCTAssertEqual(long.terminalPosition(1).x - long.terminalPosition(0).x,
                       2.0, accuracy: 1e-12)
        XCTAssertEqual(CircuitsModel.wireResistance(length: 2.0),
                       8 * CircuitsModel.wireResistance(length: 0.25),
                       accuracy: 1e-12,
                       "resistance is proportional to length")
    }

    /// Pulling an end grip swings the part around its opposite end: the
    /// pivot end stays exactly where it was, the part re-aims toward the
    /// hand, and the span is preserved for fixed-size parts.
    func testDragEndPinsTheOppositeEnd() {
        let model = CircuitsModel()
        model.add(.battery)
        let battery = model.components[0]
        let pivot = battery.terminalPosition(0)

        // Pull terminal 1's grip straight up from the pivot.
        model.dragEnd(id: battery.id, grabbedEnd: 1,
                      pivot: pivot, hand: pivot + SIMD3(0, 0.5, 0))

        let turned = model.components[0]
        XCTAssertEqual(simd_distance(turned.terminalPosition(0), pivot), 0,
                       accuracy: 1e-12, "the opposite end must stay pinned")
        XCTAssertEqual(simd_distance(turned.axis, SIMD3(0, 1, 0)), 0,
                       accuracy: 1e-12, "the part now points straight up")
        XCTAssertEqual(
            simd_distance(turned.terminalPosition(0), turned.terminalPosition(1)),
            2 * CircuitsModel.terminalOffset, accuracy: 1e-12,
            "a battery's span must not stretch")
    }

    /// The same pull on a wire aims it AND takes its length from the
    /// hand's reach (minus the grip's standoff past the terminal).
    func testDragEndStretchesAndAimsAWire() {
        let model = CircuitsModel()
        model.add(.wire)
        let wire = model.components[0]
        let pivot = wire.terminalPosition(0)
        let direction = simd_normalize(SIMD3(1.0, 1.0, 0))

        model.dragEnd(id: wire.id, grabbedEnd: 1,
                      pivot: pivot, hand: pivot + direction * 1.0)

        let pulled = model.components[0]
        XCTAssertEqual(pulled.value, 1.0 - CircuitsModel.endGripOffset,
                       accuracy: 1e-12, "length = reach minus the grip standoff")
        XCTAssertEqual(simd_distance(pulled.terminalPosition(0), pivot), 0,
                       accuracy: 1e-12)
        XCTAssertEqual(simd_distance(pulled.axis, direction), 0, accuracy: 1e-12)
    }

    /// Pulling an end grip goes through setWireLength: clamped to the
    /// slider's range, and a no-op on anything that isn't a wire.
    func testSetWireLengthClampsAndIgnoresNonWires() {
        let model = CircuitsModel()
        model.add(.wire)
        model.add(.battery)
        let wire = model.components[0]
        let battery = model.components[1]

        model.setWireLength(id: wire.id, length: 0.8)
        XCTAssertEqual(model.components[0].value, 0.8, accuracy: 1e-12)

        model.setWireLength(id: wire.id, length: 50)
        XCTAssertEqual(model.components[0].value,
                       CircuitsModel.wireLengthRange.upperBound, accuracy: 1e-12)
        model.setWireLength(id: wire.id, length: -1)
        XCTAssertEqual(model.components[0].value,
                       CircuitsModel.wireLengthRange.lowerBound, accuracy: 1e-12)

        model.setWireLength(id: battery.id, length: 1.0)
        XCTAssertEqual(model.components[1].value, 9.0, accuracy: 1e-12,
                       "a battery's voltage must not be mistaken for a length")
    }

    /// Tap–tap wiring: first tap arms, second connects, tapping the same
    /// terminal cancels, duplicates are refused.
    func testTapTapWiring() {
        let model = CircuitsModel()
        model.add(.battery)
        model.add(.resistor)
        let battery = model.components[0]
        let resistor = model.components[1]
        let a = CircuitsModel.Terminal(componentID: resistor.id, end: 0)
        let b = CircuitsModel.Terminal(componentID: battery.id, end: 0)

        model.tapTerminal(a)
        XCTAssertEqual(model.pendingTerminal, a)
        model.tapTerminal(b)
        XCTAssertNil(model.pendingTerminal)
        XCTAssertEqual(model.wires.count, 1)

        // Duplicate refused (in either direction).
        model.tapTerminal(b)
        model.tapTerminal(a)
        XCTAssertEqual(model.wires.count, 1)

        // Same-terminal tap cancels.
        model.tapTerminal(a)
        model.tapTerminal(a)
        XCTAssertNil(model.pendingTerminal)
        XCTAssertEqual(model.wires.count, 1)
    }

    /// Removing a component takes its wires with it.
    func testRemovingComponentRemovesItsWires() {
        let model = CircuitsModel()
        let (_, _, bulb) = buildLoop(on: model)
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
        model.add(.battery)
        model.add(.resistor)
        model.add(.capacitor)
        let battery = model.components[0]
        let resistor = model.components[1]
        let capacitor = model.components[2]

        // Battery → resistor → capacitor → battery, for a visible
        // time constant.
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

        // Off-sphere tray drops clamp too.
        model.reset()
        model.add(.bulb, at: CircuitsModel.buildCenter + SIMD3(100, 0, 0))
        XCTAssertLessThanOrEqual(
            simd_distance(model.components[0].position, CircuitsModel.buildCenter),
            CircuitsModel.buildRadius + 1e-9)
    }

    /// Reset clears the bench back to the empty opening state.
    func testResetClearsTheBench() {
        let model = CircuitsModel()
        _ = buildLoop(on: model)
        model.add(.capacitor)
        model.showElectronFlow = false
        model.isPaused = true

        model.reset()

        XCTAssertTrue(model.components.isEmpty)
        XCTAssertTrue(model.wires.isEmpty)
        XCTAssertTrue(model.showElectronFlow)
        XCTAssertFalse(model.isPaused)
        XCTAssertNil(model.pendingTerminal)
        XCTAssertEqual(model.totalSourcePower, 0)
    }
}
