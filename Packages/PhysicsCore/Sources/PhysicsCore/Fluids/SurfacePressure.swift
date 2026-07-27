//
//  SurfacePressure.swift
//  PhysicsCore — Fluids
//
//  Pressure ON the body, from the solved flow around it.
//
//  The smoke already carries the pressure story — for incompressible
//  flow Cp = 1 − (v/U)², so slow smoke IS high pressure — but it carries
//  it in the air, several centimetres off the surface, where it takes a
//  trained eye to read. The place people want to see pressure is on the
//  object: red across the nose that is pushing back, blue over the
//  shoulders where the flow has accelerated and the pressure has
//  dropped, which over a wing is exactly where lift comes from.
//
//  The physics is Bernoulli's equation for steady incompressible flow,
//  p + ½ρ|v|² = constant, rearranged into the dimensionless coefficient
//
//      Cp = (p − p∞) / (½ρU²) = 1 − (|v| / U)²
//
//  The one subtlety is WHERE to sample. The solver enforces zero flux
//  through solid faces, so the velocity inside the body is meaningless
//  and the cells straddling the surface are partly solid. So this walks
//  a short way OUT along the surface normal until it reaches genuine
//  fluid, and evaluates there — the standard "first cell off the wall"
//  reading, and the only one the grid can honestly give.
//

import Foundation
import simd

public enum SurfacePressure {
    /// Stagnation: the flow has been brought to rest.
    public static let maximumCp = 1.0

    /// The pressure coefficient just off a surface point.
    ///
    /// The sampling rule matters more than it looks. The solid mask is
    /// VOXELISED — whole cells are marked — so the true surface sits
    /// somewhere inside a chunky staircase, and the solver has zeroed
    /// the flux through every face touching it. That means the first
    /// fluid cell off the wall reads roughly HALF the free-stream speed
    /// no matter what the flow is really doing, which would paint a
    /// stagnation-red band over the entire body, shoulders included.
    ///
    /// So this walks out to fluid and then keeps going for
    /// `boundaryShells` more cells before evaluating — reading Cp just
    /// outside the numerical boundary layer rather than inside it. It is
    /// the standard extraction for a coarse immersed-boundary grid, and
    /// it is why the shoulders come out blue and the nose red instead of
    /// everything coming out red.
    ///
    /// - Parameters:
    ///   - point: a point on the body's surface.
    ///   - normal: the OUTWARD surface normal there.
    ///   - field: the solved flow.
    ///   - freestream: U, the tunnel speed. Cp is undefined at U = 0.
    ///   - boundaryShells: fluid cells to step past before reading.
    ///   - maximumSteps: how far to walk out looking for fluid at all.
    /// - Returns: Cp, or nil if no fluid was found within reach (a point
    ///   buried inside another solid, for instance).
    public static func coefficient(
        at point: SIMD3<Double>,
        normal: SIMD3<Double>,
        in field: FlowField,
        freestream: Double,
        boundaryShells: Int = 2,
        maximumSteps: Int = 10
    ) -> Double? {
        guard freestream > 1e-9 else { return nil }
        let unit = simd_length(normal) > 1e-12 ? simd_normalize(normal) : SIMD3(0, 1, 0)
        var fluidShellsSeen = 0
        for step in 0...maximumSteps {
            let probe = point + unit * (field.h * (0.5 + Double(step)))
            guard !field.isSolid(at: probe) else { continue }
            // Clear of the wall, but not yet clear of its influence.
            if fluidShellsSeen < boundaryShells {
                fluidShellsSeen += 1
                continue
            }
            let speed = Double(simd_length(field.velocity(at: probe)))
            let ratio = speed / freestream
            return 1 - ratio * ratio
        }
        return nil
    }

    /// Cp mapped to 0…1 for a colour ramp, with 0.5 pinned at Cp = 0
    /// (free-stream pressure) so the neutral colour always means "no
    /// change" regardless of how far the extremes run.
    ///
    /// `span` is how far below zero the ramp reaches; suction on a bluff
    /// body routinely goes to Cp ≈ −1 and beyond, while the high side is
    /// capped at +1 by stagnation.
    public static func rampPosition(_ cp: Double, span: Double = 1.5) -> Double {
        guard span > 1e-9 else { return 0.5 }
        let clamped = min(max(cp, -span), maximumCp)
        return clamped >= 0
            ? 0.5 + 0.5 * (clamped / maximumCp)
            : 0.5 * (1 + clamped / span)
    }

    /// Pressure force per unit area along the outward normal, Pa.
    /// Positive Cp pushes IN on the surface, which is why a nose with a
    /// red band is a nose that is being pushed backwards.
    public static func gaugePressure(cp: Double, density: Double,
                                     freestream: Double) -> Double {
        0.5 * density * freestream * freestream * cp
    }
}
