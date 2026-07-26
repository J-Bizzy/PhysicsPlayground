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

    /// Center of the field region: head height, just ahead — the cube
    /// reaches past the user, so the interference field surrounds them.
    nonisolated static let regionCenter = SIMD3<Double>(0, 1.4, -0.6)
    /// Half-extent of the cube sources and probe live in.
    nonisolated static let regionHalfExtent = 1.2
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
        /// Non-zero when this source is auto-cruising (the Doppler
        /// flyby). Its motion feeds the very same velocity path a hand
        /// drag does, so the field bunches ahead of it either way.
        var drift = SIMD3<Double>.zero
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
    /// Shed an expanding wavefront sphere from each source every period —
    /// the crests made visible. A moving source's shells bunch ahead and
    /// stretch behind, so this is where the Doppler effect really shows.
    var showWavefronts = true
    /// Sound the field at the listener's own head: walk into a node and
    /// hear it go quiet. This is the experience the module exists for,
    /// and it was previously only readable as a number on a probe card.
    var listenToField = true

    // MARK: Time

    var isPaused = false
    var timeScale = 1.0
    private(set) var time = 0.0

    func step(dt: Double) {
        guard !isPaused else { return }
        let simDt = min(dt, 1.0 / 30.0) * timeScale
        time += simDt
        advanceDrift(simDt: simDt)
        updateSourceVelocities(simDt: simDt)
    }

    // MARK: Doppler — source motion through the medium

    /// Advances every auto-cruising source along its drift, bouncing it
    /// off the region walls so the flyby loops in view. The position
    /// change is all it takes — updateSourceVelocities turns it into the
    /// Doppler velocity, exactly as a drag would.
    private func advanceDrift(simDt: Double) {
        let lo = Self.regionCenter - SIMD3(repeating: Self.regionHalfExtent)
        let hi = Self.regionCenter + SIMD3(repeating: Self.regionHalfExtent)
        for index in sources.indices where sources[index].drift != .zero {
            var position = sources[index].wave.position + sources[index].drift * simDt
            var drift = sources[index].drift
            for axis in 0..<3 {
                if position[axis] < lo[axis] {
                    position[axis] = lo[axis]; drift[axis] = abs(drift[axis])
                } else if position[axis] > hi[axis] {
                    position[axis] = hi[axis]; drift[axis] = -abs(drift[axis])
                }
            }
            if position.y < Self.regionFloor {
                position.y = Self.regionFloor; drift.y = abs(drift.y)
            }
            sources[index].drift = drift
            sources[index].wave.position = position
        }
    }

    /// Each source's position last step, for the finite-difference speed.
    private var previousPositions: [UUID: SIMD3<Double>] = [:]

    /// Gives every source the velocity that drives its Doppler shift:
    /// how far it moved this step, measured in the SIMULATION time the
    /// waves live in (so slow-mo makes a drag effectively more
    /// supersonic — exactly as the crawling crests would). Smoothed so a
    /// single jittery frame can't spike it, capped just under the wave
    /// speed to keep the physics subsonic, and snapped back to rest when
    /// a drag stops so the field relaxes to the exact static pattern.
    private func updateSourceVelocities(simDt: Double) {
        let maxSpeed = 0.9 * waveSpeed
        for index in sources.indices {
            let id = sources[index].id
            let position = sources[index].wave.position
            let previous = previousPositions[id] ?? position
            previousPositions[id] = position

            var velocity = sources[index].wave.velocity
            if simDt > 1e-6 {
                let raw = (position - previous) / simDt
                velocity += (raw - velocity) * 0.35   // exponential smoothing
            }
            let speed = simd_length(velocity)
            if speed > maxSpeed {
                velocity *= maxSpeed / speed
            } else if speed < 1e-4 {
                velocity = .zero                       // truly at rest
            }
            sources[index].wave.velocity = velocity
        }
        previousPositions = previousPositions.filter { id, _ in
            sources.contains { $0.id == id }
        }
    }

    // MARK: Source editing

    func addSource() {
        guard sources.count < Self.sourceBudget else { return }
        // Walk spawn points around a ring so sources don't stack.
        let angle = Double(sources.count) * 2.4 + 0.7
        let offset = SIMD3(cos(angle) * 0.6, sin(angle) * 0.3, sin(angle) * 0.45)
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

    /// The selected source's Doppler flyby: on, it cruises across the
    /// field at Mach 0.65 so you can watch the wavefronts pile up ahead
    /// of it — the ambulance driving past, hands-free.
    var selectedIsFlying: Bool {
        get { (selectedSource?.drift ?? .zero) != .zero }
        set {
            guard let index = sources.firstIndex(where: { $0.id == selectedID }) else { return }
            if newValue {
                sources[index].drift = SIMD3(0.65 * waveSpeed, 0, 0)
            } else {
                sources[index].drift = .zero
                sources[index].wave.velocity = .zero
            }
        }
    }

    var waveSources: [WaveSource] { sources.map(\.wave) }

    // MARK: Probe

    private(set) var probePosition = WavesModel.regionCenter + SIMD3(0, 0.3, 0.4)

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
            Source(id: UUID(), wave: WaveSource(position: Self.regionCenter + SIMD3(-0.4, 0, 0))),
            Source(id: UUID(), wave: WaveSource(position: Self.regionCenter + SIMD3(0.4, 0, 0))),
        ]
        selectedID = sources[1].id
        frequency = 1.5
        waveSpeed = 0.5
        showSilenceSurfaces = true
        showWavefronts = true
        listenToField = true
        isPaused = false
        timeScale = 1.0
        time = 0
        previousPositions.removeAll()
        probePosition = Self.regionCenter + SIMD3(0, 0.3, 0.4)
    }

    init() {
        reset()
    }
}
