//
//  ElasticSheet.swift
//  PhysicsCore — Oscillations
//
//  A physical elastic membrane: a square grid of masses coupled to
//  their neighbours by springs, which in the small-displacement limit
//  IS the 2-D wave equation
//
//      ∂²u/∂t² = c² ∇²u − γ ∂u/∂t
//
//  discretised on the lattice (u is transverse height). Pluck a point
//  and a wave spreads at speed c, reflects off the boundary, and — on
//  a fixed frame — settles into the drumhead's standing modes. The
//  lattice is honest: sin(mπi/N)·sin(nπj/N) is an exact eigenvector of
//  the discrete Laplacian, so a struck mode stays a pure standing wave
//  and oscillates at the lattice frequency (the tests pin this, plus
//  energy conservation and the wavefront's speed).
//
//  Boundaries are either FIXED (the rim is clamped to zero — a real
//  drumhead) or FREE (zero-gradient, the wave reflects off an open
//  edge). Any node can be PINNED to a height: that is how a hand grabs
//  and holds the sheet while the rest of the medium responds.
//

import Foundation

public struct ElasticSheet: Sendable {
    public enum Boundary: Sendable, Equatable { case fixed, free }

    /// Nodes per side.
    public let n: Int
    /// Lattice spacing (m).
    public let spacing: Double
    /// Wave speed (m/s).
    public var waveSpeed: Double
    /// Velocity damping γ (1/s); 0 = lossless.
    public var damping: Double
    public var boundary: Boundary
    /// A ceiling on the free field's amplitude (m). The linear wave
    /// equation can't blow up on its own, but a hand DRIVING a point —
    /// holding and shaking it — pumps in energy without bound. When the
    /// peak of the un-held field passes this, the whole field is gently
    /// scaled back to it (energy bled off), so the sheet can never run
    /// away and glitch. Default .infinity = no limit (the tests run
    /// unclamped).
    public var amplitudeLimit: Double = .infinity

    /// Transverse height and velocity, row-major (index = j*n + i).
    public private(set) var height: [Double]
    public private(set) var velocity: [Double]
    /// Nodes the hand holds: index → clamped height. Held nodes do not
    /// integrate; the medium around them does.
    private var pinned: [Int: Double] = [:]

    public init(n: Int = 22, spacing: Double = 0.06,
                waveSpeed: Double = 1.2, damping: Double = 0.25,
                boundary: Boundary = .fixed) {
        self.n = n
        self.spacing = spacing
        self.waveSpeed = waveSpeed
        self.damping = damping
        self.boundary = boundary
        self.height = [Double](repeating: 0, count: n * n)
        self.velocity = [Double](repeating: 0, count: n * n)
    }

    @inline(__always) public func index(_ i: Int, _ j: Int) -> Int { j * n + i }
    @inline(__always) public func isEdge(_ i: Int, _ j: Int) -> Bool {
        i == 0 || j == 0 || i == n - 1 || j == n - 1
    }

    // MARK: Manipulation

    public mutating func pin(_ i: Int, _ j: Int, to h: Double) {
        let k = index(i, j)
        pinned[k] = h
        height[k] = h
        velocity[k] = 0
    }

    public mutating func unpin(_ i: Int, _ j: Int) {
        pinned[index(i, j)] = nil
    }

    public mutating func unpinAll() { pinned.removeAll() }

    public var pinnedNodes: [Int] { Array(pinned.keys) }

    /// The node nearest a point in the sheet's LOCAL plane coordinates
    /// (origin at node 0,0; +x along i, +y along j), clamped to the
    /// grid.
    public func nearestNode(localX x: Double, localY y: Double) -> (i: Int, j: Int) {
        let i = min(max(Int((x / spacing).rounded()), 0), n - 1)
        let j = min(max(Int((y / spacing).rounded()), 0), n - 1)
        return (i, j)
    }

    /// A smooth raised bump — a fingertip pressing the sheet — added to
    /// the height with a Gaussian falloff.
    public mutating func pluck(i ci: Int, j cj: Int, amplitude: Double, radius: Double) {
        let r2 = max(radius * radius, 1e-9)
        for j in 0..<n {
            for i in 0..<n {
                if boundary == .fixed, isEdge(i, j) { continue }
                let dx = Double(i - ci) * spacing
                let dy = Double(j - cj) * spacing
                height[index(i, j)] += amplitude * exp(-(dx * dx + dy * dy) / r2)
            }
        }
    }

    /// Sets the sheet to a pure (m, n) standing-mode shape at rest —
    /// the fixed-boundary drumhead eigenfunctions.
    public mutating func setStandingMode(m: Int, p: Int, amplitude: Double) {
        for j in 0..<n {
            for i in 0..<n {
                let shape = sin(Double(m) * .pi * Double(i) / Double(n - 1))
                    * sin(Double(p) * .pi * Double(j) / Double(n - 1))
                height[index(i, j)] = amplitude * shape
                velocity[index(i, j)] = 0
            }
        }
    }

    public mutating func flatten() {
        for k in 0..<height.count { height[k] = 0; velocity[k] = 0 }
    }

    // MARK: Integration

    /// Advances by `dt`, substepping internally so the wave never
    /// outruns the lattice (CFL): c·dt_sub ≤ spacing/√2.
    public mutating func step(dt: Double) {
        guard dt > 0 else { return }
        // CFL for the 2-D lattice (max Laplacian eigenvalue 8/a²):
        // c·dt/a ≤ 1/√2 for stability — take a third of that for
        // margin. The damping term needs γ·dt ≤ 1 as well.
        let cfl = 0.35 * spacing / max(waveSpeed, 1e-6)
        let dampLimit = damping > 1e-9 ? 0.5 / damping : .infinity
        let safe = min(cfl, dampLimit)
        let substeps = max(1, Int((dt / safe).rounded(.up)))
        let h = dt / Double(substeps)
        for _ in 0..<substeps { integrate(h) }
        governAmplitude()
    }

    /// Scales the free (un-held) field back under the amplitude ceiling
    /// when it's exceeded — the safety governor. Held nodes are left
    /// alone (their height is the hand's, re-pinned each frame).
    private mutating func governAmplitude() {
        guard amplitudeLimit.isFinite else { return }
        var peak = 0.0
        for k in 0..<height.count where pinned[k] == nil {
            peak = max(peak, abs(height[k]))
        }
        guard peak > amplitudeLimit else { return }
        let scale = amplitudeLimit / peak
        for k in 0..<height.count where pinned[k] == nil {
            height[k] *= scale
            velocity[k] *= scale
        }
    }

    private func sample(_ i: Int, _ j: Int) -> Double {
        // Neighbour access with the boundary rule baked in.
        switch boundary {
        case .fixed:
            if i < 0 || j < 0 || i >= n || j >= n { return 0 }
            return height[index(i, j)]
        case .free:
            let ci = min(max(i, 0), n - 1)
            let cj = min(max(j, 0), n - 1)
            return height[index(ci, cj)]
        }
    }

    private mutating func integrate(_ dt: Double) {
        let c2 = waveSpeed * waveSpeed
        let invA2 = 1 / (spacing * spacing)
        var newVelocity = velocity
        for j in 0..<n {
            for i in 0..<n {
                let k = index(i, j)
                if pinned[k] != nil { newVelocity[k] = 0; continue }
                if boundary == .fixed, isEdge(i, j) { newVelocity[k] = 0; continue }
                let laplacian = (sample(i + 1, j) + sample(i - 1, j)
                    + sample(i, j + 1) + sample(i, j - 1)
                    - 4 * height[k]) * invA2
                let accel = c2 * laplacian - damping * velocity[k]
                newVelocity[k] = velocity[k] + accel * dt
            }
        }
        velocity = newVelocity
        for k in 0..<height.count where pinned[k] == nil {
            height[k] += velocity[k] * dt
        }
    }

    // MARK: Diagnostics

    /// Total energy per unit areal density: ½Σv² + ½c²Σ|∇u|² (lattice
    /// gradient). Conserved without damping and with a clamped rim.
    public var energy: Double {
        // Both terms carry the cell area a² so kinetic and potential
        // share units — the energy density integrated over the sheet.
        let cellArea = spacing * spacing
        var kinetic = 0.0
        for v in velocity { kinetic += 0.5 * v * v * cellArea }
        var potential = 0.0
        let c2 = waveSpeed * waveSpeed
        for j in 0..<(n - 1) {
            for i in 0..<(n - 1) {
                let du_dx = (height[index(i + 1, j)] - height[index(i, j)]) / spacing
                let du_dy = (height[index(i, j + 1)] - height[index(i, j)]) / spacing
                potential += 0.5 * c2 * (du_dx * du_dx + du_dy * du_dy) * spacing * spacing
            }
        }
        return kinetic + potential
    }

    /// The signed height extremes right now — the visualization's range.
    public var heightRange: (min: Double, max: Double) {
        (height.min() ?? 0, height.max() ?? 0)
    }
}
