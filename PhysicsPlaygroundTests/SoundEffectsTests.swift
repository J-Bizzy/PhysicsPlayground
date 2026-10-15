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

    /// The opening is choreographed to the bell: it must be the loudest
    /// moment, and it must strike at the landing (`Opening.landingTime`).
    func testTheOpeningsBellIsItsLoudestMomentAndLandsOnTime() {
        let samples = SoundEffects.oneShot("calibration")
        let peak = samples.indices.max { abs(samples[$0]) < abs(samples[$1]) }!
        let at = Double(peak) / rate
        XCTAssertGreaterThanOrEqual(at, SoundEffects.calibrationLanding)
        XCTAssertLessThan(at, SoundEffects.calibrationLanding + 0.05,
                          "the bell peaks \(at) s in, not at the landing")
        XCTAssertEqual(SoundPalette.calibrationLanding, SoundEffects.calibrationLanding)
    }

    /// The tones loop for as long as a body orbits or a circuit runs: the
    /// jump from the last sample back to the first must be an ordinary step.
    func testTheLoopingTonesHaveNoSeam() {
        for (name, tone) in [("glass", SoundEffects.glassTone()), ("hum", SoundEffects.humTone())] {
            var largest: Float = 0
            for i in 1..<tone.count { largest = max(largest, abs(tone[i] - tone[i - 1])) }
            let seam = abs(tone[0] - tone[tone.count - 1])
            XCTAssertLessThanOrEqual(seam, largest * 1.01, "\(name) jumps at its seam")
        }
    }

    /// The cache is keyed by file name, so a sound that differed between
    /// renders would differ between devices.
    func testNoiseIsSeeded() {
        for name in ["whoosh", "thud", "boom", "clack", "launch", "calibration"] {
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
}
