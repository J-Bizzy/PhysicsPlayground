//
//  CircuitsNetTests.swift
//  PhysicsPlaygroundTests
//
//  The bench's connectivity, cached. Three claims are under test here
//  and each one used to be an assumption nothing checked:
//
//  1. SLOT PARITY. `elements[i]` is `components[i]`, which is how
//     every readout finds its own current. Before the net cache this
//     was true by the accident of two loops iterating the same array
//     in the same order, and it was READ BACK at two places a hundred
//     lines apart. It is a named function now, and asserted here.
//
//  2. GEOMETRY IS NOT TOPOLOGY. Moving a part, dialling a value and
//     opening a switch must not rebuild the partition — a switch is
//     an ELEMENT between two nets, never a break in one. If the cache
//     rebuilds on a move it is not a cache, it is a rename.
//
//  3. THE SAME-NET RULE. Two terminals already at one potential
//     cannot be wired together again. The old rule rejected a
//     duplicate PAIR and missed a duplicate PATH, which is what
//     `fanOut` was quietly dividing a branch current across.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsNetTests: XCTestCase {

    /// Battery → switch → bulb → battery, wired the long way round.
    @discardableResult
    private func buildLoop(on model: CircuitsModel)
    -> (battery: UUID, toggle: UUID, bulb: UUID) {
        model.clearBench()
        let battery = model.add(.battery)!
        let toggle = model.add(.switcher)!
        let bulb = model.add(.bulb)!
        model.connectTerminals(.init(componentID: battery, end: 1),
                               .init(componentID: toggle, end: 0))
        model.connectTerminals(.init(componentID: toggle, end: 1),
                               .init(componentID: bulb, end: 0))
        model.connectTerminals(.init(componentID: bulb, end: 1),
                               .init(componentID: battery, end: 0))
        model.step(dt: 1.0 / 90.0)
        return (battery, toggle, bulb)
    }

    // MARK: 1 — the index-parity invariant

    /// `slot = 2 * componentIndex + end`, which is what keeps the
    /// stamped element array parallel with `components` without a
    /// lookup table between them. Asserted rather than assumed.
    func testSlotIsTwiceTheComponentIndexPlusEnd() {
        for index in 0..<8 {
            XCTAssertEqual(CircuitsModel.NetTopology.slot(componentIndex: index, end: 0), 2 * index)
            XCTAssertEqual(CircuitsModel.NetTopology.slot(componentIndex: index, end: 1), 2 * index + 1)
        }
        // No two (component, end) pairs may share a slot.
        var seen = Set<Int>()
        for index in 0..<8 {
            for end in 0...1 {
                XCTAssertTrue(seen.insert(
                    CircuitsModel.NetTopology.slot(componentIndex: index, end: end)).inserted,
                    "Slot collision at component \(index), end \(end).")
            }
        }
    }

    /// Every component's readout must be its own — the parity
    /// invariant observed from the far end, through the solve.
    func testEachComponentGetsItsOwnReadout() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery)!
        // Two very different resistors in series: if the readouts were
        // off by one, the currents would still match but the POWERS
        // could not.
        let small = model.add(.resistor)!
        let large = model.add(.resistor)!
        model.setComponentValue(id: small, 10)
        model.setComponentValue(id: large, 1000)
        model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: small, end: 0))
        model.connectTerminals(.init(componentID: small, end: 1), .init(componentID: large, end: 0))
        model.connectTerminals(.init(componentID: large, end: 1), .init(componentID: battery, end: 0))
        model.step(dt: 1.0 / 90.0)

        let amps = 9.0 / (10 + 1000 + 0.05)
        let smallReadout = model.readouts[small]!
        let largeReadout = model.readouts[large]!
        XCTAssertEqual(abs(smallReadout.watts), amps * amps * 10, accuracy: 1e-6)
        XCTAssertEqual(abs(largeReadout.watts), amps * amps * 1000, accuracy: 1e-4)
    }

    // MARK: 2 — geometry is not topology

    /// Fifty moves must not rebuild the partition once. This is the
    /// whole argument for the cache: a carried part changes the room
    /// every frame and changes the circuit not at all.
    func testMovingAPartDoesNotRebuildTheNets() {
        let model = CircuitsModel()
        let (_, _, bulb) = buildLoop(on: model)
        let baseline = model.netRebuildCount

        for step in 0..<50 {
            model.move(id: bulb, to: CircuitsModel.buildCenter
                        + SIMD3(Double(step) * 0.004, 0.1, 0))
            model.step(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.netRebuildCount, baseline,
                       "Moving a part rebuilt the topology \(model.netRebuildCount - baseline) times.")
    }

    /// A switch is an element between two nets, not a break in one —
    /// so opening it changes the ELEMENT stamped, never the partition.
    func testOpeningASwitchDoesNotRebuildTheNets() {
        let model = CircuitsModel()
        let (_, toggle, bulb) = buildLoop(on: model)
        let baseline = model.netRebuildCount

        model.toggleSwitch(id: toggle)
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.netRebuildCount, baseline, "Toggling a switch rebuilt the topology.")
        // And it really did open the circuit — the assertion above
        // would also pass if nothing happened at all.
        XCTAssertEqual(abs(model.readouts[bulb]?.amps ?? 1), 0, accuracy: 1e-6)
    }

    /// Dialling a value is not a topology change either.
    func testChangingAValueDoesNotRebuildTheNets() {
        let model = CircuitsModel()
        let (_, _, bulb) = buildLoop(on: model)
        let baseline = model.netRebuildCount
        for ohms in stride(from: 10.0, through: 100.0, by: 10.0) {
            model.setComponentValue(id: bulb, ohms)
            model.step(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.netRebuildCount, baseline)
    }

    /// Wiring, on the other hand, IS a topology change — and exactly
    /// one per wire. The cache has no invalidation call, so this is
    /// the test that it notices at all.
    func testWiringRebuildsTheNetsExactlyOnce() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery)!
        let bulb = model.add(.bulb)!
        model.step(dt: 1.0 / 90.0)
        let baseline = model.netRebuildCount

        model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: bulb, end: 0))
        model.step(dt: 1.0 / 90.0)
        model.step(dt: 1.0 / 90.0)
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.netRebuildCount, baseline + 1,
                       "One wire should cost exactly one rebuild, then hold.")
    }

    /// Adding and deleting parts invalidates too — the cache is keyed
    /// on the component list, so this cannot be forgotten.
    func testAddingAndRemovingPartsRebuildsTheNets() {
        let model = CircuitsModel()
        buildLoop(on: model)
        let afterAdd = model.netRebuildCount
        let extra = model.add(.resistor)!
        model.step(dt: 1.0 / 90.0)
        XCTAssertGreaterThan(model.netRebuildCount, afterAdd)

        let afterSecond = model.netRebuildCount
        model.removeComponent(id: extra)
        model.step(dt: 1.0 / 90.0)
        XCTAssertGreaterThan(model.netRebuildCount, afterSecond)
    }

    // MARK: 3 — the same-net rule

    /// Two terminals already at one potential cannot be wired again.
    func testSameNetConnectionIsRefused() {
        let model = CircuitsModel()
        let (battery, toggle, _) = buildLoop(on: model)
        let before = model.wires.count

        // battery+ and switch-left are already one point.
        let outcome = model.connectTerminals(.init(componentID: battery, end: 1),
                                             .init(componentID: toggle, end: 0))
        XCTAssertEqual(outcome, .sameNet)
        XCTAssertEqual(model.wires.count, before, "A refused connection still made a wire.")
    }

    /// Refusing a self-wire and a missing part are distinguishable
    /// outcomes, not one silent `return` — the room shows them
    /// differently.
    func testTheRefusalsAreDistinguishable() {
        let model = CircuitsModel()
        let (battery, _, _) = buildLoop(on: model)
        let plus = CircuitsModel.Terminal(componentID: battery, end: 0)
        XCTAssertEqual(model.connectTerminals(plus, plus), .sameTerminal)
        XCTAssertEqual(model.connectTerminals(plus, .init(componentID: UUID(), end: 0)), .missing)
    }

    /// THE `fanOut` LIE, CLOSED. Twenty attempts at the same
    /// connection leave one wire — and that wire carries the whole
    /// branch current, not a fraction of it divided across phantom
    /// parallel copies.
    func testRedundantWiresCannotAccumulate() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery)!
        let bulb = model.add(.bulb)!
        model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: bulb, end: 0))
        let closing = model.connectTerminals(.init(componentID: bulb, end: 1),
                                             .init(componentID: battery, end: 0))
        guard case .connected = closing else { return XCTFail("the loop refused to close") }
        model.step(dt: 1.0 / 90.0)

        for _ in 0..<20 {
            XCTAssertEqual(model.connectTerminals(.init(componentID: battery, end: 1),
                                                  .init(componentID: bulb, end: 0)), .sameNet)
        }
        XCTAssertEqual(model.wires.count, 2, "Redundant wires accumulated.")

        model.step(dt: 1.0 / 90.0)
        let amps = 9.0 / (24 + 0.05)
        let flow = model.wireFlows[model.wires[0].id] ?? 0
        XCTAssertEqual(abs(flow), amps, accuracy: amps * 1e-3,
                       "The wire must carry the whole branch current.")
    }

    /// A second path to the same point is refused as firmly as a
    /// second wire between the same two ends — that is the difference
    /// between the same-net rule and the duplicate-pair rule it
    /// replaced.
    func testASecondPATHIsRefusedNotJustASecondWire() {
        let model = CircuitsModel()
        model.clearBench()
        let a = model.add(.resistor)!
        let b = model.add(.resistor)!
        let c = model.add(.resistor)!
        // a1–b0 and b0–c0: now a1 and c0 are one point by two hops,
        // with no wire directly between them.
        model.connectTerminals(.init(componentID: a, end: 1), .init(componentID: b, end: 0))
        model.connectTerminals(.init(componentID: b, end: 0), .init(componentID: c, end: 0))
        XCTAssertEqual(model.connectTerminals(.init(componentID: a, end: 1),
                                              .init(componentID: c, end: 0)), .sameNet,
                       "A duplicate-pair check would have allowed this.")
    }

    /// The snap preview obeys the same rule, so a release cannot
    /// create what a deliberate wire would have been refused.
    func testTheSnapPreviewSkipsSameNetCandidates() {
        let model = CircuitsModel()
        model.clearBench()
        let a = model.add(.resistor, at: CircuitsModel.buildCenter)!
        let b = model.add(.resistor, at: CircuitsModel.buildCenter + SIMD3(0.17, 0, 0))!
        model.connectTerminals(.init(componentID: a, end: 1), .init(componentID: b, end: 0))
        let candidates = model.pendingJoins(for: b)
        for pair in candidates {
            XCTAssertFalse(model.areConnected(pair.from, pair.to),
                           "The preview offered a connection the release would refuse.")
        }
    }

    // MARK: The refactor changed no physics

    /// The starter loop's current, to the literal it has always been.
    /// This is the anchor: everything above is new machinery, and the
    /// machinery is only worth anything if the answers are unchanged.
    func testTheSolveIsUnchangedByTheRefactor() {
        let model = CircuitsModel()
        model.step(dt: 1.0 / 90.0)
        let bulb = model.components.first { $0.kind == .bulb }!
        let expected = 9.0 / (24 + 0.05 + CircuitSolver.switchResistance)
        XCTAssertEqual(abs(model.readouts[bulb.id]?.amps ?? 0), expected,
                       accuracy: expected * 1e-9)
    }

    /// Continuity now reads through the cache instead of a BFS the
    /// meter kept for itself. Two terminals two hops apart are still
    /// continuous.
    func testContinuityReadsThroughTheNetCache() {
        let model = CircuitsModel()
        model.clearBench()
        let a = model.add(.resistor)!
        let b = model.add(.resistor)!
        let c = model.add(.resistor)!
        model.connectTerminals(.init(componentID: a, end: 1), .init(componentID: b, end: 0))
        model.connectTerminals(.init(componentID: b, end: 0), .init(componentID: c, end: 0))
        model.step(dt: 1.0 / 90.0)

        XCTAssertTrue(model.areConnected(.init(componentID: a, end: 1),
                                         .init(componentID: c, end: 0)),
                      "Two hops is still one net.")
        XCTAssertFalse(model.areConnected(.init(componentID: a, end: 0),
                                          .init(componentID: c, end: 1)),
                       "Unwired ends are not one net.")
    }

    /// Every net the solve found has a place to stand and a potential
    /// — the skyline reads both, and a net with neither would raise a
    /// tower at the origin.
    func testEveryNetCarriesAPositionAndAVoltage() {
        let model = CircuitsModel()
        model.step(dt: 1.0 / 90.0)
        XCTAssertFalse(model.nets.isEmpty)
        for net in model.nets {
            XCTAssertFalse(net.terminals.isEmpty, "Net \(net.id) has no terminals.")
            XCTAssertNotEqual(net.position, .zero, "Net \(net.id) stands at the origin.")
            XCTAssertTrue(net.position.y > 0.2, "Net \(net.id) is under the floor.")
        }
        XCTAssertEqual(model.nets.first { $0.id == 0 }?.voltage, 0,
                       "Ground is node 0 and sits at zero volts.")
    }

    /// Nets are derived from components and wires, so the capsule
    /// never carries them — a restore rebuilds them for free.
    func testNetsAreRebuiltFromARestoreAndNotSnapshotted() {
        let model = CircuitsModel()
        model.step(dt: 1.0 / 90.0)
        let snapshot = model.captureCapsuleSnapshot()
        let netsBefore = model.nets.count

        model.clearBench()
        model.step(dt: 1.0 / 90.0)
        model.restoreCapsuleSnapshot(snapshot)
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.nets.count, netsBefore)
    }
}
