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
        }
    }

    /// Plays `sound` spatially from `entity` (which should already sit at
    /// the source position). volume 0…1 → −28…0 dB.
    static func play(_ sound: Sound, on entity: Entity, volume: Double = 1) {
        guard let resource = resources[sound] else { return }
        let decibels = -28.0 * (1 - min(max(volume, 0), 1))
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
