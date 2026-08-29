//
//  CircuitsWirePathTests.swift
//  PhysicsPlaygroundTests
//
//  Wires are straight (2026-08-29, owner's call — the catenary sag was
//  removed). What is tested here is the consequence for the distance an
//  electron walks: the conducting path is the chord sum, exactly the
//  distances the true-speed field front walks, so the readout and the
//  front agree by construction.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsWirePathTests: XCTestCase {

    /// The conducting path is the CHORD SUM. A wire is drawn taut
    /// between its terminals, the electron walks what is drawn, and
    /// the true-speed readout is built on this number.
    func testTheConductingPathIsTheChordSum() {
        let model = CircuitsModel()
        model.clearBench()
        // Two parts a long way apart, so the spans are real reaches.
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
        XCTAssertGreaterThan(chord, 0.5, "the staged spans must be real reaches")
        XCTAssertEqual(model.conductingPathLength, chord, accuracy: 1e-12,
                       "the path must be the straight line the wire draws")
    }

    /// A SNAPPED JOINT CONTRIBUTES NOTHING, because its two leads are
    /// one point. A chained bench measures what its parts measure.
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
        XCTAssertEqual(simd_distance(a, b), 0, accuracy: 1e-12,
                       "a joint with no gap must add no length to the loop")
        _ = battery
    }

    /// The true-speed claim: whatever the geometry, the RATIO between
    /// the field and the drift is thirteen-odd orders of magnitude,
    /// because both lap times are computed over the same path.
    func testTheTrueSpeedRatioIsPureSpeed() {
        let model = CircuitsModel()
        model.step(dt: 1.0 / 90.0)
        XCTAssertGreaterThan(model.driftLapTime / model.signalLapTime, 1e10)
    }
}
