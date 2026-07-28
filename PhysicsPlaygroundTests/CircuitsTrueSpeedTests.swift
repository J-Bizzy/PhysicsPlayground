//
//  CircuitsTrueSpeedTests.swift
//  PhysicsPlaygroundTests
//
//  The true-speed readout makes an extraordinary claim — that the
//  electrons in the user's own circuit take hours to do what the
//  field does in nanoseconds. These tests hold the claim to the
//  circuit actually on the bench: the drift must follow the solved
//  current, the lap times must follow the wired path, and the ratio
//  must stay in the trillions.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsTrueSpeedTests: XCTestCase {

    /// The cold-open bench is a live circuit; step it so the solver
    /// fills in currents.
    private func liveModel() -> CircuitsModel {
        let model = CircuitsModel()
        for _ in 0..<10 { model.step(dt: 1.0 / 60) }
        return model
    }

    func testTheOpeningCircuitCarriesCurrentAndAPath() {
        let model = liveModel()
        XCTAssertGreaterThan(model.peakCurrent, 5e-4,
                             "the demonstration circuit should be conducting")
        XCTAssertGreaterThan(model.conductingPathLength, 0.05,
                             "a wired loop should have measurable length")
    }

    func testElectronsCrawlAndTheFieldSprints() {
        let model = liveModel()
        // Drift at bench currents is micrometres per second…
        XCTAssertLessThan(model.driftSpeed, 1e-3)
        // …so a lap takes at least minutes, while the field takes
        // nanoseconds over the same path.
        XCTAssertGreaterThan(model.driftLapTime, 60)
        XCTAssertLessThan(model.signalLapTime, 1e-6)
        XCTAssertGreaterThan(model.driftLapTime / model.signalLapTime, 1e10)
    }

    func testDriftTracksTheSolvedCurrent() {
        let model = liveModel()
        let slow = model.driftSpeed
        // The drift speed is a function of the current the solver
        // reports — not a constant, not a guess.
        let expected = ChargeTransport.driftSpeed(
            current: model.peakCurrent, wireRadius: CircuitsModel.wireRadius)
        XCTAssertEqual(slow, expected, accuracy: expected * 1e-9)
        XCTAssertGreaterThan(expected, 0)
    }

    func testDeadCircuitReportsNoDriftAndNoLap() {
        let model = CircuitsModel()
        model.clearBench()
        for _ in 0..<5 { model.step(dt: 1.0 / 60) }
        XCTAssertEqual(model.peakCurrent, 0, accuracy: 5e-4)
        XCTAssertEqual(model.driftSpeed, 0, accuracy: 1e-12)
        XCTAssertFalse(model.driftLapTime.isFinite,
                       "no drift means an electron never completes a lap")
    }
}
