//
//  WaveField.swift
//  PhysicsCore — Waves
//
//  Linear superposition of circular waves on a surface — the ripple
//  tank. Each source contributes
//
//      u_i(p, t) = a_i · F(r_i) · sin(k·r_i − ωt + φ_i),   r_i = |p − p_i|
//
//  with k = 2πf/c and ω = 2πf shared by all sources (a common driver,
//  like a real tank), and F(r) = 1/√(1 + r/r₀) the cylindrical-spreading
//  falloff (surface wave energy spreads around a circle, so amplitude
//  decays like 1/√r; r₀ keeps the source itself finite).
//
//  The steady-state amplitude envelope — the standing fringe pattern —
//  is the phasor magnitude |Σ a·F·e^{i(k·r + φ)}|, which is what the
//  "amplitude map" mode renders and what the unit tests pin: exactly 2A
//  on the midline of two equal sources, exactly 0 where the path
//  difference is λ/2 (and swapped when one source is phase-inverted —
//  the noise-cancelling headphone trick).
//

import Foundation
import simd

public struct WaveSource: Equatable, Sendable {
    /// Position on the surface, m.
    public var position: SIMD2<Double>
    /// Peak displacement at the source, m.
    public var amplitude: Double
    /// Phase-inverted sources start half a cycle late (φ = π) — the
    /// principle behind active noise cancellation.
    public var phaseInverted: Bool

    public init(position: SIMD2<Double>, amplitude: Double = 0.008, phaseInverted: Bool = false) {
        self.position = position
        self.amplitude = amplitude
        self.phaseInverted = phaseInverted
    }

    public var phase: Double { phaseInverted ? .pi : 0 }
}

public enum WaveField {
    /// Falloff reference radius (m): F(r) = 1/√(1 + r/r₀).
    public static let falloffRadius = 0.08

    public static func wavelength(frequency: Double, speed: Double) -> Double {
        speed / frequency
    }

    static func falloff(_ distance: Double) -> Double {
        1 / (1 + distance / falloffRadius).squareRoot()
    }

    // MARK: Live displacement

    /// Surface height at `point` and `time` — the animated ripple field.
    public static func displacement(
        at point: SIMD2<Double>,
        time: Double,
        sources: [WaveSource],
        frequency: Double,
        speed: Double
    ) -> Double {
        let k = 2 * .pi * frequency / speed
        let omega = 2 * .pi * frequency
        var sum = 0.0
        for source in sources {
            let r = simd_distance(point, source.position)
            sum += source.amplitude * falloff(r) * sin(k * r - omega * time + source.phase)
        }
        return sum
    }

    // MARK: Steady-state envelope (the fringe pattern)

    /// Peak oscillation amplitude at `point` — time-independent, computed
    /// as the phasor magnitude of the summed sources.
    public static func steadyAmplitude(
        at point: SIMD2<Double>,
        sources: [WaveSource],
        frequency: Double,
        speed: Double
    ) -> Double {
        let k = 2 * .pi * frequency / speed
        var real = 0.0
        var imaginary = 0.0
        for source in sources {
            let r = simd_distance(point, source.position)
            let magnitude = source.amplitude * falloff(r)
            let phase = k * r + source.phase
            real += magnitude * cos(phase)
            imaginary += magnitude * sin(phase)
        }
        return (real * real + imaginary * imaginary).squareRoot()
    }

    // MARK: Two-source interference bookkeeping (the probe's math)

    public enum Interference: Equatable, Sendable {
        case constructive, destructive, intermediate
    }

    /// |r₁ − r₂| — the quantity the whole pattern is organized around.
    public static func pathDifference(
        at point: SIMD2<Double>, between a: WaveSource, and b: WaveSource
    ) -> Double {
        abs(simd_distance(point, a.position) - simd_distance(point, b.position))
    }

    /// Classifies `point` by the two sources' *total* phase difference —
    /// path difference plus any source inversion — so an inverted pair's
    /// midline correctly reads destructive.
    public static func interference(
        at point: SIMD2<Double>,
        between a: WaveSource, and b: WaveSource,
        frequency: Double, speed: Double,
        tolerance: Double = 0.12
    ) -> Interference {
        let k = 2 * .pi * frequency / speed
        let phaseA = k * simd_distance(point, a.position) + a.phase
        let phaseB = k * simd_distance(point, b.position) + b.phase
        // Fractional cycles of disagreement, folded to 0…0.5.
        var cycles = abs(phaseA - phaseB) / (2 * .pi)
        cycles = cycles.truncatingRemainder(dividingBy: 1)
        let folded = min(cycles, 1 - cycles)
        if folded < tolerance { return .constructive }
        if folded > 0.5 - tolerance { return .destructive }
        return .intermediate
    }
}
