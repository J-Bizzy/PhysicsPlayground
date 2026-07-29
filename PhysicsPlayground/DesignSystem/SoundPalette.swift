//
//  SoundPalette.swift
//  Physics Playground — Design system
//
//  The app's sound design, with no audio assets: every sound is
//  synthesized (sine partials, filtered noise, exponential envelopes),
//  written once as WAV files into Caches, and loaded as spatial
//  AudioFileResources. Playback is positional — a bounce sounds like it
//  happened where the ball hit.
//
//  The palette is deliberately quiet and physical: a soft pop for
//  launches, a filtered whoosh for throws, a low thud for impacts (gain
//  scaled by impact speed), a two-note chime for scores, a deep boom
//  for planetary mergers. Nothing gamified, nothing looping.
//
//  Models publish SpatialSoundEvents (pure data, unit-testable);
//  renderers position an emitter entity and play. Everything no-ops
//  gracefully if synthesis or loading fails.
//

import Foundation
import RealityKit

/// A sound request from a model: what, where (module space), how loud.
struct SpatialSoundEvent: Equatable {
    let id: Int
    let kind: SoundPalette.Sound
    let position: SIMD3<Double>
    /// 0…1, mapped to gain.
    let volume: Double
}

@MainActor
enum SoundPalette {
    enum Sound: String, CaseIterable {
        case pop, whoosh, thud, chime, boom
    }

    private static var resources: [Sound: AudioFileResource] = [:]
    private static var warmed = false

    /// Synthesize (if needed) and load every sound. Call once, early.
    static func warmUp() {
        guard !warmed else { return }
        warmed = true
        Task {
            for sound in Sound.allCases {
                guard let url = try? writeIfNeeded(sound) else { continue }
                if let resource = try? await AudioFileResource(contentsOf: url) {
                    resources[sound] = resource
                }
            }
            if let url = try? writeAmbientIfNeeded() {
                ambientResource = try? await AudioFileResource(
                    contentsOf: url,
                    configuration: .init(shouldLoop: true))
            }
            if let url = try? writeFanHumIfNeeded() {
                fanHumResource = try? await AudioFileResource(
                    contentsOf: url,
                    configuration: .init(shouldLoop: true))
            }
            if let url = try? writeResonanceToneIfNeeded() {
                resonanceToneResource = try? await AudioFileResource(
                    contentsOf: url,
                    configuration: .init(shouldLoop: true))
            }
        }
    }

    // MARK: Resonance tone (elastic-field drumhead)

    private static var resonanceToneResource: AudioFileResource?
    /// The base pitch (Hz) the tone is synthesized at; the caller shifts
    /// it with the controller's `speed` to sing the swept drive.
    static let resonanceToneBaseHz = 220.0

    /// Starts the looping resonance tone on `entity`, silent to begin
    /// with. The caller sets the controller's `gain` from how hard the
    /// membrane is ringing and its `speed` from the drive frequency, so
    /// the drum sings louder at resonance and higher as you sweep up.
    static func startResonanceTone(on entity: Entity) -> AudioPlaybackController? {
        guard let resonanceToneResource else { return nil }
        entity.components.set(SpatialAudioComponent(gain: Audio.Decibel(-80)))
        let controller = entity.playAudio(resonanceToneResource)
        controller.gain = -80
        return controller
    }

    private static func writeResonanceToneIfNeeded() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhysicsPlaygroundSounds", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("resonance-tone.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try wavData(samples: synthesizeResonanceTone()).write(to: url)
        }
        return url
    }

    /// A 1-second seamless loop of a warm drum-like tone: a 220 Hz
    /// fundamental with a couple of soft harmonics (all integer cycles in
    /// one second, so the loop seam vanishes).
    private static func synthesizeResonanceTone() -> [Float] {
        render(duration: 1.0) { t, _ in
            let f = resonanceToneBaseHz
            return 0.7 * sin(2 * .pi * f * t)
                + 0.22 * sin(2 * .pi * 2 * f * t)
                + 0.09 * sin(2 * .pi * 3 * f * t)
        }
    }

    // MARK: Ambient laboratory room tone

    private static var ambientResource: AudioFileResource?

    /// Starts the looping lab ambience on `entity` (very quiet: a deep
    /// air-handler rumble, a faint equipment hum, a whisper of hiss).
    /// Returns nil until warmUp's synthesis has finished.
    static func startAmbient(on entity: Entity, gainDecibels: Double = -22) -> AudioPlaybackController? {
        guard let ambientResource else { return nil }
        entity.components.set(SpatialAudioComponent(gain: Audio.Decibel(gainDecibels)))
        return entity.playAudio(ambientResource)
    }

    private static func writeAmbientIfNeeded() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhysicsPlaygroundSounds", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Versioned name: synthesis is cached to disk, so a redesign of
        // the soundscape must write a NEW file or every existing install
        // keeps playing the old one forever.
        // Versioned name: the file is cached on disk, so a new synthesis
        // recipe must write to a NEW name or the old sound plays forever.
        let url = directory.appendingPathComponent("ambient-lab-3.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try wavData(samples: synthesizeAmbient()).write(to: url)
        }
        return url
    }

    /// The house soundscape: a 24-second seamless loop that reads as a
    /// quiet planetarium rather than a server room. Three layers:
    ///
    ///  · a warm open-fifth drone (A2·E3·A3·E4 over a 55 Hz sub), each
    ///    voice doubled a fraction of a hertz apart so the pairs beat
    ///    slowly and the chord shimmers instead of standing still;
    ///  · a slow breath — the whole bed swells and relaxes on a 12 s
    ///    cycle, with airy filtered noise that breathes along;
    ///  · four soft chime partials spaced through the loop (A5 E5 C#6 B5),
    ///    barely there, so the room occasionally glints.
    ///
    /// The last 1.2 s crossfades into the first so the seam vanishes.
    private static func synthesizeAmbient() -> [Float] {
        // An ethereal pad, nothing else. The old room tone carried a
        // filtered-noise "air" layer that read as static over spatial
        // audio; this is PURELY TONAL — a widely voiced A-major chord
        // of gently detuned sine pairs whose beats and swells drift
        // against each other, glassy on top, warm underneath.
        //
        // Every frequency — voices, detunes, tremolos — is quantised to
        // a whole number of cycles per loop, so the loop point is
        // mathematically seamless and needs no crossfade.
        let loop = 24.0
        let grid = { (frequency: Double) in (frequency * loop).rounded() / loop }

        // A2 E3 A3 C#4 E4 A4 C#5 E5: wide, open, major — glassy up top.
        let voices: [(frequency: Double, amplitude: Double)] = [
            (grid(110.0), 0.17),
            (grid(164.81), 0.15),
            (grid(220.0), 0.13),
            (grid(277.18), 0.10),
            (grid(329.63), 0.09),
            (grid(440.0), 0.06),
            (grid(554.37), 0.035),
            (grid(659.26), 0.025),
        ]

        return render(duration: loop) { t, _ in
            var pad = 0.0
            for (index, voice) in voices.enumerated() {
                // Each voice is a detuned pair; the pair's beat completes
                // a whole number of cycles per loop (1, 2, 3… beats),
                // so the shimmer never repeats twice the same way inside
                // one pass yet loops exactly.
                let detune = Double(index + 1) / loop
                let pair = 0.5 * (sin(2 * .pi * voice.frequency * t)
                    + sin(2 * .pi * (voice.frequency + detune) * t + 0.7))
                // Slow independent swells, each on its own whole-cycle
                // period and phase — voices surface and sink in turn,
                // which is the "alive" in the pad.
                let cycles = Double((index % 3) + 2)
                let swell = 0.72 + 0.28 * sin(2 * .pi * cycles * t / loop
                                              + Double(index) * 1.9)
                pad += voice.amplitude * pair * swell
            }
            // One long communal breath over the loop.
            let breath = 1 + 0.08 * sin(2 * .pi * t / loop)
            return pad * breath
        }
    }

    // MARK: Fan hum (wind tunnel)

    private static var fanHumResource: AudioFileResource?

    /// Starts the looping fan hum on `entity`; the caller drives its
    /// gain with the wind. Returns nil until synthesis has finished.
    static func startFanHum(on entity: Entity, gainDecibels: Double = -30) -> AudioPlaybackController? {
        guard let fanHumResource else { return nil }
        entity.components.set(SpatialAudioComponent(gain: Audio.Decibel(gainDecibels)))
        return entity.playAudio(fanHumResource)
    }

    private static func writeFanHumIfNeeded() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhysicsPlaygroundSounds", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fan-hum.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try wavData(samples: synthesizeFanHum()).write(to: url)
        }
        return url
    }

    /// A 3-second seamless loop of an axial fan: broadband air noise
    /// pulsed at the blade-pass rate over a motor hum. Every periodic
    /// component is an integer number of cycles in 3 s, and the noise
    /// bed is crossfaded, so the seam vanishes.
    private static func synthesizeFanHum() -> [Float] {
        var lowPassed = 0.0
        var samples = render(duration: 3.0) { t, _ in
            let noise = Double.random(in: -1...1)
            lowPassed += 0.09 * (noise - lowPassed)
            // Six blades at ~240 rpm: 24 blade passes a second.
            let bladePass = 1 + 0.35 * sin(2 * .pi * 24 * t)
            let motor = 0.16 * sin(2 * .pi * 120 * t) + 0.05 * sin(2 * .pi * 240 * t)
            return lowPassed * 2.1 * bladePass + motor
        }
        let fade = Int(0.4 * sampleRate)
        for index in 0..<fade {
            let mix = Float(index) / Float(fade)
            let tail = samples[samples.count - fade + index]
            samples[index] = tail * (1 - mix) + samples[index] * mix
        }
        return samples
    }

    /// Plays `sound` spatially from `entity` (which should already sit at
    /// the source position). volume 0…1 → −28…0 dB.
    /// Settings' master volume, 0…1. Applied to every one-shot; the
    /// settings window writes it here so callers never have to know.
    static var masterVolume: Double = 1

    static func play(_ sound: Sound, on entity: Entity, volume: Double = 1) {
        guard let resource = resources[sound] else { return }
        let effective = min(max(volume * masterVolume, 0), 1)
        guard effective > 0.001 else { return }
        let decibels = -28.0 * (1 - effective)
        entity.components.set(SpatialAudioComponent(gain: Audio.Decibel(decibels)))
        entity.playAudio(resource)
    }

    // MARK: Synthesis

    private static let sampleRate = 44_100.0

    private static func writeIfNeeded(_ sound: Sound) throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhysicsPlaygroundSounds", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(sound.rawValue).wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try wavData(samples: synthesize(sound)).write(to: url)
        }
        return url
    }

    private static func synthesize(_ sound: Sound) -> [Float] {
        switch sound {
        case .pop:
            // A quick downward pluck: 700 → 320 Hz over 0.1 s.
            return render(duration: 0.10) { t, _ in
                let frequency = 700 - 3800 * t
                return sin(2 * .pi * max(frequency, 320) * t) * exp(-t * 38)
            }
        case .whoosh:
            // Low-passed noise with a swelling envelope.
            var lowPassed: Double = 0
            return render(duration: 0.32) { t, duration in
                let noise = Double.random(in: -1...1)
                lowPassed += 0.08 * (noise - lowPassed)
                return lowPassed * 3 * sin(.pi * t / duration)
            }
        case .thud:
            // A soft body hitting the floor: 85 Hz with a dash of noise.
            return render(duration: 0.18) { t, _ in
                (sin(2 * .pi * 85 * t) + 0.18 * .random(in: -1...1)) * exp(-t * 24)
            }
        case .chime:
            // E5 + B5 + E6, gently decaying — the score sound.
            return render(duration: 0.7) { t, _ in
                (0.5 * sin(2 * .pi * 659.26 * t)
                    + 0.3 * sin(2 * .pi * 987.77 * t)
                    + 0.2 * sin(2 * .pi * 1318.51 * t)) * exp(-t * 5.5)
            }
        case .boom:
            // Deep and round, for mergers: 55 Hz + filtered noise.
            var lowPassed: Double = 0
            return render(duration: 0.6) { t, _ in
                let noise = Double.random(in: -1...1)
                lowPassed += 0.05 * (noise - lowPassed)
                return (sin(2 * .pi * 55 * t) + 1.6 * lowPassed) * exp(-t * 7)
            }
        }
    }

    private static func render(duration: Double, _ sample: (Double, Double) -> Double) -> [Float] {
        let count = Int(duration * sampleRate)
        var peak = 1e-6
        var raw = [Double](repeating: 0, count: count)
        for index in 0..<count {
            raw[index] = sample(Double(index) / sampleRate, duration)
            peak = max(peak, abs(raw[index]))
        }
        // Normalize to a polite −6 dBFS.
        return raw.map { Float($0 / peak * 0.5) }
    }

    /// Minimal mono 16-bit PCM WAV container.
    private static func wavData(samples: [Float]) -> Data {
        var data = Data()
        let dataSize = samples.count * 2

        func append(_ string: String) { data.append(string.data(using: .ascii)!) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF"); append32(UInt32(36 + dataSize)); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1)
        append32(UInt32(sampleRate)); append32(UInt32(sampleRate) * 2)
        append16(2); append16(16)
        append("data"); append32(UInt32(dataSize))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append16(UInt16(bitPattern: Int16(clamped * 32_767)))
        }
        return data
    }
}
