//
//  WindTunnelModelTests.swift
//  PhysicsPlaygroundTests
//
//  Tests for the wind tunnel app state: the flow is assembled from the
//  controls, placement clamps work, the probe reads exact values at
//  known points, spin maps to lift and rpm, and reset restores the
//  opening scene. Flow math itself is covered in PhysicsCore's
//  PotentialFlowTests.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class WindTunnelModelTests: XCTestCase {

    func testFlowIsBuiltFromControls() {
        let model = WindTunnelModel()
        model.windSpeed = 1.4
        model.cylinderRadius = 0.08
        model.circulation = 0.6

        XCTAssertEqual(model.flow.freeStreamSpeed, 1.4)
        XCTAssertEqual(model.flow.radius, 0.08)
        XCTAssertEqual(model.flow.circulation, 0.6)
        XCTAssertEqual(model.flow.center, model.cylinderCenter)
    }

    func testCylinderClampsInsideSection() {
        let model = WindTunnelModel()
        model.moveCylinder(to: SIMD2(5, -5))
        let center = model.cylinderCenter
        XCTAssertLessThanOrEqual(abs(center.x),
                                 WindTunnelModel.halfLength - model.cylinderRadius - 0.05 + 1e-9)
        XCTAssertLessThanOrEqual(abs(center.y),
                                 WindTunnelModel.halfWidth - model.cylinderRadius - 0.02 + 1e-9)
    }

    /// The probe can't sit inside the metal: dropping it onto the
    /// cylinder pushes it just outside the surface.
    func testProbeIsPushedOutOfCylinder() {
        let model = WindTunnelModel()
        model.moveProbe(to: model.cylinderCenter)
        let distance = simd_distance(model.probePosition, model.cylinderCenter)
        XCTAssertEqual(distance, model.cylinderRadius + 0.015, accuracy: 1e-9)
    }

    /// Parked on the axis just ahead of the cylinder, the probe reads the
    /// exact on-axis solution v = U(1 − a²/r²) and its Bernoulli Cp.
    func testProbeReadsExactOnAxisValues() {
        let model = WindTunnelModel()
        model.circulation = 0
        let r = model.cylinderRadius + 0.0151
        model.moveProbe(to: model.cylinderCenter - SIMD2(r, 0))

        let expectedSpeed = model.windSpeed
            * (1 - model.cylinderRadius * model.cylinderRadius / (r * r))
        let readout = model.probeReadout
        XCTAssertEqual(readout.speed, expectedSpeed, accuracy: 1e-9)
        XCTAssertEqual(readout.pressureCoefficient,
                       1 - pow(expectedSpeed / model.windSpeed, 2), accuracy: 1e-9)
    }

    /// Lift follows Kutta–Joukowski exactly, and its sign flips with spin.
    func testLiftMatchesKuttaJoukowski() {
        let model = WindTunnelModel()
        model.windSpeed = 1.0
        model.circulation = 0.8
        XCTAssertEqual(model.liftPerSpan, -1.225 * 1.0 * 0.8, accuracy: 1e-9)
        model.circulation = -0.8
        XCTAssertEqual(model.liftPerSpan, 1.225 * 1.0 * 0.8, accuracy: 1e-9)
        model.circulation = 0
        XCTAssertEqual(model.liftPerSpan, 0)
    }

    /// Spin rpm is the rotation whose surface keeps pace with Γ:
    /// ω = Γ/(2πa²), rpm = ω·60/2π.
    func testSpinRPMMapping() {
        let model = WindTunnelModel()
        model.cylinderRadius = 0.06
        model.circulation = 0.5
        let omega = 0.5 / (2 * .pi * 0.06 * 0.06)
        XCTAssertEqual(model.spinRPM, omega * 60 / (2 * .pi), accuracy: 1e-9)
    }

    /// Shrinking the section limits when the radius grows: a fat cylinder
    /// near the wall gets pulled back in.
    func testGrowingRadiusRepositionsCylinder() {
        let model = WindTunnelModel()
        model.moveCylinder(to: SIMD2(0, WindTunnelModel.halfWidth))
        let before = abs(model.cylinderCenter.y)
        model.cylinderRadius = WindTunnelModel.radiusRange.upperBound
        XCTAssertLessThan(abs(model.cylinderCenter.y), before,
                          "a bigger cylinder must sit farther from the wall")
    }

    func testResetRestoresOpeningScene() {
        let model = WindTunnelModel()
        model.windSpeed = 1.8
        model.cylinderRadius = 0.1
        model.circulation = -1.0
        model.moveCylinder(to: SIMD2(0.3, 0.2))
        model.showStreamlines = false
        model.showParticles = false
        model.isPaused = true
        model.timeScale = 0.2

        model.reset()

        XCTAssertEqual(model.windSpeed, 1.0)
        XCTAssertEqual(model.cylinderRadius, 0.06)
        XCTAssertEqual(model.cylinderCenter, SIMD2(-0.3, 0))
        XCTAssertEqual(model.circulation, 0)
        XCTAssertTrue(model.showStreamlines)
        XCTAssertTrue(model.showParticles)
        XCTAssertFalse(model.isPaused)
        XCTAssertEqual(model.timeScale, 1.0)
    }

    /// The drag lab: F = ½ρv²CdA from the current body, size, and wind —
    /// and reset() puts the exact-flow cylinder back in the section.
    @MainActor
    func testDragForceMatchesTheDragEquation() {
        let model = WindTunnelModel()
        model.testBody = .sphere
        model.windSpeed = 2.0
        model.cylinderRadius = 0.06

        let expected = 0.5 * WindTunnelModel.airDensity * 4.0
            * DragBody.sphere.dragCoefficient * Double.pi * 0.0036
        XCTAssertEqual(model.dragForce, expected, accuracy: 1e-12)

        // Streamlining at the same size and wind: >10× less drag.
        model.testBody = .teardrop
        XCTAssertLessThan(model.dragForce, expected / 10)

        model.reset()
        XCTAssertEqual(model.testBody, .cylinder)
        XCTAssertTrue(model.obstacles.spheres.isEmpty)
    }
}
