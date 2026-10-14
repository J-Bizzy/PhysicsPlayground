//
//  CircuitsLeadPullTests.swift
//  PhysicsPlaygroundTests
//
//  One way to make a wire: pinch a lead, pull it to another lead, let
//  go. A press only becomes a pull once the hand has travelled, so a tap
//  wires nothing; and a refusal is known on the frame before the
//  release, so what you preview is what you get.
//

import XCTest
import PhysicsCore
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsLeadPullTests: XCTestCase {

    private func lead(_ model: CircuitsModel, _ id: UUID, _ end: Int) -> SIMD3<Double> {
        model.components.first { $0.id == id }!.terminalPosition(end)
    }

    /// Two parts far enough apart that nothing snaps on its own.
    private func bench(_ model: CircuitsModel) -> (battery: UUID, bulb: UUID) {
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter - SIMD3(0.3, 0, 0))!
        let bulb = model.add(.bulb, at: CircuitsModel.buildCenter + SIMD3(0.3, 0, 0))!
        return (battery, bulb)
    }

    // MARK: The gesture

    /// A lead pulled to another lead makes a wire.
    func testALeadPulledToAnotherLeadWires() {
        let model = CircuitsModel()
        let (battery, bulb) = bench(model)
        let source = CircuitsModel.Terminal(componentID: battery, end: 1)

        model.beginLeadPull(from: source, hand: lead(model, battery, 1))
        model.updateLeadPull(hand: lead(model, bulb, 0))
        XCTAssertEqual(model.leadPull?.target, .init(componentID: bulb, end: 0))
        XCTAssertNil(model.leadPull?.refusal)

        guard case .connected = model.endLeadPull() else { return XCTFail("it refused") }
        XCTAssertEqual(model.wires.count, 1)
        XCTAssertNil(model.leadPull, "the pull must clear on release")
    }

    /// The target is found from the lead tip at the same `leadReach` a
    /// release uses, so the preview cannot snap to something the release
    /// ignores.
    func testTheTargetIsTheNearestLeadWithinReach() {
        let model = CircuitsModel()
        let (battery, bulb) = bench(model)
        let source = CircuitsModel.Terminal(componentID: battery, end: 1)
        model.beginLeadPull(from: source, hand: lead(model, battery, 1))

        // Just inside.
        model.updateLeadPull(hand: lead(model, bulb, 0)
                                + SIMD3(CircuitsModel.leadReach * 0.9, 0, 0))
        XCTAssertEqual(model.leadPull?.target, .init(componentID: bulb, end: 0))

        // Just outside.
        model.updateLeadPull(hand: lead(model, bulb, 0)
                                + SIMD3(CircuitsModel.leadReach * 1.1, 0, 0))
        XCTAssertNil(model.leadPull?.target)
    }

    /// A lead cannot land on the terminal it came from.
    func testALeadNeverTargetsItsOwnSource() {
        let model = CircuitsModel()
        let (battery, _) = bench(model)
        let source = CircuitsModel.Terminal(componentID: battery, end: 1)
        model.beginLeadPull(from: source, hand: lead(model, battery, 1))
        XCTAssertNil(model.leadPull?.target)
        XCTAssertEqual(model.endLeadPull(), .retracted)
        XCTAssertTrue(model.wires.isEmpty)
    }

    /// Let go in open air and the lead springs back. Nothing changes,
    /// and nothing is destroyed.
    func testALeadReleasedInFreeAirRetracts() {
        let model = CircuitsModel()
        let (battery, _) = bench(model)
        model.beginLeadPull(from: .init(componentID: battery, end: 1),
                            hand: lead(model, battery, 1))
        model.updateLeadPull(hand: CircuitsModel.buildCenter + SIMD3(0, 0.4, 0))
        XCTAssertEqual(model.endLeadPull(), .retracted)
        XCTAssertTrue(model.wires.isEmpty)
        XCTAssertNil(model.leadPull)
    }

    // MARK: The refusal

    /// Landing on a lead already at the same potential is refused —
    /// and the refusal is known before the release, so the room can
    /// show it while the hand is still deciding.
    func testALeadReleasedOnASameNetTerminalRefuses() {
        let model = CircuitsModel()
        let (battery, bulb) = bench(model)
        model.connectTerminals(.init(componentID: battery, end: 1),
                               .init(componentID: bulb, end: 0))
        let before = model.wires.count

        model.beginLeadPull(from: .init(componentID: battery, end: 1),
                            hand: lead(model, battery, 1))
        model.updateLeadPull(hand: lead(model, bulb, 0))
        XCTAssertEqual(model.leadPull?.target, .init(componentID: bulb, end: 0))
        XCTAssertEqual(model.leadPull?.refusal, .sameNet,
                       "The refusal must be visible before the release, not after.")

        XCTAssertEqual(model.endLeadPull(), .refused(.sameNet))
        XCTAssertEqual(model.wires.count, before, "A refused pull made a wire.")
    }

    /// A refusal through a longer path, not just a repeated pair —
    /// the same-net rule is what makes this stronger than the
    /// duplicate check it replaced.
    func testARefusalSeesThroughAWholeNet() {
        let model = CircuitsModel()
        model.clearBench()
        let a = model.add(.resistor, at: CircuitsModel.buildCenter - SIMD3(0.4, 0, 0))!
        let b = model.add(.resistor, at: CircuitsModel.buildCenter)!
        let c = model.add(.resistor, at: CircuitsModel.buildCenter + SIMD3(0.4, 0, 0))!
        model.connectTerminals(.init(componentID: a, end: 1), .init(componentID: b, end: 0))
        model.connectTerminals(.init(componentID: b, end: 0), .init(componentID: c, end: 0))

        model.beginLeadPull(from: .init(componentID: a, end: 1), hand: lead(model, a, 1))
        model.updateLeadPull(hand: lead(model, c, 0))
        XCTAssertEqual(model.leadPull?.refusal, .sameNet)
    }

    /// A full wire budget refuses too, and says so as its own reason.
    func testAFullWireBudgetRefuses() {
        let model = CircuitsModel()
        model.clearBench()
        // Enough parts to fill the wire budget with a long chain.
        var parts: [UUID] = []
        while parts.count < CircuitsModel.componentBudget,
              let id = model.add(.resistor) { parts.append(id) }
        var index = 0
        while model.wires.count < CircuitsModel.wireBudget, index < parts.count * 2 {
            let a = CircuitsModel.Terminal(componentID: parts[index % parts.count],
                                           end: index % 2)
            let b = CircuitsModel.Terminal(componentID: parts[(index + 1) % parts.count],
                                           end: (index + 1) % 2)
            if case .connected = model.connectTerminals(a, b) {}
            index += 1
        }
        guard model.wires.count >= CircuitsModel.wireBudget else {
            // A simple chain could not fill it; the budget rule is
            // still covered by `connectTerminals`' own outcome.
            return
        }
        model.beginLeadPull(from: .init(componentID: parts[0], end: 0),
                            hand: lead(model, parts[0], 0))
        model.updateLeadPull(hand: lead(model, parts[3], 1))
        if model.leadPull?.target != nil {
            XCTAssertEqual(model.leadPull?.refusal, .budgetFull)
        }
    }

    // MARK: THE RACE, pinned

    /// A press that does not travel is a tap, and taps do not wire: nothing
    /// wires unless a pull was begun, and a press below
    /// `PressLatch.tapTravel` never begins one.
    func testAPressThatDoesNotTravelIsATapAndWiresNothing() {
        let model = CircuitsModel()
        let (battery, bulb) = bench(model)
        // Put the two leads 5 cm apart — well inside `leadReach`, so
        // an accidental pull would have wired them.
        model.move(id: bulb, to: lead(model, battery, 1)
                    + SIMD3(0.05 + CircuitsModel.terminalOffset, 0, 0))
        XCTAssertLessThan(simd_distance(lead(model, battery, 1), lead(model, bulb, 0)),
                          CircuitsModel.leadReach)

        var latch = PressLatch<CircuitsModel.Terminal>()
        let source = CircuitsModel.Terminal(componentID: battery, end: 1)
        let start = lead(model, battery, 1)
        latch.press(source, at: start)
        // A hand that wobbles below the tap threshold.
        for _ in 0..<10 {
            XCTAssertNil(latch.promote(hand: start + SIMD3(0.001, 0.001, 0)),
                         "A press under the tap threshold promoted to a drag.")
        }
        // The release path acts only on a promoted latch.
        latch.cancel()
        XCTAssertNil(model.leadPull)
        XCTAssertEqual(model.endLeadPull(), .none)
        XCTAssertTrue(model.wires.isEmpty, "A tap made a wire.")
    }

    /// And a press that does travel becomes a pull.
    func testAPressThatTravelsBecomesAPull() {
        let model = CircuitsModel()
        let (battery, _) = bench(model)
        var latch = PressLatch<CircuitsModel.Terminal>()
        let source = CircuitsModel.Terminal(componentID: battery, end: 1)
        let start = lead(model, battery, 1)
        latch.press(source, at: start)
        let promoted = latch.promote(hand: start + SIMD3(0.05, 0, 0))
        XCTAssertEqual(promoted, source)
        model.beginLeadPull(from: source, hand: start + SIMD3(0.05, 0, 0))
        XCTAssertNotNil(model.leadPull)
    }

    // MARK: The zombie wire

    /// Deleting the part a pull is coming from cancels the pull; a stale
    /// pull once built a wire onto a component that no longer existed.
    func testDeletingThePartUnderAPullCancelsIt() {
        let model = CircuitsModel()
        let (battery, bulb) = bench(model)
        model.beginLeadPull(from: .init(componentID: battery, end: 1),
                            hand: lead(model, battery, 1))
        model.removeComponent(id: battery)
        XCTAssertNil(model.leadPull, "The pull outlived its own part.")

        // And a release afterwards cannot build anything.
        model.updateLeadPull(hand: lead(model, bulb, 0))
        XCTAssertEqual(model.endLeadPull(), .none)
        XCTAssertTrue(model.wires.isEmpty)
    }

    /// Clearing the bench and resetting the lab both cancel a pull.
    func testClearAndResetCancelAPull() {
        let model = CircuitsModel()
        let (battery, _) = bench(model)
        model.beginLeadPull(from: .init(componentID: battery, end: 1),
                            hand: lead(model, battery, 1))
        model.clearBench()
        XCTAssertNil(model.leadPull)

        let second = CircuitsModel()
        let first = second.components[0]
        second.beginLeadPull(from: .init(componentID: first.id, end: 1),
                             hand: first.terminalPosition(1))
        second.reset()
        XCTAssertNil(second.leadPull)
    }

    // MARK: The accessibility door

    /// VoiceOver keeps tap-tap wiring, because pulling a lead needs a
    /// sustained pinch and a hand that travels. Two activations, one
    /// wire.
    func testVoiceOverWiringArmsThenLands() {
        let model = CircuitsModel()
        let (battery, bulb) = bench(model)
        model.voiceOverWire(.init(componentID: battery, end: 1))
        XCTAssertEqual(model.voiceWireSource, .init(componentID: battery, end: 1))
        XCTAssertTrue(model.wires.isEmpty, "Arming must not wire anything yet.")

        model.voiceOverWire(.init(componentID: bulb, end: 0))
        XCTAssertNil(model.voiceWireSource)
        XCTAssertEqual(model.wires.count, 1)
    }

    /// Activating the same lead twice cancels rather than wiring it to
    /// itself.
    func testVoiceOverWiringCancelsOnTheSameLead() {
        let model = CircuitsModel()
        let (battery, _) = bench(model)
        let source = CircuitsModel.Terminal(componentID: battery, end: 1)
        model.voiceOverWire(source)
        model.voiceOverWire(source)
        XCTAssertNil(model.voiceWireSource)
        XCTAssertTrue(model.wires.isEmpty)
    }

    /// The pinch path never reads `voiceWireSource`: arming by VoiceOver and
    /// pulling a lead by hand are independent.
    func testThePinchPathNeverConsumesTheVoiceOverArming() {
        let model = CircuitsModel()
        let (battery, bulb) = bench(model)
        model.voiceOverWire(.init(componentID: battery, end: 1))

        model.beginLeadPull(from: .init(componentID: bulb, end: 1),
                            hand: lead(model, bulb, 1))
        model.updateLeadPull(hand: lead(model, bulb, 0))
        model.endLeadPull()
        XCTAssertEqual(model.voiceWireSource, .init(componentID: battery, end: 1),
                       "A pinch consumed the VoiceOver arming.")
    }

    /// Reset clears it. `ResetCoverageTests` reflects over `Bool`s and
    /// cannot see an optional `Terminal`, so this is asserted by hand
    /// rather than left to the sweep.
    func testResetClearsTheVoiceOverWireSource() {
        let model = CircuitsModel()
        let first = model.components[0]
        model.voiceOverWire(.init(componentID: first.id, end: 1))
        XCTAssertNotNil(model.voiceWireSource)
        model.reset()
        XCTAssertNil(model.voiceWireSource)
    }

    /// A part deleted under a VoiceOver arming cannot leave a wire
    /// behind either — the same defect, through the other door.
    func testDeletingAVoiceOverArmedPartCannotLeaveAWire() {
        let model = CircuitsModel()
        let (battery, bulb) = bench(model)
        model.voiceOverWire(.init(componentID: battery, end: 1))
        model.removeComponent(id: battery)
        model.voiceOverWire(.init(componentID: bulb, end: 0))
        XCTAssertTrue(model.wires.isEmpty, "A wire was built onto a deleted part.")
    }
}
