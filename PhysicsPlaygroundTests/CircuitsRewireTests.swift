//
//  CircuitsRewireTests.swift
//  PhysicsPlaygroundTests
//
//  Moving a connection from one terminal to another.
//
//  The bench never had this gesture. Before it, changing where a wire
//  went meant DELETING it — by tapping it, which destroyed it on the
//  first tap with no confirmation, on a bench that survives relaunch —
//  and then drawing a new one. Every other destructive verb in this
//  app arms and then fires; this one did not even ask.
//
//  Now you pull the plug: grab the cable near the end you want, that
//  end comes off into your hand, and you put it somewhere. It reuses
//  the lead-pull machinery exactly, so the three landings are the ones
//  a lead already had — a terminal, the original terminal, or open
//  air.
//
//  THE WIRE LEAVES `wires` THE MOMENT YOU LIFT IT, and that is the
//  teach rather than an implementation detail: the circuit goes dark
//  in your hand. A bulb going out as you lift a wire says what that
//  wire was doing better than any label on it could.
//

import XCTest
import PhysicsCore
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsRewireTests: XCTestCase {

    private func lead(_ model: CircuitsModel, _ id: UUID, _ end: Int) -> SIMD3<Double> {
        model.components.first { $0.id == id }!.terminalPosition(end)
    }

    /// A live battery–bulb loop, plus a spare part to rewire onto.
    private func loop(_ model: CircuitsModel)
    -> (battery: UUID, bulb: UUID, spare: UUID, wire: UUID) {
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter - SIMD3(0.35, 0, 0))!
        let bulb = model.add(.bulb, at: CircuitsModel.buildCenter + SIMD3(0.35, 0, 0))!
        let spare = model.add(.resistor, at: CircuitsModel.buildCenter + SIMD3(0, 0.3, 0))!
        model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: bulb, end: 0))
        let closing = model.wires.count
        model.connectTerminals(.init(componentID: bulb, end: 1), .init(componentID: battery, end: 0))
        XCTAssertEqual(model.wires.count, closing + 1)
        model.step(dt: 1.0 / 90.0)
        return (battery, bulb, spare, model.wires[0].id)
    }

    // MARK: Lifting

    /// Grabbing a wire near an end takes THAT end off, and leaves the
    /// other one where it was.
    func testGrabbingAWireNearItsEndTakesThatEndOff() {
        let model = CircuitsModel()
        let (battery, bulb, _, wire) = loop(model)
        let before = model.wires.count

        model.beginRewire(wire: wire, grabbing: 1, hand: lead(model, bulb, 0))
        XCTAssertEqual(model.wires.count, before - 1, "The wire should be in your hand.")
        XCTAssertEqual(model.leadPull?.source, .init(componentID: battery, end: 1),
                       "The lead must be drawn from the end that STAYED.")
        XCTAssertEqual(model.leadPull?.detached, wire)
    }

    /// The end taken is the one the hand was nearer to.
    func testTheEndTakenIsTheNearerOne() {
        let model = CircuitsModel()
        let (battery, bulb, _, wire) = loop(model)
        XCTAssertEqual(model.nearerEnd(of: wire, to: lead(model, battery, 1)), 0)
        XCTAssertEqual(model.nearerEnd(of: wire, to: lead(model, bulb, 0)), 1)
        // A hand nowhere near either end still picks one, and picks
        // the closer: there is no third answer.
        let midpoint = (lead(model, battery, 1) + lead(model, bulb, 0)) / 2
        XCTAssertNotNil(model.nearerEnd(of: wire, to: midpoint + SIMD3(-0.01, 0, 0)))
    }

    /// THE CIRCUIT GOES DARK IN YOUR HAND. This is the teach.
    func testTheCircuitGoesOpenWhileTheEndIsInHand() {
        let model = CircuitsModel()
        let (_, bulb, _, wire) = loop(model)
        model.step(dt: 1.0 / 90.0)
        let lit = 9.0 / (24 + 0.05)
        XCTAssertEqual(abs(model.readouts[bulb]?.amps ?? 0), lit, accuracy: lit * 1e-3,
                       "the loop should be live before the lift")

        model.beginRewire(wire: wire, grabbing: 1, hand: lead(model, bulb, 0))
        model.step(dt: 1.0 / 90.0)

        // NOT "exactly zero", and the difference is the solver's, not
        // a fudge. `CircuitSolver.leakConductance` is a 1e-9 S leak on
        // the diagonal that keeps a floating node solvable at all, so
        // an open 9 V loop carries about 9 nA and always did. What the
        // lift has to do is kill the CURRENT — seven orders of
        // magnitude — and a tolerance loose enough to pass a lit bulb
        // would prove nothing, so this is stated as a ratio.
        let dark = abs(model.readouts[bulb]?.amps ?? 1)
        XCTAssertLessThan(dark, lit * 1e-6,
                          "the bulb must go out while the wire is lifted")
        XCTAssertLessThan(dark, 1e-7, "and what is left must be the solver's leak")
    }

    // MARK: The three landings

    /// Land on another terminal: rewired. One wire, in its new place.
    func testAReleaseOnAnotherTerminalRewires() {
        let model = CircuitsModel()
        let (battery, bulb, spare, wire) = loop(model)
        let before = model.wires.count

        model.beginRewire(wire: wire, grabbing: 1, hand: lead(model, bulb, 0))
        model.updateLeadPull(hand: lead(model, spare, 0))
        guard case .connected = model.endLeadPull() else { return XCTFail("it refused") }

        XCTAssertEqual(model.wires.count, before, "A rewire must not change the wire count.")
        XCTAssertTrue(model.areConnected(.init(componentID: battery, end: 1),
                                         .init(componentID: spare, end: 0)),
                      "The wire should now reach the new terminal.")
        XCTAssertFalse(model.areConnected(.init(componentID: battery, end: 1),
                                          .init(componentID: bulb, end: 0)),
                       "The wire should have left the old terminal.")
    }

    /// Land back where it came from: restored, and NOT duplicated.
    func testAReleaseBackOnTheOriginalRestoresItWithoutADuplicate() {
        let model = CircuitsModel()
        let (battery, bulb, _, wire) = loop(model)
        let before = model.wires.count

        model.beginRewire(wire: wire, grabbing: 1, hand: lead(model, bulb, 0))
        model.updateLeadPull(hand: lead(model, bulb, 0))
        model.endLeadPull()

        XCTAssertEqual(model.wires.count, before, "Putting it back made a second wire.")
        XCTAssertTrue(model.areConnected(.init(componentID: battery, end: 1),
                                         .init(componentID: bulb, end: 0)))
        model.step(dt: 1.0 / 90.0)
        let lit = 9.0 / (24 + 0.05)
        XCTAssertEqual(abs(model.readouts[bulb]?.amps ?? 0), lit, accuracy: lit * 1e-3,
                       "the loop must light again")
    }

    /// Let it go in open air: the wire is gone. You pulled the plug
    /// and dropped it.
    func testAReleaseInFreeAirDeletesTheWire() {
        let model = CircuitsModel()
        let (_, bulb, _, wire) = loop(model)
        let before = model.wires.count

        model.beginRewire(wire: wire, grabbing: 1, hand: lead(model, bulb, 0))
        model.updateLeadPull(hand: CircuitsModel.buildCenter + SIMD3(0, 0.45, 0))
        XCTAssertEqual(model.endLeadPull(), .deleted(wire))
        XCTAssertEqual(model.wires.count, before - 1)
        XCTAssertFalse(model.wires.contains { $0.id == wire })
    }

    // MARK: The refusal, and putting it back

    /// A rewire that lands somewhere it cannot go is NOT a deletion —
    /// the wire goes back where it was. Losing a connection because
    /// you aimed at an illegal target would be the harshest possible
    /// reading of a refusal.
    func testARefusedRewireRestoresTheWire() {
        let model = CircuitsModel()
        model.clearBench()
        let a = model.add(.battery, at: CircuitsModel.buildCenter - SIMD3(0.35, 0, 0))!
        let b = model.add(.bulb, at: CircuitsModel.buildCenter + SIMD3(0.35, 0, 0))!
        // Two wires between the same pair of parts, so lifting one
        // leaves the other making them the same net.
        model.connectTerminals(.init(componentID: a, end: 1), .init(componentID: b, end: 0))
        model.connectTerminals(.init(componentID: a, end: 0), .init(componentID: b, end: 1))
        let wire = model.wires[0].id
        let before = model.wires.count

        model.beginRewire(wire: wire, grabbing: 1, hand: lead(model, b, 0))
        // Land it on a terminal already on the source's net through
        // the OTHER wire and the two parts.
        model.updateLeadPull(hand: lead(model, b, 1))
        if model.leadPull?.refusal != nil {
            XCTAssertEqual(model.endLeadPull(), .refused(.sameNet))
            XCTAssertEqual(model.wires.count, before,
                           "A refused rewire lost the wire it was carrying.")
        }
    }

    /// Cancelling a rewire — the part went away, the lab reset — puts
    /// the wire back rather than silently eating it.
    func testCancellingARewirePutsTheWireBack() {
        let model = CircuitsModel()
        let (_, bulb, _, wire) = loop(model)
        let before = model.wires.count

        model.beginRewire(wire: wire, grabbing: 1, hand: lead(model, bulb, 0))
        XCTAssertEqual(model.wires.count, before - 1)
        model.cancelLeadPull()
        XCTAssertEqual(model.wires.count, before, "A cancelled rewire ate the wire.")
        XCTAssertNil(model.leadPull)
    }

    /// Deleting the part the lifted wire was anchored to cancels the
    /// rewire and does not resurrect a wire onto a missing component.
    func testDeletingTheAnchorPartDuringARewireIsSafe() {
        let model = CircuitsModel()
        let (battery, bulb, _, wire) = loop(model)
        model.beginRewire(wire: wire, grabbing: 1, hand: lead(model, bulb, 0))
        model.removeComponent(id: battery)

        XCTAssertNil(model.leadPull)
        for candidate in model.wires {
            XCTAssertTrue(model.components.contains { $0.id == candidate.from.componentID })
            XCTAssertTrue(model.components.contains { $0.id == candidate.to.componentID })
        }
    }

    // MARK: The old behaviour, refused

    /// A TAP ON A WIRE NEVER DELETES IT. It used to, on the first tap,
    /// with no confirmation, on a bench that persists across launches.
    func testATapOnAWireNeverDeletesIt() {
        let model = CircuitsModel()
        let (_, _, _, wire) = loop(model)
        let before = model.wires.count
        model.selectWire(id: wire)
        XCTAssertEqual(model.wires.count, before, "Tapping a wire destroyed it.")
        XCTAssertTrue(model.wires.contains { $0.id == wire })
    }

    /// A press on a wire that does not travel is a tap, so it cannot
    /// lift anything either — the same latch rule as a lead.
    func testAPressOnAWireThatDoesNotTravelLiftsNothing() {
        let model = CircuitsModel()
        let (_, bulb, _, wire) = loop(model)
        let before = model.wires.count

        var latch = PressLatch<CircuitsModel.WireEnd>()
        let start = lead(model, bulb, 0)
        latch.press(.init(wire: wire, end: 1), at: start)
        for _ in 0..<10 {
            XCTAssertNil(latch.promote(hand: start + SIMD3(0.001, 0, 0.001)))
        }
        latch.cancel()
        XCTAssertEqual(model.wires.count, before)
        XCTAssertNil(model.leadPull)
    }

    /// `deleteWire` survives — it lost its tap caller but it is still
    /// the free-air landing and `detachComponent`'s helper.
    func testDeleteWireStillWorksForTheCallersThatRemain() {
        let model = CircuitsModel()
        let (_, _, _, wire) = loop(model)
        let before = model.wires.count
        model.deleteWire(id: wire)
        XCTAssertEqual(model.wires.count, before - 1)
    }
}
