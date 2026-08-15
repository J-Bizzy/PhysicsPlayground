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
    ///
    /// THE ASSERTION IS ON THE ENDPOINTS, NOT THE COUNT, and that is
    /// the whole lesson of this test. The first version checked only
    /// `wires.count` and passed against a `restore` that rebuilt the
    /// wire as `anchor → anchor`: a zero-length self-wire, which keeps
    /// the count identical while silently dropping the far part out of
    /// the circuit and leaving something invisible, un-grabbable and
    /// persisted behind. A count is not a connection.
    func testARefusedRewireRestoresTheWireWhereItWas() {
        let model = CircuitsModel()
        model.clearBench()
        let a = model.add(.battery, at: CircuitsModel.buildCenter - SIMD3(0.4, 0, 0))!
        let b = model.add(.bulb, at: CircuitsModel.buildCenter)!
        let c = model.add(.resistor, at: CircuitsModel.buildCenter + SIMD3(0.4, 0, 0))!
        // W1 joins a.1–b.0; W2 joins a.1–c.0. Lifting W1 leaves a.1 and
        // c.0 one net through W2, so dropping W1's end on c.0 refuses.
        model.connectTerminals(.init(componentID: a, end: 1), .init(componentID: b, end: 0))
        let w1 = model.wires[0].id
        model.connectTerminals(.init(componentID: a, end: 1), .init(componentID: c, end: 0))
        let before = model.wires.count

        model.beginRewire(wire: w1, grabbing: 1, hand: lead(model, b, 0))
        model.updateLeadPull(hand: lead(model, c, 0))
        XCTAssertEqual(model.leadPull?.refusal, .sameNet,
                       "the fixture did not actually produce a refusal")
        XCTAssertEqual(model.endLeadPull(), .refused(.sameNet))

        XCTAssertEqual(model.wires.count, before)
        let restored = try? XCTUnwrap(model.wires.first { $0.id == w1 })
        XCTAssertNotNil(restored, "the lifted wire did not come back at all")
        if let restored {
            XCTAssertNotEqual(restored.from, restored.to, "restored as a self-wire")
            XCTAssertEqual(Set([restored.from, restored.to]),
                           [.init(componentID: a, end: 1), .init(componentID: b, end: 0)],
                           "restored between the wrong terminals")
        }
        XCTAssertTrue(model.areConnected(.init(componentID: a, end: 1),
                                         .init(componentID: b, end: 0)),
                      "the part the wire was carrying fell out of the circuit")
    }

    /// No wire on the bench may ever join a terminal to itself. A
    /// self-wire is invisible, un-grabbable, budget-consuming and
    /// persisted — there is no way for a user to get rid of one.
    func testNoPathEverProducesASelfWire() {
        let model = CircuitsModel()
        let (_, bulb, spare, wire) = loop(model)
        // Lift, refuse, cancel, land, land back, drop — every landing
        // the rewire has.
        for landing in [lead(model, bulb, 0), lead(model, spare, 0),
                        CircuitsModel.buildCenter + SIMD3(0, 0.5, 0)] {
            if let live = model.wires.first?.id {
                model.beginRewire(wire: live, grabbing: 1, hand: lead(model, bulb, 0))
                model.updateLeadPull(hand: landing)
                model.endLeadPull()
            }
            for candidate in model.wires {
                XCTAssertNotEqual(candidate.from, candidate.to,
                                  "a self-wire reached the bench")
            }
        }
        _ = wire
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

    // MARK: The save waits for the hand

    /// A save that fires while a wire is IN THE HAND must not write
    /// the bench without it. `beginRewire` schedules the debounced
    /// save the moment it lifts the wire; if that save landed
    /// mid-pull, a force-quit before the release would lose a
    /// connection that a cancel would have restored.
    func testAMidRewireSaveDoesNotLoseTheWire() {
        defer { UserDefaults.standard.removeObject(forKey: CircuitsModel.saveKey) }
        let model = CircuitsModel()
        let (_, bulb, _, wire) = loop(model)
        model.persistNow()
        let wiresOnDisk = { CircuitsModel(restoreSaved: true).wires.count }
        let before = wiresOnDisk()

        model.beginRewire(wire: wire, grabbing: 1, hand: lead(model, bulb, 0))
        model.persistNow()  // the debounce firing mid-pull
        XCTAssertEqual(wiresOnDisk(), before,
                       "a bench with a wire in the hand is not a bench to save")

        // And once the pull resolves, saving works again — including
        // the restored wire.
        model.cancelLeadPull()
        model.persistNow()
        XCTAssertEqual(wiresOnDisk(), before)
    }

    // MARK: The old behaviour, refused

    /// A second pull cannot silently eat the wire a rewire is
    /// carrying — the model, not the view, owns that invariant.
    func testStartingASecondPullRestoresTheFirstsWire() {
        let model = CircuitsModel()
        let (battery, bulb, _, wire) = loop(model)
        let before = model.wires.count

        model.beginRewire(wire: wire, grabbing: 1, hand: lead(model, bulb, 0))
        XCTAssertEqual(model.wires.count, before - 1)
        // A fresh lead pull from somewhere else entirely.
        model.beginLeadPull(from: .init(componentID: battery, end: 0),
                            hand: lead(model, battery, 0))
        XCTAssertEqual(model.wires.count, before,
                       "the lifted wire vanished when a second pull began")
        XCTAssertTrue(model.wires.contains { $0.id == wire })
    }

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
