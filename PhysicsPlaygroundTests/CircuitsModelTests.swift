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

        // The reading is a formatted display: the meter has modes and each
        // answers a different question. The drop itself is still the solver's.
        model.meterMode = .voltsDC
        model.setProbe(.red, to: rA)
        model.setProbe(.black, to: rB)
        let reading = try XCTUnwrap(model.multimeterReading)
        XCTAssertFalse(reading.fault)
        XCTAssertEqual(reading.display,
                       CircuitsModel.autoRange(model.readouts[resistor]!.volts,
                                               unit: "V"),
                       "the meter reads the same drop the solver computes")

        // Probes on the two ends of one wire: continuity.
        model.meterMode = .continuity
        model.setProbe(.red, to: bPlus)
        model.setProbe(.black, to: rA)
        XCTAssertTrue(try XCTUnwrap(model.multimeterReading).beeping,
                      "wired-together terminals show continuity")
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
    /// ghost wires promise is exactly what the release creates.
    func testPendingJoinPreviewMatchesRelease() {
        let model = CircuitsModel()
        model.clearBench()
        guard let battery = model.add(.battery, at: SIMD3(0, 1.2, -0.9)),
              let bulb = model.add(.bulb, at: SIMD3(0.2, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        // battery t1 at x = 0.085; bulb t0 at 0.115 — a 3 cm gap,
        // inside `leadReach`.
        let pairs = model.pendingJoins(for: bulb)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].from, CircuitsModel.Terminal(componentID: bulb, end: 0))
        XCTAssertEqual(pairs[0].to, CircuitsModel.Terminal(componentID: battery, end: 1))

        model.release(id: bulb)
        XCTAssertEqual(model.wires.count, 1)
        // The preview clears for a stronger reason than it used to:
        // not "there is already a wire between exactly these two", but
        // "these two are already one electrical point".
        XCTAssertTrue(model.pendingJoins(for: bulb).isEmpty,
                      "once wired, the preview clears")
        XCTAssertTrue(model.areConnected(pairs[0].from, pairs[0].to))
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

        model.connectTerminals(.init(componentID: battery.id, end: 1), .init(componentID: toggle.id, end: 0))
        model.connectTerminals(.init(componentID: toggle.id, end: 1), .init(componentID: bulb.id, end: 0))
        model.connectTerminals(.init(componentID: bulb.id, end: 1), .init(componentID: battery.id, end: 0))

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
        XCTAssertNil(model.leadPull)
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

    /// Shorting a battery to itself trips the overload flag; the healthy
    /// starter loop does not.
    func testShortCircuitTripsTheOverloadWarning() {
        let model = CircuitsModel()
        model.clearBench()
        model.add(.battery)
        let battery = model.components[0]
        model.connectTerminals(.init(componentID: battery.id, end: 1),
                               .init(componentID: battery.id, end: 0))
        model.step(dt: 1.0 / 90.0)
        XCTAssertTrue(model.hasOverloadedBattery,
                      "9 V through milliohms is a dead short (~150 A)")

        model.reset()
        XCTAssertFalse(model.hasOverloadedBattery,
                       "the starter loop draws well under an amp")
    }

    /// Removing a component takes its wires with it.
    func testRemovingComponentRemovesItsWires() {
        let model = CircuitsModel()
        let bulb = model.components.first { $0.kind == .bulb }!
        model.removeComponent(id: bulb.id)
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
        model.connectTerminals(.init(componentID: battery.id, end: 0), .init(componentID: resistor.id, end: 0))
        model.connectTerminals(.init(componentID: resistor.id, end: 1), .init(componentID: capacitor.id, end: 0))
        model.connectTerminals(.init(componentID: capacitor.id, end: 1), .init(componentID: battery.id, end: 1))

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
        assertInTheRoom(position)
        XCTAssertGreaterThanOrEqual(position.y, CircuitsModel.floorMargin - 1e-9)

        // A drop from the far side of the building lands in the room too.
        model.clearBench()
        model.add(.bulb, at: CircuitsModel.buildCenter + SIMD3(100, 0, 0))
        assertInTheRoom(model.components[0].position)
    }

    // MARK: The hand meets no wall

    /// A part is born where your hand is: the shelf stands outside the
    /// bench box by the station margin, by construction, so a clamp on
    /// `add` jumped every new part inward the instant it existed.
    func testAPartIsBornAtTheHandAndNotDraggedOntoTheBench() {
        let model = CircuitsModel()
        model.clearBench()
        let rack = CircuitsPartsLayout.rightSlot(index: 0)
        let hand = SIMD3<Double>(rack)

        guard let id = model.add(.resistor, at: hand) else {
            return XCTFail("bench refused the part")
        }
        let born = model.components.first { $0.id == id }!.position

        XCTAssertEqual(simd_distance(born, hand), 0, accuracy: 1e-9, """
            the part was born \(simd_distance(born, hand)) m from the hand \
            that pulled it — it jumped out of your grip on the first frame.
            """)
        XCTAssertGreaterThan(
            abs(born.x), CircuitsModel.buildHalfExtents.x,
            "the rack is meant to stand outside the bench box; if this fails "
            + "the test is no longer exercising the case that was broken")
    }

    /// …and the hand goes on being obeyed for the whole drag, which is the
    /// same rule `FieldClampTests` holds for Electric Fields.
    func testADragPastTheBenchIsObeyed() {
        let model = CircuitsModel()
        model.clearBench()
        guard let id = model.add(.resistor, at: CircuitsModel.buildCenter) else {
            return XCTFail("bench refused the part")
        }
        let reached = CircuitsModel.buildCenter + SIMD3(1.4, 0.3, 0.2)
        model.move(id: id, to: reached)

        XCTAssertEqual(
            simd_distance(model.components[0].position, reached), 0,
            accuracy: 1e-9,
            "a hand carrying a part off the bench met an invisible wall")
    }

    /// The safety box is still there, and it is what a runaway meets.
    func testTheRoomScaleSafetyBoxStillCatchesARunaway() {
        let model = CircuitsModel()
        model.clearBench()
        guard let id = model.add(.resistor, at: CircuitsModel.buildCenter) else {
            return XCTFail("bench refused the part")
        }
        model.move(id: id, to: CircuitsModel.buildCenter + SIMD3(40, 0, 0))
        assertInTheRoom(model.components[0].position)
    }

    /// A bench saved before the bench narrowed comes back untouched: the
    /// restore path transforms kinds, never positions. A position clamp in
    /// `migrated` would move everybody's saved circuits.
    func testABenchSavedAtTheOldWidthRestoresWhereItWasSaved() {
        // This one writes the real save key, because the restore path is
        // what is under test. Put back whatever was there.
        let previous = UserDefaults.standard.data(forKey: CircuitsModel.saveKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: CircuitsModel.saveKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CircuitsModel.saveKey)
            }
        }

        let model = CircuitsModel()
        model.clearBench()
        // 0.70 — hard against the wall as it stood before the narrowing.
        let atTheOldWall = SIMD3<Double>(0.70, 1.25, -0.9)
        guard let id = model.add(.battery, at: atTheOldWall) else {
            return XCTFail("bench refused the part")
        }
        XCTAssertEqual(simd_distance(model.components[0].position, atTheOldWall),
                       0, accuracy: 1e-9)
        model.persistNow()

        let reopened = CircuitsModel(restoreSaved: true)
        let restored = reopened.components.first { $0.id == id }
        XCTAssertNotNil(restored, "the saved bench did not come back at all")
        XCTAssertEqual(
            simd_distance(restored?.position ?? .zero, atTheOldWall), 0,
            accuracy: 1e-9, """
            a part saved at the old bench wall came back at \
            \(restored?.position ?? .zero) — something is clamping on restore, \
            and it has just moved a saved circuit nobody asked it to move.
            """)
    }

    /// Room-scale, not bench-scale: what the safety box promises.
    private func assertInTheRoom(
        _ position: SIMD3<Double>,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let low = CircuitsModel.buildCenter - CircuitsModel.safetyHalfExtents
        let high = CircuitsModel.buildCenter + CircuitsModel.safetyHalfExtents
        for axis in 0..<3 {
            XCTAssertGreaterThanOrEqual(
                position[axis], low[axis] - 1e-9,
                "a part left the room on axis \(axis)", file: file, line: line)
            XCTAssertLessThanOrEqual(
                position[axis], high[axis] + 1e-9,
                "a part left the room on axis \(axis)", file: file, line: line)
        }
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
        model.multimeterArmed = true

        model.reset()

        XCTAssertEqual(model.components.count, 3)
        XCTAssertEqual(model.wires.count, 3)
        XCTAssertTrue(model.showElectronFlow)
        XCTAssertFalse(model.isPaused)
        XCTAssertNil(model.leadPull)
        XCTAssertGreaterThan(model.totalSourcePower, 3, "the loop comes back lit")

        // Every lamp standing beside this bench, back where it started.
        XCTAssertFalse(model.trueSpeedMode)
        XCTAssertFalse(model.showVoltageHeights)
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
            + SIMD3(0.03 + CircuitsModel.terminalOffset, 0, 0)
        model.add(.bulb, at: near)
        let bulb = model.components[1]

        model.release(id: bulb.id)
        XCTAssertEqual(model.wires.count, 1, "the close pair self-connects")
        // And they are now coincident, not merely wired: the release
        // aligns as well as connecting.
        XCTAssertEqual(
            simd_distance(model.components.first { $0.id == bulb.id }!.terminalPosition(0),
                          model.components[0].terminalPosition(1)),
            0, accuracy: 1e-12)
        XCTAssertFalse(model.wires.contains {
            $0.from.end == 1 && $0.to.end == 1
        }, "only the near terminals joined")

        // A part released far away connects nothing.
        model.add(.resistor, at: CircuitsModel.buildCenter + SIMD3(0, 0.8, 0))
        model.release(id: model.components[2].id)
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
        model.connectTerminals(.init(componentID: battery.id, end: 1), .init(componentID: resistor.id, end: 0))
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

    /// Whole-bench changes save like every other edit (2026-10-14). A
    /// preset and a cleared bench never reached `persistSoon`, so a relaunch
    /// reopened the bench the wearer had just replaced. An empty save opens
    /// as the starter loop, which is what a cleared bench should come back as.
    func testPresetsAndClearingAreSaved() {
        UserDefaults.standard.removeObject(forKey: CircuitsModel.saveKey)
        defer { UserDefaults.standard.removeObject(forKey: CircuitsModel.saveKey) }

        let model = CircuitsModel()
        model.loadPreset(.parallel)
        let presetSaved = expectation(description: "the preset is saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { presetSaved.fulfill() }
        wait(for: [presetSaved], timeout: 3)
        let afterPreset = CircuitsModel(restoreSaved: true)
        XCTAssertEqual(afterPreset.components.filter { $0.kind == .bulb }.count, 2,
                       "a relaunch after a preset reopened some other bench")

        // Build something, save it, then clear the way the plate does.
        model.add(.resistor)
        model.persistNow()
        model.clearBench()
        model.commitBench()
        let clearSaved = expectation(description: "the clear is saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { clearSaved.fulfill() }
        wait(for: [clearSaved], timeout: 3)
        let afterClear = CircuitsModel(restoreSaved: true)
        XCTAssertFalse(afterClear.components.contains { $0.kind == .resistor },
                       "a relaunch after Clear bench brought the cleared bench back")
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
        model.connectTerminals(.init(componentID: battery.id, end: 1), .init(componentID: bulb.id, end: 0))
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

    /// A wired part carried any distance keeps its wire: a connection is
    /// undone by pulling the wire off its terminal, never by distance.
    func testCarryingAWiredPartFarKeepsItsWire() {
        let model = CircuitsModel()
        model.clearBench()
        guard let a = model.add(.battery, at: SIMD3(0, 1.2, -0.9)),
              let b = model.add(.resistor, at: SIMD3(0.17, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        model.connectTerminals(.init(componentID: a, end: 1), .init(componentID: b, end: 0))
        XCTAssertEqual(model.wires.count, 1)

        for x in stride(from: 0.3, through: 1.2, by: 0.15) {
            model.drag(id: b, toward: SIMD3(x, 1.2, -0.9))
            XCTAssertEqual(model.wires.count, 1, "the wire let go at \(x) m")
        }
        XCTAssertGreaterThan(model.wireLength(model.wires[0]), 0.5,
                             "the wire should be stretched across the room, still joined")
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

    /// Parts released a few centimetres apart still join — the reach
    /// is forgiving, but it is one number now (`leadReach`, 0.06)
    /// rather than a release radius of 0.13 and a drag radius of 0.09
    /// that disagreed about the same fact.
    func testAReleaseJoinsAcrossTheLeadReach() {
        let model = CircuitsModel()
        model.clearBench()
        guard let a = model.add(.battery, at: SIMD3(0, 1.2, -0.9)),
              let b = model.add(.resistor, at: SIMD3(0.17 + 0.04, 1.2, -0.9)) else {
            return XCTFail("bench refused parts")
        }
        let gap = simd_distance(
            model.components.first { $0.id == a }!.terminalPosition(1),
            model.components.first { $0.id == b }!.terminalPosition(0))
        XCTAssertLessThan(gap, CircuitsModel.leadReach)
        model.release(id: b)
        XCTAssertEqual(model.wires.count, 1, "close-enough terminals magnetise")
    }

    // MARK: The meter

    /// A voltmeter goes across, and reads the potential difference.
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

    /// An ammeter goes in series: touching one across a component already
    /// carrying current is a short. The meter refuses rather than teach the
    /// classic mistake.
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
    /// live circuit and says so. Built explicitly rather than leaning on
    /// the opening bench.
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

    /// A capacitor has no resistance to report — its opposition is a
    /// reactance that depends on frequency.
    func testACapacitorHasNoResistanceToReport() {
        let capacitor = CircuitsModel.Component(
            id: UUID(), kind: .capacitor, position: .zero, value: 1e-4)
        XCTAssertNil(CircuitsModel.resistance(of: capacitor))
    }

    /// The display auto-ranges the way a real one does, at one resolution
    /// in every band.
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

    /// Deleting an armed part must not leave a wire behind: a half-made
    /// wire naming the destroyed part once appended an invisible,
    /// un-pinchable, persisted `Wire` on the next tap.
    func testDeletingAnArmedPartCannotLeaveAWireBehind() throws {
        let model = CircuitsModel()
        // A fresh model arrives with a seeded circuit already wired, so the
        // bench is cleared first.
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery))
        let bulb = try XCTUnwrap(model.add(.bulb))
        let before = model.wires.count

        // Start a wire from the battery, then delete the battery.
        model.beginLeadPull(from: .init(componentID: battery, end: 0),
                            hand: model.components.first { $0.id == battery }!
                                .terminalPosition(0))
        model.removeComponent(id: battery)

        // The release must not build anything.
        model.updateLeadPull(hand: model.components.first { $0.id == bulb }!
                                .terminalPosition(0))
        model.endLeadPull()

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
        _ = try XCTUnwrap(model.add(.bulb))

        let before = model.wires.count

        model.voiceOverWire(.init(componentID: battery, end: 0))
        // A terminal on a component that was never added at all.
        model.voiceOverWire(.init(componentID: UUID(), end: 1))
        XCTAssertEqual(model.wires.count, before,
                       "a wire was built onto a component that never existed")
    }

    /// The guard must refuse the impossible wire without refusing the
    /// ordinary one. Its own fixture: the refusal above consumes the arming.
    func testTheOrdinaryWireIsStillBuilt() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery))
        let bulb = try XCTUnwrap(model.add(.bulb))

        model.voiceOverWire(.init(componentID: battery, end: 0))
        model.voiceOverWire(.init(componentID: bulb, end: 1))
        XCTAssertEqual(model.wires.count, 1)
    }

    // MARK: The ammeter

    /// A⎓ reports a current only when the probes bracket a component whose
    /// loop is otherwise broken. The "is it already live" guard once
    /// compared against a hand-typed `1e-9`, which is the solver's leak
    /// conductance, so an open switch on 9 V tripped it.
    func testTheAmmeterAcceptsALoopTheUserHasBroken() throws {
        let model = CircuitsModel()
        model.clearBench()

        // Battery — switch — bulb, in a ring, with the switch open.
        let battery = try XCTUnwrap(model.add(.battery))
        let switcher = try XCTUnwrap(model.add(.switcher))
        let bulb = try XCTUnwrap(model.add(.bulb))
        model.connectTerminals(.init(componentID: battery, end: 0), .init(componentID: switcher, end: 0))
        model.connectTerminals(.init(componentID: switcher, end: 1), .init(componentID: bulb, end: 0))
        model.connectTerminals(.init(componentID: bulb, end: 1), .init(componentID: battery, end: 1))
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

        // The meter and the bulb are in series, so the meter must read the
        // bulb's own current — a stronger claim than any literal.
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

    /// The shunt must not disturb what it measures: closing the switch
    /// gives the same loop without the meter, and the two currents agree to
    /// well under a percent.
    func testTheAmmeterBarelyDisturbsTheLoopItMeasures() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery))
        let switcher = try XCTUnwrap(model.add(.switcher))
        let bulb = try XCTUnwrap(model.add(.bulb))
        model.connectTerminals(.init(componentID: battery, end: 0), .init(componentID: switcher, end: 0))
        model.connectTerminals(.init(componentID: switcher, end: 1), .init(componentID: bulb, end: 0))
        model.connectTerminals(.init(componentID: bulb, end: 1), .init(componentID: battery, end: 1))

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

    /// In V⎓ the meter is not an element. A voltmeter's shunt across a
    /// live part would short it — so the stamp is gated on the mode, and
    /// this is what would catch that gate being dropped.
    func testTheMeterIsNotStampedInVoltageMode() throws {
        let model = CircuitsModel()
        model.clearBench()
        let battery = try XCTUnwrap(model.add(.battery))
        let bulb = try XCTUnwrap(model.add(.bulb))
        model.connectTerminals(.init(componentID: battery, end: 0), .init(componentID: bulb, end: 0))
        model.connectTerminals(.init(componentID: bulb, end: 1), .init(componentID: battery, end: 1))
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

    /// …and it must still refuse a live one, or the fix has simply
    /// disabled the guard.
    func testTheAmmeterStillRefusesALiveComponent() throws {
        let model = CircuitsModel()
        model.clearBench()

        let battery = try XCTUnwrap(model.add(.battery))
        let bulb = try XCTUnwrap(model.add(.bulb))
        model.connectTerminals(.init(componentID: battery, end: 0), .init(componentID: bulb, end: 0))
        model.connectTerminals(.init(componentID: bulb, end: 1), .init(componentID: battery, end: 1))
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

    /// The rail and the bench label must agree: `formatValue` once printed
    /// `%.0f` of `value × 1000`, collapsing the whole microfarad range to
    /// "0 mF".
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


    // MARK: The coil, heat, and a tunable AC source

    /// A closed loop of the given kinds, each part wired end 1 → next
    /// part's end 0, the last back to the first. `reverseFirst` wires the
    /// first part the other way round — which is what reversing a battery
    /// is.
    private func loop(_ kinds: [CircuitsModel.ComponentKind],
                      reverseFirst: Bool = false) -> (CircuitsModel, [UUID]) {
        let model = CircuitsModel()
        model.clearBench()
        var ids: [UUID] = []
        for (index, kind) in kinds.enumerated() {
            ids.append(model.add(kind, at: SIMD3(Double(index) * 0.3 - 0.45, 1.3, -0.85))!)
        }
        for index in ids.indices {
            let next = ids[(index + 1) % ids.count]
            let fromEnd = (index == 0 && reverseFirst) ? 0 : 1
            let toEnd = (next == ids[0] && reverseFirst) ? 1 : 0
            _ = model.connectTerminals(.init(componentID: ids[index], end: fromEnd),
                                       .init(componentID: next, end: toEnd))
        }
        return (model, ids)
    }

    private func run(_ model: CircuitsModel, seconds: Double, dt: Double = 1.0 / 90.0) {
        for _ in 0..<Int((seconds / dt).rounded()) { model.step(dt: dt) }
    }

    /// The inductance implies the coil: 0.5 H of air-core windings of the
    /// drawn size is about five thousand turns.
    func testTheInductanceImpliesTheTurnCount() {
        let turns = CircuitsModel.inductorTurns(henries: 0.5)
        XCTAssertEqual(turns, 4960, accuracy: 60)
        // And it recovers the inductance it was derived from.
        let area = CurrentLoop.area(radius: CircuitsModel.inductorCoilRadius)
        let henries = CurrentLoop.mu0 * Double(turns * turns) * area / CircuitsModel.inductorCoilLength
        XCTAssertEqual(henries, 0.5, accuracy: 0.5 * 0.03)
    }

    /// With current in the coil the bench's field on the coil's axis is
    /// the loop's far field — the point dipole and the exact axial
    /// formula agree to a few percent thirteen radii out — and it flips
    /// when the current does.
    func testTheCoilIsAMagnetWhoseFieldIsTheLoopsFarField() throws {
        let bare = CircuitsModel()
        bare.clearBench()
        XCTAssertTrue(bare.coilMagnets.isEmpty, "no coil, no magnet")

        let (model, ids) = loop([.battery, .resistor, .inductor])
        run(model, seconds: 1.0)
        let coil = try XCTUnwrap(model.components.first { $0.id == ids[2] })
        XCTAssertGreaterThan(abs(coil.inductorCurrent), 1e-3, "the loop carries current")
        XCTAssertEqual(model.coilMagnets.count, 1)

        let turns = CircuitsModel.inductorTurns(henries: coil.value)
        let distance = 0.25
        let probe = coil.position + coil.axis * distance
        let expected = CurrentLoop.axialField(
            turns: turns, current: coil.inductorCurrent,
            radius: CircuitsModel.inductorCoilRadius, distance: distance)
        let along = simd_dot(model.magneticField(at: probe), coil.axis)
        XCTAssertGreaterThan(abs(expected), 1e-7, "a field worth drawing")
        XCTAssertEqual(along, expected, accuracy: abs(expected) * 0.05)

        // Reverse the battery — the same loop wired the other way round:
        // the current, the moment and the field flip.
        let (reversed, reversedIDs) = loop([.battery, .resistor, .inductor], reverseFirst: true)
        run(reversed, seconds: 1.0)
        let reversedCoil = try XCTUnwrap(reversed.components.first { $0.id == reversedIDs[2] })
        XCTAssertLessThan(reversedCoil.inductorCurrent * coil.inductorCurrent, 0,
                          "the current runs the other way")
        let flipped = simd_dot(reversed.magneticField(at: probe), reversedCoil.axis)
        XCTAssertLessThan(flipped * along, 0, "reversing the battery reverses the coil's field")
    }

    /// 9 V across 10 Ω is eight watts into a two-watt part: it scorches
    /// within a second; 470 Ω never does; Replace makes it whole.
    func testAResistorPastItsRatingScorchesAndOneWithinItNever() throws {
        let (hot, hotIDs) = loop([.battery, .resistor])
        hot.setComponentValue(id: hotIDs[1], 10)
        run(hot, seconds: 0.2)
        XCTAssertGreaterThan(hot.dissipation(id: hotIDs[1]), 2, "well past the rating")
        XCTAssertFalse(try XCTUnwrap(hot.components.first { $0.id == hotIDs[1] }).failed,
                       "a fifth of a second is a spike, and a spike is forgiven")
        run(hot, seconds: 1.5)
        let scorched = try XCTUnwrap(hot.components.first { $0.id == hotIDs[1] })
        XCTAssertTrue(scorched.failed, "sustained overload scorches it")
        XCTAssertEqual(hot.dissipation(id: hotIDs[1]), 0, accuracy: 1e-9,
                       "a scorched resistor is an open circuit")
        hot.replaceFailed(id: hotIDs[1])
        let replaced = try XCTUnwrap(hot.components.first { $0.id == hotIDs[1] })
        XCTAssertFalse(replaced.failed)
        XCTAssertEqual(replaced.thermalEnergy, 0)

        let (cool, coolIDs) = loop([.battery, .resistor])
        run(cool, seconds: 5.0)
        XCTAssertFalse(try XCTUnwrap(cool.components.first { $0.id == coolIDs[1] }).failed,
                       "470 Ω dissipates a sixth of a watt and never warms")
    }

    /// The source runs at its own frequency: a quarter period after the
    /// start it is at its peak, and half a period later at its trough.
    func testTheACSourceRunsAtItsOwnFrequency() throws {
        let (model, ids) = loop([.acSource, .bulb])
        model.setACFrequency(id: ids[0], 2.5)
        XCTAssertEqual(try XCTUnwrap(model.components.first { $0.id == ids[0] }).acFrequency, 2.5)
        let dt = 0.01
        run(model, seconds: 0.1, dt: dt)           // t = 0.1 s = quarter period
        let peak = model.readouts[ids[0]]?.volts ?? 0
        XCTAssertEqual(abs(peak), 6, accuracy: 6 * 0.05)
        run(model, seconds: 0.2, dt: dt)           // t = 0.3 s = three quarters
        let trough = model.readouts[ids[0]]?.volts ?? 0
        XCTAssertEqual(abs(trough), 6, accuracy: 6 * 0.05)
        XCTAssertLessThan(peak * trough, 0, "opposite halves of the cycle")
        // The rail clamps to its range.
        model.setACFrequency(id: ids[0], 40)
        XCTAssertEqual(try XCTUnwrap(model.components.first { $0.id == ids[0] }).acFrequency,
                       CircuitsModel.acFrequencyRange.upperBound)
    }
}
