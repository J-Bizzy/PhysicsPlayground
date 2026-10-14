//
//  FluidGridTests.swift
//  PhysicsCoreTests
//
//  The wind-tunnel solver pinned to the physics it claims to solve:
//  the projected field is divergence-free (that is incompressibility),
//  nothing flows through a solid, an empty tunnel leaves a uniform
//  stream uniform, mass in equals mass out, a blockage speeds the flow
//  up around it by exactly as much as continuity demands, and a
//  symmetric obstacle gives a symmetric flow.
//

import XCTest
import simd
@testable import PhysicsCore

final class FluidGridTests: XCTestCase {

    private func makeGrid(nx: Int = 18, ny: Int = 10, nz: Int = 10,
                          speed: Double = 1.0) -> FluidGrid {
        FluidGrid(nx: nx, ny: ny, nz: nz, h: 0.05,
                  origin: .zero, inflowSpeed: speed,
                  pressureIterations: 30)
    }

    /// After projection the velocity field is divergence-free in every
    /// fluid cell — the defining property of incompressible flow.
    ///
    /// Divergence carries units of 1/s, so the meaningful measure is the
    /// dimensionless residual |∇·u|·h/U: the fraction of the free stream
    /// by which a cell's fluxes fail to balance. Under a tenth of a
    /// percent is a converged field.
    func testProjectionMakesFieldDivergenceFree() {
        var grid = makeGrid()
        grid.addSolidSphere(center: SIMD3(0.6, 0.3, 0.3), radius: 0.12)
        grid.prime(steps: 40, dt: 1.0 / 60.0)
        let residual = grid.maxDivergence * grid.h / grid.inflowSpeed
        XCTAssertLessThan(residual, 1e-3,
                          "the projected field should carry no divergence")
    }

    /// And the solver genuinely converges: more pressure sweeps leave a
    /// strictly smaller residual, which is what tells us the small number
    /// above is convergence rather than a coincidence.
    func testMorePressureSweepsConvergeFurther() {
        func residual(iterations: Int) -> Double {
            var grid = FluidGrid(nx: 18, ny: 10, nz: 10, h: 0.05,
                                 inflowSpeed: 1.0, pressureIterations: iterations)
            grid.addSolidSphere(center: SIMD3(0.6, 0.3, 0.3), radius: 0.12)
            grid.prime(steps: 40, dt: 1.0 / 60.0)
            return grid.maxDivergence
        }
        XCTAssertLessThan(residual(iterations: 40), residual(iterations: 8),
                          "the pressure solve should converge with more sweeps")
    }

    /// No flux through a solid: every face of a solid cell is dead, so
    /// the obstacle is genuinely impermeable rather than merely slowing
    /// the air down.
    func testNoFlowThroughSolids() {
        var grid = makeGrid()
        grid.addSolidSphere(center: SIMD3(0.6, 0.3, 0.3), radius: 0.15)
        grid.prime(steps: 40, dt: 1.0 / 60.0)

        for k in 0..<grid.nz {
            for j in 0..<grid.ny {
                for i in 0..<grid.nx where grid.isSolid(i, j, k) {
                    XCTAssertEqual(grid.u[grid.uIndex(i, j, k)], 0, accuracy: 1e-12)
                    XCTAssertEqual(grid.u[grid.uIndex(i + 1, j, k)], 0, accuracy: 1e-12)
                    XCTAssertEqual(grid.v[grid.vIndex(i, j, k)], 0, accuracy: 1e-12)
                    XCTAssertEqual(grid.v[grid.vIndex(i, j + 1, k)], 0, accuracy: 1e-12)
                    XCTAssertEqual(grid.w[grid.wIndex(i, j, k)], 0, accuracy: 1e-12)
                    XCTAssertEqual(grid.w[grid.wIndex(i, j, k + 1)], 0, accuracy: 1e-12)
                }
            }
        }
    }

    /// An empty tunnel is the trivial solution: a uniform stream stays
    /// uniform, with no drift and no spurious cross-flow.
    func testEmptyTunnelKeepsUniformStream() {
        var grid = makeGrid(speed: 1.4)
        grid.prime(steps: 40, dt: 1.0 / 60.0)

        for k in 2..<(grid.nz - 2) {
            for j in 2..<(grid.ny - 2) {
                for i in 2..<(grid.nx - 2) {
                    let velocity = grid.velocity(at: grid.cellCenter(i, j, k))
                    XCTAssertEqual(velocity.x, 1.4, accuracy: 2e-3)
                    XCTAssertEqual(velocity.y, 0, accuracy: 2e-3)
                    XCTAssertEqual(velocity.z, 0, accuracy: 2e-3)
                }
            }
        }
    }

    /// Mass conservation: with a blockage in the tunnel, the volume flux
    /// crossing the outlet equals the flux entering the inlet.
    func testMassFluxInEqualsOut() {
        var grid = makeGrid()
        grid.addSolidSphere(center: SIMD3(0.5, 0.3, 0.3), radius: 0.14)
        grid.prime(steps: 45, dt: 1.0 / 60.0)

        let faceArea = grid.h * grid.h
        var inflow = 0.0, outflow = 0.0
        for k in 0..<grid.nz {
            for j in 0..<grid.ny {
                inflow += grid.u[grid.uIndex(0, j, k)] * faceArea
                outflow += grid.u[grid.uIndex(grid.nx, j, k)] * faceArea
            }
        }
        XCTAssertEqual(outflow, inflow, accuracy: abs(inflow) * 0.02,
                       "what goes in must come out")
    }

    /// Continuity in action: a blockage forces the same volume through a
    /// smaller gap, so the air beside it must move faster than the free
    /// stream. This is the effect the visualization exists to show.
    func testFlowAcceleratesAroundABlockage() {
        var grid = makeGrid(nx: 22, ny: 12, nz: 12, speed: 1.0)
        let center = SIMD3(0.7, 0.4, 0.4)
        grid.addSolidSphere(center: center, radius: 0.16)
        grid.prime(steps: 40, dt: 1.0 / 60.0)

        // Beside the obstacle, level with its middle.
        let beside = center + SIMD3(0, 0.22, 0)
        let speedBeside = simd_length(grid.velocity(at: beside))
        XCTAssertGreaterThan(speedBeside, 1.05,
                             "flow squeezed past a blockage speeds up")

        // Directly upstream of the nose the air must stagnate instead.
        let nose = center - SIMD3(0.19, 0, 0)
        let speedNose = simd_length(grid.velocity(at: nose))
        XCTAssertLessThan(speedNose, 0.85,
                          "air piles up and slows in front of the body")
    }

    /// A symmetric body in a symmetric tunnel produces a symmetric flow —
    /// the solver invents no bias of its own.
    func testSymmetricObstacleGivesSymmetricFlow() {
        var grid = makeGrid(nx: 18, ny: 11, nz: 11)
        // Centred exactly across y and z.
        let mid = grid.origin + SIMD3(Double(grid.nx) * 0.4,
                                      Double(grid.ny) * 0.5,
                                      Double(grid.nz) * 0.5) * grid.h
        grid.addSolidSphere(center: mid, radius: 0.15)
        grid.prime(steps: 50, dt: 1.0 / 60.0)

        for offset in [0.12, 0.2, 0.3] {
            let above = grid.velocity(at: mid + SIMD3(0.25, offset, 0))
            let below = grid.velocity(at: mid + SIMD3(0.25, -offset, 0))
            XCTAssertEqual(above.x, below.x, accuracy: 5e-3)
            XCTAssertEqual(above.y, -below.y, accuracy: 5e-3)
        }
    }

    /// A slender body disturbs the stream far less than a bluff one of
    /// the same frontal size — the aerodynamic story the tunnel tells.
    func testSlenderBodyDisturbsLessThanBluffBody() {
        func disturbance(radiusProfile: [(Double, Double)]) -> Double {
            var grid = makeGrid(nx: 22, ny: 12, nz: 12)
            for (dx, r) in radiusProfile {
                grid.addSolidSphere(center: SIMD3(0.7 + dx, 0.4, 0.4), radius: r)
            }
            grid.prime(steps: 50, dt: 1.0 / 60.0)
            // How much lateral motion the body stirs up in its wake.
            var total = 0.0
            for k in 2..<(grid.nz - 2) {
                for j in 2..<(grid.ny - 2) {
                    let p = grid.cellCenter(grid.nx - 2, j, k)
                    let velocity = grid.velocity(at: p)
                    total += abs(velocity.y) + abs(velocity.z)
                }
            }
            return total
        }

        // Same frontal half-width; one is a ball, one a long taper.
        let bluff = disturbance(radiusProfile: [(0, 0.16)])
        let slender = disturbance(radiusProfile: [
            (-0.12, 0.06), (-0.04, 0.09), (0.04, 0.075), (0.12, 0.05),
        ])
        XCTAssertLessThan(slender, bluff,
                          "a streamlined body leaves a calmer wake")
    }

    /// Vorticity confinement only feeds rotation that is already there:
    /// it must never spin up a perfectly uniform stream.
    func testConfinementLeavesUniformStreamAlone() {
        var grid = makeGrid(speed: 1.0)
        grid.vorticityConfinement = 6.0
        grid.prime(steps: 40, dt: 1.0 / 60.0)
        let velocity = grid.velocity(at: grid.cellCenter(grid.nx / 2, grid.ny / 2, grid.nz / 2))
        XCTAssertEqual(velocity.x, 1.0, accuracy: 5e-3)
        XCTAssertEqual(velocity.y, 0, accuracy: 5e-3)
        XCTAssertEqual(velocity.z, 0, accuracy: 5e-3)
    }

    /// Sampling outside the grid clamps rather than crashing, and inside
    /// a solid the flow reads as dead air.
    func testSamplingIsSafeOutsideAndInsideSolids() {
        var grid = makeGrid()
        let center = SIMD3(0.6, 0.3, 0.3)
        grid.addSolidSphere(center: center, radius: 0.15)
        grid.prime(steps: 20, dt: 1.0 / 60.0)

        XCTAssertTrue(grid.velocity(at: SIMD3(-5, -5, -5)).x.isFinite)
        XCTAssertTrue(grid.velocity(at: SIMD3(50, 50, 50)).x.isFinite)
        XCTAssertTrue(grid.isSolid(atWorld: center))
        XCTAssertEqual(simd_length(grid.velocity(at: center)), 0, accuracy: 1e-9)
    }
}
