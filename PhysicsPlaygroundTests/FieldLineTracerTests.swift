//
//  FieldLineTracerTests.swift
//  PhysicsPlaygroundTests
//
//  Tests for the RK4 field-line tracer. Like all physics tests these run
//  on plain Swift values — no rendering involved.
//

import XCTest
import simd
@testable import PhysicsPlayground

final class FieldLineTracerTests: XCTestCase {

    private var config: FieldLineTracer.Config {
        var config = FieldLineTracer.Config()
        config.boundsCenter = .zero
        config.boundsRadius = 1.0
        return config
    }

    /// Around a single positive charge the field is radial, so every traced
    /// line must stay on its own radial ray from seed to end.
    func testLinesFromIsolatedPositiveChargeAreRadial() {
        let charge = PointCharge(position: .zero, charge: 1e-6)
        let lines = FieldLineTracer.trace(charges: [charge], config: config)

        XCTAssertEqual(lines.count, config.seedsPerCharge)
        for line in lines {
            let seedDirection = simd_normalize(line.first! - charge.position)
            for point in line {
                let direction = simd_normalize(point - charge.position)
                XCTAssertEqual(simd_dot(direction, seedDirection), 1.0, accuracy: 1e-6,
                               "field line around a lone charge must be a straight radial ray")
            }
            // Lines run outward until they leave the bounds.
            XCTAssertGreaterThan(simd_length(line.last!), config.boundsRadius - config.stepSize)
        }
    }

    /// In a dipole, lines leaving the positive charge toward the negative one
    /// must terminate on it (that's the defining picture of field lines).
    func testDipoleLinesTerminateOnNegativeCharge() {
        let positive = PointCharge(position: SIMD3(-0.15, 0, 0), charge: 1e-6)
        let negative = PointCharge(position: SIMD3(0.15, 0, 0), charge: -1e-6)
        let lines = FieldLineTracer.trace(charges: [positive, negative], config: config)

        let terminating = lines.filter { line in
            simd_distance(line.last!, negative.position) < config.terminationRadius + config.stepSize
        }
        XCTAssertGreaterThanOrEqual(terminating.count, config.seedsPerCharge / 3,
                                    "a healthy fraction of dipole lines must land on the negative charge")
    }

    /// Every charge gets seeded all around, so a dipole draws lines from BOTH
    /// charges — including outward from the negative one's far side, which
    /// previously showed no lines at all.
    func testEveryChargeRadiatesLinesInAllDirections() {
        let positive = PointCharge(position: SIMD3(-0.15, 0, 0), charge: 1e-6)
        let negative = PointCharge(position: SIMD3(0.15, 0, 0), charge: -1e-6)
        let lines = FieldLineTracer.trace(charges: [positive, negative], config: config)

        XCTAssertEqual(lines.count, 2 * config.seedsPerCharge)

        for charge in [positive, negative] {
            // Lines seeded on this charge…
            let own = lines.filter { simd_distance($0.first!, charge.position) < config.seedRadius * 1.5 }
            XCTAssertEqual(own.count, config.seedsPerCharge)
            // …must start off in genuinely different directions: some toward
            // the partner charge (+x side for the positive), some away.
            let startDirections = own.map { simd_normalize($0.first! - charge.position) }
            XCTAssertTrue(startDirections.contains { $0.x > 0.3 })
            XCTAssertTrue(startDirections.contains { $0.x < -0.3 })
            XCTAssertTrue(startDirections.contains { $0.y > 0.3 })
            XCTAssertTrue(startDirections.contains { $0.y < -0.3 })
        }
    }

    /// A negative-only scene still draws lines (traced backwards along −E).
    func testNegativeOnlySceneStillProducesLines() {
        let charge = PointCharge(position: .zero, charge: -1e-6)
        let lines = FieldLineTracer.trace(charges: [charge], config: config)
        XCTAssertEqual(lines.count, config.seedsPerCharge)
        // −E points away from a negative charge, so these trace outward too.
        for line in lines {
            XCTAssertGreaterThan(simd_length(line.last!), simd_length(line.first!))
        }
    }

    /// Unit-speed parametrization: consecutive points are ~stepSize apart.
    func testPointSpacingMatchesStepSize() {
        let charge = PointCharge(position: .zero, charge: 1e-6)
        let lines = FieldLineTracer.trace(charges: [charge], config: config)
        for line in lines {
            for i in 1..<line.count {
                let spacing = simd_distance(line[i], line[i - 1])
                XCTAssertEqual(spacing, config.stepSize, accuracy: config.stepSize * 0.5)
            }
        }
    }

    /// Every traced point is finite and every line respects maxSteps.
    func testLinesAreFiniteAndBounded() {
        let charges = [
            PointCharge(position: SIMD3(-0.1, 0.05, 0), charge: 2e-6),
            PointCharge(position: SIMD3(0.12, -0.03, 0.05), charge: -1e-6),
            PointCharge(position: SIMD3(0, 0.1, -0.1), charge: 0.5e-6),
        ]
        let lines = FieldLineTracer.trace(charges: charges, config: config)
        XCTAssertFalse(lines.isEmpty)
        for line in lines {
            XCTAssertLessThanOrEqual(line.count, config.maxSteps + 1)
            for point in line {
                XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite)
            }
        }
    }

    /// The Fibonacci sphere must give unit vectors spread over both hemispheres.
    func testFibonacciSphereCoverage() {
        let directions = FieldLineTracer.fibonacciSphere(count: 20)
        XCTAssertEqual(directions.count, 20)
        for direction in directions {
            XCTAssertEqual(simd_length(direction), 1.0, accuracy: 1e-9)
        }
        XCTAssertTrue(directions.contains { $0.y > 0.5 })
        XCTAssertTrue(directions.contains { $0.y < -0.5 })
    }

    /// No charges → no lines (and no crash).
    func testNoChargesProducesNoLines() {
        XCTAssertTrue(FieldLineTracer.trace(charges: [], config: config).isEmpty)
    }
}
