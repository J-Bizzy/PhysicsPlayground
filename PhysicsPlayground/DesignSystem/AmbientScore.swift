//
//  AmbientScore.swift
//  Physics Playground — Design system
//
//  The house soundscape, synthesized once and cached by `SoundPalette`:
//  a 64 s stereo loop of four suspended chords that hand over to each
//  other through the tones they share (E and G♯ ring through three of
//  them), each a bed of warm detuned saws under a glass layer of sines,
//  with a few soft bells answered by echoes, all in a long room.
//
//  Two rules keep it from being heard as a loop:
//  • Everything is an event on a timeline rendered past the loop's end,
//    and the overhang is folded back onto the start. The mix is linear
//    up to the final limiter, so the fold is exactly what the previous
//    pass would have left ringing — the seam does not exist.
//  • Nothing is random at runtime. A seeded generator places the bells,
//    so every launch writes the same file (the cache is versioned by
//    filename, and a file that changed under the same name would never
//    be rewritten).
//
//  Pure Foundation: `SoundPalette` writes it as a WAV, and the same file
//  compiles on the Mac for listening previews.
//

import Foundation

nonisolated enum AmbientScore {

    /// One full pass, seconds. Four chords of 16 s.
    static let loopSeconds = 64.0
    /// RMS per channel, the level the previous mono pad sat at (−17.3 dBFS),
    /// so changing the music does not change how loud the room is.
    static let targetRMS = 0.136
    /// Nothing passes this: the limiter's ceiling, about −1 dBFS.
    static let ceiling = 0.89

    /// Renders one seamless pass at `sampleRate`, normalized and limited,
    /// as two channels of equal length.
    static func render(sampleRate: Double = 44_100) -> (left: [Float], right: [Float]) {
        var mix = Mix(sampleRate: sampleRate, seconds: loopSeconds + overhang)
        for (index, chord) in progression.enumerated() {
            mix.addChord(chord, at: Double(index) * chordSeconds - 2.5)
        }
        mix.addBells(seed: 0x5EED_A11B)
        return mix.finish(loopSeconds: loopSeconds)
    }

    // MARK: The harmony

    /// How long each chord leads. Its voices bloom in over ~5 s before
    /// that and ring out ~7 s after, so neighbours always overlap.
    static let chordSeconds = 16.0
    /// Everything that sounds past the loop's end is folded back onto its
    /// start, so the render runs this far beyond it: the longest chord
    /// plus its release plus the reverb's tail.
    static let overhang = 34.0

    nonisolated struct Chord {
        /// The bass, an octave under the pad, a pure sine.
        let sub: Int
        /// The pad's notes, MIDI, low to high.
        let notes: [Int]
    }

    /// A major, drifting: Amaj9 → F♯m9 → Dmaj9♯11 (no third, so it stays
    /// open) → Esus2/4, which leans back into A. The voicings keep the old
    /// pad's suspended, glassy colour — fifths and ninths up top, thirds
    /// only where they are the colour.
    static let progression: [Chord] = [
        Chord(sub: 33, notes: [45, 52, 59, 61, 68]),        // A1 | A2 E3 B3 C♯4 G♯4
        Chord(sub: 30, notes: [42, 49, 57, 64, 68]),        // F♯1 | F♯2 C♯3 A3 E4 G♯4
        Chord(sub: 38, notes: [50, 57, 61, 64, 68]),        // D2 | D3 A3 C♯4 E4 G♯4
        Chord(sub: 40, notes: [52, 57, 59, 66, 71]),        // E2 | E3 A3 B3 F♯4 B4
    ]

    static func hertz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    // MARK: The mix

    nonisolated struct Mix {
        let sampleRate: Double
        let frames: Int
        // Dry buses, and what is sent on to the echoes and the room.
        var dryL: [Double], dryR: [Double]
        var echoSendL: [Double], echoSendR: [Double]
        var roomSendL: [Double], roomSendR: [Double]
        let sine = SineTable()

        init(sampleRate: Double, seconds: Double) {
            self.sampleRate = sampleRate
            frames = Int(seconds * sampleRate)
            let zeros = [Double](repeating: 0, count: frames)
            dryL = zeros; dryR = zeros
            echoSendL = zeros; echoSendR = zeros
            roomSendL = zeros; roomSendR = zeros
        }

        // MARK: Pad, glass and sub

        mutating func addChord(_ chord: Chord, at start: Double) {
            let length = AmbientScore.chordSeconds + 4.5   // overlaps the next chord's bloom
            // The sub: soft, centred, the chord's floor.
            addSine(AmbientScore.hertz(chord.sub), at: start + 0.5, length: length,
                    attack: 6, release: 7, gain: 0.10, pan: 0, tremolo: 0)
            for (index, note) in chord.notes.enumerated() {
                let f = AmbientScore.hertz(note)
                // Upper voices bloom a beat after the lower ones.
                let enter = start + Double(index) * 0.6
                // A gentle tilt: the low notes carry the body, the high ones
                // the air.
                let gain = 0.20 * pow(110 / f, 0.32)
                // The lowest note sits centred; the rest spread wider as they
                // climb, alternating sides so neither ear carries the chord.
                let side: Double = index.isMultiple(of: 2) ? 1 : -1
                let pan = index == 0 ? 0 : side * min(0.15 + Double(index) * 0.14, 0.7)
                addSawPad(f, at: enter, length: length, gain: gain, pan: pan,
                          breathe: 0.045 + 0.011 * Double(index))
                // The glass: the old pad's pure tones, kept on top of the warmth.
                if f > 180 {
                    addSine(f * 2.0006, at: enter + 1.2, length: length,
                            attack: 7, release: 8, gain: gain * 0.30, pan: -pan,
                            tremolo: 0.11 + 0.05 * Double(index))
                }
            }
        }

        /// Three band-limited saws, detuned −8 / 0 / +7 cents and spread
        /// across the stereo field, each side through its own soft 24 dB/oct
        /// low-pass (two state-variable stages) whose cutoff breathes
        /// slowly. Dark on purpose: the saws are the warmth under the glass,
        /// and a saw's upper harmonics are what turn a pad from ethereal to
        /// buzzy.
        mutating func addSawPad(_ f: Double, at start: Double, length: Double,
                                gain: Double, pan: Double, breathe: Double) {
            let attack = 5.0, release = 7.0
            let detunes = [-8.0, 0.0, 7.0]
            let saws = detunes.enumerated().map { index, cents in
                Saw(frequency: f * pow(2, cents / 1200), sampleRate: sampleRate,
                    phase: Double(index) * 0.37 + f.truncatingRemainder(dividingBy: 1))
            }
            // Each saw's place: the voice's own pan, opened out by its detune.
            let places = detunes.map { cents in max(-1, min(1, pan + cents / 20)) }
            var oscillators = saws
            // Two stages a side, damped for a Butterworth response: round,
            // no resonant peak.
            var stagesL = (SVF(), SVF()), stagesR = (SVF(), SVF())
            let base = min(max(f * 2.2, 300), 1_100)
            let rate = sampleRate
            render(at: start, length: length + release) { frame, t, add in
                var left = 0.0, right = 0.0
                for i in 0..<3 {
                    let v = oscillators[i].next()
                    let (gl, gr) = Self.panGains(places[i])
                    left += v * gl; right += v * gr
                }
                // Coefficients every 16 samples: the cutoff moves over
                // seconds, so per-sample is waste.
                if frame & 15 == 0 {
                    let opening = 0.6 + 0.4 * AmbientScore.envelope(
                        t, length: length, attack: attack, release: release)
                    let breath = 1 + 0.25 * sin(2 * .pi * breathe * t + f)
                    let cutoff = min(base * opening * breath, rate * 0.45)
                    stagesL.0.tune(cutoff: cutoff, sampleRate: rate, damping: 1.848)
                    stagesL.1.tune(cutoff: cutoff, sampleRate: rate, damping: 0.765)
                    stagesR.0.tune(cutoff: cutoff, sampleRate: rate, damping: 1.848)
                    stagesR.1.tune(cutoff: cutoff, sampleRate: rate, damping: 0.765)
                }
                let amp = gain / 3 * AmbientScore.envelope(
                    t, length: length, attack: attack, release: release)
                left = stagesL.1.lowpass(stagesL.0.lowpass(left)) * amp
                right = stagesR.1.lowpass(stagesR.0.lowpass(right)) * amp
                add(left, right, 0.55, 0)
            }
        }

        /// A pure tone with a slow tremolo — the sub and the glass.
        mutating func addSine(_ f: Double, at start: Double, length: Double,
                              attack: Double, release: Double, gain: Double,
                              pan: Double, tremolo: Double) {
            var phase = 0.0
            let step = f / sampleRate
            let (gl, gr) = Self.panGains(pan)
            let table = sine
            render(at: start, length: length + release) { _, t, add in
                let shimmer = tremolo > 0 ? 0.8 + 0.2 * sin(2 * .pi * tremolo * t) : 1
                let v = table.value(phase) * gain * shimmer
                    * AmbientScore.envelope(t, length: length, attack: attack, release: release)
                phase += step
                if phase >= 1 { phase -= 1 }
                add(v * gl, v * gr, tremolo > 0 ? 0.7 : 0.15, 0)
            }
        }

        // MARK: Bells

        /// A dozen soft two-operator FM bells, a fifth of the way between a
        /// celesta and glass, each on a tone of the chord sounding beneath
        /// it, two octaves up; placed by a seeded generator so the loop
        /// never shows its grid, and sent hard to the echoes and the room.
        mutating func addBells(seed: UInt64) {
            var random = SplitMix64(seed: seed)
            var t = 3.0
            let chords = AmbientScore.progression
            while t < AmbientScore.loopSeconds - 1 {
                let chord = chords[Int(t / AmbientScore.chordSeconds) % chords.count]
                let pitches = Array(chord.notes.suffix(3))
                var midi = pitches[Int(random.next() * Double(pitches.count))] + 24
                // Above F♯6 a bell turns to a whistle: drop it an octave,
                // never off the chord.
                if midi > 90 { midi -= 12 }
                let gain = 0.035 + 0.03 * random.next()
                let pan = (random.next() * 2 - 1) * 0.75
                addBell(AmbientScore.hertz(midi), at: t, gain: gain, pan: pan)
                // Uneven gaps, 3.5–7.5 s: sparse enough to stay ambient.
                t += 3.5 + 4 * random.next()
            }
        }

        mutating func addBell(_ f: Double, at start: Double, gain: Double, pan: Double) {
            let (gl, gr) = Self.panGains(pan)
            let table = sine
            var carrier = 0.0, modulator = 0.0, sparkle = 0.0
            let carrierStep = f / sampleRate
            let modulatorStep = f * 2.0 / sampleRate
            let sparkleStep = f * 4.07 / sampleRate
            render(at: start, length: 7) { _, t, add in
                // A soft 12 ms onset (no click), a long glassy decay; the
                // FM index falls faster than the tone, so the strike is
                // bright and the ring is pure.
                let onset = t < 0.012 ? 0.5 - 0.5 * cos(.pi * t / 0.012) : 1
                let ring = exp(-t * 1.05)
                let index = 1.6 * exp(-t * 3.2)
                let mod = table.value(modulator) * index
                var v = table.value(carrier + mod / (2 * .pi))
                v += 0.12 * table.value(sparkle) * exp(-t * 2.5)
                v *= gain * onset * ring
                carrier += carrierStep; if carrier >= 1 { carrier -= 1 }
                modulator += modulatorStep; if modulator >= 1 { modulator -= 1 }
                sparkle += sparkleStep; if sparkle >= 1 { sparkle -= 1 }
                add(v * gl, v * gr, 0.85, 0.7)
            }
        }

        // MARK: Plumbing

        /// Runs `voice` over [start, start + length) and accumulates what it
        /// adds: dry left/right, then how much of it goes to the room and to
        /// the echoes. Times before zero wrap to the end of the loop's
        /// timeline (so the first chord can bloom across the seam).
        private mutating func render(
            at start: Double, length: Double,
            _ voice: (_ frame: Int, _ t: Double,
                      _ add: (_ l: Double, _ r: Double, _ room: Double, _ echo: Double) -> Void) -> Void
        ) {
            let begin = start < 0 ? start + AmbientScore.loopSeconds : start
            let first = Int(begin * sampleRate)
            let count = Int(length * sampleRate)
            var frame = 0
            let total = frames
            dryL.withUnsafeMutableBufferPointer { dl in
            dryR.withUnsafeMutableBufferPointer { dr in
            roomSendL.withUnsafeMutableBufferPointer { rl in
            roomSendR.withUnsafeMutableBufferPointer { rr in
            echoSendL.withUnsafeMutableBufferPointer { el in
            echoSendR.withUnsafeMutableBufferPointer { er in
                while frame < count {
                    let index = first + frame
                    guard index < total else { break }
                    let t = Double(frame) / sampleRate
                    voice(frame, t) { l, r, room, echo in
                        dl[index] += l; dr[index] += r
                        rl[index] += l * room; rr[index] += r * room
                        if echo > 0 { el[index] += l * echo; er[index] += r * echo }
                    }
                    frame += 1
                }
            }}}}}}
        }

        /// Equal-power pan, −1 (left) … 1 (right).
        static func panGains(_ pan: Double) -> (Double, Double) {
            let angle = (pan + 1) * .pi / 4
            return (cos(angle), sin(angle))
        }

        // MARK: Mastering

        mutating func finish(loopSeconds: Double) -> (left: [Float], right: [Float]) {
            // Echoes first, so they ring in the room too.
            var echoes = PingPong(sampleRate: sampleRate)
            for i in 0..<frames {
                let (l, r) = echoes.process(echoSendL[i], echoSendR[i])
                dryL[i] += l * 0.55; dryR[i] += r * 0.55
                roomSendL[i] += l * 0.6; roomSendR[i] += r * 0.6
            }
            var room = Room(sampleRate: sampleRate)
            var wetL = [Double](repeating: 0, count: frames)
            var wetR = [Double](repeating: 0, count: frames)
            for i in 0..<frames {
                (wetL[i], wetR[i]) = room.process(roomSendL[i], roomSendR[i])
            }
            // The room is set against the dry signal by measure, not by a
            // hand-tuned constant: a wet/dry ratio by RMS.
            let wetGain = 0.95 * Self.rms(dryL, dryR) / max(Self.rms(wetL, wetR), 1e-9)

            // Fold the overhang back onto the start: one seamless pass.
            let n = Int(loopSeconds * sampleRate)
            var left = [Double](repeating: 0, count: n)
            var right = [Double](repeating: 0, count: n)
            for i in 0..<frames {
                let j = i % n
                left[j] += dryL[i] + wetL[i] * wetGain
                right[j] += dryR[i] + wetR[i] * wetGain
            }

            // Each side levelled to the room's old loudness (which also
            // balances them — the voicings lean a decibel left), then a soft
            // knee under the ceiling, then 16-bit-sized dither so the
            // reverb's quiet tail fades into noise rather than into
            // quantisation steps.
            let scaleL = AmbientScore.targetRMS / max(Self.rms(left, left), 1e-9)
            let scaleR = AmbientScore.targetRMS / max(Self.rms(right, right), 1e-9)
            var dither = SplitMix64(seed: 0xD1_7E5)
            let lsb = 1.0 / 32_768
            func master(_ x: Double, _ scale: Double) -> Float {
                let y = Self.softLimit(x * scale)
                let tpdf = (dither.next() - dither.next()) * lsb
                return Float(y + tpdf)
            }
            return (left.map { master($0, scaleL) }, right.map { master($0, scaleR) })
        }

        /// Unity below the knee, then a tanh shoulder to the ceiling.
        static func softLimit(_ x: Double) -> Double {
            let knee = 0.7, ceiling = AmbientScore.ceiling
            let magnitude = abs(x)
            guard magnitude > knee else { return x }
            let over = (magnitude - knee) / (ceiling - knee)
            return (knee + (ceiling - knee) * tanh(over)) * (x < 0 ? -1 : 1)
        }

        static func rms(_ a: [Double], _ b: [Double]) -> Double {
            var sum = 0.0
            for i in a.indices { sum += a[i] * a[i] + b[i] * b[i] }
            return sqrt(sum / Double(max(a.count * 2, 1)))
        }
    }

    // MARK: Building blocks

    /// Raised-cosine in, hold, raised-cosine out: no corner anywhere, so
    /// nothing clicks.
    static func envelope(_ t: Double, length: Double, attack: Double, release: Double) -> Double {
        if t < attack { return 0.5 - 0.5 * cos(.pi * t / attack) }
        if t < length { return 1 }
        let out = t - length
        return out < release ? 0.5 + 0.5 * cos(.pi * out / release) : 0
    }

    /// One cycle of sine, read with linear interpolation; `phase` in [0, 1).
    nonisolated struct SineTable {
        private let table: [Double]
        private let size = 4_096
        init() {
            table = (0...4_096).map { sin(2 * .pi * Double($0) / 4_096) }
        }
        func value(_ phase: Double) -> Double {
            var p = phase - phase.rounded(.down)
            p *= Double(size)
            let i = Int(p)
            let fraction = p - Double(i)
            return table[i] + (table[i + 1] - table[i]) * fraction
        }
    }

    /// A sawtooth with PolyBLEP corners, so it does not alias.
    nonisolated struct Saw {
        var phase: Double
        let step: Double
        init(frequency: Double, sampleRate: Double, phase: Double) {
            step = frequency / sampleRate
            self.phase = phase - phase.rounded(.down)
        }
        mutating func next() -> Double {
            var v = 2 * phase - 1
            if phase < step {
                let x = phase / step
                v -= x + x - x * x - 1
            } else if phase > 1 - step {
                let x = (phase - 1) / step
                v -= x * x + x + x + 1
            }
            phase += step
            if phase >= 1 { phase -= 1 }
            return v
        }
    }

    /// A zero-delay-feedback state-variable low-pass (Simper's form):
    /// stable however fast the cutoff moves.
    nonisolated struct SVF {
        private var ic1 = 0.0, ic2 = 0.0
        private var a1 = 0.0, a2 = 0.0, a3 = 0.0
        mutating func tune(cutoff: Double, sampleRate: Double, damping: Double) {
            let g = tan(.pi * cutoff / sampleRate)
            a1 = 1 / (1 + g * (g + damping))
            a2 = g * a1
            a3 = g * a2
        }
        mutating func lowpass(_ v0: Double) -> Double {
            let v3 = v0 - ic2
            let v1 = a1 * ic1 + a2 * v3
            let v2 = ic2 + a2 * ic1 + a3 * v3
            ic1 = 2 * v1 - ic1
            ic2 = 2 * v2 - ic2
            return v2
        }
    }

    /// Cross-fed stereo echoes, darker each time round.
    nonisolated struct PingPong {
        private var left: [Double], right: [Double]
        private var index = 0
        private var toneL = 0.0, toneR = 0.0
        private let damping: Double
        init(sampleRate: Double) {
            left = [Double](repeating: 0, count: Int(0.54 * sampleRate))
            right = [Double](repeating: 0, count: Int(0.81 * sampleRate))
            damping = exp(-2 * .pi * 2_600 / sampleRate)
        }
        mutating func process(_ inL: Double, _ inR: Double) -> (Double, Double) {
            let outL = left[index % left.count]
            let outR = right[index % right.count]
            toneL = outR * (1 - damping) + toneL * damping
            toneR = outL * (1 - damping) + toneR * damping
            left[index % left.count] = inL + toneL * 0.42
            right[index % right.count] = inR + toneR * 0.42
            index += 1
            return (outL, outR)
        }
    }

    /// A Schroeder–Moorer room (the Freeverb topology): eight damped combs
    /// in parallel and four all-passes in series per side, the right side
    /// detuned from the left for width, behind a short pre-delay and a
    /// gentle low cut so the low notes do not muddy the tail.
    nonisolated struct Room {
        private var combsL: [Comb], combsR: [Comb]
        private var passesL: [AllPass], passesR: [AllPass]
        private var preDelay: [Double]
        private var preIndex = 0
        private var lowCutState = 0.0
        private let lowCut: Double

        init(sampleRate: Double) {
            let scale = sampleRate / 44_100
            let combs = [1_116, 1_188, 1_277, 1_356, 1_422, 1_491, 1_557, 1_617]
            let passes = [556, 441, 341, 225]
            let spread = 23
            func length(_ n: Int) -> Int { max(Int(Double(n) * scale), 1) }
            combsL = combs.map { Comb(length: length($0), feedback: 0.93, damp: 0.42) }
            combsR = combs.map { Comb(length: length($0 + spread), feedback: 0.93, damp: 0.42) }
            passesL = passes.map { AllPass(length: length($0)) }
            passesR = passes.map { AllPass(length: length($0 + spread)) }
            preDelay = [Double](repeating: 0, count: max(Int(0.035 * sampleRate), 1))
            lowCut = exp(-2 * .pi * 170 / sampleRate)
        }

        mutating func process(_ inL: Double, _ inR: Double) -> (Double, Double) {
            let delayed = preDelay[preIndex]
            preDelay[preIndex] = (inL + inR) * 0.5
            preIndex = (preIndex + 1) % preDelay.count
            lowCutState = delayed * (1 - lowCut) + lowCutState * lowCut
            let input = (delayed - lowCutState) * 0.03
            var outL = 0.0, outR = 0.0
            for i in combsL.indices {
                outL += combsL[i].process(input)
                outR += combsR[i].process(input)
            }
            for i in passesL.indices {
                outL = passesL[i].process(outL)
                outR = passesR[i].process(outR)
            }
            return (outL, outR)
        }

        nonisolated struct Comb {
            private var buffer: [Double]
            private var index = 0
            private var store = 0.0
            let feedback: Double, damp: Double
            init(length: Int, feedback: Double, damp: Double) {
                buffer = [Double](repeating: 0, count: length)
                self.feedback = feedback
                self.damp = damp
            }
            mutating func process(_ input: Double) -> Double {
                let output = buffer[index]
                store = output * (1 - damp) + store * damp
                buffer[index] = input + store * feedback
                index += 1
                if index == buffer.count { index = 0 }
                return output
            }
        }

        nonisolated struct AllPass {
            private var buffer: [Double]
            private var index = 0
            init(length: Int) { buffer = [Double](repeating: 0, count: length) }
            mutating func process(_ input: Double) -> Double {
                let stored = buffer[index]
                buffer[index] = input + stored * 0.5
                index += 1
                if index == buffer.count { index = 0 }
                return stored - input
            }
        }
    }

    /// A small seeded generator, so the score is the same on every device.
    nonisolated struct SplitMix64 {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        /// Uniform in [0, 1).
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }
}
