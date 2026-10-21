//
//  SoundEffectsTests.swift
//  PhysicsPlaygroundTests
//
//  The sound effects are rendered once per device and cached for good,
//  so what an ear would catch has to be pinned here: every sound the
//  palette names has a recipe, none clicks at either end, the opening's
//  bell is its loudest moment and lands on time, the looping tones have
//  no seam, the noise is seeded, and the interface family really is in
//  the music's key.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class SoundEffectsTests: XCTestCase {

    private let rate = 44_100.0

    func testEverySoundThePaletteNamesHasARecipe() {
        for sound in SoundPalette.Sound.allCases {
            XCTAssertTrue(SoundEffects.names.contains(sound.rawValue),
                          "\(sound.rawValue) has no recipe in SoundEffects")
            XCTAssertFalse(SoundEffects.oneShot(sound.rawValue).isEmpty)
        }
    }

    /// A sound that starts or stops on a non-zero sample clicks — and these
    /// play on every grab, every pinch, every bounce.
    func testNoSoundClicksAtEitherEnd() {
        for name in SoundEffects.names {
            let samples = SoundEffects.oneShot(name)
            XCTAssertLessThan(abs(samples.first ?? 1), 1e-3, "\(name) starts on a step")
            XCTAssertLessThan(abs(samples.last ?? 1), 1e-3, "\(name) stops on a step")
            for sample in samples {
                XCTAssertTrue(sample.isFinite, "\(name) has a non-finite sample")
                XCTAssertLessThanOrEqual(abs(sample), 0.76, "\(name) is over its level")
            }
        }
    }

    /// The arrival's one soft tone: struck at once, never louder than the
    /// chime it shares a key with, and gone within a few seconds.
    func testTheArrivalIsOneSoftTone() {
        let tone = SoundEffects.oneShot("arrival")
        let chime = SoundEffects.oneShot("chime")
        let peak = tone.indices.max { abs(tone[$0]) < abs(tone[$1]) } ?? 0
        XCTAssertLessThan(Double(peak) / rate, 0.15, "the tone swells instead of sounding")
        XCTAssertLessThan(tone.map { abs($0) }.max() ?? 1, chime.map { abs($0) }.max() ?? 0)
        XCTAssertLessThan(Double(tone.count) / rate, 3.5)
    }

    /// The tones loop for as long as a body orbits or a circuit runs: the
    /// jump from the last sample back to the first must be an ordinary step.
    func testTheLoopingTonesHaveNoSeam() {
        for (name, tone) in [("glass", SoundEffects.glassTone()), ("hum", SoundEffects.humTone()),
                             ("beep", SoundEffects.beepTone())] {
            var largest: Float = 0
            for i in 1..<tone.count { largest = max(largest, abs(tone[i] - tone[i - 1])) }
            let seam = abs(tone[0] - tone[tone.count - 1])
            XCTAssertLessThanOrEqual(seam, largest * 1.01, "\(name) jumps at its seam")
        }
    }

    /// The cache is keyed by file name, so a sound that differed between
    /// renders would differ between devices.
    func testNoiseIsSeeded() {
        for name in ["whoosh", "thud", "boom", "clack", "launch", "arrival", "gleam"] {
            XCTAssertEqual(SoundEffects.oneShot(name), SoundEffects.oneShot(name), name)
        }
    }

    /// The ticks are notes of the music's key: the grab on E6, the
    /// release a fourth lower on B5.
    func testTheTicksAreInTheMusicsKey() {
        func pitch(_ name: String) -> Double {
            let samples = SoundEffects.oneShot(name)
            let window = samples.prefix(Int(0.04 * rate))
            var crossings = 0
            for (a, b) in zip(window, window.dropFirst()) where (a < 0) != (b < 0) {
                crossings += 1
            }
            return Double(crossings) / 2 / (Double(window.count) / rate)
        }
        XCTAssertEqual(pitch("grabTick"), 1_318.5, accuracy: 1_318.5 * 0.04)
        XCTAssertEqual(pitch("releaseTick"), 987.8, accuracy: 987.8 * 0.04)
    }

    /// The continuity beep is A6, the key's own note, and every tone the
    /// palette names has a loop.
    func testTheBeepIsAnA() {
        let beep = SoundEffects.beepTone()
        var crossings = 0
        for (a, b) in zip(beep, beep.dropFirst()) where (a < 0) != (b < 0) { crossings += 1 }
        let hertz = Double(crossings) / 2 / (Double(beep.count) / rate)
        XCTAssertEqual(hertz, 1_760, accuracy: 1_760 * 0.02)
        XCTAssertEqual(SoundEffects.beepHz, AmbientScore.hertz(93), accuracy: 0.5)
        XCTAssertEqual(Set(SoundPalette.Tone.allCases.map(\.rawValue)), ["glass", "hum", "beep"])
    }

    /// The gleam is quieter than the chime it must never outrank, and it
    /// rings: a remark lingers where a tick does not.
    func testTheGleamSitsUnderTheChimeAndLingers() {
        func rms(_ samples: [Float]) -> Double {
            sqrt(samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count))
        }
        let gleam = SoundEffects.oneShot("gleam"), chime = SoundEffects.oneShot("chime")
        XCTAssertLessThan(gleam.map { abs($0) }.max() ?? 1, chime.map { abs($0) }.max() ?? 0)
        XCTAssertGreaterThan(Double(gleam.count) / rate, 2)
        XCTAssertGreaterThan(rms(Array(gleam[Int(1.0 * rate)..<Int(1.2 * rate)])), 0.005,
                             "the gleam is gone within a second")
    }
}
