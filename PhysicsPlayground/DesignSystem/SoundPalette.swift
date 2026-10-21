//
//  SoundPalette.swift
//  Physics Playground — Design system
//
//  All sounds are synthesized (`SoundEffects`, `AmbientScore`), written once
//  as WAVs into Caches, and loaded as AudioFileResources. Models publish SpatialSoundEvents; renderers
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
    /// Each recipe is in `SoundEffects`, under the same name.
    enum Sound: String, CaseIterable {
        case pop, whoosh, thud, chime, boom
        /// Grab acknowledgement; `releaseTick` answers a set-down and closes
        /// a ring (open keeps its pop, so the pair reads unfold/fold).
        case grabTick, releaseTick
        /// The opening's swell. Its bell time and `Opening.landingTime` are
        /// pinned to each other in `OpeningTests` — they must not drift.
        case calibration
        /// Steel on steel: Newton's cradle (it borrowed `pop` until 2026-10-14).
        case clack
        /// The launcher's pneumatic thump (it borrowed `pop` too).
        case launch
        /// A remarkable moment, through `Remark` and nowhere else.
        case gleam
    }

    /// When `calibration`'s bell strikes, seconds into the file — must match `Opening.landingTime`.
    nonisolated static let calibrationLanding = SoundEffects.calibrationLanding

    private static var resources: [Sound: AudioFileResource] = [:]
    private static var warmed = false

    /// Every WAV this palette needs, once they exist on disk.
    private nonisolated struct CachedSounds: Sendable {
        var oneShots: [Sound: URL] = [:]
        var tones: [Tone: URL] = [:]
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
                for tone in Tone.allCases {
                    cached.tones[tone] = try? writeIfNeeded(tone)
                }
                return cached
            }.value

            for (sound, url) in cached.oneShots {
                if let resource = try? await AudioFileResource(contentsOf: url) {
                    resources[sound] = resource
                }
            }
            for (tone, url) in cached.tones {
                toneResources[tone] = try? await AudioFileResource(
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

    /// Deletes earlier versions of a cached file — `pop-1.wav` once
    /// `pop-2.wav` exists — so a re-voiced sound does not leave the old
    /// one behind in Caches for ever.
    private nonisolated static func removeOlderVersions(of prefix: String, keeping current: String,
                                                        in directory: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(prefix) && name != current {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    // MARK: Looping tones (sonification)

    /// The continuous voices. `glass` sings the orbital chord; `hum` is
    /// Circuit Workshop's mains, played slowed to ~52 Hz (they were one
    /// tone until 2026-10-14, which made the chord buzz or the hum ring);
    /// `beep` is the multimeter's continuity tone, at its own pitch.
    enum Tone: String, CaseIterable {
        case glass, hum, beep
    }

    private static var toneResources: [Tone: AudioFileResource] = [:]
    /// The base pitch (Hz) both tones are synthesized at; the caller shifts
    /// it with the controller's `speed`.
    nonisolated static let resonanceToneBaseHz = SoundEffects.toneBaseHz

    /// Starts a looping tone on `entity`, silent. The caller sets `gain`
    /// from loudness and `speed` from pitch.
    static func startTone(_ tone: Tone, on entity: Entity) -> AudioPlaybackController? {
        guard let resource = toneResources[tone] else { return nil }
        entity.components.set(SpatialAudioComponent(gain: Audio.Decibel(-80)))
        let controller = entity.playAudio(resource)
        controller.gain = -80
        return controller
    }

    private nonisolated static func writeIfNeeded(_ tone: Tone) throws -> URL {
        let directory = try soundsDirectory()
        let name = "tone-\(tone.rawValue)-1.wav"
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            let samples = switch tone {
            case .glass: SoundEffects.glassTone(sampleRate: sampleRate)
            case .hum: SoundEffects.humTone(sampleRate: sampleRate)
            case .beep: SoundEffects.beepTone(sampleRate: sampleRate)
            }
            try wavData(samples: samples).write(to: url)
        }
        removeOlderVersions(of: "tone-\(tone.rawValue)-", keeping: name, in: directory)
        // The single tone both voices shared before they were split.
        removeOlderVersions(of: "resonance-tone-", keeping: "", in: directory)
        return url
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
    /// Returns the playback, for the one caller that must stop it early
    /// (a skipped opening fades its swell out rather than let it play on).
    @discardableResult
    static func play(_ sound: Sound, on entity: Entity, volume: Double = 1) -> AudioPlaybackController? {
        guard let resource = resources[sound] else { return nil }
        let effective = min(max(volume * masterVolume, 0), 1)
        guard effective > 0.001 else { return nil }
        let decibels = -28.0 * (1 - effective)
        entity.components.set(SpatialAudioComponent(gain: Audio.Decibel(decibels)))
        return entity.playAudio(resource)
    }

    // MARK: Synthesis

    private nonisolated static let sampleRate = 44_100.0

    /// Cache names carry the recipe's version: bump it whenever
    /// `SoundEffects` changes a sound, or nobody who has launched before
    /// will hear the change. Version 2 is the 2026-10-14 re-voicing; 3, the
    /// opening re-scored for "Birth of a System" (2026-10-20).
    private nonisolated static let oneShotVersion = 3

    private nonisolated static func writeIfNeeded(_ sound: Sound) throws -> URL {
        let directory = try soundsDirectory()
        let name = "\(sound.rawValue)-\(oneShotVersion).wav"
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try wavData(samples: SoundEffects.oneShot(sound.rawValue, sampleRate: sampleRate))
                .write(to: url)
        }
        removeOlderVersions(of: "\(sound.rawValue)-", keeping: name, in: directory)
        return url
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
