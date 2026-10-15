//
//  SoundEffects.swift
//  Physics Playground — Design system
//
//  Every one-shot and looping tone `SoundPalette` plays, as sample math.
//  One family with the house music (`AmbientScore`, whose oscillators,
//  filters and room it borrows): everything tonal is tuned to A major —
//  ticks on E6 and B5, the pop on A5, the chime a rolled A-major triad
//  of the score's own bells — and everything physical is shaped from
//  filtered noise and falling pitch, never raw white noise. Every sound
//  opens on a soft onset and decays to true silence, so none of them
//  clicks at either end.
//
//  Pure Foundation, so the same file renders listening previews on the
//  Mac. Seeded noise: every device writes the same files, which matters
//  because the cache is versioned by file name.
//

import Foundation

nonisolated enum SoundEffects {

    /// When the opening's bell strikes, seconds into `calibration` —
    /// `Opening.landingTime` is pinned to it by `OpeningTests`.
    static let calibrationLanding = 2.65

    /// Every one-shot, by the name `SoundPalette.Sound` uses.
    static let names = ["pop", "whoosh", "thud", "chime", "boom",
                        "grabTick", "releaseTick", "calibration", "clack", "launch"]

    /// One-shot samples, mono, peak-normalised to −6 dBFS (what every
    /// call site's volume was tuned against) times the sound's own trim.
    static func oneShot(_ name: String, sampleRate: Double = 44_100) -> [Float] {
        let raw: [Double]
        var trim = 1.0
        switch name {
        case "pop": raw = pop(sampleRate)
        case "whoosh": raw = whoosh(sampleRate)
        case "thud": raw = thud(sampleRate)
        case "chime": raw = chime(sampleRate); trim = 0.9
        // Sustained, so at the old peak it measured 3.6 dB louder.
        case "boom": raw = boom(sampleRate); trim = 0.68
        case "grabTick": raw = tick(sampleRate, frequency: hz(88), decay: 85, length: 0.07)
        case "releaseTick": raw = tick(sampleRate, frequency: hz(83), decay: 62, length: 0.09)
        case "calibration": raw = calibration(sampleRate)
        // Twenty milliseconds of ring reads quieter than its peak says.
        case "clack": raw = clack(sampleRate); trim = 1.5
        case "launch": raw = launch(sampleRate)
        default: raw = []
        }
        return normalise(fadeOut(raw, sampleRate), peak: 0.5 * trim)
    }

    /// A raised-cosine fade over the last quarter of a sound, at most
    /// 80 ms: whatever a recipe leaves ringing at the cut, the file ends
    /// on silence.
    static func fadeOut(_ raw: [Double], _ rate: Double) -> [Double] {
        var out = raw
        let fade = min(raw.count / 4, Int(0.08 * rate))
        guard fade > 0 else { return out }
        for k in 0..<fade {
            out[raw.count - 1 - k] *= 0.5 - 0.5 * cos(.pi * Double(k) / Double(fade))
        }
        return out
    }

    // MARK: The interface family

    /// A glass droplet on A5: a quick glide down into the note and one
    /// inharmonic glass mode that dies first. Rings, wells, petals, a
    /// wire landing.
    static func pop(_ rate: Double) -> [Double] {
        var phase = 0.0
        let dry = samples(0.22, rate) { t in
            let f = hz(81) * (1 + 0.32 * exp(-t * 55))
            phase += f / rate
            let tone = sin(2 * .pi * phase)
                + 0.16 * sin(2 * .pi * phase * 2.76) * exp(-t * 45)
            return tone * onset(t, 0.0015) * exp(-t * 24)
        }
        return withRoom(dry, rate, size: 0.72, wet: 0.14, tail: 0.25)
    }

    /// The grab and the set-down: a pure tone with the shortest possible
    /// soft attack, so it reads as a tick and never as a click. A grab on
    /// E6, a release a fourth lower on B5 and a touch longer.
    static func tick(_ rate: Double, frequency: Double, decay: Double, length: Double) -> [Double] {
        var phase = 0.0
        return samples(length, rate) { t in
            let f = frequency * (1 + 0.04 * exp(-t * 120))
            phase += f / rate
            return (sin(2 * .pi * phase) + 0.1 * sin(4 * .pi * phase))
                * onset(t, 0.0008) * exp(-t * decay)
        }
    }

    /// Success: a rolled A-major triad (A5, C♯6, E6) of the score's FM
    /// bells, 45 ms apart, in a small room. The hoop, a choice, a capture.
    static func chime(_ rate: Double) -> [Double] {
        let notes: [(at: Double, midi: Int, gain: Double)] = [
            (0, 81, 1), (0.045, 85, 0.8), (0.09, 88, 0.7),
        ]
        var dry = [Double](repeating: 0, count: Int(1.4 * rate))
        for note in notes {
            let bell = fmBell(rate, frequency: hz(note.midi), length: 1.3, ring: 2.3)
            let start = Int(note.at * rate)
            for i in bell.indices where start + i < dry.count {
                dry[start + i] += bell[i] * note.gain
            }
        }
        return withRoom(dry, rate, size: 0.8, wet: 0.22, tail: 0.6)
    }

    /// The opening: the score's first chord rising out of nothing — warm
    /// saws behind a filter that opens as it swells, under an airy rise
    /// — which lets go the instant the bell strikes at the landing.
    static func calibration(_ rate: Double) -> [Double] {
        let landing = calibrationLanding
        let length = 4.8
        var out = [Double](repeating: 0, count: Int(length * rate))

        // The swell: A2 E3 B3 C♯4 through a low-pass opening 250 → 1,400 Hz.
        for (index, midi) in [45, 52, 59, 61].enumerated() {
            var saws = [-7.0, 6.0].map {
                AmbientScore.Saw(frequency: hz(midi) * pow(2, $0 / 1200),
                                 sampleRate: rate, phase: Double(index) * 0.31)
            }
            var stage1 = AmbientScore.SVF(), stage2 = AmbientScore.SVF()
            let gain = 0.22 * pow(110 / hz(midi), 0.3)
            for i in out.indices {
                let t = Double(i) / rate
                guard t < landing + 0.6 else { break }
                if i & 15 == 0 {
                    let open = min(t / landing, 1)
                    let cutoff = 250 + 1_150 * open * open
                    stage1.tune(cutoff: cutoff, sampleRate: rate, damping: 1.848)
                    stage2.tune(cutoff: cutoff, sampleRate: rate, damping: 0.765)
                }
                let rise = pow(min(t / landing, 1), 2.2)
                let letGo = t < landing ? 1 : exp(-(t - landing) * 9)
                let v = (saws[0].next() + saws[1].next()) * 0.5
                out[i] += stage2.lowpass(stage1.lowpass(v)) * gain * rise * letGo
            }
        }

        // The air: seeded noise in a band rising 1.5 → 5 kHz, cresting
        // into the landing.
        var noise = AmbientScore.SplitMix64(seed: 0xCA1B)
        var air = AmbientScore.SVF()
        for i in out.indices {
            let t = Double(i) / rate
            guard t < landing + 0.3 else { break }
            if i & 15 == 0 {
                air.tune(cutoff: 1_500 + 3_500 * min(t / landing, 1),
                         sampleRate: rate, damping: 0.9)
            }
            let rise = pow(min(t / landing, 1), 3)
            let letGo = t < landing ? 1 : exp(-(t - landing) * 14)
            out[i] += air.bandpass(noise.next() * 2 - 1) * 0.05 * rise * letGo
        }

        // The bell: A4 under A5 and E6, struck at the landing.
        let landingIndex = Int(landing * rate)
        for (midi, gain) in [(69, 0.55), (81, 1.0), (88, 0.6)] {
            let bell = fmBell(rate, frequency: hz(midi), length: length - landing, ring: 1.2)
            for i in bell.indices where landingIndex + i < out.count {
                out[landingIndex + i] += bell[i] * gain * 0.55
            }
        }
        return withRoom(out, rate, size: 0.86, wet: 0.3, tail: 0)
    }

    // MARK: The physical family

    /// A soft body meeting something: a body tone falling 150 → 62 Hz, a
    /// second mode, and a contact that is filtered noise, not hiss. A
    /// ball's bounce, a magnet's snap, and every "no".
    static func thud(_ rate: Double) -> [Double] {
        var phase = 0.0
        var noise = AmbientScore.SplitMix64(seed: 0x7_4D)
        var contact = AmbientScore.SVF()
        contact.tune(cutoff: 900, sampleRate: rate, damping: 1.2)
        return samples(0.32, rate) { t in
            let f = 62 + 88 * exp(-t * 28)
            phase += f / rate
            let body = sin(2 * .pi * phase) * exp(-t * 17)
                + 0.25 * sin(2 * .pi * phase * 2.3) * exp(-t * 34)
            let hit = contact.lowpass(noise.next() * 2 - 1) * exp(-t * 110) * 0.9
            return (body + hit) * onset(t, 0.001)
        }
    }

    /// Air moving past: two bands of seeded noise sweeping up and back,
    /// cresting a third of the way in. A throw, a fling.
    static func whoosh(_ rate: Double) -> [Double] {
        let length = 0.42
        var noise = AmbientScore.SplitMix64(seed: 0x1_005)
        var low = AmbientScore.SVF(), high = AmbientScore.SVF()
        // A band-pass's skirts leave hiss above it; this takes the air out
        // of the air.
        var soften = AmbientScore.SVF()
        soften.tune(cutoff: 3_000, sampleRate: rate, damping: 1.4)
        return samples(length, rate) { t in
            let x = t / length
            // An asymmetric bump: quick rise, longer fall.
            let shape = x < 0.33 ? sin(.pi / 2 * x / 0.33) : cos(.pi / 2 * (x - 0.33) / 0.67)
            let sweep = shape * shape
            low.tune(cutoff: 380 + 1_100 * sweep, sampleRate: rate, damping: 0.8)
            high.tune(cutoff: 900 + 2_400 * sweep, sampleRate: rate, damping: 1.1)
            let n = noise.next() * 2 - 1
            return soften.lowpass(low.bandpass(n) + 0.45 * high.bandpass(n)) * sweep
        }
    }

    /// Something enormous: a sub falling 78 → 38 Hz, a low rumble of
    /// filtered noise, and a body tone an octave and a fifth up that
    /// dies first. Mergers, the binary split, a part burning out.
    static func boom(_ rate: Double) -> [Double] {
        var phase = 0.0, bodyPhase = 0.0
        var noise = AmbientScore.SplitMix64(seed: 0xB0_0B)
        var rumble = AmbientScore.SVF(), rumble2 = AmbientScore.SVF()
        rumble.tune(cutoff: 220, sampleRate: rate, damping: 1.848)
        rumble2.tune(cutoff: 220, sampleRate: rate, damping: 0.765)
        return samples(1.5, rate) { t in
            let f = 38 + 40 * exp(-t * 6)
            phase += f / rate
            bodyPhase += f * 3 / rate
            let sub = sin(2 * .pi * phase) * exp(-t * 3.0)
            let body = 0.25 * sin(2 * .pi * bodyPhase) * exp(-t * 9)
            let roar = rumble2.lowpass(rumble.lowpass(noise.next() * 2 - 1)) * 1.9 * exp(-t * 2.6)
            return (sub + body + roar) * onset(t, 0.004)
        }
    }

    /// Two steel balls: three of a steel sphere's high inharmonic modes,
    /// each ringing a few milliseconds, behind a contact a quarter of a
    /// millisecond long. Newton's cradle.
    static func clack(_ rate: Double) -> [Double] {
        var noise = AmbientScore.SplitMix64(seed: 0xC1_AC)
        let modes: [(f: Double, gain: Double, decay: Double)] = [
            (2_870, 1.0, 70), (4_610, 0.55, 95), (6_730, 0.3, 130),
        ]
        return samples(0.11, rate) { t in
            var ring = 0.0
            for mode in modes {
                ring += mode.gain * sin(2 * .pi * mode.f * t) * exp(-t * mode.decay)
            }
            let contact = (noise.next() * 2 - 1) * exp(-t * 4_000) * 0.6
            return (ring + contact) * onset(t, 0.0002)
        }
    }

    /// The launcher: a pneumatic thump — a tone falling 180 → 70 Hz, a
    /// burst of air in a band round 900 Hz, and a brighter hiss of escaping
    /// air that trails it.
    static func launch(_ rate: Double) -> [Double] {
        var phase = 0.0
        var noise = AmbientScore.SplitMix64(seed: 0x1A_C4)
        var burst = AmbientScore.SVF(), escape = AmbientScore.SVF(), soften = AmbientScore.SVF()
        burst.tune(cutoff: 900, sampleRate: rate, damping: 0.9)
        escape.tune(cutoff: 3_200, sampleRate: rate, damping: 1.3)
        soften.tune(cutoff: 5_000, sampleRate: rate, damping: 1.4)
        return samples(0.38, rate) { t in
            let f = 70 + 110 * exp(-t * 22)
            phase += f / rate
            let thump = sin(2 * .pi * phase) * exp(-t * 14)
            let n = noise.next() * 2 - 1
            let air = burst.bandpass(n) * 1.4 * exp(-t * 30)
                + soften.lowpass(escape.bandpass(n)) * 0.35 * exp(-t * 11)
            return (thump + air) * onset(t, 0.0015)
        }
    }

    // MARK: Looping tones

    /// The base pitch both loops are written at; callers shift it with
    /// playback speed.
    static let toneBaseHz = 220.0

    /// The orbital chord's voice: a soft glass tone — fundamental, a
    /// chorus partner 0.25 Hz above, and a few quiet harmonics. Four
    /// seconds, so every partial (and the chorus's beat) completes whole
    /// cycles and the loop has no seam.
    static func glassTone(sampleRate rate: Double = 44_100) -> [Float] {
        let f = toneBaseHz
        let raw = samples(4.0, rate) { t in
            sin(2 * .pi * f * t)
                + 0.55 * sin(2 * .pi * (f + 0.25) * t + 1.1)
                + 0.2 * sin(2 * .pi * 2 * f * t)
                + 0.06 * sin(2 * .pi * 3 * f * t)
                + 0.025 * sin(2 * .pi * 4 * f * t)
        }
        return normalise(raw, peak: 0.5)
    }

    /// The bench's mains hum: a full harmonic series, odd harmonics
    /// leaning forward the way a transformer's do, gently saturated. One
    /// second at 220 Hz, played at a quarter speed or so for ~52 Hz.
    static func humTone(sampleRate rate: Double = 44_100) -> [Float] {
        let f = toneBaseHz
        let raw = samples(1.0, rate) { t in
            var v = 0.0
            for n in 1...10 {
                let weight = pow(Double(n), -1.25) * (n.isMultiple(of: 2) ? 0.7 : 1.15)
                v += weight * sin(2 * .pi * Double(n) * f * t + Double(n) * 0.4)
            }
            return tanh(v * 0.9)
        }
        return normalise(raw, peak: 0.5)
    }

    // MARK: Building blocks

    static func hz(_ midi: Int) -> Double { AmbientScore.hertz(midi) }

    /// A raised-cosine onset over `seconds`: never a corner, never a click.
    static func onset(_ t: Double, _ seconds: Double) -> Double {
        t < seconds ? 0.5 - 0.5 * cos(.pi * t / seconds) : 1
    }

    /// `length` seconds of `sample(t)`.
    static func samples(_ length: Double, _ rate: Double,
                        _ sample: (Double) -> Double) -> [Double] {
        (0..<Int(length * rate)).map { sample(Double($0) / rate) }
    }

    /// The score's bell: a two-operator FM voice whose brightness decays
    /// faster than its ring.
    static func fmBell(_ rate: Double, frequency f: Double, length: Double,
                       ring: Double) -> [Double] {
        var carrier = 0.0, modulator = 0.0, sparkle = 0.0
        return samples(length, rate) { t in
            let index = 1.5 * exp(-t * 3.5)
            let v = sin(2 * .pi * carrier + index * sin(2 * .pi * modulator))
                + 0.1 * sin(2 * .pi * sparkle) * exp(-t * 3)
            carrier += f / rate
            modulator += 2 * f / rate
            sparkle += 4.07 * f / rate
            return v * onset(t, 0.004) * exp(-t * ring)
        }
    }

    /// `dry` in a small room (the score's, smaller), mixed `wet`, with
    /// `tail` seconds added for it to ring into. Mono out.
    static func withRoom(_ dry: [Double], _ rate: Double, size: Double,
                         wet: Double, tail: Double) -> [Double] {
        let total = dry.count + Int(tail * rate)
        var room = AmbientScore.Room(sampleRate: rate, size: size)
        var reverb = [Double](repeating: 0, count: total)
        for i in 0..<total {
            let x = i < dry.count ? dry[i] : 0
            let (l, r) = room.process(x, x)
            reverb[i] = (l + r) * 0.5
        }
        // Wet set by measure against the dry, as the score does it.
        let dryPower = dry.reduce(0) { $0 + $1 * $1 }
        let wetPower = reverb.reduce(0) { $0 + $1 * $1 }
        let gain = wet * sqrt(dryPower / max(wetPower, 1e-12))
        var out = [Double](repeating: 0, count: total)
        for i in 0..<total {
            out[i] = (i < dry.count ? dry[i] : 0) + reverb[i] * gain
        }
        // The room's last moments fade to true silence.
        let fade = min(Int(0.05 * rate), total)
        for k in 0..<fade {
            out[total - 1 - k] *= Double(k) / Double(fade)
        }
        return out
    }

    static func normalise(_ raw: [Double], peak: Double) -> [Float] {
        let top = raw.reduce(1e-9) { max($0, abs($1)) }
        return raw.map { Float($0 / top * peak) }
    }
}
