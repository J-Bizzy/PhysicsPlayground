//
//  WindFlowSolver.swift
//  Physics Playground — Wind Tunnel module
//
//  The wind tunnel's live air. An actor owns a PhysicsCore FluidGrid —
//  a real incompressible flow solve — so the whole simulation runs off
//  the main thread and only finished geometry ever crosses back.
//
//  Each pass it rebuilds the solid mask from whatever is in the stream
//  (the test body, the user's tracked hands, reconstructed room
//  surfaces), advances the flow, and hands back a sampled copy of the
//  field. The RENDERER owns everything visual: it interpolates between
//  the last two fields and rebuilds smoke and streamlines every frame,
//  so nothing on screen moves at the solve's slower cadence.
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
import simd

actor WindFlowSolver {
    /// A ball of solid the flow has to get around, section-local.
    struct Obstacle: Sendable, Equatable {
        var center: SIMD3<Double>
        var radius: Double
    }

    /// What crosses back to the renderer: just the sampled field.
    struct Snapshot: Sendable {
        /// The solved field, for the renderer to advect smoke through
        /// every frame.
        var field: FlowField
        /// Free-stream speed this snapshot was taken at, for normalising.
        var referenceSpeed: Float = 1
    }

    // MARK: Grid geometry (section-local)

    /// Cell size. Small enough to resolve a car's shoulder, large enough
    /// that the pressure solve finishes well inside a frame — measured at
    /// ~10 ms a step for this grid, on a background actor.
    private static let h = 0.042
    private static let origin = SIMD3<Double>(-1.05, -0.44, -0.63)
    private static let nx = 50, ny = 21, nz = 30

    private var grid: FluidGrid
    private var isPrimed = false
    private var referenceObstacles: [Obstacle] = []
    private var needsCatchUp = false
    /// Enough sweeps to look settled around the new position without
    /// making the drag itself stutter.
    private static let catchUpSteps = 6

    /// A move worth re-establishing the flow for: about a cell's travel
    /// since the flow was last established, or any change in the number
    /// of solids (a hand entering or leaving the stream).
    private static func moved(from old: [Obstacle], to new: [Obstacle]) -> Bool {
        guard old.count == new.count else { return true }
        let threshold = h * h
        for (a, b) in zip(old, new)
        where simd_length_squared(a.center - b.center) > threshold
            || abs(a.radius - b.radius) > h * 0.5 {
            return true
        }
        return false
    }

    init() {
        grid = FluidGrid(
            nx: Self.nx, ny: Self.ny, nz: Self.nz, h: Self.h,
            origin: Self.origin, inflowSpeed: 1.0,
            vorticityConfinement: 9.0,
            pressureIterations: 24)
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
        // Did anything actually MOVE? A body dragged through the stream
        // invalidates the flow pattern already in the grid, which
        // describes where it used to be.
        // Compared against where things were at the LAST catch-up, not
        // the last frame: a slow drag never trips a per-frame threshold
        // yet still ends up far from where the flow was established.
        if Self.moved(from: referenceObstacles, to: obstacles) {
            needsCatchUp = true
            referenceObstacles = obstacles
        }

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

    /// Advances the field and hands back a sampled copy of it. The smoke
    /// is NOT advected here — the renderer rides this field every frame,
    /// which is what keeps the motion continuous even though the solve
    /// itself only refreshes a dozen or so times a second.
    func advance(dt: Double) -> Snapshot {
        if needsCatchUp {
            needsCatchUp = false
            // Waiting for the stale pattern to convect away costs a full
            // domain crossing (L/U ≈ 2 s here) — that is the lag you see
            // as the lines "catching up" with your hand. Wipe it and
            // re-establish around the new position instead.
            grid.resetFlow()
            grid.prime(steps: Self.catchUpSteps, dt: 1.0 / 60.0)
        }
        grid.step(dt: min(max(dt, 1.0 / 120.0), 1.0 / 10.0))
        return Snapshot(field: grid.exportField(),
                        referenceSpeed: Float(grid.inflowSpeed))
    }
}
