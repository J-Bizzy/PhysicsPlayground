//
//  PotentialFlowTests.swift
//  PhysicsCoreTests
//
//  The flow is exact, so the tests are exacting: the classical features
//  (2U at the top, stagnation at front and back, no penetration) to near
//  machine precision, and the two famous theorems recovered numerically —
//  Kutta–Joukowski lift and d'Alembert's zero drag both emerge from
//  integrating the Bernoulli pressure around the surface.
//

import XCTest
import simd
@testable import PhysicsCore

final class PotentialFlowTests: XCTestCase {

    private let flow = CylinderFlow(freeStreamSpeed: 1.0, radius: 0.06)

    func testFarFieldRecoversFreeStream() {
        let v = flow.velocity(at: SIMD2(0, 8))
        XCTAssertEqual(v.x, 1.0, accuracy: 1e-4)
        XCTAssertEqual(v.y, 0.0, accuracy: 1e-4)
    }

    /// The cylinder surface is a streamline: zero radial velocity all the
    /// way around.
    func testNoPenetrationOnSurface() {
        for index in 0..<72 {
            let theta = Double(index) / 72 * 2 * .pi
            let normal = SIMD2(cos(theta), sin(theta))
            let point = flow.center + flow.radius * normal * (1 + 1e-12)
            let radialSpeed = simd_dot(flow.velocity(at: point), normal)
            XCTAssertEqual(radialSpeed, 0, accuracy: 1e-9,
                           "flow must slide along the surface at θ = \(theta)")
        }
    }

    /// Without spin: exactly 2U at the shoulders, rest at nose and tail.
    func testClassicSurfaceSpeeds() {
        XCTAssertEqual(flow.surfaceSpeed(atAngle: .pi / 2), 2.0, accuracy: 1e-12)
        XCTAssertEqual(flow.surfaceSpeed(atAngle: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(flow.surfaceSpeed(atAngle: .pi), 0, accuracy: 1e-12)

        let points = flow.stagnationPoints()
        XCTAssertEqual(points.count, 2)
        for point in points {
            XCTAssertEqual(flow.speed(at: point * (1 + 1e-12)), 0, accuracy: 1e-6)
        }
    }

    /// Spin moves the stagnation points to sin θ = Γ/(4πUa) — verified
    /// against the actual velocity field, not just the formula — and
    /// strong enough spin lifts them off the surface entirely.
    func testStagnationPointsFollowCirculation() {
        var spinning = flow
        spinning.circulation = 0.3
        let expectedSine = 0.3 / (4 * .pi * 1.0 * 0.06)
        let points = spinning.stagnationPoints()
        XCTAssertEqual(points.count, 2)
        for point in points {
            let sine = (point.y - spinning.center.y) / spinning.radius
            XCTAssertEqual(sine, expectedSine, accuracy: 1e-9)
            // The field itself must actually rest there.
            XCTAssertEqual(spinning.speed(at: point * (1 + 1e-12)), 0, accuracy: 1e-6)
        }

        spinning.circulation = 4 * .pi * 1.0 * 0.06 * 1.5
        XCTAssertTrue(spinning.stagnationPoints().isEmpty,
                      "supercritical spin has no surface stagnation point")
    }

    /// Kutta–Joukowski, *derived*: integrating the Bernoulli surface
    /// pressure recovers L' = ρUΓ along −y…
    func testPressureIntegrationRecoversKuttaJoukowskiLift() {
        var spinning = flow
        spinning.circulation = 0.8
        let force = spinning.integratedPressureForce()
        XCTAssertEqual(force.y, -1.225 * 1.0 * 0.8, accuracy: 1.225 * 0.8 * 0.005)
    }

    /// …and exactly zero drag — d'Alembert's paradox.
    func testDAlembertZeroDrag() {
        var spinning = flow
        spinning.circulation = 0.8
        let force = spinning.integratedPressureForce()
        XCTAssertEqual(force.x, 0, accuracy: 1e-9,
                       "ideal flow exerts no drag, however wrong that felt in 1752")
    }

    /// The vortex is real: the velocity line integral around any loop
    /// enclosing the cylinder returns Γ.
    func testLineIntegralRecoversCirculation() {
        var spinning = flow
        spinning.circulation = 0.5
        let loopRadius = 5 * spinning.radius
        let samples = 5000
        var integral = 0.0
        for index in 0..<samples {
            let theta = Double(index) / Double(samples) * 2 * .pi
            let point = spinning.center + loopRadius * SIMD2(cos(theta), sin(theta))
            let tangent = SIMD2(-sin(theta), cos(theta))
            integral += simd_dot(spinning.velocity(at: point), tangent)
                * loopRadius * 2 * .pi / Double(samples)
        }
        XCTAssertEqual(integral, 0.5, accuracy: 0.5 * 1e-3)
    }

    func testInsideCylinderIsStill() {
        XCTAssertEqual(flow.velocity(at: flow.center), .zero)
        XCTAssertEqual(flow.velocity(at: flow.center + SIMD2(0.03, 0)), .zero)
    }
}
