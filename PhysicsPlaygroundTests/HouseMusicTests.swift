//
//  HouseMusicTests.swift
//  PhysicsPlaygroundTests
//
//  The house music's level as the space opens (2026-11-02): it plays from
//  the first frame, swelling with the arrival's wordmark and settling to
//  where it always sat once the labs are in. Held on the envelope the
//  player is handed, since nobody can listen to a test.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class HouseMusicTests: XCTestCase {

    /// The level the music holds after its last step, dB.
    private func settled(_ envelope: (gain: Double, steps: [SoundPalette.AmbientStep])) -> Double {
        envelope.gain + (envelope.steps.last?.gain ?? 0)
    }

    /// The swell ends exactly where the plain start does: at the house
    /// level, which it does not change.
    func testTheSwellSettlesAtTheHouseLevel() {
        XCTAssertEqual(SoundPalette.ambientLevel, -22)
        XCTAssertEqual(settled(SoundPalette.ambientEnvelope(swell: true)),
                       SoundPalette.ambientLevel, accuracy: 1e-9)
        XCTAssertEqual(settled(SoundPalette.ambientEnvelope(swell: false)),
                       SoundPalette.ambientLevel, accuracy: 1e-9)
    }

    /// It rises once, out of silence, to a few decibels over the house
    /// level, and only once it is up does it come down.
    func testTheSwellRisesOnceThenSettles() {
        let swell = SoundPalette.ambientEnvelope(swell: true)
        XCTAssertEqual(swell.steps.count, 2)
        let (rise, settle) = (swell.steps[0], swell.steps[1])
        XCTAssertEqual(rise.at, 0)
        XCTAssertEqual(swell.gain + rise.gain - SoundPalette.ambientLevel,
                       SoundPalette.swellLift, accuracy: 1e-9)
        XCTAssertGreaterThan(SoundPalette.swellLift, 0)
        XCTAssertLessThanOrEqual(SoundPalette.swellLift, 10, "a swell, not a blast")
        XCTAssertGreaterThan(settle.at, rise.at + rise.duration, "it comes down before it is up")
        XCTAssertLessThan(settle.gain, rise.gain)
        // A playback's gain is relative to its emitter's and never above it.
        for step in swell.steps { XCTAssertLessThanOrEqual(step.gain, 0) }
    }

    /// Timed to the arrival, which starts a moment after the space opens:
    /// up as the wordmark comes down, held while the labs rise, back at
    /// the house level a few seconds after they are in.
    func testTheSwellIsTimedToTheArrival() {
        let swell = SoundPalette.ambientEnvelope(swell: true)
        let peaked = swell.steps[0].at + swell.steps[0].duration
        let settling = swell.steps[1].at
        XCTAssertGreaterThan(peaked, Opening.titleStart)
        XCTAssertLessThanOrEqual(peaked, Opening.labsStart + 0.5)
        XCTAssertGreaterThanOrEqual(settling, Opening.labsArrived)
        XCTAssertLessThan(settling + swell.steps[1].duration, 12)
    }

    /// Switching the music on in Settings is the plain fade it always was.
    func testSwitchingItOnIsThePlainFade() {
        let plain = SoundPalette.ambientEnvelope(swell: false)
        XCTAssertEqual(plain.gain, SoundPalette.ambientLevel)
        XCTAssertEqual(plain.steps, [SoundPalette.AmbientStep(at: 0, gain: 0,
                                                              duration: SoundPalette.ambientFadeIn)])
    }
}
