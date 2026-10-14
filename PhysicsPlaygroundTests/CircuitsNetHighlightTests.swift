//
//  CircuitsNetHighlightTests.swift
//  PhysicsPlaygroundTests
//
//  "What is this connected to?": tap a lead or a wire and every
//  terminal at that potential lights, with every wire between them.
//  Selection-driven, not hover (there is no hover callback). What is
//  stored is the tapped terminal and the node is resolved on read,
//  because deleting any part renumbers every net. Not a `Bool`, so
//  reset, clear and the capsule are covered here by hand.
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

    /// Tapping a wire lights its net too — a wire is a statement that
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

    /// The highlight follows A rewire. Net ids are recomputed from the
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

    /// It is never snapshotted. A highlight is the observer's state,
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

    /// Deleting a part must not re-point the highlight at a different net:
    /// node ids are assigned by lowest slot, so removing a part renumbers
    /// every net after it.
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
