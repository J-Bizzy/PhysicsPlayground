//
//  WavesModel.swift
//  Physics Playground — Waves module
//
//  App state for the 3D interference field: up to four wave sources
//  float anywhere in a ~1.1 m cube in front of the user (immersive-space
//  coordinates, 1:1 with the room), radiating spherical waves that
//  superpose everywhere in the volume — a sound field slowed down until
//  its crests are walkable.
//
//  All sources share one frequency; each has its own amplitude and a
//  phase-invert switch — the noise-cancellation control. The probe
//  reports the true local amplitude and, with exactly two sources, the
//  path-difference math the whole pattern is organized around. The
//  silence surfaces (3D nodal sheets) are extracted by the renderer
//  from the steady-state envelope.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class WavesModel {
    // MARK: Region (immersive-space coordinates) & budgets

    /// Center of the field region: chest height, a meter ahead.
    nonisolated static let regionCenter = SIMD3<Double>(0, 1.3, -1.1)
    /// Half-extent of the cube sources and probe live in.
    nonisolated static let regionHalfExtent = 0.55
    /// Nothing sinks below this height (no sources in the floor).
    nonisolated static let regionFloor = 0.25

    nonisolated static let sourceBudget = 4

    nonisolated static let frequencyRange = 0.5...3.0     // Hz
    nonisolated static let speedRange = 0.2...1.0         // m/s
    nonisolated static let amplitudeRange = 0.002...0.015 // m
    nonisolated static let timeScaleRange = 0.1...1.0

    // MARK: Sources

    struct Source: Identifiable, Equatable {
        let id: UUID
        var wave: WaveSource
    }

    private(set) var sources: [Source] = []
    private(set) var selectedID: UUID?

    var selectedSource: Source? {
        guard let selectedID else { return nil }
        return sources.first { $0.id == selectedID }
    }

    // MARK: Wave parameters (shared driver)

    var frequency = 1.5
    var waveSpeed = 0.5
    var wavelength: Double { WaveField.wavelength(frequency: frequency, speed: waveSpeed) }

    /// Show the 3D sheets where the field cancels to silence.
    var showSilenceSurfaces = true

    // MARK: Time

    var isPaused = false
    var timeScale = 1.0
    private(set) var time = 0.0

    func step(dt: Double) {
        guard !isPaused else { return }
        time += min(dt, 1.0 / 30.0) * timeScale
    }

    // MARK: Source editing

    func addSource() {
        guard sources.count < Self.sourceBudget else { return }
        // Walk spawn points around a ring so sources don't stack.
        let angle = Double(sources.count) * 2.4 + 0.7
        let offset = SIMD3(cos(angle) * 0.3, sin(angle) * 0.15, sin(angle) * 0.2)
        let source = Source(
            id: UUID(),
            wave: WaveSource(position: clamp(Self.regionCenter + offset)))
        sources.append(source)
        selectedID = source.id
    }

    func removeSelectedSource() {
        guard let selectedID, sources.count > 1 else { return }
        sources.removeAll { $0.id == selectedID }
        self.selectedID = sources.last?.id
    }

    func select(id: UUID) {
        guard sources.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func moveSource(id: UUID, to point: SIMD3<Double>) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].wave.position = clamp(point)
    }

    private func clamp(_ point: SIMD3<Double>) -> SIMD3<Double> {
        var clamped = simd_clamp(
            point,
            Self.regionCenter - SIMD3(repeating: Self.regionHalfExtent),
            Self.regionCenter + SIMD3(repeating: Self.regionHalfExtent)
        )
        clamped.y = max(clamped.y, Self.regionFloor)
        return clamped
    }

    var selectedAmplitude: Double {
        get { selectedSource?.wave.amplitude ?? 0.008 }
        set {
            guard let index = sources.firstIndex(where: { $0.id == selectedID }) else { return }
            sources[index].wave.amplitude = newValue
        }
    }

    var selectedInverted: Bool {
        get { selectedSource?.wave.phaseInverted ?? false }
        set {
            guard let index = sources.firstIndex(where: { $0.id == selectedID }) else { return }
            sources[index].wave.phaseInverted = newValue
        }
    }

    var waveSources: [WaveSource] { sources.map(\.wave) }

    // MARK: Probe

    private(set) var probePosition = WavesModel.regionCenter + SIMD3(0, 0.25, 0.2)

    func moveProbe(to point: SIMD3<Double>) {
        probePosition = clamp(point)
    }

    struct ProbeReadout: Equatable {
        /// Peak oscillation amplitude here, m (true value).
        var amplitude: Double
        /// Only meaningful with exactly two sources.
        var pathDifference: Double?
        var pathDifferenceInWavelengths: Double?
        var interference: WaveField.Interference?
    }

    var probeReadout: ProbeReadout {
        let amplitude = WaveField.steadyAmplitude(
            at: probePosition, sources: waveSources,
            frequency: frequency, speed: waveSpeed)
        guard sources.count == 2 else {
            return ProbeReadout(amplitude: amplitude, pathDifference: nil,
                                pathDifferenceInWavelengths: nil, interference: nil)
        }
        let difference = WaveField.pathDifference(
            at: probePosition, between: sources[0].wave, and: sources[1].wave)
        return ProbeReadout(
            amplitude: amplitude,
            pathDifference: difference,
            pathDifferenceInWavelengths: difference / wavelength,
            interference: WaveField.interference(
                at: probePosition, between: sources[0].wave, and: sources[1].wave,
                frequency: frequency, speed: waveSpeed)
        )
    }

    // MARK: Two-source pattern bookkeeping

    /// Separation of the first two sources, if there are exactly two.
    var sourceSeparation: Double? {
        guard sources.count == 2 else { return nil }
        return simd_distance(sources[0].wave.position, sources[1].wave.position)
    }

    /// How many silence surfaces (3D nodal sheets) thread between the two
    /// sources. Same-phase pairs go quiet where Δr = (m+½)λ; an inverted
    /// pair where Δr = mλ — including the midplane itself.
    var silentSurfaceCount: Int? {
        guard sources.count == 2, let d = sourceSeparation else { return nil }
        let inverted = sources[0].wave.phaseInverted != sources[1].wave.phaseInverted
        let lambda = wavelength
        var count = 0
        if inverted {
            count = 1  // the midplane (Δr = 0)
            var m = 1
            while Double(m) * lambda < d * (1 - 1e-9) {
                count += 2
                m += 1
            }
        } else {
            var m = 0
            while (Double(m) + 0.5) * lambda < d * (1 - 1e-9) {
                count += 2
                m += 1
            }
        }
        return count
    }

    // MARK: Reset

    /// Two in-phase sources a comfortable arm-span apart, chest height.
    func reset() {
        sources = [
            Source(id: UUID(), wave: WaveSource(position: Self.regionCenter + SIMD3(-0.22, 0, 0))),
            Source(id: UUID(), wave: WaveSource(position: Self.regionCenter + SIMD3(0.22, 0, 0))),
        ]
        selectedID = sources[1].id
        frequency = 1.5
        waveSpeed = 0.5
        showSilenceSurfaces = true
        isPaused = false
        timeScale = 1.0
        time = 0
        probePosition = Self.regionCenter + SIMD3(0, 0.25, 0.2)
    }

    init() {
        reset()
    }
}
