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
        /// The grab acknowledgement (2026-08-06): a short bright pluck,
        /// quieter and quicker than `pop` — the audio half of the
        /// pickup pulse. Its gentler sibling `releaseTick` answers a
        /// set-down, and closes a control ring (open keeps its pop, so
        /// the pair reads as unfold/fold rather than two unfolds).
        case grabTick, releaseTick
        /// The home's arrival (2026-08-14): a warm swell under the
        /// centred wordmark that resolves into a soft bell exactly as
        /// the mark lands on the wall, then dies away with the cascade.
        /// Its bell time and `HubIntro.landingTime` are pinned to each
        /// other in `HubIntroTests` — the sound is the choreography's
        /// clock made audible, and the two must not drift.
        case calibration
    }

    /// When `calibration`'s bell strikes, seconds into the file — the
    /// moment the wordmark lands. See `HubIntro.landingTime`.
    nonisolated static let calibrationLanding = 2.65

    private static var resources: [Sound: AudioFileResource] = [:]
    private static var warmed = false

    /// Every WAV this palette needs, once they exist on disk.
    private nonisolated struct CachedSounds: Sendable {
        var oneShots: [Sound: URL] = [:]
        var ambient: URL?
        var resonanceTone: URL?
    }

    /// Synthesize (if needed) and load every sound. Call once, early.
    ///
    /// THE SYNTHESIS RUNS OFF THE MAIN THREAD and must keep doing so.
    /// This enum is `@MainActor`, so an unstructured `Task {}` inside it
    /// INHERITS the main actor, and `writeIfNeeded` and friends are
    /// synchronous — which meant that until 2026-08-07 first launch
    /// rendered ~40 s of audio (36 s of it the ambient pad, every sample
    /// summing nine detuned voice pairs, then a 3.2 MB `Data` built two
    /// bytes at a time) on the main thread while the home screen was
    /// trying to draw. Invisible on a warm simulator, because the files
    /// are already on disk; a multi-second stall on a cold install and
    /// after any purge of Caches.
    ///
    /// The sample math is pure `[Float]` arithmetic over `Sendable`
    /// values and reads no actor state, so it is `nonisolated` and runs
    /// detached. Only the `AudioFileResource` loads and the property
    /// writes come back here.
    static func warmUp() {
        guard !warmed else { return }
        warmed = true
        Task {
            let cached = await Task.detached(priority: .utility) { () -> CachedSounds in
                var cached = CachedSounds()
                for sound in Sound.allCases {
                    cached.oneShots[sound] = try? writeIfNeeded(sound)
                }
                cached.ambient = try? writeAmbientIfNeeded()
                cached.resonanceTone = try? writeResonanceToneIfNeeded()
                return cached
            }.value

            for (sound, url) in cached.oneShots {
                if let resource = try? await AudioFileResource(contentsOf: url) {
                    resources[sound] = resource
                }
            }
            if let url = cached.ambient {
                ambientResource = try? await AudioFileResource(
                    contentsOf: url,
                    configuration: .init(shouldLoop: true))
            }
            if let url = cached.resonanceTone {
                resonanceToneResource = try? await AudioFileResource(
                    contentsOf: url,
                    configuration: .init(shouldLoop: true))
            }
        }
    }

    /// The cache directory every `write…IfNeeded` writes into.
    ///
    /// CACHE FILENAMES CARRY A VERSION SUFFIX, all four of them as of
    /// 2026-08-07. Synthesis is cached to disk and only ever written
    /// when the file is absent, so editing a recipe without renaming its
    /// file changes nothing for anyone who has already launched the app.
    /// `ambient-lab-4.wav` had followed that rule since it was written;
    /// the pops, the fan hum and the resonance tone had not, so three of
    /// the four recipes were uneditable in practice and the comment
    /// stating the rule was a rule we followed once.
    private nonisolated static func soundsDirectory() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhysicsPlaygroundSounds", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: Resonance tone (elastic-field drumhead)

    private static var resonanceToneResource: AudioFileResource?
    /// The base pitch (Hz) the tone is synthesized at; the caller shifts
    /// it with the controller's `speed` to sing the swept drive.
    nonisolated static let resonanceToneBaseHz = 220.0

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

    private nonisolated static func writeResonanceToneIfNeeded() throws -> URL {
        let url = try soundsDirectory().appendingPathComponent("resonance-tone-1.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try wavData(samples: synthesizeResonanceTone()).write(to: url)
        }
        return url
    }

    /// A 1-second seamless loop of a warm drum-like tone: a 220 Hz
    /// fundamental with a couple of soft harmonics (all integer cycles in
    /// one second, so the loop seam vanishes).
    private nonisolated static func synthesizeResonanceTone() -> [Float] {
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

    private nonisolated static func writeAmbientIfNeeded() throws -> URL {
        let url = try soundsDirectory().appendingPathComponent("ambient-lab-4.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try wavData(samples: synthesizeAmbient()).write(to: url)
        }
        return url
    }

    /// The house soundscape, fourth recipe: a 36-second seamless drift
    /// that reads as a planetarium after closing.
    ///
    /// What changed from the third, and why. ETHEREAL is voicing:
    /// the previous pad was a full A-major chord, and a major third is
    /// SWEET — resolved, earthbound. This one is suspended: open fifths
    /// and a ninth (A·E·B) with no third anywhere, octaves whispering
    /// above, so the chord floats without ever landing. SOOTHING is
    /// tempo: the loop is half again as long, every swell is slower,
    /// the top voices are quieter and surface rarely, and the one
    /// communal breath takes the whole 36 seconds. Three far-away bell
    /// glints cross the loop — sparse enough to be noticed maybe once
    /// a minute, never awaited.
    ///
    /// Still PURELY TONAL (the filtered-noise "air" of recipe two read
    /// as static over spatial audio), and still mathematically seamless:
    /// every sustained frequency, detune and swell is quantised to a
    /// whole number of cycles per loop. The glints are enveloped to
    /// silence well inside the loop, so they need no quantising.
    private nonisolated static func synthesizeAmbient() -> [Float] {
        let loop = 36.0
        let grid = { (frequency: Double) in (frequency * loop).rounded() / loop }

        // A1 sub, then A2 E3 A3 B3 E4 B4 E5 A5 — fifths, ninths,
        // octaves. No third: suspended, open, glassy.
        let voices: [(frequency: Double, amplitude: Double)] = [
            (grid(55.0), 0.10),
            (grid(110.0), 0.16),
            (grid(164.81), 0.14),
            (grid(220.0), 0.12),
            (grid(246.94), 0.08),
            (grid(329.63), 0.07),
            (grid(493.88), 0.04),
            (grid(659.26), 0.025),
            (grid(880.0), 0.015),
        ]

        // The glints: three soft bells far off in the dark, each an
        // octave-ish pair with a slightly inharmonic partial (what makes
        // a bell a bell and not an organ). Attack eased so there is no
        // click; tails die out before the loop ends.
        let glints: [(at: Double, frequency: Double, amplitude: Double)] = [
            (6.0, 1318.51, 0.020),   // E6
            (17.5, 880.0, 0.016),    // A5
            (28.0, 987.77, 0.018),   // B5
        ]

        return render(duration: loop) { t, _ in
            var pad = 0.0
            for (index, voice) in voices.enumerated() {
                // Detuned pairs whose beats complete 1, 2, 3… whole
                // cycles per loop — the shimmer never repeats the same
                // way twice inside one pass yet loops exactly.
                let detune = Double(index + 1) / loop
                let pair = 0.5 * (sin(2 * .pi * voice.frequency * t)
                    + sin(2 * .pi * (voice.frequency + detune) * t + 0.7))
                // Slow independent swells — 36, 18 and 12 second
                // periods, so voices surface and sink in turn. The high
                // voices ride the slowest swells: glass should drift,
                // not flicker.
                let cycles = Double((index % 3) + 1)
                let swell = 0.68 + 0.32 * sin(2 * .pi * cycles * t / loop
                                              + Double(index) * 2.1)
                pad += voice.amplitude * pair * swell
            }
            // One long communal breath across the whole loop.
            let breath = 1 + 0.06 * sin(2 * .pi * t / loop)

            var bells = 0.0
            for glint in glints where t >= glint.at {
                let age = t - glint.at
                let envelope = (1 - exp(-age * 9)) * exp(-age * 0.9)
                bells += glint.amplitude * envelope
                    * (sin(2 * .pi * glint.frequency * age)
                        + 0.35 * sin(2 * .pi * glint.frequency * 2.41 * age))
            }
            return pad * breath + bells
        }
    }

    // THE FAN HUM WENT WITH THE WIND TUNNEL, three days late.
    //
    // A 3-second axial-fan loop — broadband air noise pulsed at the
    // blade-pass rate over a motor hum — synthesized, written to
    // Caches, and loaded as an `AudioFileResource` on every launch.
    // `startFanHum` had no callers anywhere, including tests: the
    // module it blew through was archived 2026-07-30 and the sound
    // kept being made for it for ten days. Deleted 2026-08-09.
    //
    // It is the only piece of residue found in this pass that cost
    // anything at RUNTIME rather than just space on the page, which is
    // the argument for checking `warmUp`'s list against its callers
    // whenever a module leaves: synthesis is keyed off `CachedSounds`,
    // and a field nobody reads still gets rendered.

    /// Settings' master volume, 0…1. Applied to every one-shot; the
    /// settings window writes it here so callers never have to know.
    static var masterVolume: Double = 1

    /// Plays `sound` spatially from `entity` (which should already sit at
    /// the source position). volume 0…1 → −28…0 dB.
    static func play(_ sound: Sound, on entity: Entity, volume: Double = 1) {
        guard let resource = resources[sound] else { return }
        let effective = min(max(volume * masterVolume, 0), 1)
        guard effective > 0.001 else { return }
        let decibels = -28.0 * (1 - effective)
        entity.components.set(SpatialAudioComponent(gain: Audio.Decibel(decibels)))
        entity.playAudio(resource)
    }

    // MARK: Synthesis

    private nonisolated static let sampleRate = 44_100.0

    private nonisolated static func writeIfNeeded(_ sound: Sound) throws -> URL {
        let url = try soundsDirectory().appendingPathComponent("\(sound.rawValue)-1.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try wavData(samples: synthesize(sound)).write(to: url)
        }
        return url
    }

    private nonisolated static func synthesize(_ sound: Sound) -> [Float] {
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
        case .calibration:
            // The arrival. A warm low fifth (A2 + E3, with an octave
            // shade) swelling in over the beat, a soft A4/E5 bell at
            // the landing, a shared tail out under the cascade. The
            // pad's slow square-law swell is what makes it read as an
            // instrument warming rather than a note starting.
            let landing = calibrationLanding
            return render(duration: 3.4) { t, _ in
                let swell = min(t / 2.0, 1)
                let pad = (sin(2 * .pi * 110 * t)
                           + 0.7 * sin(2 * .pi * 165.05 * t)
                           + 0.35 * sin(2 * .pi * 220.3 * t))
                    * 0.2 * swell * swell * exp(-max(t - landing, 0) * 2.2)
                var bell = 0.0
                if t > landing {
                    let struck = t - landing
                    bell = (0.5 * sin(2 * .pi * 440 * struck)
                            + 0.3 * sin(2 * .pi * 659.26 * struck)
                            + 0.15 * sin(2 * .pi * 880 * struck))
                        * exp(-struck * 4.5) * 0.8
                }
                return pad + bell
            }
        case .grabTick:
            // A short bright pluck: 1200 → 900 Hz over 40 ms, gone
            // before the hand has finished closing.
            return render(duration: 0.04) { t, _ in
                let frequency = 1200 - 7500 * t
                return sin(2 * .pi * max(frequency, 900) * t) * exp(-t * 70)
            }
        case .releaseTick:
            // The set-down: lower, softer, slightly longer — an answer,
            // not an echo.
            return render(duration: 0.055) { t, _ in
                let frequency = 900 - 3600 * t
                return sin(2 * .pi * max(frequency, 700) * t) * exp(-t * 55)
            }
        }
    }

    private nonisolated static func render(duration: Double, _ sample: (Double, Double) -> Double) -> [Float] {
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
    private nonisolated static func wavData(samples: [Float]) -> Data {
        let dataSize = samples.count * 2
        // The ambient pad is 36 s at 44.1 kHz — a 3.2 MB `Data` grown
        // two bytes at a time is a few dozen reallocations and copies.
        var data = Data()
        data.reserveCapacity(44 + dataSize)

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
