//
//  SurfacePressure.swift
//  Bernoulli pressure coefficient on a body from the solved flow: Cp = (p − p∞)/(½ρU²) = 1 − (|v|/U)², sampled by walking OUT along the surface normal to genuine fluid (in-body velocity is meaningless on a voxelised grid).
//

import Foundation
import simd

public enum SurfacePressure {
    /// Stagnation: the flow has been brought to rest.
    public static let maximumCp = 1.0

    /// Cp just off a surface point (`normal` = OUTWARD; nil when no fluid found within `maximumSteps`).
    /// Must step `boundaryShells` fluid cells PAST the wall before reading: the first fluid cell off a voxelised solid reads ~half the free-stream speed regardless of the flow, painting stagnation-red over the whole body.
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

    /// Cp mapped to 0…1 for a colour ramp, 0.5 pinned at Cp = 0 so neutral always means free-stream;
    /// `span` is the reach below zero (suction passes −1; the high side is capped at +1 by stagnation).
    public static func rampPosition(_ cp: Double, span: Double = 1.5) -> Double {
        guard span > 1e-9 else { return 0.5 }
        let clamped = min(max(cp, -span), maximumCp)
        return clamped >= 0
            ? 0.5 + 0.5 * (clamped / maximumCp)
            : 0.5 * (1 + clamped / span)
    }

    /// Pressure per unit area along the outward normal, Pa — positive Cp pushes IN on the surface.
    public static func gaugePressure(cp: Double, density: Double,
                                     freestream: Double) -> Double {
        0.5 * density * freestream * freestream * cp
    }
}
