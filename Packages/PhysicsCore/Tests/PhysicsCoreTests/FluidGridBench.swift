//
//  FluidGridBench.swift
//  PhysicsCoreTests — timing probe (not a correctness test)
//

import XCTest
import simd
@testable import PhysicsCore

final class FluidGridBench: XCTestCase {
    /// Times one solver step at the size the wind tunnel actually runs,
    /// so the frame budget is a measured number rather than a hope.
    func testStepCostAtAppResolution() {
        var grid = FluidGrid(nx: 50, ny: 21, nz: 30, h: 0.042,
                             origin: SIMD3(-1.05, -0.44, -0.63),
                             inflowSpeed: 1.0,
                             vorticityConfinement: 9.0,
                             pressureIterations: 24)
        grid.addSolidSphere(center: SIMD3(-0.3, 0, 0), radius: 0.13)
        grid.step(dt: 1.0 / 60.0)   // warm

        let iterations = 8
        let start = Date()
        for _ in 0..<iterations { grid.step(dt: 1.0 / 60.0) }
        let ms = Date().timeIntervalSince(start) / Double(iterations) * 1000
        print("FLUIDGRID step: \(String(format: "%.2f", ms)) ms/step  (\(grid.nx)x\(grid.ny)x\(grid.nz))")

                // A probe, not a budget guard: the number that matters is the
                // release one (`swift test -c release --filter FluidGridBench`),
                // and a debug build runs two orders of magnitude slower. What is
                // asserted is that the solver stayed finite under this load.
        XCTAssertTrue(ms.isFinite && ms > 0)
        XCTAssertLessThan(grid.maxDivergence * grid.h / grid.inflowSpeed, 1e-3)
    }
}
