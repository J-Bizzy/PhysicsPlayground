//
//  KeplerSweepTests.swift
//  The sweep must rediscover Kepler's second law from raw integrated orbits; dA/dt = L/2m.
//

import XCTest
import simd
@testable import PhysicsCore

final class KeplerSweepTests: XCTestCase {

    private func sweptOrbit(eccentricity: Double,
                            days: Double,
                            stepHours: Double = 6)
    -> (sweep: KeplerSweep, period: Double) {
        let sun = CelestialBody(
            name: "Sun", mass: 1.989e30, radius: 6.96e8,
            position: .zero, velocity: .zero)
        let au = CelestialBody.astronomicalUnit
        let planet = CelestialBody(
            name: "P", mass: 5.97e24, radius: 6.4e6,
            position: .zero, velocity: .zero
        ).onEllipticalOrbit(of: sun, semiMajorAxis: au,
                            eccentricity: eccentricity, inclination: 0.2)

        var system = [sun, planet]
        var sweep = KeplerSweep(horizon: days * 86_400)
        let h = stepHours * 3600
        var time = 0.0
        sweep.record(time: time, position: system[1].position - system[0].position)
        while time < days * 86_400 {
            NBody.step(bodies: &system, dt: h)
            time += h
            sweep.record(time: time, position: system[1].position - system[0].position)
        }
        let period = NBody.orbitalPeriod(
            semiMajorAxis: au, centralMass: sun.mass + planet.mass) ?? 0
        return (sweep, period)
    }

    func testEqualAreasInEqualTimesOnAnEccentricOrbit() {
        // e = 0.6: the two sectors look nothing alike; areas must still agree.
        let (sweep, period) = sweptOrbit(eccentricity: 0.6, days: 400)
        let window = period / 12
        let fast = sweep.area(from: 0, to: window)
        let slow = sweep.area(from: period / 2, to: period / 2 + window)
        XCTAssertGreaterThan(fast, 0)
        XCTAssertEqual(fast / slow, 1.0, accuracy: 0.02,
                       "Equal times must sweep equal areas everywhere on the orbit")
    }

    func testAreaRateIsAngularMomentumOverTwoM() {
        // dA/dt = L/2m, checked against the initial state directly.
        let (sweep, period) = sweptOrbit(eccentricity: 0.3, days: 200)
        guard let first = sweep.samples.first else { return XCTFail("no samples") }

        guard sweep.samples.count > 1 else { return XCTFail("too few samples") }
        let second = sweep.samples[1]
        let velocity = (second.position - first.position) / (second.time - first.time)
        let areaRateFromL = simd_length(simd_cross(first.position, velocity)) / 2

        let window = period / 20
        let measured = sweep.area(from: 0, to: window) / window
        XCTAssertEqual(measured / areaRateFromL, 1.0, accuracy: 0.02)
    }

    func testCircularOrbitSweepsTheFullDiscInOnePeriod() {
        let (sweep, period) = sweptOrbit(eccentricity: 0, days: 400, stepHours: 3)
        let au = CelestialBody.astronomicalUnit
        let fullOrbit = sweep.area(from: 0, to: period)
        XCTAssertEqual(fullOrbit / (Double.pi * au * au), 1.0, accuracy: 0.01,
                       "One period of a circular orbit sweeps πr²")
    }

    func testOutOfOrderRecordResetsInsteadOfLying() {
        var sweep = KeplerSweep(horizon: 100)
        sweep.record(time: 0, position: SIMD3(1, 0, 0))
        sweep.record(time: 1, position: SIMD3(0, 1, 0))
        XCTAssertEqual(sweep.samples.count, 2)
        // Time runs backwards (reset, body swap): history must clear.
        sweep.record(time: 0.5, position: SIMD3(1, 1, 0))
        XCTAssertEqual(sweep.samples.count, 1)
        XCTAssertEqual(sweep.area(from: 0, to: 1), 0)
    }

    func testArcInterpolatesWindowEdges() {
        var sweep = KeplerSweep(horizon: 100)
        sweep.record(time: 0, position: SIMD3(0, 0, 0))
        sweep.record(time: 2, position: SIMD3(2, 0, 0))
        let arc = sweep.arc(from: 0.5, to: 1.5)
        XCTAssertEqual(arc.count, 2)
        XCTAssertEqual(arc.first?.x ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(arc.last?.x ?? -1, 1.5, accuracy: 1e-9)
    }
}
