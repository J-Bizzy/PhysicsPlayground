//
//  SoundPalette.swift
//  Physics Playground — Design system
//
//  All sounds are synthesized, written once as WAVs into Caches, and loaded
//  as AudioFileResources. Models publish SpatialSoundEvents; renderers
//  position an emitter and play. The one sound that is not in the room is
//  the house music (`AmbientScore`), a head-locked stereo bed. No-ops if
//  loading fails.
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
        /// Grab acknowledgement; `releaseTick` answers a set-down and closes
        /// a ring (open keeps its pop, so the pair reads unfold/fold).
        case grabTick, releaseTick
        /// The opening's swell. Its bell time and `Opening.landingTime` are
        /// pinned to each other in `OpeningTests` — they must not drift.
        case calibration
    }

    /// When `calibration`'s bell strikes, seconds into the file — must match `Opening.landingTime`.
    nonisolated static let calibrationLanding = 2.65

    private static var resources: [Sound: AudioFileResource] = [:]
    private static var warmed = false

    /// Every WAV this palette needs, once they exist on disk.
    private nonisolated struct CachedSounds: Sendable {
        var oneShots: [Sound: URL] = [:]
        var resonanceTone: URL?
    }

    /// Synthesize (if needed) and load every sound. Call once, early.
    /// Synthesis must stay off the main actor: an unstructured `Task {}`
    /// here inherits @MainActor, so the sample math runs detached
    /// (`nonisolated`); only the resource loads come back here.
    ///
    /// The one-shots come first: the opening's bell plays within seconds of
    /// a first launch, and the score takes about a second to render — it
    /// must never queue in front of them.
    static func warmUp() {
        guard !warmed else { return }
        warmed = true
        Task {
            let cached = await Task.detached(priority: .utility) { () -> CachedSounds in
                var cached = CachedSounds()
                for sound in Sound.allCases {
                    cached.oneShots[sound] = try? writeIfNeeded(sound)
                }
                cached.resonanceTone = try? writeResonanceToneIfNeeded()
                return cached
            }.value

            for (sound, url) in cached.oneShots {
                if let resource = try? await AudioFileResource(contentsOf: url) {
                    resources[sound] = resource
                }
            }
            if let url = cached.resonanceTone {
                resonanceToneResource = try? await AudioFileResource(
                    contentsOf: url,
                    configuration: .init(shouldLoop: true))
            }

            let ambient = await Task.detached(priority: .utility) {
                try? writeAmbientIfNeeded()
            }.value
            if let ambient {
                ambientResource = try? await AudioFileResource(
                    contentsOf: ambient,
                    configuration: .init(shouldLoop: true))
            }
        }
    }

    /// The cache directory. Cache filenames carry A version suffix: a file
    /// is only written when absent, so editing a recipe without renaming
    /// its file changes nothing for anyone who has already launched.
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

    /// Starts the looping resonance tone on `entity`, silent. The caller
    /// sets `gain` from ring amplitude and `speed` from drive frequency.
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

    /// A 1 s seamless loop: 220 Hz fundamental plus soft harmonics — all
    /// integer cycles per second, so the loop seam vanishes.
    private nonisolated static func synthesizeResonanceTone() -> [Float] {
        render(duration: 1.0) { t, _ in
            let f = resonanceToneBaseHz
            return 0.7 * sin(2 * .pi * f * t)
                + 0.22 * sin(2 * .pi * 2 * f * t)
                + 0.09 * sin(2 * .pi * 3 * f * t)
        }
    }

    // MARK: The house music

    private static var ambientResource: AudioFileResource?
    /// How long the music takes to come up from silence when it starts.
    static let ambientFadeIn: TimeInterval = 4

    /// Starts the looping house music on `entity`, rising out of silence.
    /// It is a stereo bed, not a thing in the room: `ChannelAudioComponent`
    /// plays it head-locked and unspatialized, the way visionOS plays
    /// background music, where the old mono pad hung at one point a metre
    /// in front of the wearer and changed as they walked. Returns nil until
    /// warmUp's synthesis has finished.
    static func startAmbient(on entity: Entity, gainDecibels: Double = -22) -> AudioPlaybackController? {
        guard let ambientResource else { return nil }
        entity.components.remove(SpatialAudioComponent.self)
        entity.components.set(ChannelAudioComponent(gain: Audio.Decibel(gainDecibels)))
        let controller = entity.playAudio(ambientResource)
        controller.gain = -60
        controller.fade(to: 0, duration: ambientFadeIn)
        return controller
    }

    /// Lets the music fall away rather than cutting it off.
    static func stopAmbient(_ controller: AudioPlaybackController) {
        controller.fade(to: -60, duration: 1.2)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_300))
            controller.stop()
        }
    }

    /// The score (`AmbientScore`), rendered once to a stereo WAV. The
    /// version is in the name: bump it whenever the score changes, or
    /// nobody who has launched before will ever hear the change.
    private nonisolated static let ambientFileName = "ambient-score-1.wav"

    private nonisolated static func writeAmbientIfNeeded() throws -> URL {
        let directory = try soundsDirectory()
        let url = directory.appendingPathComponent(ambientFileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            let (left, right) = AmbientScore.render(sampleRate: sampleRate)
            try wavData(channels: [left, right]).write(to: url)
        }
        // Earlier soundtracks (`ambient-lab-1…4`, the mono pad) are dead
        // weight in Caches once the score exists.
        let stale = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in stale where name.hasPrefix("ambient-") && name != ambientFileName {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        return url
    }

    // When a module leaves, check `CachedSounds` against its callers — a
    // field nobody reads still renders on every cold launch.

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
            // A warm low fifth swelling in, a soft bell at the landing,
            // a shared tail out under the cascade.
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
            // A short bright pluck: 1200 → 900 Hz over 40 ms.
            return render(duration: 0.04) { t, _ in
                let frequency = 1200 - 7500 * t
                return sin(2 * .pi * max(frequency, 900) * t) * exp(-t * 70)
            }
        case .releaseTick:
            // The set-down: lower, softer, slightly longer.
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
        wavData(channels: [samples])
    }

    /// Minimal 16-bit PCM WAV container, channels interleaved; every
    /// channel the same length.
    nonisolated static func wavData(channels: [[Float]]) -> Data {
        let count = channels.count
        let frames = channels.first?.count ?? 0
        let dataSize = frames * count * 2
        // Reserve up front — the score is 11 MB; growing two bytes at a
        // time reallocates dozens of times.
        var data = Data()
        data.reserveCapacity(44 + dataSize)

        func append(_ string: String) { data.append(string.data(using: .ascii)!) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF"); append32(UInt32(36 + dataSize)); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(UInt16(count))
        append32(UInt32(sampleRate)); append32(UInt32(sampleRate) * UInt32(count) * 2)
        append16(UInt16(count * 2)); append16(16)
        append("data"); append32(UInt32(dataSize))
        for frame in 0..<frames {
            for channel in channels {
                let clamped = max(-1, min(1, channel[frame]))
                append16(UInt16(bitPattern: Int16(clamped * 32_767)))
            }
        }
        return data
    }
}
