//
//  TestChargeDynamicsTests.swift
//  PhysicsCoreTests
//
//  Tests for the velocity-Verlet probe integrator. Because the integrator
//  takes the field as a closure, we can feed it analytic fields with exact
//  closed-form trajectories and check against those.
//

import XCTest
import simd
@testable import PhysicsCore

final class TestChargeDynamicsTests: XCTestCase {

    typealias Probe = TestChargeDynamics.ProbeState

    // Realistic probe values (10 nC, 0.5 g) — the same ones the app's
    // FieldModel uses, inlined here so PhysicsCore tests stay app-independent.
    private let probeChargeMagnitude = 1e-8
    private let probeMass = 5e-4

    /// Zero field → Newton's first law: straight line at constant velocity.
    func testZeroFieldGivesUniformMotion() {
        var state = Probe(position: .zero, velocity: SIMD3(0.3, -0.1, 0.2))
        let dt = 0.01
        for _ in 0..<100 {
            state = TestChargeDynamics.step(state, chargeToMassRatio: 1, dt: dt) { _ in .zero }
        }
        // After 1 s: r = v·t exactly.
        XCTAssertEqual(state.position.x, 0.3, accuracy: 1e-12)
        XCTAssertEqual(state.position.y, -0.1, accuracy: 1e-12)
        XCTAssertEqual(state.position.z, 0.2, accuracy: 1e-12)
        XCTAssertEqual(state.velocity, SIMD3(0.3, -0.1, 0.2))
    }

    /// Uniform field → constant acceleration: velocity Verlet reproduces the
    /// analytic parabola r = r₀ + v₀t + ½at² *exactly* (it's exact for
    /// constant acceleration — a property worth pinning down).
    func testUniformFieldMatchesAnalyticParabola() {
        let qOverM = 2.0
        let field = SIMD3<Double>(0, -5, 0)     // "gravity"-like uniform E
        let a = qOverM * field                  // (0, -10, 0)
        let v0 = SIMD3<Double>(1, 2, 0)

        var state = Probe(position: .zero, velocity: v0)
        let dt = 0.005
        let steps = 200
        for _ in 0..<steps {
            state = TestChargeDynamics.step(state, chargeToMassRatio: qOverM, dt: dt) { _ in field }
        }

        let t = Double(steps) * dt              // 1 s
        let expected = v0 * t + 0.5 * a * t * t
        XCTAssertEqual(state.position.x, expected.x, accuracy: 1e-10)
        XCTAssertEqual(state.position.y, expected.y, accuracy: 1e-10)
        XCTAssertEqual(state.velocity.y, (v0 + a * t).y, accuracy: 1e-10)
    }

    /// Total energy E = ½mv² + qV must be (nearly) conserved as the probe
    /// falls toward a negative point charge — the symplectic property that
    /// justifies choosing velocity Verlet.
    func testEnergyConservationNearPointCharge() {
        let source = PointCharge(position: .zero, charge: -1e-6)
        let q = probeChargeMagnitude
        let m = probeMass

        func totalEnergy(_ state: Probe) -> Double {
            let kinetic = 0.5 * m * simd_length_squared(state.velocity)
            let potential = q * ElectricField.potential(at: state.position, dueTo: source)
            return kinetic + potential
        }

        var state = Probe(position: SIMD3(0.3, 0, 0), velocity: SIMD3(0, 0.05, 0))
        let initialEnergy = totalEnergy(state)

        // Fine steps: near the close approach the force gradient is steep,
        // and Verlet's energy error scales with h².
        for _ in 0..<10000 {
            state = TestChargeDynamics.step(state, chargeToMassRatio: q / m, dt: 5e-4) { point in
                ElectricField.vector(at: point, dueTo: source)
            }
            // Stop before entering the singular core, as the app does.
            if simd_length(state.position) < 0.06 { break }
        }

        let drift = abs(totalEnergy(state) - initialEnergy)
        XCTAssertLessThan(drift, abs(initialEnergy) * 0.01,
                          "energy must drift less than 1% over the trajectory")
    }

    /// A positive probe accelerates away from a positive source charge along
    /// the line joining them (radial repulsion).
    func testProbeRepelsRadiallyFromPositiveCharge() {
        let source = PointCharge(position: .zero, charge: 1e-6)
        var state = Probe(position: SIMD3(0.2, 0, 0))
        for _ in 0..<200 {
            state = TestChargeDynamics.step(
                state,
                chargeToMassRatio: probeChargeMagnitude / probeMass,
                dt: 0.005
            ) { ElectricField.vector(at: $0, dueTo: source) }
        }
        XCTAssertGreaterThan(state.position.x, 0.2, "must move outward")
        XCTAssertEqual(state.position.y, 0, accuracy: 1e-12)
        XCTAssertEqual(state.position.z, 0, accuracy: 1e-12)
        XCTAssertGreaterThan(state.velocity.x, 0)
    }

    /// The substepped variant covers the same time span as single steps.
    func testSubstepsCoverSameTimeSpan() {
        let field: (SIMD3<Double>) -> SIMD3<Double> = { _ in SIMD3(0, -3, 0) }
        let single = TestChargeDynamics.step(
            Probe(position: .zero), chargeToMassRatio: 1, dt: 0.02, field: field
        )
        let substepped = TestChargeDynamics.step(
            Probe(position: .zero), chargeToMassRatio: 1, dt: 0.02, substeps: 4, field: field
        )
        // For a uniform field both are exact, so they must agree.
        XCTAssertEqual(single.position.y, substepped.position.y, accuracy: 1e-12)
        XCTAssertEqual(single.velocity.y, substepped.velocity.y, accuracy: 1e-12)
    }

    /// Pure B: the probe rides an exact cyclotron circle of radius
    /// r = v/((q/m)·B) at constant speed.
    func testBorisCyclotronCircle() {
        let ratio = 2.0, b = 3.0, speed = 0.5
        var state = TestChargeDynamics.ProbeState(
            position: .zero, velocity: SIMD3(speed, 0, 0))
        let omega = ratio * b
        let period = 2 * Double.pi / omega
        let dt = period / 4000
        for _ in 0..<4000 {
            state = TestChargeDynamics.stepLorentz(
                state, chargeToMassRatio: ratio, dt: dt, substeps: 1,
                electricField: { _ in .zero },
                magneticField: SIMD3(0, b, 0))
            XCTAssertEqual(simd_length(state.velocity), speed, accuracy: 1e-12,
                           "magnetic force never changes speed")
        }
        // One full period returns home.
        XCTAssertEqual(simd_length(state.position), 0, accuracy: speed * period * 1e-4)
        // Radius check via the farthest excursion ≈ diameter.
        var probe = TestChargeDynamics.ProbeState(
            position: .zero, velocity: SIMD3(speed, 0, 0))
        var maxR = 0.0
        for _ in 0..<2000 {
            probe = TestChargeDynamics.stepLorentz(
                probe, chargeToMassRatio: ratio, dt: dt, substeps: 1,
                electricField: { _ in .zero },
                magneticField: SIMD3(0, b, 0))
            maxR = max(maxR, simd_length(probe.position))
        }
        XCTAssertEqual(maxR, 2 * speed / omega, accuracy: 2 * speed / omega * 1e-3,
                       "diameter = 2mv/qB")
    }
}
