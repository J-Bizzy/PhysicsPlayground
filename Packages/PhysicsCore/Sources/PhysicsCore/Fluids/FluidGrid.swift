//
//  FluidGrid.swift
//  Incompressible Euler solver (∂u/∂t + (u·∇)u = −∇p/ρ, ∇·u = 0) on a 3-D staggered MAC grid, operator-split per Stam "Stable Fluids": semi-Lagrangian advect (unconditionally stable) → vorticity confine (Fedkiw; restores curl the discretisation lost, never invents rotation) → pressure project (∇²p = (ρ/Δt)∇·u), which is what bends flow around solids.
//  Boundaries: −x face is the inflow (Dirichlet velocity), +x the open outflow (p = 0), side walls free-slip; per-cell solids carry zero face flux and the Poisson solve drops them (homogeneous Neumann — "the wall is a streamline").
//

import Foundation
import simd

public struct FluidGrid: Sendable {
    // MARK: Geometry

    /// Cells along each axis. x is downstream.
    public let nx: Int, ny: Int, nz: Int
    /// Cell size (m) — the grid is uniform and cubic.
    public let h: Double
    /// World position of the grid's minimum corner.
    public let origin: SIMD3<Double>

    // MARK: Fields (staggered — each component lives on its own faces)

    /// x-velocity on x-faces, (nx+1)·ny·nz.
    public private(set) var u: [Double]
    /// y-velocity on y-faces, nx·(ny+1)·nz.
    public private(set) var v: [Double]
    /// z-velocity on z-faces, nx·ny·(nz+1).
    public private(set) var w: [Double]
    /// Solid occupancy per cell, nx·ny·nz.
    public private(set) var solid: [Bool]
    /// Pressure per cell — kept between frames to warm-start the iterative solve.
    public private(set) var pressure: [Double]

    // MARK: Parameters

    /// Free-stream speed held at the inlet (m/s, along +x).
    public var inflowSpeed: Double
    /// Air density (kg/m³) — only scales the pressure, not the shape.
    public var density: Double
    /// Vorticity-confinement gain ε. 0 disables it entirely.
    public var vorticityConfinement: Double
    /// Gauss–Seidel sweeps per projection. More = tighter incompressibility.
    public var pressureIterations: Int

    // MARK: Init

    public init(nx: Int, ny: Int, nz: Int, h: Double,
                origin: SIMD3<Double> = .zero,
                inflowSpeed: Double = 1.0,
                density: Double = 1.225,
                vorticityConfinement: Double = 0.0,
                pressureIterations: Int = 24) {
        precondition(nx > 1 && ny > 1 && nz > 1 && h > 0)
        self.nx = nx; self.ny = ny; self.nz = nz
        self.h = h
        self.origin = origin
        self.inflowSpeed = inflowSpeed
        self.density = density
        self.vorticityConfinement = vorticityConfinement
        self.pressureIterations = pressureIterations
        u = [Double](repeating: inflowSpeed, count: (nx + 1) * ny * nz)
        v = [Double](repeating: 0, count: nx * (ny + 1) * nz)
        w = [Double](repeating: 0, count: nx * ny * (nz + 1))
        solid = [Bool](repeating: false, count: nx * ny * nz)
        pressure = [Double](repeating: 0, count: nx * ny * nz)
    }

    // MARK: Indexing

    @inline(__always) public func cellIndex(_ i: Int, _ j: Int, _ k: Int) -> Int {
        (k * ny + j) * nx + i
    }
    @inline(__always) func uIndex(_ i: Int, _ j: Int, _ k: Int) -> Int {
        (k * ny + j) * (nx + 1) + i
    }
    @inline(__always) func vIndex(_ i: Int, _ j: Int, _ k: Int) -> Int {
        (k * (ny + 1) + j) * nx + i
    }
    @inline(__always) func wIndex(_ i: Int, _ j: Int, _ k: Int) -> Int {
        (k * ny + j) * nx + i
    }

    @inline(__always) public func isSolid(_ i: Int, _ j: Int, _ k: Int) -> Bool {
        guard i >= 0, j >= 0, k >= 0, i < nx, j < ny, k < nz else { return false }
        return solid[cellIndex(i, j, k)]
    }

    /// The grid's world-space bounds.
    public var bounds: (min: SIMD3<Double>, max: SIMD3<Double>) {
        (origin, origin + SIMD3(Double(nx), Double(ny), Double(nz)) * h)
    }

    /// Cell-center world position.
    public func cellCenter(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Double> {
        origin + SIMD3(Double(i) + 0.5, Double(j) + 0.5, Double(k) + 0.5) * h
    }

    // MARK: Solids

    public mutating func clearSolids() {
        for index in solid.indices { solid[index] = false }
    }

    /// Marks the cell containing `point` solid; false if outside the grid.
    @discardableResult
    public mutating func addSolid(atWorld point: SIMD3<Double>) -> Bool {
        let g = (point - origin) / h
        let i = Int(g.x.rounded(.down)), j = Int(g.y.rounded(.down)), k = Int(g.z.rounded(.down))
        guard i >= 0, j >= 0, k >= 0, i < nx, j < ny, k < nz else { return false }
        solid[cellIndex(i, j, k)] = true
        return true
    }

    /// Marks every cell whose center lies within `radius` of `center`.
    public mutating func addSolidSphere(center: SIMD3<Double>, radius: Double) {
        guard radius > 0 else { return }
        let lo = (center - SIMD3(repeating: radius) - origin) / h
        let hi = (center + SIMD3(repeating: radius) - origin) / h
        let i0 = max(Int(lo.x.rounded(.down)), 0), i1 = min(Int(hi.x.rounded(.up)), nx - 1)
        let j0 = max(Int(lo.y.rounded(.down)), 0), j1 = min(Int(hi.y.rounded(.up)), ny - 1)
        let k0 = max(Int(lo.z.rounded(.down)), 0), k1 = min(Int(hi.z.rounded(.up)), nz - 1)
        guard i0 <= i1, j0 <= j1, k0 <= k1 else { return }
        let r2 = radius * radius
        for k in k0...k1 {
            for j in j0...j1 {
                for i in i0...i1 {
                    if simd_length_squared(cellCenter(i, j, k) - center) <= r2 {
                        solid[cellIndex(i, j, k)] = true
                    }
                }
            }
        }
    }

    // MARK: Sampling

    /// Trilinear velocity at a world point — each component sampled from its own staggered lattice.
    public func velocity(at point: SIMD3<Double>) -> SIMD3<Double> {
        let g = (point - origin) / h
        return SIMD3(
            sample(u, gx: g.x, gy: g.y - 0.5, gz: g.z - 0.5, dx: nx + 1, dy: ny, dz: nz),
            sample(v, gx: g.x - 0.5, gy: g.y, gz: g.z - 0.5, dx: nx, dy: ny + 1, dz: nz),
            sample(w, gx: g.x - 0.5, gy: g.y - 0.5, gz: g.z, dx: nx, dy: ny, dz: nz + 1)
        )
    }

    /// Whether a world point falls inside a solid cell.
    public func isSolid(atWorld point: SIMD3<Double>) -> Bool {
        let g = (point - origin) / h
        let i = Int(g.x.rounded(.down)), j = Int(g.y.rounded(.down)), k = Int(g.z.rounded(.down))
        return isSolid(i, j, k)
    }

    private func sample(_ field: [Double], gx: Double, gy: Double, gz: Double,
                        dx: Int, dy: Int, dz: Int) -> Double {
        let cx = min(max(gx, 0), Double(dx - 1))
        let cy = min(max(gy, 0), Double(dy - 1))
        let cz = min(max(gz, 0), Double(dz - 1))
        let i0 = min(Int(cx), dx - 1), j0 = min(Int(cy), dy - 1), k0 = min(Int(cz), dz - 1)
        let i1 = min(i0 + 1, dx - 1), j1 = min(j0 + 1, dy - 1), k1 = min(k0 + 1, dz - 1)
        let fx = cx - Double(i0), fy = cy - Double(j0), fz = cz - Double(k0)

        @inline(__always) func at(_ i: Int, _ j: Int, _ k: Int) -> Double {
            field[(k * dy + j) * dx + i]
        }
        let c00 = at(i0, j0, k0) * (1 - fx) + at(i1, j0, k0) * fx
        let c10 = at(i0, j1, k0) * (1 - fx) + at(i1, j1, k0) * fx
        let c01 = at(i0, j0, k1) * (1 - fx) + at(i1, j0, k1) * fx
        let c11 = at(i0, j1, k1) * (1 - fx) + at(i1, j1, k1) * fx
        let c0 = c00 * (1 - fy) + c10 * fy
        let c1 = c01 * (1 - fy) + c11 * fy
        return c0 * (1 - fz) + c1 * fz
    }

    // MARK: Step

    /// Advances the flow by `dt`: advect → confine → project.
    public mutating func step(dt: Double) {
        guard dt > 0 else { return }
        advect(dt: dt)
        if vorticityConfinement > 0 { confineVorticity(dt: dt) }
        applyBoundaries()
        project(dt: dt)
    }

    /// Runs the solver until the field is developed — for scene changes.
    public mutating func prime(steps: Int, dt: Double) {
        for _ in 0..<max(0, steps) { step(dt: dt) }
    }

    // MARK: 1. Advection (semi-Lagrangian)

    private mutating func advect(dt: Double) {
        var newU = u, newV = v, newW = w

        for k in 0..<nz {
            for j in 0..<ny {
                for i in 0...nx {
                    let p = origin + SIMD3(Double(i), Double(j) + 0.5, Double(k) + 0.5) * h
                    let back = p - velocity(at: p) * dt
                    newU[uIndex(i, j, k)] = sample(u, gx: (back.x - origin.x) / h,
                                                   gy: (back.y - origin.y) / h - 0.5,
                                                   gz: (back.z - origin.z) / h - 0.5,
                                                   dx: nx + 1, dy: ny, dz: nz)
                }
            }
        }
        for k in 0..<nz {
            for j in 0...ny {
                for i in 0..<nx {
                    let p = origin + SIMD3(Double(i) + 0.5, Double(j), Double(k) + 0.5) * h
                    let back = p - velocity(at: p) * dt
                    newV[vIndex(i, j, k)] = sample(v, gx: (back.x - origin.x) / h - 0.5,
                                                   gy: (back.y - origin.y) / h,
                                                   gz: (back.z - origin.z) / h - 0.5,
                                                   dx: nx, dy: ny + 1, dz: nz)
                }
            }
        }
        for k in 0...nz {
            for j in 0..<ny {
                for i in 0..<nx {
                    let p = origin + SIMD3(Double(i) + 0.5, Double(j) + 0.5, Double(k)) * h
                    let back = p - velocity(at: p) * dt
                    newW[wIndex(i, j, k)] = sample(w, gx: (back.x - origin.x) / h - 0.5,
                                                   gy: (back.y - origin.y) / h - 0.5,
                                                   gz: (back.z - origin.z) / h,
                                                   dx: nx, dy: ny, dz: nz + 1)
                }
            }
        }
        u = newU; v = newV; w = newW
    }

    // MARK: 2. Vorticity confinement

    /// Cell-center velocity (average of the two opposing faces).
    @inline(__always) private func centerVelocity(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Double> {
        SIMD3(
            0.5 * (u[uIndex(i, j, k)] + u[uIndex(i + 1, j, k)]),
            0.5 * (v[vIndex(i, j, k)] + v[vIndex(i, j + 1, k)]),
            0.5 * (w[wIndex(i, j, k)] + w[wIndex(i, j, k + 1)])
        )
    }

    private mutating func confineVorticity(dt: Double) {
        guard nx > 2, ny > 2, nz > 2 else { return }
        let count = nx * ny * nz
        var omega = [SIMD3<Double>](repeating: .zero, count: count)
        var magnitude = [Double](repeating: 0, count: count)

        // ω = ∇ × u, central differences on cell-center velocities.
        for k in 1..<(nz - 1) {
            for j in 1..<(ny - 1) {
                for i in 1..<(nx - 1) {
                    let dx = centerVelocity(i + 1, j, k) - centerVelocity(i - 1, j, k)
                    let dy = centerVelocity(i, j + 1, k) - centerVelocity(i, j - 1, k)
                    let dz = centerVelocity(i, j, k + 1) - centerVelocity(i, j, k - 1)
                    let curl = SIMD3(
                        (dy.z - dz.y) / (2 * h),
                        (dz.x - dx.z) / (2 * h),
                        (dx.y - dy.x) / (2 * h)
                    )
                    let index = cellIndex(i, j, k)
                    omega[index] = curl
                    magnitude[index] = simd_length(curl)
                }
            }
        }

        // f = ε·h·(N × ω), N = ∇|ω|/|∇|ω|| — spins the existing eddy back up.
        var force = [SIMD3<Double>](repeating: .zero, count: count)
        for k in 1..<(nz - 1) {
            for j in 1..<(ny - 1) {
                for i in 1..<(nx - 1) {
                    let index = cellIndex(i, j, k)
                    guard !solid[index] else { continue }
                    let gradient = SIMD3(
                        magnitude[cellIndex(i + 1, j, k)] - magnitude[cellIndex(i - 1, j, k)],
                        magnitude[cellIndex(i, j + 1, k)] - magnitude[cellIndex(i, j - 1, k)],
                        magnitude[cellIndex(i, j, k + 1)] - magnitude[cellIndex(i, j, k - 1)]
                    ) / (2 * h)
                    let length = simd_length(gradient)
                    guard length > 1e-12 else { continue }
                    force[index] = vorticityConfinement * h
                        * simd_cross(gradient / length, omega[index])
                }
            }
        }

        // Scatter the cell-center force onto the faces it straddles.
        for k in 1..<(nz - 1) {
            for j in 1..<(ny - 1) {
                for i in 1..<(nx - 1) {
                    let f = force[cellIndex(i, j, k)] * dt
                    u[uIndex(i, j, k)] += 0.5 * f.x
                    u[uIndex(i + 1, j, k)] += 0.5 * f.x
                    v[vIndex(i, j, k)] += 0.5 * f.y
                    v[vIndex(i, j + 1, k)] += 0.5 * f.y
                    w[wIndex(i, j, k)] += 0.5 * f.z
                    w[wIndex(i, j, k + 1)] += 0.5 * f.z
                }
            }
        }
    }

    // MARK: 3. Boundaries

    /// Inlet holds the free stream; outlet open; side walls free-slip; solid faces carry no flux.
    private mutating func applyBoundaries() {
        for k in 0..<nz {
            for j in 0..<ny {
                u[uIndex(0, j, k)] = inflowSpeed
                u[uIndex(nx, j, k)] = u[uIndex(nx - 1, j, k)]   // zero-gradient
            }
        }
        for k in 0..<nz {
            for i in 0..<nx {
                v[vIndex(i, 0, k)] = 0
                v[vIndex(i, ny, k)] = 0
            }
        }
        for j in 0..<ny {
            for i in 0..<nx {
                w[wIndex(i, j, 0)] = 0
                w[wIndex(i, j, nz)] = 0
            }
        }
        enforceSolidFaces()
    }

    /// Zero every fluid–solid face — the no-penetration condition that makes the flow go around.
    private mutating func enforceSolidFaces() {
        for k in 0..<nz {
            for j in 0..<ny {
                for i in 0..<nx where solid[cellIndex(i, j, k)] {
                    u[uIndex(i, j, k)] = 0
                    u[uIndex(i + 1, j, k)] = 0
                    v[vIndex(i, j, k)] = 0
                    v[vIndex(i, j + 1, k)] = 0
                    w[wIndex(i, j, k)] = 0
                    w[wIndex(i, j, k + 1)] = 0
                }
            }
        }
    }

    // MARK: 4. Pressure projection

    /// Divergence of a cell (1/s). Zero everywhere is incompressibility.
    public func divergence(_ i: Int, _ j: Int, _ k: Int) -> Double {
        (u[uIndex(i + 1, j, k)] - u[uIndex(i, j, k)]
            + v[vIndex(i, j + 1, k)] - v[vIndex(i, j, k)]
            + w[wIndex(i, j, k + 1)] - w[wIndex(i, j, k)]) / h
    }

    /// Largest |divergence| over the fluid cells — the residual the tests hold to zero.
    public var maxDivergence: Double {
        var worst = 0.0
        for k in 0..<nz {
            for j in 0..<ny {
                for i in 0..<nx where !solid[cellIndex(i, j, k)] {
                    worst = max(worst, abs(divergence(i, j, k)))
                }
            }
        }
        return worst
    }

    private mutating func project(dt: Double) {
        let scale = density / dt
        var rhs = [Double](repeating: 0, count: nx * ny * nz)
        var neighbours = [Double](repeating: 0, count: nx * ny * nz)

        for k in 0..<nz {
            for j in 0..<ny {
                for i in 0..<nx {
                    let index = cellIndex(i, j, k)
                    guard !solid[index] else { pressure[index] = 0; continue }
                    rhs[index] = scale * divergence(i, j, k) * h * h
                    // Neighbours: solids and the inlet wall are Neumann (dropped); the open outlet is Dirichlet p = 0 (kept, contributing zero).
                    var n = 0.0
                    if i > 0, !solid[cellIndex(i - 1, j, k)] { n += 1 }
                    if i < nx - 1 { if !solid[cellIndex(i + 1, j, k)] { n += 1 } } else { n += 1 }
                    if j > 0, !solid[cellIndex(i, j - 1, k)] { n += 1 }
                    if j < ny - 1, !solid[cellIndex(i, j + 1, k)] { n += 1 }
                    if k > 0, !solid[cellIndex(i, j, k - 1)] { n += 1 }
                    if k < nz - 1, !solid[cellIndex(i, j, k + 1)] { n += 1 }
                    neighbours[index] = n
                }
            }
        }

        // SOR (ω ≈ 1.8): plain Gauss–Seidel converges far too slowly to finish inside a frame.
        let omega = 1.8
        for _ in 0..<pressureIterations {
            for k in 0..<nz {
                for j in 0..<ny {
                    for i in 0..<nx {
                        let index = cellIndex(i, j, k)
                        let n = neighbours[index]
                        guard n > 0, !solid[index] else { continue }
                        var sum = 0.0
                        if i > 0, !solid[cellIndex(i - 1, j, k)] { sum += pressure[cellIndex(i - 1, j, k)] }
                        if i < nx - 1, !solid[cellIndex(i + 1, j, k)] { sum += pressure[cellIndex(i + 1, j, k)] }
                        if j > 0, !solid[cellIndex(i, j - 1, k)] { sum += pressure[cellIndex(i, j - 1, k)] }
                        if j < ny - 1, !solid[cellIndex(i, j + 1, k)] { sum += pressure[cellIndex(i, j + 1, k)] }
                        if k > 0, !solid[cellIndex(i, j, k - 1)] { sum += pressure[cellIndex(i, j, k - 1)] }
                        if k < nz - 1, !solid[cellIndex(i, j, k + 1)] { sum += pressure[cellIndex(i, j, k + 1)] }
                        let target = (sum - rhs[index]) / n
                        pressure[index] += omega * (target - pressure[index])
                    }
                }
            }
        }

        // u ← u − (Δt/ρ)∇p, on every face between two fluid cells.
        let gradientScale = dt / (density * h)
        for k in 0..<nz {
            for j in 0..<ny {
                for i in 1..<nx {
                    let a = cellIndex(i - 1, j, k), b = cellIndex(i, j, k)
                    guard !solid[a], !solid[b] else { continue }
                    u[uIndex(i, j, k)] -= gradientScale * (pressure[b] - pressure[a])
                }
                // Outlet face closes against p = 0 — copying the interior value would put divergence back into the last column.
                let last = cellIndex(nx - 1, j, k)
                if !solid[last] {
                    u[uIndex(nx, j, k)] -= gradientScale * (0 - pressure[last])
                }
            }
        }
        for k in 0..<nz {
            for j in 1..<ny {
                for i in 0..<nx {
                    let a = cellIndex(i, j - 1, k), b = cellIndex(i, j, k)
                    guard !solid[a], !solid[b] else { continue }
                    v[vIndex(i, j, k)] -= gradientScale * (pressure[b] - pressure[a])
                }
            }
        }
        for k in 1..<nz {
            for j in 0..<ny {
                for i in 0..<nx {
                    let a = cellIndex(i, j, k - 1), b = cellIndex(i, j, k)
                    guard !solid[a], !solid[b] else { continue }
                    w[wIndex(i, j, k)] -= gradientScale * (pressure[b] - pressure[a])
                }
            }
        }

        enforceSolidFaces()
    }

    /// Wipes back to a uniform stream. A moved obstacle's stale wake takes a full domain crossing
    /// (~L/U) to drain naturally; reset + re-prime re-establishes the flow immediately.
    public mutating func resetFlow() {
        for index in u.indices { u[index] = inflowSpeed }
        for index in v.indices { v[index] = 0 }
        for index in w.indices { w[index] = 0 }
        for index in pressure.indices { pressure[index] = 0 }
        enforceSolidFaces()
    }

    // MARK: Export

    /// Cheap immutable copy of the solved field (cell-centre velocities + solid mask) so the
    /// renderer can sample every frame while the expensive solve refreshes at its own pace.
    public func exportField() -> FlowField {
        var cells = [SIMD3<Float>](repeating: .zero, count: nx * ny * nz)
        for k in 0..<nz {
            for j in 0..<ny {
                for i in 0..<nx {
                    cells[cellIndex(i, j, k)] = SIMD3<Float>(centerVelocity(i, j, k))
                }
            }
        }
        return FlowField(nx: nx, ny: ny, nz: nz, h: h, origin: origin,
                         cells: cells, solid: solid)
    }
}

/// Sampled snapshot of a solved flow (cell-centre velocities + solid mask) — Sendable and
/// self-contained, sampled per frame without touching the solver.
public struct FlowField: Sendable {
    public let nx: Int, ny: Int, nz: Int
    public let h: Double
    public let origin: SIMD3<Double>
    public let cells: [SIMD3<Float>]
    public let solid: [Bool]

    public init(nx: Int, ny: Int, nz: Int, h: Double, origin: SIMD3<Double>,
                cells: [SIMD3<Float>], solid: [Bool]) {
        self.nx = nx; self.ny = ny; self.nz = nz
        self.h = h; self.origin = origin
        self.cells = cells; self.solid = solid
    }

    public var bounds: (min: SIMD3<Double>, max: SIMD3<Double>) {
        (origin, origin + SIMD3(Double(nx), Double(ny), Double(nz)) * h)
    }

    public func isSolid(at point: SIMD3<Double>) -> Bool {
        let g = (point - origin) / h
        let i = Int(g.x.rounded(.down)), j = Int(g.y.rounded(.down)), k = Int(g.z.rounded(.down))
        guard i >= 0, j >= 0, k >= 0, i < nx, j < ny, k < nz else { return false }
        return solid[(k * ny + j) * nx + i]
    }

    /// Trilinearly interpolated velocity at a world point.
    public func velocity(at point: SIMD3<Double>) -> SIMD3<Float> {
        let g = (point - origin) / h
        let cx = min(max(g.x - 0.5, 0), Double(nx - 1))
        let cy = min(max(g.y - 0.5, 0), Double(ny - 1))
        let cz = min(max(g.z - 0.5, 0), Double(nz - 1))
        let i0 = min(Int(cx), nx - 1), j0 = min(Int(cy), ny - 1), k0 = min(Int(cz), nz - 1)
        let i1 = min(i0 + 1, nx - 1), j1 = min(j0 + 1, ny - 1), k1 = min(k0 + 1, nz - 1)
        let fx = Float(cx - Double(i0)), fy = Float(cy - Double(j0)), fz = Float(cz - Double(k0))

        @inline(__always) func at(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Float> {
            cells[(k * ny + j) * nx + i]
        }
        let c00 = at(i0, j0, k0) * (1 - fx) + at(i1, j0, k0) * fx
        let c10 = at(i0, j1, k0) * (1 - fx) + at(i1, j1, k0) * fx
        let c01 = at(i0, j0, k1) * (1 - fx) + at(i1, j0, k1) * fx
        let c11 = at(i0, j1, k1) * (1 - fx) + at(i1, j1, k1) * fx
        let c0 = c00 * (1 - fy) + c10 * fy
        let c1 = c01 * (1 - fy) + c11 * fy
        return c0 * (1 - fz) + c1 * fz
    }
}
