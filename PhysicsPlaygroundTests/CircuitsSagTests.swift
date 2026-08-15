//
//  CircuitsSagTests.swift
//  PhysicsPlaygroundTests
//
//  Wires hang. The catenary itself is PhysicsCore's business
//  (`CatenaryTests`); what is tested here is the bench's policy about
//  when a cable has slack in it at all, and the consequence for the
//  distance an electron walks.
//
//  THE POLICY EXISTS TO PROTECT THE PREVIOUS STAGE. Snap-align makes
//  parts click nose to tail; if every joint then sprouted a droop,
//  the tidiness would have been given back immediately. So a short
//  span is taut and only a real reach across the bench hangs.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsSagTests: XCTestCase {

    /// A snapped joint has no cable to hang.
    func testASnappedJointHasNoSag() {
        XCTAssertEqual(CircuitsModel.slack(span: 0), 0)
        XCTAssertEqual(CircuitsModel.slack(span: CircuitsModel.leadReach * 0.5), 0)
        XCTAssertEqual(CircuitsModel.slack(span: CircuitsModel.leadReach), 0)
    }

    /// And a real span does.
    func testALongSpanHasSlack() {
        XCTAssertGreaterThan(CircuitsModel.slack(span: 0.5), 0)
        XCTAssertGreaterThan(CircuitsModel.slack(span: 1.0),
                             CircuitsModel.slack(span: 0.5))
    }

    /// Slack never runs away with the span: a long reach droops like
    /// cable, not like rope. A wire at bench height whose sag went
    /// unbounded would hang through the floor.
    func testSlackStaysAProportionOfTheSpan() {
        for span in stride(from: 0.1, through: 3.0, by: 0.1) {
            let slack = CircuitsModel.slack(span: span)
            XCTAssertLessThanOrEqual(slack, 0.18 * span + 1e-9,
                                     "span \(span) slacked \(slack)")
        }
    }

    /// The curve actually dips below the straight line it replaces.
    func testALongSpanSagsBelowItsChord() {
        let a = SIMD3<Double>(-0.5, 1.3, -0.9)
        let b = SIMD3<Double>(0.5, 1.3, -0.9)
        let curve = Catenary.points(from: a, to: b,
                                    slack: CircuitsModel.slack(span: simd_distance(a, b)))
        XCTAssertLessThan(curve.map(\.y).min()!, 1.3 - 1e-3)
    }

    /// And a short one does not.
    func testAShortSpanStaysStraight() {
        let a = SIMD3<Double>(0, 1.3, -0.9)
        let b = a + SIMD3(CircuitsModel.leadReach * 0.8, 0, 0)
        let curve = Catenary.points(from: a, to: b,
                                    slack: CircuitsModel.slack(span: simd_distance(a, b)))
        for point in curve {
            XCTAssertEqual(point.y, 1.3, accuracy: 1e-12)
        }
    }

    // MARK: What the electron walks

    /// The conducting path is measured along the ARC. A hanging cable
    /// is longer than the gap it crosses, and the true-speed readout
    /// is built on this number.
    func testTheConductingPathIsArcNotChord() {
        let model = CircuitsModel()
        model.clearBench()
        // Two parts a long way apart, so their wires really hang.
        let battery = model.add(.battery, at: CircuitsModel.buildCenter - SIMD3(0.6, 0, 0))!
        let bulb = model.add(.bulb, at: CircuitsModel.buildCenter + SIMD3(0.6, 0, 0))!
        model.connectTerminals(.init(componentID: battery, end: 1), .init(componentID: bulb, end: 0))
        model.connectTerminals(.init(componentID: bulb, end: 1), .init(componentID: battery, end: 0))
        model.step(dt: 1.0 / 90.0)

        var chord = 0.0
        for wire in model.wires {
            let a = model.components.first { $0.id == wire.from.componentID }!
                .terminalPosition(wire.from.end)
            let b = model.components.first { $0.id == wire.to.componentID }!
                .terminalPosition(wire.to.end)
            chord += simd_distance(a, b)
        }
        XCTAssertGreaterThan(model.conductingPathLength, chord,
                             "the arc must be longer than the straight line")
        // And not absurdly longer — this is a cable, not a coil.
        XCTAssertLessThan(model.conductingPathLength, chord * 1.3)
    }

    /// A SNAPPED JOINT CONTRIBUTES ITS CHORD EXACTLY, because it has
    /// no slack to add. This is the half that protects the previous
    /// stage: a chained bench measures what it always measured.
    func testASnappedJointContributesNoExtraLength() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter)!
        let bulb = model.add(.bulb, at: model.components[0].terminalPosition(1)
                                + SIMD3(0.02 + CircuitsModel.terminalOffset, 0, 0))!
        model.release(id: bulb)

        // The joint really is coincident, so its wire spans nothing.
        let joint = model.wires[0]
        let a = model.components.first { $0.id == joint.from.componentID }!
            .terminalPosition(joint.from.end)
        let b = model.components.first { $0.id == joint.to.componentID }!
            .terminalPosition(joint.to.end)
        XCTAssertEqual(simd_distance(a, b), 0, accuracy: 1e-12)
        XCTAssertEqual(CircuitsModel.slack(span: simd_distance(a, b)), 0)
        XCTAssertEqual(
            Catenary.arcLength(from: a, to: b, slack: 0), 0, accuracy: 1e-12,
            "a joint with no gap must add no length to the loop")
        _ = battery
    }

    /// A DEAD-VERTICAL WIRE CONTRIBUTES ITS CHORD, not chord + slack.
    /// `Catenary.path` draws a near-vertical span as a straight drop
    /// (horizontal run under a fifth of the chord), so the electron
    /// walks the chord — and the path the readout divides by must be
    /// the path the electron actually walks.
    func testAVerticalWireContributesItsChordExactly() {
        let model = CircuitsModel()
        model.clearBench()
        let battery = model.add(.battery, at: CircuitsModel.buildCenter)!
        // Offset by twice the terminal reach in x so the bulb's LEFT
        // terminal sits exactly above the battery's RIGHT one: the
        // wire between them is dead vertical.
        let bulb = model.add(.bulb, at: CircuitsModel.buildCenter
                                + SIMD3(2 * CircuitsModel.terminalOffset, 0.5, 0))!
        model.connectTerminals(.init(componentID: battery, end: 1),
                               .init(componentID: bulb, end: 0))
        model.connectTerminals(.init(componentID: bulb, end: 1),
                               .init(componentID: battery, end: 0))
        model.step(dt: 1.0 / 90.0)

        var expected = 0.0
        for wire in model.wires {
            let a = model.components.first { $0.id == wire.from.componentID }!
                .terminalPosition(wire.from.end)
            let b = model.components.first { $0.id == wire.to.componentID }!
                .terminalPosition(wire.to.end)
            let span = simd_distance(a, b)
            let delta = b - a
            let horizontal = simd_length(SIMD2(delta.x, delta.z))
            if horizontal > 0.2 * span {
                expected += span + CircuitsModel.slack(span: span)
            } else {
                // The vertical drop: chord only. This is the branch
                // under test — one of the two wires must land here.
                XCTAssertLessThan(horizontal, 1e-9,
                                  "the staged wire should be dead vertical")
                expected += span
            }
        }
        XCTAssertEqual(model.conductingPathLength, expected, accuracy: 1e-12)
        // The old policy — slack on every span — measurably overshoots.
        let slackOnEverything = model.wires.reduce(0.0) { sum, wire in
            let a = model.components.first { $0.id == wire.from.componentID }!
                .terminalPosition(wire.from.end)
            let b = model.components.first { $0.id == wire.to.componentID }!
                .terminalPosition(wire.to.end)
            let span = simd_distance(a, b)
            return sum + span + CircuitsModel.slack(span: span)
        }
        XCTAssertLessThan(model.conductingPathLength, slackOnEverything - 1e-3,
                          "a vertical drop must not be credited with slack")
        // And the vertical wire genuinely spans something, so this is
        // not the snapped-joint case in disguise.
        XCTAssertGreaterThan(expected, 0.5)
    }

    /// The true-speed claim survives: whatever the path length, the
    /// RATIO between the field and the drift is thirteen-odd orders of
    /// magnitude, because both are computed over the same path.
    func testTheTrueSpeedRatioIsUnchangedBySag() {
        let model = CircuitsModel()
        model.step(dt: 1.0 / 90.0)
        XCTAssertGreaterThan(model.driftLapTime / model.signalLapTime, 1e10)
    }
}
