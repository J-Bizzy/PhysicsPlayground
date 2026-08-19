//
//  Sonification.swift
//  Physics Playground — Design System
//
//  Continuous sonification: `ToneVoice` wraps one looping synthesized tone,
//  exposing pitch (a rate shift off the synthesized base frequency) and
//  loudness in dB, both smoothed so a jittery frame can't click.
//

import Foundation
import RealityKit

/// One continuously-sounding quantity, attached to a point in space.
@MainActor
final class ToneVoice {
    private var controller: AudioPlaybackController?
    private let emitter: Entity
    /// The frequency the underlying loop was synthesized at.
    private let baseHz: Double
    private let floorDecibels: Double
    private let ceilingDecibels: Double

    private var smoothedGain: Double
    private var smoothedPitch: Double

    /// - Parameters:
    ///   - emitter: an entity in the scene; the tone is spatial, so it
    ///     comes from wherever the physics actually is.
    ///   - baseHz: the synthesized loop's fundamental.
    ///   - range: quiet-to-loud decibel range this voice sweeps.
    init(on emitter: Entity,
         baseHz: Double = SoundPalette.resonanceToneBaseHz,
         range: ClosedRange<Double> = (-72)...(-16)) {
        self.emitter = emitter
        self.baseHz = baseHz
        self.floorDecibels = range.lowerBound
        self.ceilingDecibels = range.upperBound
        self.smoothedGain = range.lowerBound
        self.smoothedPitch = baseHz
    }

    /// Begins playback, silent. Safe to call repeatedly — resources
    /// synthesize asynchronously at launch, so retry next frame on failure.
    @discardableResult
    func start() -> Bool {
        guard controller == nil else { return true }
        controller = SoundPalette.startResonanceTone(on: emitter)
        return controller != nil
    }

    func stop() {
        controller?.stop()
        controller = nil
    }

    /// Drives the voice from a physical quantity.
    /// - Parameters:
    ///   - pitchHz: the frequency to sing at.
    ///   - loudness: 0…1, mapped across the voice's decibel range; 0 is
    ///     silence, not a quiet drone.
    ///   - smoothing: fraction of the way to the target each call, so a
    ///     per-frame call never clicks.
    func update(pitchHz: Double, loudness: Double, smoothing: Double = 0.12) {
        guard let controller else { return }
        let clampedLoudness = min(max(loudness, 0), 1)
        let targetGain = clampedLoudness < 0.005
            ? floorDecibels - 20
            : floorDecibels + (ceilingDecibels - floorDecibels) * clampedLoudness
        smoothedGain += (targetGain - smoothedGain) * smoothing
        smoothedPitch += (max(pitchHz, 20) - smoothedPitch) * smoothing
        controller.gain = Audio.Decibel(smoothedGain)
        controller.speed = smoothedPitch / baseHz
    }

    /// Silences the voice without tearing it down (pause, module hidden).
    func mute() {
        guard let controller else { return }
        smoothedGain = floorDecibels - 20
        controller.gain = Audio.Decibel(smoothedGain)
    }
}

enum Sonification {
    /// Maps a physical period to pitch: the reference period sings at
    /// `referenceHz`, and each halving of the period is an octave up.
    static func pitch(forPeriodSeconds period: Double,
                      referencePeriod: Double,
                      referenceHz: Double = 220) -> Double {
        guard period > 1e-9, referencePeriod > 1e-9 else { return referenceHz }
        let ratio = referencePeriod / period
        // Keep it inside a range that stays pleasant and audible.
        return min(max(referenceHz * ratio, 60), 1800)
    }

    /// Maps a magnitude to 0…1 loudness with a soft knee, so a quantity
    /// that spends most of its time near zero still has usable dynamics.
    static func loudness(_ value: Double, full: Double, knee: Double = 0.6) -> Double {
        guard full > 1e-12 else { return 0 }
        let normalized = min(max(abs(value) / full, 0), 1)
        return pow(normalized, knee)
    }
}
