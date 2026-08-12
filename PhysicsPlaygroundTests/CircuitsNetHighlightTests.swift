//
//  CircuitsNetHighlightTests.swift
//  PhysicsPlaygroundTests
//
//  "What is this connected to?" — answered by the bench rather than by
//  a sentence about the bench.
//
//  Tap a lead or a wire and every terminal at that same potential
//  lights, along with every wire between them. It is the one question
//  a circuit builder asks constantly and the room had no way to
//  answer: a terminal wired through three hops looked exactly like a
//  terminal wired to nothing.
//
//  SELECTION-DRIVEN, NOT HOVER, and that is a limit rather than a
//  preference. `HoverEffectComponent` is drawn by the system with no
//  callback, and there is no hover event without `SpatialEventGesture`
//  — so "light what my gaze is on" is not reachable from where this
//  module stands today.
//
//  WHAT IS STORED IS THE TAPPED TERMINAL, and the node is resolved on
//  read. Node ids come from slot numbers, so deleting any part
//  renumbers every net after it — held as an `Int`, the highlight
//  silently re-pointed at a net it had never been asked for. Neither
//  form is a `Bool`, which is also deliberate: `ResetCoverageTests`
//  reflects over every `Bool` and demands a flip case for each, and
//  this is a selection rather than a display layer, so the tests
//  below cover reset, clear and the capsule by hand.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsNetHighlightTests: XCTestCase {

    /// battery —w1— bulb —w2— resistor —w3— battery: one loop, four
    /// nets, and every net has more than one terminal on it.
    private func loop(_ model: CircuitsModel)
    -> (battery: UUID, bulb: UUID, resistor: UUID) {
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter - SIMD3(0.35, 0, 0))!
        let bulb = model.add(.bulb, at: CircuitsModel.buildCenter)!
        let resistor = model.add(.resistor, at: CircuitsModel.buildCenter + SIMD3(0.35, 0, 0))!
        model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: bulb, end: 0))
        model.connectTerminals(.init(componentID: bulb, end: 1),
                               .init(componentID: resistor, end: 0))
        model.connectTerminals(.init(componentID: resistor, end: 1),
                               .init(componentID: battery, end: 0))
        model.step(dt: 1.0 / 90.0)
        return (battery, bulb, resistor)
    }

    /// Lighting a terminal lights exactly the terminals at its
    /// potential — no more, and no fewer.
    func testHighlightingLightsExactlyItsNet() {
        let model = CircuitsModel()
        let (battery, bulb, resistor) = loop(model)
        model.highlightNet(containing: .init(componentID: battery, end: 1))

        XCTAssertEqual(Set(model.highlightedTerminals),
                       [.init(componentID: battery, end: 1),
                        .init(componentID: bulb, end: 0)])
        XCTAssertFalse(model.highlightedTerminals
            .contains(.init(componentID: resistor, end: 0)))
    }

    /// A net reached through several hops lights whole — this is the
    /// case the room could not show at all.
    func testAMultiHopNetLightsWhole() {
        let model = CircuitsModel()
        model.clearBench()
        let a = model.add(.resistor, at: CircuitsModel.buildCenter - SIMD3(0.4, 0, 0))!
        let b = model.add(.resistor, at: CircuitsModel.buildCenter)!
        let c = model.add(.resistor, at: CircuitsModel.buildCenter + SIMD3(0.4, 0, 0))!
        model.connectTerminals(.init(componentID: a, end: 1), .init(componentID: b, end: 0))
        model.connectTerminals(.init(componentID: b, end: 0), .init(componentID: c, end: 0))

        model.highlightNet(containing: .init(componentID: a, end: 1))
        XCTAssertEqual(Set(model.highlightedTerminals),
                       [.init(componentID: a, end: 1),
                        .init(componentID: b, end: 0),
                        .init(componentID: c, end: 0)])
    }

    /// Every wire inside the lit net is lit; wires outside it are not.
    func testExactlyTheNetsWiresAreLit() {
        let model = CircuitsModel()
        let (battery, bulb, _) = loop(model)
        model.highlightNet(containing: .init(componentID: battery, end: 1))

        let litWires = model.wires.filter { model.isHighlighted(wire: $0) }
        XCTAssertEqual(litWires.count, 1)
        let lit = litWires[0]
        XCTAssertTrue([lit.from, lit.to].contains(.init(componentID: battery, end: 1)))
        XCTAssertTrue([lit.from, lit.to].contains(.init(componentID: bulb, end: 0)))
    }

    /// Tapping a wire lights its net too — a wire IS a statement that
    /// its two ends are one point, so either end answers.
    func testTappingAWireLightsItsNet() {
        let model = CircuitsModel()
        let (battery, bulb, _) = loop(model)
        let wire = model.wires.first {
            [$0.from, $0.to].contains(.init(componentID: battery, end: 1))
        }!
        model.selectWire(id: wire.id)
        XCTAssertEqual(Set(model.highlightedTerminals),
                       [.init(componentID: battery, end: 1),
                        .init(componentID: bulb, end: 0)])
    }

    /// Nothing lit is the resting state, and clearing returns to it.
    func testNothingIsLitToBeginWithAndClearingReturnsThere() {
        let model = CircuitsModel()
        let (battery, _, _) = loop(model)
        XCTAssertNil(model.highlightedNet)
        XCTAssertTrue(model.highlightedTerminals.isEmpty)

        model.highlightNet(containing: .init(componentID: battery, end: 1))
        XCTAssertNotNil(model.highlightedNet)
        model.clearNetHighlight()
        XCTAssertNil(model.highlightedNet)
        XCTAssertTrue(model.highlightedTerminals.isEmpty)
        XCTAssertFalse(model.wires.contains { model.isHighlighted(wire: $0) })
    }

    /// THE HIGHLIGHT FOLLOWS A REWIRE. Net ids are recomputed from the
    /// bench, so a net that grows or splits under a lit highlight
    /// shows the new truth rather than a remembered one.
    func testTheHighlightFollowsARewire() {
        let model = CircuitsModel()
        let (battery, bulb, resistor) = loop(model)
        model.highlightNet(containing: .init(componentID: battery, end: 1))
        XCTAssertEqual(model.highlightedTerminals.count, 2)

        // Wire the resistor's free-ish end onto that same net: it
        // should join the lit set without the highlight being touched.
        model.connectTerminals(.init(componentID: bulb, end: 0),
                               .init(componentID: resistor, end: 0))
        XCTAssertTrue(model.highlightedTerminals
            .contains(.init(componentID: resistor, end: 0)),
            "The lit net did not grow when the bench did.")
    }

    /// Every lit terminal really is at one potential — the highlight
    /// and the solve must not be able to disagree.
    func testEverythingLitIsAtOnePotential() {
        let model = CircuitsModel()
        let (battery, _, _) = loop(model)
        model.highlightNet(containing: .init(componentID: battery, end: 1))
        model.step(dt: 1.0 / 90.0)

        let volts = model.highlightedTerminals.compactMap { model.terminalVoltages[$0] }
        XCTAssertEqual(volts.count, model.highlightedTerminals.count)
        for value in volts {
            XCTAssertEqual(value, volts[0], accuracy: 1e-9,
                           "A lit terminal is at a different potential from its net.")
        }
    }

    // MARK: It is display state, and display state only

    /// Reset, Clear bench and a capsule restore all put it out.
    func testResetAndClearPutTheHighlightOut() {
        let model = CircuitsModel()
        let (battery, _, _) = loop(model)
        model.highlightNet(containing: .init(componentID: battery, end: 1))
        model.reset()
        XCTAssertNil(model.highlightedNet)

        let (second, _, _) = loop(model)
        model.highlightNet(containing: .init(componentID: second, end: 1))
        model.clearBench()
        XCTAssertNil(model.highlightedNet)
    }

    /// It is NEVER snapshotted. A highlight is the observer's state,
    /// not the experiment's, and the Time Capsule's rule is that only
    /// the experiment goes in.
    func testHighlightingIsPurelyDisplayAndNeverSnapshotted() {
        let model = CircuitsModel()
        let (battery, _, _) = loop(model)
        let clean = model.captureCapsuleSnapshot()

        model.highlightNet(containing: .init(componentID: battery, end: 1))
        XCTAssertEqual(model.captureCapsuleSnapshot(), clean,
                       "The highlight leaked into the capsule snapshot.")
    }

    /// And it changes no physics.
    func testHighlightingChangesNoReadings() {
        let model = CircuitsModel()
        let (battery, bulb, _) = loop(model)
        model.step(dt: 1.0 / 90.0)
        let before = model.readouts[bulb]?.amps ?? 0

        model.highlightNet(containing: .init(componentID: battery, end: 1))
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(model.readouts[bulb]?.amps ?? 0, before, accuracy: 1e-12)
    }

    /// DELETING A PART MUST NOT RE-POINT THE HIGHLIGHT AT A
    /// DIFFERENT NET.
    ///
    /// Node ids are assigned by lowest slot, and slots are
    /// `2 * componentIndex + end` — so removing any part renumbers
    /// every net after it. Held as an `Int`, the highlight silently
    /// followed the NUMBER rather than the net: light the switch–bulb
    /// net on the starter loop, delete the battery, and the bench went
    /// on lighting "net 2", which by then was a terminal that had
    /// never been in the net and was not connected to it. It holds the
    /// tapped TERMINAL now and resolves the node on read.
    func testDeletingAPartDoesNotRepointTheHighlight() {
        let model = CircuitsModel()
        let (battery, bulb, resistor) = loop(model)
        model.highlightNet(containing: .init(componentID: bulb, end: 1))
        let litBefore = Set(model.highlightedTerminals)
        XCTAssertEqual(litBefore, [.init(componentID: bulb, end: 1),
                                   .init(componentID: resistor, end: 0)])

        model.removeComponent(id: battery)
        model.step(dt: 1.0 / 90.0)
        XCTAssertEqual(Set(model.highlightedTerminals), litBefore,
                       "the highlight moved to a different net when a part was deleted")
    }

    /// Deleting the lit part itself puts the highlight out rather than
    /// leaving it pointing at whatever inherited the number.
    func testDeletingTheLitPartClearsTheHighlight() {
        let model = CircuitsModel()
        let (battery, _, _) = loop(model)
        model.highlightNet(containing: .init(componentID: battery, end: 1))
        model.removeComponent(id: battery)
        model.step(dt: 1.0 / 90.0)
        XCTAssertNil(model.highlightedNet)
        XCTAssertTrue(model.highlightedTerminals.isEmpty)
    }
}
