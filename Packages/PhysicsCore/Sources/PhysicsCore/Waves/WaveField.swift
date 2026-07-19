//
//  WaveField.swift
//  PhysicsCore — Waves
//
//  Linear superposition of spherical waves in 3D — a sound-like field.
//  Each source contributes
//
//      u_i(p, t) = a_i · F(r_i) · sin(k·r_i − ωt + φ_i),   r_i = |p − p_i|
//
//  with k = 2πf/c and ω = 2πf shared by all sources (a common driver),
//  and F(r) = r₀/max(r, r₀) the spherical-spreading falloff — wave
//  energy spreads over a sphere, so amplitude decays as 1/r (the real
//  law for sound), clamped at r₀ so the source itself stays finite.
//
//  The steady-state amplitude envelope is the phasor magnitude
//  |Σ a·F·e^{i(k·r + φ)}|. Its zero set — the SILENCE SURFACES, nodal
//  hyperboloids in 3D — is what the module extracts as isosurfaces.
//  The unit tests pin the textbook results: exactly 2A where equal
//  waves arrive in phase, exactly 0 at λ/2 path difference, and the
//  two swapped when one source is phase-inverted — the noise-cancelling
//  headphone principle.
//

import Foundation
import simd

public struct WaveSource: Equatable, Sendable {
    /// Position in space, m.
    public var position: SIMD3<Double>
    /// Peak displacement at the falloff radius, m.
    public var amplitude: Double
    /// Phase-inverted sources start half a cycle late (φ = π) — the
    /// principle behind active noise cancellation.
    public var phaseInverted: Bool

    public init(position: SIMD3<Double>, amplitude: Double = 0.008, phaseInverted: Bool = false) {
        self.position = position
        self.amplitude = amplitude
        self.phaseInverted = phaseInverted
    }

    public var phase: Double { phaseInverted ? .pi : 0 }
}

public enum WaveField {
    /// Falloff reference radius (m): F(r) = r₀/max(r, r₀).
    public static let falloffRadius = 0.1

    public static func wavelength(frequency: Double, speed: Double) -> Double {
        speed / frequency
    }

    /// Spherical-spreading amplitude factor: F(r) = r₀/max(r, r₀).
    public static func falloff(_ distance: Double) -> Double {
        falloffRadius / max(distance, falloffRadius)
    }

    // MARK: Live displacement

    /// Field value at `point` and `time` — the animated wave.
    public static func displacement(
        at point: SIMD3<Double>,
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

    /// The standing-wave decomposition of the field at one point:
    ///
    ///     u(p, t) = c·cos(ωt) − s·sin(ωt)
    ///
    /// with c = Σ a·F·sin(k·r + φ) and s = Σ a·F·cos(k·r + φ). All the
    /// spatial work — distances, falloff, trig — folds into these two
    /// numbers, so animating the field costs two multiplies per point
    /// per frame instead of a trig call per source. The identity is
    /// exact (sin(θ − ωt) expanded), and √(c² + s²) is the envelope —
    /// both pinned by the unit tests.
    public static func phasorCoefficients(
        at point: SIMD3<Double>,
        sources: [WaveSource],
        frequency: Double,
        speed: Double
    ) -> (c: Double, s: Double) {
        let k = 2 * .pi * frequency / speed
        var c = 0.0
        var s = 0.0
        for source in sources {
            let r = simd_distance(point, source.position)
            let magnitude = source.amplitude * falloff(r)
            let theta = k * r + source.phase
            c += magnitude * sin(theta)
            s += magnitude * cos(theta)
        }
        return (c, s)
    }

    // MARK: Steady-state envelope (the interference pattern)

    /// Peak oscillation amplitude at `point` — time-independent, computed
    /// as the phasor magnitude of the summed sources. Its near-zero set
    /// is the silence surfaces.
    public static func steadyAmplitude(
        at point: SIMD3<Double>,
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
        at point: SIMD3<Double>, between a: WaveSource, and b: WaveSource
    ) -> Double {
        abs(simd_distance(point, a.position) - simd_distance(point, b.position))
    }

    /// Classifies `point` by the two sources' *total* phase difference —
    /// path difference plus any source inversion — so an inverted pair's
    /// midplane correctly reads destructive.
    public static func interference(
        at point: SIMD3<Double>,
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
