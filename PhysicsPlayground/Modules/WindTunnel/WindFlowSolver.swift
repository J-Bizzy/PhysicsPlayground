//
//  WindFlowSolver.swift
//  Physics Playground — Wind Tunnel module
//
//  The wind tunnel's live air. An actor owns a PhysicsCore FluidGrid —
//  a real incompressible flow solve — so the whole simulation runs off
//  the main thread and only finished geometry ever crosses back.
//
//  Every frame it:
//    · rebuilds the solid mask from whatever is in the stream (the test
//      body, the user's tracked hands, reconstructed room surfaces),
//    · advances the flow one step,
//    · traces a rake of streamlines through the solved field, and
//    · advects a cloud of smoke particles along it.
//
//  Because the obstacles are voxels in the pressure solve rather than
//  local deflectors, the air bends around ANYTHING — a car, a chair, a
//  forearm — for the same reason real air does: mass cannot pass through
//  it, so the pressure field pushes the flow around, and a wake forms
//  behind on its own.
//
//  Everything here is in SECTION-LOCAL coordinates: x downstream, y up,
//  z lateral, origin on the beam axis at the section's middle.
//

import Foundation
import PhysicsCore
import RenderKit
import simd

actor WindFlowSolver {
    /// A ball of solid the flow has to get around, section-local.
    struct Obstacle: Sendable, Equatable {
        var center: SIMD3<Double>
        var radius: Double
    }

    /// What the renderer draws: tube geometry that is already built, plus
    /// the smoke positions. Nothing here needs the main thread to do more
    /// than upload it.
    struct Snapshot: Sendable {
        /// One tube buffer per speed-colour bucket (slow → fast).
        var ribbonBuffers: [TubeBuffers] = []
        /// The smoke as ONE ready-to-upload sprite mesh. Built here so the
        /// main thread uploads a single mesh instead of writing a
        /// transform onto hundreds of separate entities every frame.
        var smoke = SmokeBuffers()
        /// Free-stream speed this snapshot was taken at, for normalising.
        var referenceSpeed: Float = 1
    }

    /// Camera-facing quads for the smoke, with UVs into a soft radial
    /// puff texture — many overlapping translucent puffs is what reads as
    /// volume, where hard little spheres read as confetti.
    struct SmokeBuffers: Sendable {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        var isEmpty: Bool { indices.isEmpty }
    }

    /// Local speed ratio → colour bucket, matching the renderer's palette:
    /// red where the air stagnates, green in the free stream, cyan where
    /// the body squeezes it faster.
    static func speedBucket(_ ratio: Double) -> Int {
        switch ratio {
        case ..<0.40: 0
        case ..<0.72: 1
        case ..<0.95: 2
        case ..<1.08: 3
        default: 4
        }
    }
    static let bucketCount = 5

    // MARK: Grid geometry (section-local)

    /// Cell size. Small enough to resolve a car's shoulder, large enough
    /// that the pressure solve finishes well inside a frame — measured at
    /// ~10 ms a step for this grid, on a background actor.
    private static let h = 0.042
    private static let origin = SIMD3<Double>(-1.05, -0.44, -0.63)
    private static let nx = 50, ny = 21, nz = 30

    private var grid: FluidGrid
    private var isPrimed = false

    // MARK: Streamline rake

    /// Ribbons are seeded on a rake just inside the inlet, concentrated
    /// on the body rather than spread across the whole tunnel — like a
    /// real smoke rake, every filament is aimed at the shape so every one
    /// of them visibly has to get around it.
    private static let ribbonHeights: [Double] = [-0.13, -0.05, 0.03, 0.11, 0.20]
    private static let ribbonLaterals: [Double] = [-0.21, -0.14, -0.07, 0, 0.07, 0.14, 0.21]
    private static let ribbonSteps = 150
    private static let ribbonStride = 0.022

    // MARK: Smoke

    /// One mesh means the cost is geometry, not entities, so the cloud
    /// can be dense enough to actually look like smoke.
    private static let smokeCount = 950
    private var smoke: [SIMD3<Double>] = []
    private var smokeAge: [Double] = []
    /// A mote crosses the 2.1 m section in about two seconds at 1 m/s.
    /// Much more life than that and the ones caught in the slow
    /// recirculation behind a body pile into a solid wall of smoke
    /// instead of reading as a wake.
    private static let smokeLife = 4.0

    init() {
        grid = FluidGrid(
            nx: Self.nx, ny: Self.ny, nz: Self.nz, h: Self.h,
            origin: Self.origin, inflowSpeed: 1.0,
            vorticityConfinement: 9.0,
            pressureIterations: 24)
        smoke = (0..<Self.smokeCount).map { _ in Self.randomInletPoint() }
        smokeAge = (0..<Self.smokeCount).map { _ in Double.random(in: 0..<Self.smokeLife) }
    }

    /// Motes enter in the same band the ribbon rake covers, so the smoke
    /// is dense where the body is instead of thinly filling the tunnel.
    private static func randomInletPoint() -> SIMD3<Double> {
        SIMD3(
            Double.random(in: -1.02 ... -0.90),
            Double.random(in: -0.20 ... 0.28),
            Double.random(in: -0.30 ... 0.30)
        )
    }

    // MARK: Configuration

    /// Points the tunnel at a new free-stream speed.
    func setInflow(_ speed: Double) {
        grid.inflowSpeed = max(speed, 0.01)
    }

    /// Replaces the solid mask with the current contents of the stream.
    /// Cheap enough to call every frame, which is what lets a moving hand
    /// push the air around live.
    func setObstacles(_ obstacles: [Obstacle]) {
        grid.clearSolids()
        for obstacle in obstacles {
            // Anything the tracker reports has to be at least one cell
            // across to exist for the solver at all — a fingertip sphere is
            // smaller than a cell, and left un-inflated it would mark no
            // cells and the air would blow straight through the user's
            // hand. Rounding it up to half a cell is the honest statement
            // of the grid's resolution limit.
            let radius = max(obstacle.radius, Self.h * 0.55)
            grid.addSolidSphere(center: obstacle.center, radius: radius)
        }
    }

    /// Develops the flow before the first frame is shown, so the module
    /// opens with air already moving around the body instead of a blank
    /// tunnel filling in.
    func primeIfNeeded() {
        guard !isPrimed else { return }
        isPrimed = true
        // Enough to establish the flow around the body without holding
        // the first frame — the rest develops live, which reads as the
        // tunnel spinning up rather than as a stall.
        grid.prime(steps: 25, dt: 1.0 / 60.0)
    }

    // MARK: Per-frame

    func advance(dt: Double, traceRibbons wantRibbons: Bool,
                 smokeVisible: Bool) -> Snapshot {
        grid.step(dt: min(max(dt, 1.0 / 120.0), 1.0 / 20.0))
        if smokeVisible { advectSmoke(dt: dt) }
        return Snapshot(
            ribbonBuffers: wantRibbons ? buildRibbonBuffers() : [],
            smoke: smokeVisible ? buildSmokeQuads() : SmokeBuffers(),
            referenceSpeed: Float(grid.inflowSpeed))
    }

    /// Builds the smoke sprite mesh. Each mote is a quad facing the front
    /// of the section (where the tunnel is watched from), sized by how
    /// long it has been drifting — young motes are tight and bright,
    /// older ones spread and soften, so the wake blooms into haze rather
    /// than staying a cloud of identical dots.
    private func buildSmokeQuads() -> SmokeBuffers {
        var buffers = SmokeBuffers()
        let count = smoke.count
        buffers.positions.reserveCapacity(count * 4)
        buffers.normals.reserveCapacity(count * 4)
        buffers.uvs.reserveCapacity(count * 4)
        buffers.indices.reserveCapacity(count * 6)

        for (index, p) in smoke.enumerated() {
            let age = Float(smokeAge[index] / Self.smokeLife)     // 0…1
            let size = Self.smokeSizeNear + (Self.smokeSizeFar - Self.smokeSizeNear) * age
            let c = SIMD3<Float>(p)
            let base = UInt32(buffers.positions.count)
            buffers.positions.append(c + SIMD3(-size, -size, 0))
            buffers.positions.append(c + SIMD3(size, -size, 0))
            buffers.positions.append(c + SIMD3(size, size, 0))
            buffers.positions.append(c + SIMD3(-size, size, 0))
            for _ in 0..<4 { buffers.normals.append([0, 0, 1]) }
            buffers.uvs.append([0, 1]); buffers.uvs.append([1, 1])
            buffers.uvs.append([1, 0]); buffers.uvs.append([0, 0])
            buffers.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return buffers
    }

    /// A puff starts tight and spreads as it drifts downstream.
    private static let smokeSizeNear: Float = 0.009
    private static let smokeSizeFar: Float = 0.024

    /// Traces the rake and turns it straight into tube geometry, split by
    /// speed colour — all of it here on the solver, so the main thread
    /// only ever uploads a finished mesh.
    private func buildRibbonBuffers() -> [TubeBuffers] {
        let reference = max(grid.inflowSpeed, 1e-9)
        var bucketLines: [[[SIMD3<Float>]]] =
            Array(repeating: [], count: Self.bucketCount)

        for ribbon in traceRibbons() {
            // Smooth the speed along the filament before choosing colours.
            // Raw per-vertex speeds cross a bucket edge back and forth in
            // the turbulent wake, which chops the tube into dashes; a short
            // moving average keeps each filament a continuous ribbon.
            let smoothed = Self.movingAverage(ribbon.speeds, window: 7)
            var run: [SIMD3<Float>] = []
            var runBucket = -1
            for (index, point) in ribbon.points.enumerated() {
                let bucket = Self.speedBucket(Double(smoothed[index]) / reference)
                if runBucket == -1 { runBucket = bucket }
                run.append(point)
                if bucket != runBucket {
                    if run.count > 1 { bucketLines[runBucket].append(run) }
                    // Start the next run AT this point so the ribbon is
                    // visually continuous across a colour change.
                    run = [point]
                    runBucket = bucket
                }
            }
            if run.count > 1, runBucket >= 0 { bucketLines[runBucket].append(run) }
        }
        return bucketLines.map {
            TubeMesh.buffers(lines: $0, radius: Self.ribbonRadius, sides: 4)
        }
    }

    /// Fat enough to read as a sheet of smoke rather than a wire.
    private static let ribbonRadius: Float = 0.0055

    private static func movingAverage(_ values: [Float], window: Int) -> [Float] {
        guard values.count > window, window > 1 else { return values }
        let half = window / 2
        var result = [Float](repeating: 0, count: values.count)
        for index in values.indices {
            let lo = max(0, index - half), hi = min(values.count - 1, index + half)
            var sum: Float = 0
            for k in lo...hi { sum += values[k] }
            result[index] = sum / Float(hi - lo + 1)
        }
        return result
    }

    // MARK: Streamlines

    private struct Ribbon {
        var points: [SIMD3<Float>] = []
        var speeds: [Float] = []
    }

    /// Integrates streamlines through the solved field (RK2). A streamline
    /// is everywhere tangent to the velocity, so these ARE the paths the
    /// air takes — they wrap the body because the field does.
    private func traceRibbons() -> [Ribbon] {
        var result: [Ribbon] = []
        result.reserveCapacity(Self.ribbonHeights.count * Self.ribbonLaterals.count)
        let xStart = Self.origin.x + Self.h * 0.6
        let maxX = Self.origin.x + Double(Self.nx) * Self.h - Self.h

        for height in Self.ribbonHeights {
            for lateral in Self.ribbonLaterals {
                var ribbon = Ribbon()
                ribbon.points.reserveCapacity(Self.ribbonSteps)
                var p = SIMD3(xStart, height, lateral)
                for _ in 0..<Self.ribbonSteps {
                    let v1 = grid.velocity(at: p)
                    let speed = simd_length(v1)
                    ribbon.points.append(SIMD3<Float>(p))
                    ribbon.speeds.append(Float(speed))
                    guard speed > 1e-5 else { break }
                    // RK2 midpoint, marching a fixed arc length so the
                    // vertex spacing stays even however fast the air moves.
                    let half = p + (v1 / speed) * (Self.ribbonStride * 0.5)
                    let v2 = grid.velocity(at: half)
                    let s2 = simd_length(v2)
                    let direction = s2 > 1e-6 ? v2 / s2 : v1 / speed
                    p += direction * Self.ribbonStride
                    if p.x > maxX { break }
                    if grid.isSolid(atWorld: p) { break }
                }
                if ribbon.points.count > 3 { result.append(ribbon) }
            }
        }
        return result
    }

    // MARK: Smoke

    private func advectSmoke(dt: Double) {
        // Confine the smoke to the volume that is actually solved. Beyond
        // the grid the sampler only clamps, so a mote that escapes drifts
        // on stale velocity and ends up scattered around the room instead
        // of in the tunnel.
        let (lo, hi) = grid.bounds
        let margin = Self.h
        for index in smoke.indices {
            var p = smoke[index]
            p += grid.velocity(at: p) * dt
            smokeAge[index] += dt

            // Recycle at the inlet once a mote leaves the tunnel, ages
            // out, or is overtaken by a solid (a hand closing over it).
            if p.x > hi.x - margin || smokeAge[index] > Self.smokeLife
                || grid.isSolid(atWorld: p)
                || p.y < lo.y + margin || p.y > hi.y - margin
                || p.z < lo.z + margin || p.z > hi.z - margin {
                p = Self.randomInletPoint()
                smokeAge[index] = 0
            }
            smoke[index] = p
        }
    }
}
