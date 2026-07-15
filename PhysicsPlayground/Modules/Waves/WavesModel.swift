//
//  WavesModel.swift
//  Physics Playground — Waves module
//
//  App state for the ripple tank: a 1.2 m pool at table height whose
//  surface is the live superposition of up to four circular wave
//  sources. Sources and the probe live in pool-plane coordinates
//  (meters, origin at the pool center) — 1:1 with the room, no scaling.
//
//  All sources share one frequency (a common driver, like a real ripple
//  tank); each has its own amplitude and a phase-invert switch — the
//  noise-cancellation control. The probe reports the true local
//  amplitude and, with exactly two sources, the path-difference math
//  the whole fringe pattern is organized around.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class WavesModel {
    // MARK: Pool geometry & budgets

    /// Half-width of the square pool, m.
    nonisolated static let poolHalfExtent = 0.6
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

    /// Render the standing fringe pattern instead of the moving waves.
    var showEnvelope = false

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
        let position = SIMD2(cos(angle) * 0.3, sin(angle) * 0.3)
        let source = Source(id: UUID(), wave: WaveSource(position: clamp(position)))
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

    func moveSource(id: UUID, to point: SIMD2<Double>) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].wave.position = clamp(point)
    }

    private func clamp(_ point: SIMD2<Double>) -> SIMD2<Double> {
        let limit = Self.poolHalfExtent - 0.05
        return SIMD2(min(max(point.x, -limit), limit), min(max(point.y, -limit), limit))
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

    // MARK: Surface sampling (used by the renderer per vertex)

    func surfaceHeight(at point: SIMD2<Double>) -> Double {
        showEnvelope
            ? WaveField.steadyAmplitude(at: point, sources: waveSources,
                                        frequency: frequency, speed: waveSpeed)
            : WaveField.displacement(at: point, time: time, sources: waveSources,
                                     frequency: frequency, speed: waveSpeed)
    }

    // MARK: Probe

    private(set) var probePosition = SIMD2<Double>(0, 0.35)

    func moveProbe(to point: SIMD2<Double>) {
        probePosition = clamp(point)
    }

    struct ProbeReadout: Equatable {
        /// Peak oscillation amplitude here, m (true value, not exaggerated).
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

    // MARK: Two-source fringe bookkeeping

    /// Separation of the first two sources, if there are exactly two.
    var sourceSeparation: Double? {
        guard sources.count == 2 else { return nil }
        return simd_distance(sources[0].wave.position, sources[1].wave.position)
    }

    /// How many silent (nodal) lines cross the pool for the two-source
    /// pattern. Same-phase pairs go quiet where Δr = (m+½)λ; an inverted
    /// pair goes quiet where Δr = mλ — including the midline itself.
    var silentLineCount: Int? {
        guard sources.count == 2, let d = sourceSeparation else { return nil }
        let inverted = sources[0].wave.phaseInverted != sources[1].wave.phaseInverted
        let lambda = wavelength
        var count = 0
        if inverted {
            count = 1  // the midline (Δr = 0)
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

    /// Two in-phase sources a comfortable hand-width apart — the classic
    /// double-source pattern, moving.
    func reset() {
        sources = [
            Source(id: UUID(), wave: WaveSource(position: SIMD2(-0.18, 0))),
            Source(id: UUID(), wave: WaveSource(position: SIMD2(0.18, 0))),
        ]
        selectedID = sources[1].id
        frequency = 1.5
        waveSpeed = 0.5
        showEnvelope = false
        isPaused = false
        timeScale = 1.0
        time = 0
        probePosition = SIMD2(0, 0.35)
    }

    init() {
        reset()
    }
}
