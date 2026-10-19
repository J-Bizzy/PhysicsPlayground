//
//  KeplerOrbitTests.swift
//  The two-body problem in time: Kepler's equation solved to the last
//  bits, energy and angular momentum constant along every orbit, a period
//  that closes, a Hohmann departure that matches the textbook, a transfer
//  that arrives at its far end exactly, and Pluto's orbit from JPL's
//  mean elements.
//

import XCTest
import simd
@testable import PhysicsCore

final class KeplerOrbitTests: XCTestCase {

    func testKeplersEquationIsSolvedForEveryBoundOrbit() {
        for e in stride(from: 0.0, through: 0.95, by: 0.05) {
            for m in stride(from: -7.0, through: 7.0, by: 0.173) {
                let anomaly = KeplerOrbit.eccentricAnomaly(meanAnomaly: m, eccentricity: e)
                XCTAssertEqual(anomaly - e * sin(anomaly), m, accuracy: 1e-12, "e \(e), M \(m)")
            }
        }
    }

    private func ellipse(e: Double, mu: Double = 0.3795) -> KeplerOrbit {
        let normal = simd_normalize(SIMD3<Double>(0.2, 1, 0.1))
        let periapsis = simd_normalize(simd_cross(normal, SIMD3(0, 0, 1)))
        let rp = 0.4
        let ra = rp * (1 + e) / (1 - e)
        return KeplerOrbit(frame: ApsisFrame(periapsisDirection: periapsis, orbitNormal: normal,
                                             periapsisRadius: rp, apoapsisRadius: ra,
                                             trueAnomaly: 0.3, mu: mu), epoch: 1.7)
    }

    func testEnergyAndAngularMomentumAreConstantAndThePeriodCloses() {
        for e in [0.0, 0.3, 0.8] {
            let orbit = ellipse(e: e)
            let start = orbit.state(at: orbit.epoch)
            let h0 = simd_cross(start.position, start.velocity)
            for k in 0...40 {
                let t = orbit.epoch + Double(k) * 0.137
                let s = orbit.state(at: t)
                let energy = simd_length_squared(s.velocity) / 2 - orbit.mu / simd_length(s.position)
                XCTAssertEqual(energy, orbit.specificEnergy, accuracy: 1e-10)
                XCTAssertLessThan(simd_distance(simd_cross(s.position, s.velocity), h0), 1e-10)
            }
            let around = orbit.state(at: orbit.epoch + orbit.period)
            XCTAssertLessThan(simd_distance(around.position, start.position), 1e-10)
            // The state reproduces the elements it was built from.
            let elements = OrbitalElements.from(position: start.position, velocity: start.velocity,
                                                mu: orbit.mu)!
            XCTAssertEqual(elements.eccentricity, e, accuracy: 1e-10)
        }
    }

    func testPeriapsisToApoapsisIsHalfAPeriod() {
        let orbit = ellipse(e: 0.5)
        XCTAssertEqual(orbit.timeOfFlight(from: 0, to: .pi), orbit.period / 2, accuracy: 1e-12)
    }

    /// Earth to Mars: the departure burn is 2.94 km/s.
    func testAHohmannDepartureFromEarthToMars() throws {
        let au = CelestialBody.astronomicalUnit
        let mu = 1.32712440018e20
        let earth = SIMD3<Double>(au, 0, 0)
        let mars = SIMD3<Double>(-1.523679 * au, 0, 0)
        let transfer = try XCTUnwrap(KeplerOrbit.reaching(apoapsis: mars, through: earth,
                                                          sense: SIMD3(0, 1, 0), mu: mu, at: 0))
        let departure = transfer.state(at: 0)
        let circular = (mu / au).squareRoot()
        XCTAssertEqual(simd_length(departure.velocity) - circular, 2943, accuracy: 15)
        XCTAssertEqual(transfer.eccentricity, (1.523679 - 1) / (1.523679 + 1), accuracy: 1e-12)
    }

    /// A transfer arrives exactly at its far end, at rest radially.
    func testATransferArrivesAtItsApoapsisExactly() throws {
        let mu = 0.3795
        let portal = SIMD3<Double>(-0.9, -0.3, 2.1)
        for departure in [SIMD3<Double>(0.4, 0.05, -0.2), SIMD3(-0.1, 0, -0.6), SIMD3(0.5, -0.1, 0.3)] {
            let transfer = try XCTUnwrap(KeplerOrbit.reaching(apoapsis: portal, through: departure,
                                                              sense: SIMD3(0, 1, 0), mu: mu, at: 2))
            XCTAssertLessThan(simd_distance(transfer.state(at: 2).position, departure), 1e-12)
            let arrival = transfer.state(at: transfer.apoapsisTime)
            XCTAssertLessThan(simd_distance(arrival.position, portal), 1e-9)
            XCTAssertEqual(simd_dot(arrival.position, arrival.velocity), 0, accuracy: 1e-9)
            XCTAssertGreaterThan(simd_dot(transfer.frame.orbitNormal, SIMD3(0, 1, 0)), 0)
        }
        XCTAssertNil(KeplerOrbit.reaching(apoapsis: SIMD3(1, 0, 0), through: SIMD3(0, 2, 0),
                                          sense: SIMD3(0, 0, 1), mu: mu, at: 0),
                     "a point beyond the far end is on no such ellipse")
    }

    // MARK: Pluto, and the Sun from there

    func testPlutosPerihelionWas1989At29Point66AU() {
        let pluto = MeanElements.pluto
        XCTAssertEqual(pluto.a.0 * (1 - pluto.e.0), 29.66, accuracy: 0.01)
        // M = L − ϖ crosses zero near 1989.7.
        let t = (pluto.perihelionLongitude.0 - pluto.meanLongitude.0)
            / (pluto.meanLongitude.1 - pluto.perihelionLongitude.1)
        XCTAssertEqual(2000 + 100 * t, 1989.7, accuracy: 0.3)
        let jd = MeanElements.j2000 + t * 36525
        XCTAssertEqual(simd_length(pluto.heliocentricEcliptic(julianDate: jd)), 29.66, accuracy: 0.02)
    }

    func testTheSunFromPlutoIsAMagnitudeMinusNineteenStarWithNoDisc() {
        XCTAssertEqual(MeanElements.julianDate(year: 2000, month: 1, day: 1), 2_451_544.5)
        let sun = MeanElements.pluto.sunSeen(julianDate: MeanElements.julianDate(year: 2026, month: 12, day: 15))
        XCTAssertEqual(sun.distance, 35.7, accuracy: 0.4)
        XCTAssertEqual(sun.magnitude, -19.0, accuracy: 0.1)
        XCTAssertEqual(sun.diameter * 180 / .pi * 3600, 54, accuracy: 1.5)
        XCTAssertEqual(simd_length(sun.direction), 1, accuracy: 1e-12)
    }
}
