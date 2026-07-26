//
//  Sonification.swift
//  Physics Playground — Design System
//
//  Physics you can HEAR, continuously — not just event chirps.
//
//  The app had a good event palette (pop, thud, chime) and exactly one
//  continuous voice, in the Elastic Field. But a headset puts sound
//  everywhere in space, and a continuously-sounding quantity is
//  something a page cannot do: an orbit's period as a pitch, a circuit's
//  current as a mains hum, wind noise that rises with the tunnel speed,
//  the wave field's amplitude at YOUR HEAD as you walk through a node.
//  You hear the physics while you're looking somewhere else.
//
//  A `ToneVoice` wraps one looping synthesized tone on one emitter and
//  exposes the two knobs that matter: pitch (played back as a rate
//  shift off the synthesized base frequency) and loudness in decibels,
//  both smoothed so a jittery frame can't click. Silent until asked.
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

    /// Begins playback, silent. Safe to call repeatedly — the resources
    /// are synthesized asynchronously at launch, so the first few
    /// attempts can fail and the caller simply tries again next frame.
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
    /// Maps a physical period to a musical pitch: shorter period, higher
    /// note. Used for the orbital chord in Gravity Lab, where Kepler's
    /// third law becomes something you can hear go out of tune when you
    /// perturb an orbit.
    ///
    /// Anchored so a one-year orbit sings at A3 (220 Hz), then log-scaled
    /// so each halving of the period is an octave up — exactly what
    /// frequency ratio means.
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
