//
//  WaveFieldTests.swift
//  PhysicsCoreTests
//
//  Interference pinned to the textbook results: equal sources double on
//  the midline and cancel at λ/2 path difference; inverting one source
//  swaps those outcomes (the noise-cancellation principle); the envelope
//  agrees with the animated field's actual maximum over a cycle.
//

import XCTest
import simd
@testable import PhysicsCore

final class WaveFieldTests: XCTestCase {

    private let frequency = 1.5
    private let speed = 0.5
    private var wavelength: Double { speed / frequency }

    /// Two equal sources, both distance R from the midpoint: constructive
    /// everywhere on the perpendicular bisector — amplitude exactly 2A·F(R).
    func testMidlineDoublesForEqualSources() {
        let a = WaveSource(position: SIMD2(-0.15, 0))
        let b = WaveSource(position: SIMD2(0.15, 0))
        let point = SIMD2(0.0, 0.2)
        let r = simd_distance(point, a.position)
        let expected = 2 * a.amplitude * WaveField.falloff(r)

        let amplitude = WaveField.steadyAmplitude(
            at: point, sources: [a, b], frequency: frequency, speed: speed)
        XCTAssertEqual(amplitude, expected, accuracy: expected * 1e-9)
        XCTAssertEqual(
            WaveField.interference(at: point, between: a, and: b,
                                   frequency: frequency, speed: speed),
            .constructive)
    }

    /// A point whose path difference is exactly λ/2 sits on a nodal line:
    /// with equal falloff the cancellation is exact.
    func testHalfWavelengthPathDifferenceCancels() {
        // Place sources so a symmetric-falloff point has Δr = λ/2: on the
        // line through both sources, between them, r1 − r2 = λ/2 with
        // r1 + r2 = d. Equal falloff requires equal amplitudes at unequal
        // distances — so give the nearer source a compensating amplitude.
        let d = 0.3
        let r1 = (d + wavelength / 2) / 2
        let r2 = (d - wavelength / 2) / 2
        let a = WaveSource(position: SIMD2(-d / 2, 0))
        var b = WaveSource(position: SIMD2(d / 2, 0))
        // Compensate the falloff difference so the two arrivals match.
        b.amplitude = a.amplitude * WaveField.falloff(r1) / WaveField.falloff(r2)

        let point = SIMD2(-d / 2 + r1, 0.0)
        XCTAssertEqual(simd_distance(point, a.position), r1, accuracy: 1e-12)
        XCTAssertEqual(simd_distance(point, b.position), r2, accuracy: 1e-12)

        let amplitude = WaveField.steadyAmplitude(
            at: point, sources: [a, b], frequency: frequency, speed: speed)
        XCTAssertEqual(amplitude, 0, accuracy: a.amplitude * 1e-9,
                       "λ/2 path difference with matched arrivals must cancel exactly")
        XCTAssertEqual(
            WaveField.interference(at: point, between: a, and: b,
                                   frequency: frequency, speed: speed),
            .destructive)
    }

    /// Inverting one source swaps constructive and destructive — the
    /// noise-cancelling headphone trick, on the midline.
    func testPhaseInversionSwapsMidlineToSilence() {
        let a = WaveSource(position: SIMD2(-0.15, 0))
        var b = WaveSource(position: SIMD2(0.15, 0))
        b.phaseInverted = true

        let point = SIMD2(0.0, 0.25)
        let amplitude = WaveField.steadyAmplitude(
            at: point, sources: [a, b], frequency: frequency, speed: speed)
        XCTAssertEqual(amplitude, 0, accuracy: a.amplitude * 1e-9,
                       "equal-and-opposite arrivals must silence the midline")
        XCTAssertEqual(
            WaveField.interference(at: point, between: a, and: b,
                                   frequency: frequency, speed: speed),
            .destructive)
    }

    /// The envelope is honest: sampling the animated field over one full
    /// period never exceeds the phasor amplitude, and gets within 1% of it.
    func testEnvelopeMatchesTimeMaximum() {
        let sources = [
            WaveSource(position: SIMD2(-0.12, 0.05)),
            WaveSource(position: SIMD2(0.2, -0.1), amplitude: 0.005, phaseInverted: true),
        ]
        let point = SIMD2(0.07, 0.18)
        let envelope = WaveField.steadyAmplitude(
            at: point, sources: sources, frequency: frequency, speed: speed)

        let period = 1 / frequency
        var observedMax = 0.0
        for step in 0..<500 {
            let u = WaveField.displacement(
                at: point, time: period * Double(step) / 500,
                sources: sources, frequency: frequency, speed: speed)
            observedMax = max(observedMax, abs(u))
        }
        XCTAssertLessThanOrEqual(observedMax, envelope * (1 + 1e-9))
        XCTAssertEqual(observedMax, envelope, accuracy: envelope * 0.01)
    }

    /// Spatial periodicity: at fixed time, a single source's field repeats
    /// every wavelength (up to falloff), and λ = c/f.
    func testWavelengthIsSpeedOverFrequency() {
        XCTAssertEqual(WaveField.wavelength(frequency: 2, speed: 0.5), 0.25)

        let source = [WaveSource(position: .zero)]
        let r = 0.3
        let u1 = WaveField.displacement(at: SIMD2(r, 0), time: 0.123,
                                        sources: source, frequency: frequency, speed: speed)
            / WaveField.falloff(r)
        let u2 = WaveField.displacement(at: SIMD2(r + wavelength, 0), time: 0.123,
                                        sources: source, frequency: frequency, speed: speed)
            / WaveField.falloff(r + wavelength)
        XCTAssertEqual(u1, u2, accuracy: 1e-9,
                       "normalized displacement must repeat every wavelength")
    }

    /// Time periodicity: the whole field repeats with period 1/f.
    func testFieldIsPeriodicInTime() {
        let sources = [
            WaveSource(position: SIMD2(-0.1, 0)),
            WaveSource(position: SIMD2(0.15, 0.1)),
        ]
        let point = SIMD2(0.05, 0.22)
        let u1 = WaveField.displacement(at: point, time: 0.4,
                                        sources: sources, frequency: frequency, speed: speed)
        let u2 = WaveField.displacement(at: point, time: 0.4 + 1 / frequency,
                                        sources: sources, frequency: frequency, speed: speed)
        XCTAssertEqual(u1, u2, accuracy: 1e-12)
    }
}
