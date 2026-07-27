//
//  SurfacePressureTests.swift
//  PhysicsCoreTests
//
//  The pressure skin has to be read off the SOLVED flow, not invented,
//  so these run the real fluid solver and check the coefficient against
//  what Bernoulli requires: zero in an undisturbed stream, one at a
//  stagnation point, negative where the flow speeds up.
//

import XCTest
import simd
@testable import PhysicsCore

final class SurfacePressureTests: XCTestCase {

    /// A small tunnel with a blockage in the middle of it.
    private func solvedTunnel(withBlock: Bool,
                              sweeps: Int = 260) -> (FlowField, Double) {
        let speed = 1.0
        var grid = FluidGrid(nx: 30, ny: 14, nz: 14, h: 0.05,
                             origin: SIMD3(0, 0, 0))
        grid.inflowSpeed = speed
        grid.pressureIterations = sweeps
        if withBlock {
            // A solid block across the middle of the section, marked the
            // same way the module marks a test body.
            grid.addSolidSphere(center: SIMD3(0.68, 0.35, 0.35), radius: 0.14)
        }
        for _ in 0..<26 { grid.step(dt: 0.02) }
        return (grid.exportField(), speed)
    }

    // MARK: The coefficient itself

    /// Undisturbed stream: |v| = U everywhere, so Cp = 0 everywhere.
    func testUniformStreamHasZeroPressureCoefficient() {
        let (field, speed) = solvedTunnel(withBlock: false)
        for point in [SIMD3<Double>(0.4, 0.35, 0.35),
                      SIMD3(0.8, 0.3, 0.4),
                      SIMD3(1.1, 0.4, 0.3)] {
            let cp = SurfacePressure.coefficient(
                at: point, normal: SIMD3(0, 1, 0), in: field, freestream: speed)
            XCTAssertNotNil(cp)
            XCTAssertEqual(cp!, 0, accuracy: 0.05,
                           "nothing in the way means no pressure change")
        }
    }

    /// The nose of a blockage is a stagnation region: the flow is brought
    /// to rest, so Cp climbs toward its theoretical maximum of 1.
    func testNoseOfABlockageReadsHighPressure() {
        let (field, speed) = solvedTunnel(withBlock: true)
        // Just upstream of the slab's leading face, normal into the wind.
        let nose = SIMD3<Double>(0.68 - 0.14, 0.35, 0.35)
        let cp = SurfacePressure.coefficient(
            at: nose, normal: SIMD3(-1, 0, 0), in: field, freestream: speed)
        XCTAssertNotNil(cp)
        XCTAssertGreaterThan(cp!, 0.25, "the nose is being pushed on")
        XCTAssertLessThanOrEqual(cp!, SurfacePressure.maximumCp + 1e-9,
                                 "Cp can never exceed 1 in incompressible flow")
    }

    /// Beside the blockage the flow has to speed up to get past, so the
    /// pressure there DROPS below free stream — the same effect that
    /// lifts a wing.
    func testShoulderOfABlockageReadsLowPressure() {
        let (field, speed) = solvedTunnel(withBlock: true)
        // Just above the sphere's top, normal pointing up and out.
        let shoulder = SIMD3<Double>(0.68, 0.35 + 0.14, 0.35)
        let cp = SurfacePressure.coefficient(
            at: shoulder, normal: SIMD3(0, 1, 0), in: field, freestream: speed)
        XCTAssertNotNil(cp)
        XCTAssertLessThan(cp!, 0, "accelerated flow means suction")
    }

    /// The reason `boundaryShells` exists: read the FIRST fluid cell off
    /// a voxelised wall and everything looks like a stagnation point,
    /// because the solver has zeroed the flux through the faces touching
    /// the mask. The shoulder flips sign purely on where you sample.
    func testReadingTheFirstCellOffTheWallWouldMisreportSuctionAsPressure() {
        let (field, speed) = solvedTunnel(withBlock: true)
        let shoulder = SIMD3<Double>(0.68, 0.35 + 0.14, 0.35)
        let naive = SurfacePressure.coefficient(
            at: shoulder, normal: SIMD3(0, 1, 0), in: field,
            freestream: speed, boundaryShells: 0)!
        let corrected = SurfacePressure.coefficient(
            at: shoulder, normal: SIMD3(0, 1, 0), in: field,
            freestream: speed, boundaryShells: 2)!
        // The sign FLIPS on where you sample — which is the whole
        // reason the parameter exists. Naively you would paint this
        // shoulder red (pressure) when it is really blue (suction).
        XCTAssertGreaterThan(naive, 0.2, "the wall drags the first cells to a crawl")
        XCTAssertLessThan(corrected, 0, "…and the real flow out there is fast")
    }

    /// The nose is at higher pressure than the shoulder. This is the
    /// whole visual claim of the skin — red in front, blue on top —
    /// stated as an inequality the solver has to satisfy.
    func testNoseIsAlwaysAtHigherPressureThanTheShoulder() {
        let (field, speed) = solvedTunnel(withBlock: true)
        let nose = SurfacePressure.coefficient(
            at: SIMD3(0.68 - 0.14, 0.35, 0.35),
            normal: SIMD3(-1, 0, 0), in: field, freestream: speed)!
        let shoulder = SurfacePressure.coefficient(
            at: SIMD3(0.68, 0.35 + 0.14, 0.35),
            normal: SIMD3(0, 1, 0), in: field, freestream: speed)!
        XCTAssertGreaterThan(nose, shoulder + 0.2)
    }

    /// Cp is DIMENSIONLESS: it must not care how fast the tunnel is
    /// running, only about the shape. Scaling the whole velocity field
    /// and the free stream together leaves it unchanged.
    func testCoefficientIsIndependentOfTunnelSpeed() {
        let (field, speed) = solvedTunnel(withBlock: true)
        let point = SIMD3<Double>(0.68, 0.35 + 0.14, 0.35)
        let normal = SIMD3<Double>(0, 1, 0)
        let slow = SurfacePressure.coefficient(
            at: point, normal: normal, in: field, freestream: speed)!

        // The same field with every velocity doubled, and U doubled too.
        let doubled = FlowField(
            nx: field.nx, ny: field.ny, nz: field.nz, h: field.h,
            origin: field.origin, cells: field.cells.map { $0 * 2 },
            solid: field.solid)
        let fast = SurfacePressure.coefficient(
            at: point, normal: normal, in: doubled, freestream: speed * 2)!
        XCTAssertEqual(slow, fast, accuracy: 1e-9)
    }

    /// A still tunnel has no defined coefficient rather than a divide by
    /// zero.
    func testZeroFreestreamGivesNoCoefficient() {
        let (field, _) = solvedTunnel(withBlock: false)
        XCTAssertNil(SurfacePressure.coefficient(
            at: SIMD3(0.5, 0.35, 0.35), normal: SIMD3(0, 1, 0),
            in: field, freestream: 0))
    }

    // MARK: The colour ramp

    /// Free-stream pressure sits exactly in the middle of the ramp, so
    /// the neutral colour always means "unchanged".
    func testRampPinsZeroAtTheMiddle() {
        XCTAssertEqual(SurfacePressure.rampPosition(0), 0.5, accuracy: 1e-12)
    }

    func testRampRunsFromSuctionToStagnation() {
        XCTAssertEqual(SurfacePressure.rampPosition(1.0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(SurfacePressure.rampPosition(-1.5, span: 1.5), 0, accuracy: 1e-12)
    }

    func testRampIsMonotonicAndClamped() {
        var previous = -1.0
        for cp in stride(from: -3.0, through: 2.0, by: 0.25) {
            let position = SurfacePressure.rampPosition(cp)
            XCTAssertGreaterThanOrEqual(position, previous - 1e-12)
            XCTAssertTrue((0...1).contains(position))
            previous = position
        }
    }

    /// The gauge pressure is the coefficient times the dynamic pressure —
    /// so a stagnation point on a 1.225 kg/m³, 1 m/s stream reads
    /// ½·1.225·1² = 0.6125 Pa above ambient.
    func testGaugePressureIsCpTimesDynamicPressure() {
        XCTAssertEqual(
            SurfacePressure.gaugePressure(cp: 1, density: 1.225, freestream: 1),
            0.6125, accuracy: 1e-12)
        XCTAssertEqual(
            SurfacePressure.gaugePressure(cp: -0.5, density: 1.225, freestream: 2),
            -1.225, accuracy: 1e-12)
    }
}
