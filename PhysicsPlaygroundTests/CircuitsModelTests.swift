//
//  CircuitsModelTests.swift
//  PhysicsPlaygroundTests
//
//  Tests for the circuit-lab app state: the lab opens with a lit
//  battery–switch–bulb starter loop (Clear bench gives the blank
//  slate), a hand-built loop carries the exact Ohm's-law current, the
//  switch gates it, tap-tap wiring behaves, parts aim in 3D, capacitors
//  charge through time, and edits stay consistent. Solver math itself
//  is covered in PhysicsCore's CircuitSolverTests.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsModelTests: XCTestCase {

    /// The multimeter reads the true potential difference across a
    /// component, and continuity through a wire.
    func testMultimeterReadsVoltageAndContinuity() throws {
        let model = CircuitsModel()
        model.clearBench()
        guard let battery = model.add(.battery, at: SIMD3(-0.3, 1.2, -0.9)),
              let resistor = model.add(.resistor, at: SIMD3(0.3, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        let bPlus = CircuitsModel.Terminal(componentID: battery, end: 0)
        let bMinus = CircuitsModel.Terminal(componentID: battery, end: 1)
        let rA = CircuitsModel.Terminal(componentID: resistor, end: 0)
        let rB = CircuitsModel.Terminal(componentID: resistor, end: 1)
        model.connectTerminals(bPlus, rA)
        model.connectTerminals(bMinus, rB)
        model.step(dt: 1.0 / 90.0)

        // The reading is a FORMATTED display now, not a bag of raw
        // numbers, because the meter has modes and each one answers a
        // different question. The drop itself is still the solver's —
        // asserted against `readouts` through the string the meter shows.
        model.meterMode = .voltsDC
        model.setProbe(.red, to: rA)
        model.setProbe(.black, to: rB)
        let reading = try XCTUnwrap(model.multimeterReading)
        XCTAssertFalse(reading.fault)
        XCTAssertEqual(reading.display,
                       CircuitsModel.autoRange(model.readouts[resistor]!.volts,
                                               unit: "V"),
                       "the meter reads the same drop the solver computes")

        // Probes on the two ends of one WIRE: continuity.
        model.meterMode = .continuity
        model.setProbe(.red, to: bPlus)
        model.setProbe(.black, to: rA)
        XCTAssertTrue(try XCTUnwrap(model.multimeterReading).beeping,
                      "wired-together terminals show continuity")
    }

    /// The scope buffers the selected part's live samples and clears
    /// when the selection changes.
    func testScopeBuffersSelectedComponent() {
        let model = CircuitsModel()
        model.clearBench()
        guard let battery = model.add(.battery, at: SIMD3(-0.3, 1.2, -0.9)),
              let resistor = model.add(.resistor, at: SIMD3(0.3, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        model.connectTerminals(.init(componentID: battery, end: 0), .init(componentID: resistor, end: 0))
        model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: resistor, end: 1))
        model.select(id: resistor)
        for _ in 0..<90 { model.step(dt: 1.0 / 90.0) }
        XCTAssertGreaterThan(model.scopeSamples.count, 30, "a second of samples")
        XCTAssertEqual(model.scopeSamples.last!.volts,
                       model.readouts[resistor]!.volts, accuracy: 1e-9)
        model.select(id: battery)
        XCTAssertTrue(model.scopeSamples.isEmpty, "new selection, fresh trace")
    }


    /// A bare LED across a 9 V battery burns out in one live step; a
    /// Replace puts it back in service.
    func testLEDBurnsOutWithoutSeriesResistance() {
        let model = CircuitsModel()
        model.clearBench()
        guard let battery = model.add(.battery, at: SIMD3(-0.3, 1.2, -0.9)),
              let led = model.add(.led, at: SIMD3(0.3, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        let bPlus = CircuitsModel.Terminal(componentID: battery, end: 0)
        let bMinus = CircuitsModel.Terminal(componentID: battery, end: 1)
        let lA = CircuitsModel.Terminal(componentID: led, end: 0)
        let lB = CircuitsModel.Terminal(componentID: led, end: 1)
        model.connectTerminals(bPlus, lA)
        model.connectTerminals(bMinus, lB)
        model.step(dt: 1.0 / 90.0)
        XCTAssertTrue(model.components.first { $0.id == led }!.failed,
                      "9 V straight into a 2 V/12 Ω LED is far past 30 mA")
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(abs(model.readouts[led]?.amps ?? 1), 0, accuracy: 1e-6,
                       "a burned LED is an open circuit")
        model.replaceFailed(id: led)
        XCTAssertFalse(model.components.first { $0.id == led }!.failed)
    }

    /// A shorted battery through a 1 A fuse blows it — and the blown
    /// fuse then protects the circuit as an open.
    func testFuseBlowsAboveItsRating() {
        let model = CircuitsModel()
        model.clearBench()
        guard let battery = model.add(.battery, at: SIMD3(-0.3, 1.2, -0.9)),
              let fuse = model.add(.fuse, at: SIMD3(0.3, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        model.connectTerminals(.init(componentID: battery, end: 0), .init(componentID: fuse, end: 0))
        model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: fuse, end: 1))
        model.step(dt: 1.0 / 90.0)
        XCTAssertTrue(model.components.first { $0.id == fuse }!.failed,
                      "a dead short pushes far beyond the 1 A rating")
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(abs(model.readouts[fuse]?.amps ?? 1), 0, accuracy: 1e-6)
    }

    /// The AC source really alternates: over one full period the
    /// resistor's current flows both ways.
    func testACSourceAlternates() {
        let model = CircuitsModel()
        model.clearBench()
        guard let source = model.add(.acSource, at: SIMD3(-0.3, 1.2, -0.9)),
              let resistor = model.add(.resistor, at: SIMD3(0.3, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        model.connectTerminals(.init(componentID: source, end: 0), .init(componentID: resistor, end: 0))
        model.connectTerminals(.init(componentID: source, end: 1), .init(componentID: resistor, end: 1))
        var sawPositive = false
        var sawNegative = false
        for _ in 0..<240 {   // ~2.7 s at 90 Hz: beyond one 2 s period
            model.step(dt: 1.0 / 90.0)
            let amps = model.readouts[resistor]?.amps ?? 0
            if amps > 1e-4 { sawPositive = true }
            if amps < -1e-4 { sawNegative = true }
        }
        XCTAssertTrue(sawPositive && sawNegative,
                      "current must flow both directions over a full AC cycle")
    }


    /// The carry preview and the release do the same thing: what the
    /// ghost wires promise is exactly what autoConnect creates.
    func testAutoConnectPreviewMatchesRelease() {
        let model = CircuitsModel()
        model.clearBench()
        guard let battery = model.add(.battery, at: SIMD3(0, 1.2, -0.9)),
              let bulb = model.add(.bulb, at: SIMD3(0.2, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        // battery t1 at x = 0.085; bulb t0 at 0.115 — a 3 cm gap, inside snap.
        let pairs = model.autoConnectCandidates(id: bulb)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].from, CircuitsModel.Terminal(componentID: bulb, end: 0))
        XCTAssertEqual(pairs[0].to, CircuitsModel.Terminal(componentID: battery, end: 1))

        model.autoConnect(id: bulb)
        XCTAssertEqual(model.wires.count, 1)
        XCTAssertTrue(model.autoConnectCandidates(id: bulb).isEmpty,
                      "once wired, the preview clears")
    }

    /// Drag-to-wire lands anywhere: distance-free, duplicate-proof.
    func testConnectTerminalsDirectly() {
        let model = CircuitsModel()
        model.clearBench()
        guard let battery = model.add(.battery, at: SIMD3(-0.4, 1.2, -0.9)),
              let bulb = model.add(.bulb, at: SIMD3(0.5, 1.4, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        let a = CircuitsModel.Terminal(componentID: battery, end: 1)
        let b = CircuitsModel.Terminal(componentID: bulb, end: 0)
        model.connectTerminals(a, b)
        XCTAssertEqual(model.wires.count, 1)
        model.connectTerminals(b, a)
        XCTAssertEqual(model.wires.count, 1, "duplicates rejected either way round")
        model.connectTerminals(a, a)
        XCTAssertEqual(model.wires.count, 1, "no self-wires")
    }


    /// The exact current of a 9 V battery–switch–bulb loop.
    private var starterLoopAmps: Double {
        9.0 / (24 + CircuitsModel.batteryInternalResistance
               + CircuitSolver.switchResistance)
    }

    /// Clears the bench and builds the classic loop the way a user
    /// would: three parts, three tap-tap wires — battery → switch →
    /// bulb → battery.
    private func buildLoop(on model: CircuitsModel)
    -> (battery: CircuitsModel.Component, toggle: CircuitsModel.Component, bulb: CircuitsModel.Component) {
        model.clearBench()
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

    /// The lab opens with the starter loop already flowing: bulb lit
    /// with the exact Ohm's-law current, electrons moving in every wire.
    func testOpensWithAFlowingStarterLoop() {
        let model = CircuitsModel()
        XCTAssertEqual(model.components.count, 3)
        XCTAssertEqual(model.wires.count, 3)

        let bulb = model.components.first { $0.kind == .bulb }!
        let readout = try! XCTUnwrap(model.readouts[bulb.id])
        XCTAssertEqual(abs(readout.amps), starterLoopAmps,
                       accuracy: starterLoopAmps * 1e-3)
        XCTAssertGreaterThan(model.totalSourcePower, 3, "the loop opens lit")

        // Every wire carries the loop current, so electrons flow on open.
        XCTAssertEqual(model.wireFlows.count, 3)
        for flow in model.wireFlows.values {
            XCTAssertGreaterThan(abs(flow), 0.1)
        }
    }

    /// Clear bench is the blank slate — everything gone, nothing armed.
    func testClearBenchEmptiesEverything() {
        let model = CircuitsModel()
        model.clearBench()
        XCTAssertTrue(model.components.isEmpty)
        XCTAssertTrue(model.wires.isEmpty)
        XCTAssertEqual(model.totalSourcePower, 0)
        XCTAssertNil(model.pendingTerminal)
        XCTAssertNil(model.selectedID)
    }

    /// A tray pickup drops the copy at the pinch point (clamped to the
    /// build sphere), not at some fixed spawn slot.
    func testAddAtPointSpawnsThere() {
        let model = CircuitsModel()
        model.clearBench()
        let point = CircuitsModel.buildCenter + SIMD3(0.4, 0.2, -0.3)
        model.add(.resistor, at: point)
        XCTAssertEqual(model.components.count, 1)
        XCTAssertEqual(simd_distance(model.components[0].position, point), 0,
                       accuracy: 1e-12)
        XCTAssertEqual(model.selectedID, model.components[0].id,
                       "a fresh pickup is the selection")
    }

    /// A hand-built battery–switch–bulb loop carries exactly
    /// V / (R_bulb + r_internal + R_switch).
    func testBuiltLoopLightsTheBulb() {
        let model = CircuitsModel()
        let (_, _, bulb) = buildLoop(on: model)
        XCTAssertEqual(model.wires.count, 3)

        let readout = try! XCTUnwrap(model.readouts[bulb.id])
        XCTAssertEqual(abs(readout.amps), starterLoopAmps,
                       accuracy: starterLoopAmps * 1e-3)
        XCTAssertEqual(abs(readout.watts), starterLoopAmps * starterLoopAmps * 24,
                       accuracy: 0.05)
    }

    /// Pinching the starter loop's switch open stops everything.
    func testOpeningTheSwitchKillsTheCurrent() {
        let model = CircuitsModel()
        let toggle = model.components.first { $0.kind == .switcher }!
        model.toggleSwitch(id: toggle.id)
        model.step(dt: 1.0 / 90.0)

        let bulb = model.components.first { $0.kind == .bulb }!
        XCTAssertEqual(abs(model.readouts[bulb.id]?.amps ?? 1), 0, accuracy: 1e-6)
        XCTAssertEqual(model.totalSourcePower, 0, accuracy: 1e-6)
    }

    /// The solver keeps running while a component is being carried — the
    /// starter loop never freezes mid-move.
    func testCarryingAComponentKeepsTheCircuitLive() {
        let model = CircuitsModel()
        let bulb = model.components.first { $0.kind == .bulb }!

        // Drag the bulb across the room mid-simulation.
        model.move(id: bulb.id, to: CircuitsModel.buildCenter + SIMD3(0.8, 0.4, 0.2))
        model.step(dt: 1.0 / 90.0)

        XCTAssertEqual(abs(model.readouts[bulb.id]?.amps ?? 0), starterLoopAmps,
                       accuracy: starterLoopAmps * 1e-3,
                       "moving a part must not interrupt the current")
    }

    /// Wire jumpers are honest copper: a battery–wire–bulb–wire loop
    /// carries V / (R_bulb + r_internal + 2·R_wire) with R = ρL/A.
    func testWireJumpersConductTheLoop() {
        let model = CircuitsModel()
        model.clearBench()
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

    /// Pulling an end grip swings the part around its opposite end: the
    /// pivot end stays exactly where it was, the part re-aims toward the
    /// hand, and the span is preserved for fixed-size parts.
    func testDragEndPinsTheOppositeEnd() {
        let model = CircuitsModel()
        model.clearBench()
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
        model.clearBench()
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

    /// A twist during a carry is adopted on release: setAxis normalizes,
    /// and rejects a degenerate axis rather than corrupting the part.
    func testSetAxisNormalizesAndRejectsDegenerate() {
        let model = CircuitsModel()
        model.clearBench()
        model.add(.resistor)
        let id = model.components[0].id

        model.setAxis(id: id, axis: SIMD3(0, 3, 0))
        XCTAssertEqual(simd_distance(model.components[0].axis, SIMD3(0, 1, 0)), 0,
                       accuracy: 1e-12)

        model.setAxis(id: id, axis: .zero)
        XCTAssertEqual(simd_distance(model.components[0].axis, SIMD3(0, 1, 0)), 0,
                       accuracy: 1e-12, "a zero axis must be ignored")
    }

    /// Shorting a battery through bare wire trips the overload flag; the
    /// healthy starter loop doesn't.
    func testShortCircuitTripsTheOverloadWarning() {
        let model = CircuitsModel()
        model.clearBench()
        model.add(.battery)
        model.add(.wire)
        let battery = model.components[0]
        let wire = model.components[1]
        model.tapTerminal(.init(componentID: battery.id, end: 1))
        model.tapTerminal(.init(componentID: wire.id, end: 0))
        model.tapTerminal(.init(componentID: wire.id, end: 1))
        model.tapTerminal(.init(componentID: battery.id, end: 0))
        model.step(dt: 1.0 / 90.0)
        XCTAssertTrue(model.hasOverloadedBattery,
                      "9 V through milliohms is a dead short (~150 A)")

        model.reset()
        XCTAssertFalse(model.hasOverloadedBattery,
                       "the starter loop draws well under an amp")
    }

    /// Tap–tap wiring: first tap arms, second connects, tapping the same
    /// terminal cancels, duplicates are refused.
    func testTapTapWiring() {
        let model = CircuitsModel()
        model.clearBench()
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
        model.clearBench()
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
        assertOnTheBench(position)
        XCTAssertGreaterThanOrEqual(position.y, CircuitsModel.floorMargin - 1e-9)

        // Off-bench tray drops clamp too.
        model.clearBench()
        model.add(.bulb, at: CircuitsModel.buildCenter + SIMD3(100, 0, 0))
        assertOnTheBench(model.components[0].position)
    }

    /// The bench is a BOX, not the 3 m sphere it was before the E&M
    /// world stood a magnetic field 1.33 m to its right. A part that
    /// can be dragged three metres is a part that can be parked inside
    /// the neighbouring apparatus.
    private func assertOnTheBench(
        _ position: SIMD3<Double>,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let low = CircuitsModel.buildCenter - CircuitsModel.buildHalfExtents
        let high = CircuitsModel.buildCenter + CircuitsModel.buildHalfExtents
        for axis in 0..<3 {
            XCTAssertGreaterThanOrEqual(
                position[axis], low[axis] - 1e-9,
                "a part escaped the bench on axis \(axis)", file: file, line: line)
            XCTAssertLessThanOrEqual(
                position[axis], high[axis] + 1e-9,
                "a part escaped the bench on axis \(axis)", file: file, line: line)
        }
    }

    /// Pulling an end grip goes through setWireLength: clamped to the
    /// slider's range, and a no-op on anything that isn't a wire.
    func testSetWireLengthClampsAndIgnoresNonWires() {
        let model = CircuitsModel()
        model.clearBench()
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

    /// A wire's length is adjustable: its terminals spread to span it
    /// and its resistance grows with it (R = ρL/A).
    func testWireLengthMovesTerminalsAndScalesResistance() {
        let model = CircuitsModel()
        model.clearBench()
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

    /// Reset restores the welcome scene: the lit starter loop, defaults
    /// back, edits gone.
    func testResetRestoresTheStarterLoop() {
        let model = CircuitsModel()
        model.clearBench()
        model.add(.capacitor)
        model.showElectronFlow = false
        model.isPaused = true
        // The other three states the bank shows, plus the meter — all of
        // which reset used to leave exactly as it found them.
        model.trueSpeedMode = true
        model.showVoltageHeights = true
        model.electronView = true
        model.multimeterArmed = true

        model.reset()

        XCTAssertEqual(model.components.count, 3)
        XCTAssertEqual(model.wires.count, 3)
        XCTAssertTrue(model.showElectronFlow)
        XCTAssertFalse(model.isPaused)
        XCTAssertNil(model.pendingTerminal)
        XCTAssertGreaterThan(model.totalSourcePower, 3, "the loop comes back lit")

        // Every lamp standing beside this bench, back where it started.
        // Reset from Electron View used to hand back a bench still
        // swollen to 4× with three lit plates over it — the worst of the
        // four reset defects found across the app in one day.
        XCTAssertFalse(model.trueSpeedMode)
        XCTAssertFalse(model.showVoltageHeights)
        XCTAssertFalse(model.electronView, "the bench stayed inside the copper")
        XCTAssertFalse(model.multimeterArmed)
    }

    /// Disarming the meter drops both probes, so a stale pair cannot come
    /// back the next time it is armed. The meter is an object on the
    /// bench now and its lit face is a claim about exactly this.
    func testDisarmingTheMeterForgetsItsProbes() {
        let model = CircuitsModel()
        model.multimeterArmed = true
        let battery = model.components.first { $0.kind == .battery }!
        let bulb = model.components.first { $0.kind == .bulb }!
        model.step(dt: 1.0 / 90.0)
        model.probeTap(CircuitsModel.Terminal(componentID: battery.id, end: 0))
        model.probeTap(CircuitsModel.Terminal(componentID: bulb.id, end: 1))
        XCTAssertNotNil(model.multimeterReading)

        model.multimeterArmed = false
        XCTAssertNil(model.multimeterReading,
                     "a disarmed meter must not still be reading")

        model.multimeterArmed = true
        XCTAssertNil(model.multimeterReading,
                     "re-arming must start from nothing probed")
    }

    /// Releasing a part with a terminal near another part's terminal
    /// wires them automatically; distant terminals stay loose.
    func testAutoConnectSnapsNearbyTerminals() {
        let model = CircuitsModel()
        model.clearBench()
        model.add(.battery, at: CircuitsModel.buildCenter)
        let battery = model.components[0]
        // Drop a bulb so its terminal 0 lands 3 cm from battery terminal 1.
        let near = battery.terminalPosition(1)
            + SIMD3(0.03 + battery.terminalHalfSpan, 0, 0)
        model.add(.bulb, at: near)
        let bulb = model.components[1]

        model.autoConnect(id: bulb.id)
        XCTAssertEqual(model.wires.count, 1, "the close pair self-connects")
        XCTAssertFalse(model.wires.contains {
            $0.from.end == 1 && $0.to.end == 1
        }, "only the near terminals joined")

        // A part released far away connects nothing.
        model.add(.resistor, at: CircuitsModel.buildCenter + SIMD3(0, 0.8, 0))
        model.autoConnect(id: model.components[2].id)
        XCTAssertEqual(model.wires.count, 1)
    }

    /// The preset library carries exact textbook numbers: series bulbs
    /// share current, parallel bulbs each draw full current, the
    /// divider splits 9 V by resistance, and the short trips the
    /// warning.
    func testPresetCircuitsCarryTextbookValues() {
        let model = CircuitsModel()

        model.loadPreset(.series)
        let seriesBulbs = model.components.filter { $0.kind == .bulb }
        let seriesExpected = 9.0 / (48 + CircuitsModel.batteryInternalResistance
                                    + CircuitSolver.switchResistance)
        for bulb in seriesBulbs {
            XCTAssertEqual(abs(model.readouts[bulb.id]?.amps ?? 0), seriesExpected,
                           accuracy: seriesExpected * 1e-3,
                           "series bulbs thread the same current")
        }

        model.loadPreset(.parallel)
        let battery = model.components.first { $0.kind == .battery }!
        let parallelBulb = model.components.first { $0.kind == .bulb }!
        let batteryAmps = abs(model.readouts[battery.id]?.amps ?? 0)
        let bulbAmps = abs(model.readouts[parallelBulb.id]?.amps ?? 0)
        XCTAssertEqual(batteryAmps, 2 * bulbAmps, accuracy: batteryAmps * 0.01,
                       "the battery feeds both branches")

        model.loadPreset(.divider)
        let resistors = model.components.filter { $0.kind == .resistor }
        let v470 = abs(model.readouts[resistors.first { $0.value == 470 }!.id]?.volts ?? 0)
        let v1000 = abs(model.readouts[resistors.first { $0.value == 1000 }!.id]?.volts ?? 0)
        XCTAssertEqual(v1000 / v470, 1000.0 / 470.0, accuracy: 0.02,
                       "voltage splits in proportion to resistance")
        XCTAssertEqual(v470 + v1000, 9.0, accuracy: 0.05,
                       "the shares add back to the source (minus internal drop)")

        model.loadPreset(.shortCircuit)
        XCTAssertTrue(model.hasOverloadedBattery, "the short trips the warning")

        model.loadPreset(.rcCharger)
        let capacitor = model.components.first { $0.kind == .capacitor }!
        for _ in 0..<180 { model.step(dt: 1.0 / 90.0) }  // 2 s ~ 0.9 tau
        let charged = model.components.first { $0.id == capacitor.id }!.capacitorVoltage
        XCTAssertGreaterThan(abs(charged), 3, "well into the charge curve after 2 s")
        XCTAssertLessThan(abs(charged), 8, "but nowhere near full yet")
    }

    /// The bench survives relaunch: an edited build saves, a fresh
    /// restoring model reopens it exactly, and non-restoring models
    /// (like every other test here) always get the starter loop.
    func testBenchPersistsAcrossRelaunch() {
        UserDefaults.standard.removeObject(forKey: CircuitsModel.saveKey)

        let model = CircuitsModel()
        model.clearBench()
        model.add(.battery)
        model.add(.resistor)
        let battery = model.components[0]
        let resistor = model.components[1]
        model.select(id: resistor.id)
        model.selectedValue = 2200
        model.tapTerminal(.init(componentID: battery.id, end: 1))
        model.tapTerminal(.init(componentID: resistor.id, end: 0))
        model.setAxis(id: resistor.id, axis: SIMD3(0, 1, 0))
        model.persistNow()

        // "Relaunch": a restoring model reopens the build.
        let restored = CircuitsModel(restoreSaved: true)
        XCTAssertEqual(restored.components.count, 2)
        XCTAssertEqual(restored.wires.count, 1)
        let restoredResistor = restored.components.first { $0.kind == .resistor }!
        XCTAssertEqual(restoredResistor.value, 2200, accuracy: 1e-12)
        XCTAssertEqual(simd_distance(restoredResistor.axis, SIMD3(0, 1, 0)), 0,
                       accuracy: 1e-12, "orientation survives too")

        // Non-restoring init ignores the save (starter loop as always).
        let fresh = CircuitsModel()
        XCTAssertEqual(fresh.components.count, 3)

        UserDefaults.standard.removeObject(forKey: CircuitsModel.saveKey)
    }

    /// Named slots: save a build, wreck the bench, load it back exactly;
    /// deletion removes it; a fresh model sees the same slot list.
    func testNamedSaveSlotsRoundTrip() {
        UserDefaults.standard.removeObject(forKey: CircuitsModel.slotsKey)
        UserDefaults.standard.removeObject(forKey: CircuitsModel.saveKey)

        let model = CircuitsModel()
        model.clearBench()
        model.add(.battery)
        model.add(.bulb)
        let battery = model.components[0]
        let bulb = model.components[1]
        model.tapTerminal(.init(componentID: battery.id, end: 1))
        model.tapTerminal(.init(componentID: bulb.id, end: 0))
        XCTAssertTrue(model.saveSlot(named: "  My loop  "),
                      "names are trimmed and accepted")
        XCTAssertEqual(model.slotNames, ["My loop"])

        model.clearBench()
        XCTAssertTrue(model.components.isEmpty)
        XCTAssertTrue(model.loadSlot(named: "My loop"))
        XCTAssertEqual(model.components.count, 2)
        XCTAssertEqual(model.wires.count, 1)

        // A fresh model sees the saved slot too.
        let fresh = CircuitsModel()
        XCTAssertEqual(fresh.slotNames, ["My loop"])

        model.deleteSlot(named: "My loop")
        XCTAssertTrue(model.slotNames.isEmpty)
        XCTAssertFalse(model.loadSlot(named: "My loop"))

        UserDefaults.standard.removeObject(forKey: CircuitsModel.slotsKey)
        UserDefaults.standard.removeObject(forKey: CircuitsModel.saveKey)
    }

    // MARK: Attach / detach (the magnet)

    /// Detach drops every wire on a part but leaves the part itself.
    func testDetachComponentDropsItsWiresButKeepsThePart() {
        let model = CircuitsModel()
        model.clearBench()
        guard let battery = model.add(.battery, at: SIMD3(-0.3, 1.2, -0.9)),
              let resistor = model.add(.resistor, at: SIMD3(0.3, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        model.connectTerminals(.init(componentID: battery, end: 0), .init(componentID: resistor, end: 0))
        model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: resistor, end: 1))
        XCTAssertEqual(model.wires.count, 2)

        model.detachComponent(id: resistor)
        XCTAssertTrue(model.wires.isEmpty, "both wires touched the resistor")
        XCTAssertNotNil(model.components.first { $0.id == resistor }, "the part stays")
    }

    /// A snapped contact (short at grab time) pops when the part is
    /// carried past the break distance — pull-apart to detach.
    func testCarryingASnappedPartFarPopsItOff() {
        let model = CircuitsModel()
        model.clearBench()
        // Two parts whose facing terminals coincide — a zero-length
        // contact.
        guard let a = model.add(.battery, at: SIMD3(0, 1.2, -0.9)),
              let b = model.add(.resistor, at: SIMD3(0.17, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        model.connectTerminals(.init(componentID: a, end: 1), .init(componentID: b, end: 0))
        XCTAssertEqual(model.wires.count, 1)

        model.beginCarry(id: b)
        model.move(id: b, to: SIMD3(0.9, 1.2, -0.9))   // well past breakDistance
        model.breakOverstretchedWires(id: b)
        XCTAssertTrue(model.wires.isEmpty, "the stretched contact snapped off")
        model.endCarry()
    }

    /// A deliberately long span wire (already long at grab time) is NOT
    /// yanked off by moving a part — only short contacts pop.
    func testLongSpanWireSurvivesACarry() {
        let model = CircuitsModel()
        model.clearBench()
        guard let a = model.add(.battery, at: SIMD3(-0.4, 1.2, -0.9)),
              let b = model.add(.resistor, at: SIMD3(0.4, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        // Facing terminals are ~0.63 apart — a long span from the start.
        let wire = (CircuitsModel.Terminal(componentID: a, end: 1),
                    CircuitsModel.Terminal(componentID: b, end: 0))
        model.connectTerminals(wire.0, wire.1)
        XCTAssertGreaterThan(model.wireLength(model.wires[0]), CircuitsModel.breakDistance)

        model.beginCarry(id: b)
        model.move(id: b, to: SIMD3(0.6, 1.2, -0.9))
        model.breakOverstretchedWires(id: b)
        XCTAssertEqual(model.wires.count, 1, "an intentional long wire is never auto-broken")
        model.endCarry()
    }

    // MARK: Motor (a real DC motor)

    /// A motor across a battery settles at the steady speed the model's
    /// constants predict, ω = kV/(bR + k²), and doubling the drive
    /// voltage doubles the steady speed.
    func testMotorSteadySpeedIsProportionalToVoltage() {
        func steadySpeed(voltage: Double) -> Double {
            let model = CircuitsModel()
            model.clearBench()
            guard let battery = model.add(.battery, at: SIMD3(-0.3, 1.2, -0.9)),
                  let motor = model.add(.motor, at: SIMD3(0.3, 1.2, -0.9)) else {
                XCTFail("bench refused parts"); return 0
            }
            model.select(id: battery)
            model.selectedValue = voltage
            model.connectTerminals(.init(componentID: battery, end: 0), .init(componentID: motor, end: 0))
            model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: motor, end: 1))
            for _ in 0..<3000 { model.step(dt: 1.0 / 240.0) }   // to steady state
            return model.components.first { $0.id == motor }!.motorSpeed
        }

        let k = CircuitsModel.motorTorqueConstant
        let b = CircuitsModel.motorFriction
        let r = 8.0   // default coil resistance
        let predicted = k * 9.0 / (b * r + k * k)

        let omega9 = steadySpeed(voltage: 9)
        XCTAssertEqual(omega9, predicted, accuracy: predicted * 0.05,
                       "steady speed matches ω = kV/(bR + k²)")
        XCTAssertGreaterThan(omega9, 1, "it actually spins")

        let omega18 = steadySpeed(voltage: 18)
        XCTAssertEqual(omega18 / omega9, 2, accuracy: 0.05, "speed ∝ voltage")
    }

    /// The rotor spins up from rest, not instantly — inertia is real.
    func testMotorSpinsUpGradually() {
        let model = CircuitsModel()
        model.clearBench()
        guard let battery = model.add(.battery, at: SIMD3(-0.3, 1.2, -0.9)),
              let motor = model.add(.motor, at: SIMD3(0.3, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        model.connectTerminals(.init(componentID: battery, end: 0), .init(componentID: motor, end: 0))
        model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: motor, end: 1))
        model.step(dt: 1.0 / 240.0)
        let early = model.components.first { $0.id == motor }!.motorSpeed
        for _ in 0..<2000 { model.step(dt: 1.0 / 240.0) }
        let late = model.components.first { $0.id == motor }!.motorSpeed
        XCTAssertGreaterThan(late, early * 5, "it keeps accelerating toward steady state")
    }

    /// A more forgiving snap radius: parts a few centimeters apart still
    /// auto-connect on release.
    func testAutoConnectReachesAcrossTheSnapDistance() {
        let model = CircuitsModel()
        model.clearBench()
        guard let a = model.add(.battery, at: SIMD3(0, 1.2, -0.9)),
              let b = model.add(.resistor, at: SIMD3(0.17 + 0.1, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        // The facing terminals are ~0.1 m apart — inside the 0.13 snap.
        let gap = simd_distance(
            model.components.first { $0.id == a }!.terminalPosition(1),
            model.components.first { $0.id == b }!.terminalPosition(0))
        XCTAssertLessThan(gap, CircuitsModel.snapDistance)
        model.autoConnect(id: b)
        XCTAssertEqual(model.wires.count, 1, "close-enough terminals magnetise")
    }

    // MARK: The meter

    /// A voltmeter goes ACROSS, and reads the potential difference.
    @MainActor
    func testVoltsModeReadsAcrossAComponent() throws {
        let model = CircuitsModel()
        let battery = try XCTUnwrap(model.components.first { $0.kind == .battery })
        model.meterMode = .voltsDC
        model.setProbe(.red, to: .init(componentID: battery.id, end: 0))
        model.setProbe(.black, to: .init(componentID: battery.id, end: 1))
        model.step(dt: 1.0 / 90)

        let reading = try XCTUnwrap(model.multimeterReading)
        XCTAssertFalse(reading.fault)
        XCTAssertTrue(reading.display.hasSuffix("V"), reading.display)
    }

    /// THE ONE THAT MATTERS. An ammeter goes IN SERIES: touching one
    /// across a component that is already carrying current puts a
    /// near-zero resistance in parallel with it, which is a short and in
    /// a real lab a blown fuse.
    ///
    /// A simulated meter that quietly printed the right current for that
    /// placement would be teaching one of the most common mistakes in an
    /// introductory lab. This asserts that it refuses instead.
    @MainActor
    func testAmpsModeRefusesToBePutAcrossALiveComponent() throws {
        let model = CircuitsModel()
        model.meterMode = .ampsDC
        // The opening bench is a live loop, so its bulb is carrying.
        let live = try XCTUnwrap(model.components.first {
            abs(model.readouts[$0.id]?.amps ?? 0) > 1e-6
        })
        model.setProbe(.red, to: .init(componentID: live.id, end: 0))
        model.setProbe(.black, to: .init(componentID: live.id, end: 1))

        let reading = try XCTUnwrap(model.multimeterReading)
        XCTAssertTrue(reading.fault, "an ammeter across a live part is a short")
        XCTAssertEqual(reading.display, "FUSE")
        XCTAssertTrue(reading.note.lowercased().contains("break the loop"),
                      "the meter should say WHY: \(reading.note)")
    }

    /// An ohmmeter drives its own current, so it cannot be trusted on a
    /// live circuit — and says so rather than printing a number.
    ///
    /// Built explicitly rather than leaning on the opening bench: what
    /// this asserts is a relationship between "the source is delivering
    /// power" and "the ohmmeter refuses", and a test that depended on
    /// the cold-open's contents would break the next time that scene is
    /// re-authored, for reasons having nothing to do with the meter.
    @MainActor
    func testOhmsModeRefusesOnALiveCircuit() throws {
        let model = CircuitsModel(restoreSaved: false)
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery))
        let resistor = try XCTUnwrap(model.add(.resistor))
        model.connectTerminals(.init(componentID: battery, end: 0),
                               .init(componentID: resistor, end: 0))
        model.connectTerminals(.init(componentID: battery, end: 1),
                               .init(componentID: resistor, end: 1))
        model.step(dt: 1.0 / 90)
        XCTAssertGreaterThan(abs(model.totalSourcePower), 1e-6,
                             "the fixture is not actually live")

        model.meterMode = .ohms
        model.setProbe(.red, to: .init(componentID: resistor, end: 0))
        model.setProbe(.black, to: .init(componentID: resistor, end: 1))

        let live = try XCTUnwrap(model.multimeterReading)
        XCTAssertTrue(live.fault)
        XCTAssertTrue(live.note.contains("live"), live.note)

        // Open the loop and the same probes give a number.
        for wire in model.wires { model.deleteWire(id: wire.id) }
        model.step(dt: 1.0 / 90)
        let dead = try XCTUnwrap(model.multimeterReading)
        XCTAssertFalse(dead.fault, "with the source off an ohmmeter should read")
        XCTAssertTrue(dead.display.contains("Ω"), dead.display)
    }

    /// A capacitor has no resistance to report — its opposition to
    /// current is a REACTANCE that depends on frequency, and calling
    /// that a resistance would be exactly the quiet simplification this
    /// app exists not to make.
    func testACapacitorHasNoResistanceToReport() {
        let capacitor = CircuitsModel.Component(
            id: UUID(), kind: .capacitor, position: .zero, value: 1e-4)
        XCTAssertNil(CircuitsModel.resistance(of: capacitor))
    }

    /// The display auto-ranges the way a real one does.
    ///
    /// AND AT ONE RESOLUTION IN EVERY BAND, which the hand-rolled
    /// prefixer did not: it showed one decimal in milli, three in the
    /// base unit and two in kilo. A 3½-digit bench meter shows the same
    /// digits wherever the range lands — that is what auto-ranging is
    /// for — so the assertions below now pin the resolution as well as
    /// the prefix.
    func testTheDisplayAutoRanges() {
        XCTAssertEqual(CircuitsModel.autoRange(0.0042, unit: "A"), "4.200 mA")
        XCTAssertEqual(CircuitsModel.autoRange(9.0, unit: "V"), "9.000 V")
        XCTAssertEqual(CircuitsModel.autoRange(4700, unit: "Ω"), "4.700 kΩ")
        // Zero is a reading, not an absence.
        XCTAssertEqual(CircuitsModel.autoRange(0, unit: "A"), "0.000 A")
    }

    /// A probe lands on the terminal it is nearest, and only if it is
    /// near one — a probe waved in mid-air measures nothing.
    @MainActor
    func testAProbeLatchesOntoTheNearestTerminalOrNothing() throws {
        let model = CircuitsModel()
        let component = try XCTUnwrap(model.components.first)
        let terminal = CircuitsModel.Terminal(componentID: component.id, end: 0)
        let position = component.terminalPosition(0)

        XCTAssertEqual(model.nearestTerminal(to: position, within: 0.035), terminal)
        XCTAssertNil(model.nearestTerminal(to: position + SIMD3(0, 5, 0),
                                           within: 0.035),
                     "a probe in mid-air should latch onto nothing")
    }

    // MARK: Zombie wires

    /// DELETING AN ARMED PART LEFT A WIRE THAT COULD NEVER BE REMOVED.
    ///
    /// Pinch a terminal (arms it), open that part's ring, tap Delete.
    /// `pendingTerminal` still named the destroyed part, so the next
    /// terminal tap anywhere appended a `Wire` whose `from` component
    /// does not exist. The renderer disables it, so it is invisible and
    /// un-pinchable; it permanently consumes one of the 36 budget slots;
    /// and `persistSoon` writes it to `UserDefaults`, so it comes back
    /// after a relaunch. There was no way to get rid of it.
    func testDeletingAnArmedPartCannotLeaveAWireBehind() throws {
        let model = CircuitsModel()
        // A fresh model arrives with a seeded circuit already wired, so
        // the bench is cleared first — otherwise the duplicate-wire
        // guard, not the fix, is what these tests measure.
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery))
        let bulb = try XCTUnwrap(model.add(.bulb))
        let before = model.wires.count

        // Arm a terminal on the battery, then delete the battery.
        model.tapTerminal(.init(componentID: battery, end: 0))
        model.removeComponent(id: battery)

        // The next tap must not build anything.
        model.tapTerminal(.init(componentID: bulb, end: 0))

        XCTAssertEqual(model.wires.count, before,
                       "a wire was created onto a component that no longer exists")
        for wire in model.wires {
            XCTAssertTrue(
                model.components.contains { $0.id == wire.from.componentID },
                "wire.from names a deleted component — invisible, un-pinchable, "
                + "and persisted to disk")
            XCTAssertTrue(model.components.contains { $0.id == wire.to.componentID })
        }
    }

    /// The second half of the same guard: even if an arming survives by
    /// some other route, the wire must still refuse to be built.
    func testAWireIsNeverBuiltOntoAMissingComponent() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery))
        let bulb = try XCTUnwrap(model.add(.bulb))

        let before = model.wires.count

        model.tapTerminal(.init(componentID: battery, end: 0))
        // A terminal on a component that was never added at all.
        model.tapTerminal(.init(componentID: UUID(), end: 1))
        XCTAssertEqual(model.wires.count, before,
                       "a wire was built onto a component that never existed")
    }

    /// The guard must refuse the impossible wire WITHOUT refusing the
    /// ordinary one — a fix that simply stopped wiring anything would
    /// pass the test above.
    ///
    /// Its own fixture, because the refusal path deliberately returns
    /// before `tapTerminal`'s `defer` and so leaves the first terminal
    /// still armed. That is reasonable behaviour — a tap on nothing
    /// should not throw away what you had selected — but it means the
    /// two cases cannot share a sequence.
    func testTheOrdinaryWireIsStillBuilt() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery))
        let bulb = try XCTUnwrap(model.add(.bulb))

        model.tapTerminal(.init(componentID: battery, end: 0))
        model.tapTerminal(.init(componentID: bulb, end: 1))
        XCTAssertEqual(model.wires.count, 1)
    }

    // MARK: The ammeter

    /// THE METER REFUSED THE ONE THING IT EXISTS TO REWARD.
    ///
    /// A⎓ reports a current only when the probes bracket a component
    /// whose loop is otherwise BROKEN — the meter completing the circuit
    /// is the meter being in series, and getting that right is the whole
    /// lesson. But the "is it already live" guard compared against a
    /// hand-typed `1e-9`, and `CircuitSolver.leakConductance` is `1e-9`:
    /// every open element leaks `volts × leakConductance`, so an open
    /// switch on a 9 V supply carries 9 nA and tripped it. The meter
    /// told you to break the loop you had just broken.
    func testTheAmmeterAcceptsALoopTheUserHasBroken() throws {
        let model = CircuitsModel()
        model.clearBench()

        // Battery — switch — bulb, in a ring, with the switch OPEN.
        let battery = try XCTUnwrap(model.add(.battery))
        let switcher = try XCTUnwrap(model.add(.switcher))
        let bulb = try XCTUnwrap(model.add(.bulb))
        model.tapTerminal(.init(componentID: battery, end: 0))
        model.tapTerminal(.init(componentID: switcher, end: 0))
        model.tapTerminal(.init(componentID: switcher, end: 1))
        model.tapTerminal(.init(componentID: bulb, end: 0))
        model.tapTerminal(.init(componentID: bulb, end: 1))
        model.tapTerminal(.init(componentID: battery, end: 1))
        if model.components.first(where: { $0.id == switcher })?.isClosed == true {
            model.toggleSwitch(id: switcher)
        }
        model.step(dt: 1.0 / 60)

        model.multimeterArmed = true
        model.meterMode = .ampsDC
        model.setProbe(.red, to: .init(componentID: switcher, end: 0))
        model.setProbe(.black, to: .init(componentID: switcher, end: 1))
        model.step(dt: 1.0 / 60)

        let reading = try XCTUnwrap(model.multimeterReading)
        XCTAssertNotEqual(reading.display, "FUSE",
                          "the meter refused a correctly broken loop")

        // THE ASSERTION THIS TEST ASKED FOR. It used to demand
        // "0.000 A" and say, in its own failure message, that a real
        // current here would mean the meter had been stamped into the
        // network and the test should be replaced. It has, and this is
        // the replacement.
        //
        // NO MAGIC NUMBER: the meter and the bulb are in series, so the
        // meter must read the loop current, which is the bulb's own.
        // Comparing the two is a stronger claim than any literal — it
        // would fail if the shunt were stamped in the wrong place, or
        // sized so badly it changed the loop it was measuring.
        let meter = try XCTUnwrap(model.meterCurrent)
        let loop = try XCTUnwrap(model.readouts[bulb]?.amps)
        XCTAssertGreaterThan(abs(meter), 1e-3,
                             "the meter still reads nothing through a loop it "
                             + "has itself completed")
        XCTAssertEqual(abs(meter), abs(loop), accuracy: abs(loop) * 0.02, """
            the meter reads \(meter) A while the bulb it is in series with \
            carries \(loop) A — an ammeter in series must read the loop \
            current.
            """)
        XCTAssertNotEqual(reading.display, "0.000 A")
    }

    /// THE SHUNT MUST NOT DISTURB WHAT IT MEASURES, which is the whole
    /// design requirement for an ammeter and the reason it is 1 mΩ
    /// rather than a perfect conductor.
    ///
    /// Closing the switch gives the same loop WITHOUT the meter in it,
    /// so the two currents should agree to well under a percent. A shunt
    /// sized carelessly would show up here as a loop that runs faster
    /// when you measure it.
    func testTheAmmeterBarelyDisturbsTheLoopItMeasures() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery))
        let switcher = try XCTUnwrap(model.add(.switcher))
        let bulb = try XCTUnwrap(model.add(.bulb))
        model.tapTerminal(.init(componentID: battery, end: 0))
        model.tapTerminal(.init(componentID: switcher, end: 0))
        model.tapTerminal(.init(componentID: switcher, end: 1))
        model.tapTerminal(.init(componentID: bulb, end: 0))
        model.tapTerminal(.init(componentID: bulb, end: 1))
        model.tapTerminal(.init(componentID: battery, end: 1))

        // Closed switch, no meter: the reference loop.
        if model.components.first(where: { $0.id == switcher })?.isClosed == false {
            model.toggleSwitch(id: switcher)
        }
        model.step(dt: 1.0 / 60)
        let undisturbed = try XCTUnwrap(model.readouts[bulb]?.amps)

        // Open switch, meter bridging the gap: the same loop, through
        // the shunt.
        model.toggleSwitch(id: switcher)
        model.multimeterArmed = true
        model.meterMode = .ampsDC
        model.setProbe(.red, to: .init(componentID: switcher, end: 0))
        model.setProbe(.black, to: .init(componentID: switcher, end: 1))
        model.step(dt: 1.0 / 60)
        let measured = try XCTUnwrap(model.meterCurrent)

        XCTAssertEqual(abs(measured), abs(undisturbed),
                       accuracy: abs(undisturbed) * 0.01, """
            measuring the loop changed it: \(undisturbed) A closed, \
            \(measured) A through the meter. The shunt is too large.
            """)
    }

    /// IN V⎓ THE METER IS NOT AN ELEMENT. A voltmeter's shunt across a
    /// live part would short it — so the stamp is gated on the mode, and
    /// this is what would catch that gate being dropped.
    func testTheMeterIsNotStampedInVoltageMode() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery))
        let bulb = try XCTUnwrap(model.add(.bulb))
        model.tapTerminal(.init(componentID: battery, end: 0))
        model.tapTerminal(.init(componentID: bulb, end: 0))
        model.tapTerminal(.init(componentID: bulb, end: 1))
        model.tapTerminal(.init(componentID: battery, end: 1))
        model.step(dt: 1.0 / 60)
        let before = try XCTUnwrap(model.readouts[bulb]?.amps)

        model.multimeterArmed = true
        model.meterMode = .voltsDC
        model.setProbe(.red, to: .init(componentID: bulb, end: 0))
        model.setProbe(.black, to: .init(componentID: bulb, end: 1))
        model.step(dt: 1.0 / 60)

        XCTAssertNil(model.meterCurrent,
                     "a voltmeter was stamped into the network as an element")
        let after = try XCTUnwrap(model.readouts[bulb]?.amps)
        XCTAssertEqual(after, before, accuracy: abs(before) * 1e-6,
                       "probing a bulb in V⎓ changed the current through it")
    }

    /// …and it must still refuse a LIVE one, or the fix has simply
    /// disabled the guard.
    func testTheAmmeterStillRefusesALiveComponent() throws {
        let model = CircuitsModel()
        model.clearBench()

        let battery = try XCTUnwrap(model.add(.battery))
        let bulb = try XCTUnwrap(model.add(.bulb))
        model.tapTerminal(.init(componentID: battery, end: 0))
        model.tapTerminal(.init(componentID: bulb, end: 0))
        model.tapTerminal(.init(componentID: bulb, end: 1))
        model.tapTerminal(.init(componentID: battery, end: 1))
        model.step(dt: 1.0 / 60)

        model.multimeterArmed = true
        model.meterMode = .ampsDC
        model.setProbe(.red, to: .init(componentID: bulb, end: 0))
        model.setProbe(.black, to: .init(componentID: bulb, end: 1))
        model.step(dt: 1.0 / 60)

        let reading = try XCTUnwrap(model.multimeterReading)
        XCTAssertEqual(reading.display, "FUSE",
                       "probes across a live bulb would short it; the meter has "
                       + "to say so rather than print a number")
    }

    // MARK: The capacitor's own number

    /// THE RAIL SAID "0 mF" WHILE THE PART SAID "100 µF".
    ///
    /// `formatValue` printed `%.0f` of `value × 1000`, and a capacitor on
    /// this bench is measured in MICROfarads: 100 µF is 1e-4 F, times
    /// 1000 is 0.1, rounded to "0". The whole usable range of the
    /// component collapsed to the same string, so the readout under the
    /// rail you were dragging never moved and contradicted the bench
    /// label on the part itself.
    func testTheCapacitorRailAgreesWithTheBenchLabel() {
        // Every value the rail can actually reach must print something
        // that is not "0" — a readout that cannot change is not one.
        let range = CircuitsModel.valueRange(for: .capacitor)
        var seen = Set<String>()
        for step in 0...20 {
            let value = range.lowerBound
                + (range.upperBound - range.lowerBound) * Double(step) / 20
            let text = CircuitsModel.formatValue(value, for: .capacitor)
            XCTAssertFalse(text.hasPrefix("0 "),
                           "\(value) F printed as \(text) — the whole "
                           + "microfarad range used to round to `0 mF`")
            seen.insert(text)
        }
        XCTAssertGreaterThan(seen.count, 5,
                             "the readout barely changes across the rail's "
                             + "entire range: \(seen.sorted())")

        // And the headline case from the audit, exactly.
        XCTAssertEqual(CircuitsModel.formatValue(100e-6, for: .capacitor),
                       "100 µF")
    }
}
