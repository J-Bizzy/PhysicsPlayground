//
//  WaveFieldTests.swift
//  PhysicsCoreTests
//
//  3D interference pinned to the textbook results: equal sources double
//  on the midplane and cancel at λ/2 path difference; inverting one
//  source swaps those outcomes (the noise-cancellation principle); the
//  envelope agrees with the animated field's actual maximum over a cycle.
//

import XCTest
import simd
@testable import PhysicsCore

final class WaveFieldTests: XCTestCase {

    private let frequency = 1.5
    private let speed = 0.5
    private var wavelength: Double { speed / frequency }

    /// The phasor decomposition u = c·cos(ωt) − s·sin(ωt) reproduces the
    /// live field exactly at arbitrary points and times — the identity
    /// the renderer leans on to animate without per-frame trig.
    func testPhasorCoefficientsReproduceTheLiveField() {
        let sources = [
            WaveSource(position: SIMD3(-0.2, 0.05, -0.1), amplitude: 0.008),
            WaveSource(position: SIMD3(0.25, -0.1, 0.15), amplitude: 0.005,
                       phaseInverted: true),
            WaveSource(position: SIMD3(0.0, 0.3, 0.05), amplitude: 0.011),
        ]
        let omega = 2 * Double.pi * frequency
        for point in [SIMD3(0.1, 0.12, -0.07), SIMD3(-0.31, 0.02, 0.2),
                      SIMD3(0.05, -0.18, 0.33)] {
            let (c, s) = WaveField.phasorCoefficients(
                at: point, sources: sources, frequency: frequency, speed: speed)
            for time in [0.0, 0.137, 0.5, 1.234, 7.7] {
                let direct = WaveField.displacement(
                    at: point, time: time, sources: sources,
                    frequency: frequency, speed: speed)
                let folded = c * cos(omega * time) - s * sin(omega * time)
                XCTAssertEqual(folded, direct, accuracy: 1e-15)
            }
        }
    }

    /// √(c² + s²) is the steady-state envelope — same phasor, same math.
    func testPhasorMagnitudeIsTheEnvelope() {
        let sources = [
            WaveSource(position: SIMD3(-0.15, 0, 0)),
            WaveSource(position: SIMD3(0.15, 0.1, -0.2), amplitude: 0.004),
        ]
        let point = SIMD3(0.07, 0.21, 0.14)
        let (c, s) = WaveField.phasorCoefficients(
            at: point, sources: sources, frequency: frequency, speed: speed)
        let envelope = WaveField.steadyAmplitude(
            at: point, sources: sources, frequency: frequency, speed: speed)
        XCTAssertEqual((c * c + s * s).squareRoot(), envelope, accuracy: 1e-15)
    }

    /// Two equal sources, both distance R from a midplane point:
    /// constructive everywhere on the plane — amplitude exactly 2A·F(R).
    func testMidplaneDoublesForEqualSources() {
        let a = WaveSource(position: SIMD3(-0.15, 0, 0))
        let b = WaveSource(position: SIMD3(0.15, 0, 0))
        let point = SIMD3(0.0, 0.2, 0.1)
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

    /// A point whose path difference is exactly λ/2 sits on a silence
    /// surface: with matched arrivals the cancellation is exact.
    func testHalfWavelengthPathDifferenceCancels() {
        // On the axis between the sources, r₁ − r₂ = λ/2 with r₁ + r₂ = d.
        // The nearer source gets a compensating amplitude so the two
        // arrivals match despite the 1/r falloff difference.
        let d = 0.3
        let r1 = (d + wavelength / 2) / 2
        let r2 = (d - wavelength / 2) / 2
        let a = WaveSource(position: SIMD3(-d / 2, 0, 0))
        var b = WaveSource(position: SIMD3(d / 2, 0, 0))
        b.amplitude = a.amplitude * WaveField.falloff(r1) / WaveField.falloff(r2)

        let point = SIMD3(-d / 2 + r1, 0.0, 0.0)
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
    /// noise-cancelling headphone trick, on the midplane.
    func testPhaseInversionSwapsMidplaneToSilence() {
        let a = WaveSource(position: SIMD3(-0.15, 0, 0))
        var b = WaveSource(position: SIMD3(0.15, 0, 0))
        b.phaseInverted = true

        let point = SIMD3(0.0, 0.25, -0.15)
        let amplitude = WaveField.steadyAmplitude(
            at: point, sources: [a, b], frequency: frequency, speed: speed)
        XCTAssertEqual(amplitude, 0, accuracy: a.amplitude * 1e-9,
                       "equal-and-opposite arrivals must silence the midplane")
        XCTAssertEqual(
            WaveField.interference(at: point, between: a, and: b,
                                   frequency: frequency, speed: speed),
            .destructive)
    }

    /// The envelope is honest: sampling the animated field over one full
    /// period never exceeds the phasor amplitude, and gets within 1% of it.
    func testEnvelopeMatchesTimeMaximum() {
        let sources = [
            WaveSource(position: SIMD3(-0.12, 0.05, 0.08)),
            WaveSource(position: SIMD3(0.2, -0.1, -0.05), amplitude: 0.005, phaseInverted: true),
        ]
        let point = SIMD3(0.07, 0.18, 0.11)
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
    /// every wavelength (up to falloff), and λ = c/f. Spherical spreading:
    /// doubling the distance halves the falloff.
    func testWavelengthAndSphericalSpreading() {
        XCTAssertEqual(WaveField.wavelength(frequency: 2, speed: 0.5), 0.25)
        XCTAssertEqual(WaveField.falloff(0.4), WaveField.falloff(0.2) / 2, accuracy: 1e-12,
                       "sound amplitude falls as 1/r")

        let source = [WaveSource(position: .zero)]
        let r = 0.3
        let u1 = WaveField.displacement(at: SIMD3(r, 0, 0), time: 0.123,
                                        sources: source, frequency: frequency, speed: speed)
            / WaveField.falloff(r)
        let u2 = WaveField.displacement(at: SIMD3(r + wavelength, 0, 0), time: 0.123,
                                        sources: source, frequency: frequency, speed: speed)
            / WaveField.falloff(r + wavelength)
        XCTAssertEqual(u1, u2, accuracy: 1e-9,
                       "normalized displacement must repeat every wavelength")
    }

    /// Time periodicity: the whole field repeats with period 1/f.
    func testFieldIsPeriodicInTime() {
        let sources = [
            WaveSource(position: SIMD3(-0.1, 0, 0.05)),
            WaveSource(position: SIMD3(0.15, 0.1, -0.1)),
        ]
        let point = SIMD3(0.05, 0.22, 0.09)
        let u1 = WaveField.displacement(at: point, time: 0.4,
                                        sources: sources, frequency: frequency, speed: speed)
        let u2 = WaveField.displacement(at: point, time: 0.4 + 1 / frequency,
                                        sources: sources, frequency: frequency, speed: speed)
        XCTAssertEqual(u1, u2, accuracy: 1e-12)
    }

    // MARK: Doppler — a moving source

    /// With the source at rest the retarded distance is just the straight
    /// line, so the moving-source field reduces exactly to the static one
    /// (every test above still holds).
    func testRetardedDistanceReducesToGeometryAtRest() {
        let source = WaveSource(position: SIMD3(0.1, -0.2, 0.05))
        let point = SIMD3(0.4, 0.3, -0.15)
        XCTAssertEqual(
            WaveField.retardedDistance(from: source, to: point, speed: speed),
            simd_distance(point, source.position), accuracy: 1e-12)
    }

    /// The light-cone solution in closed form: a source moving at v along
    /// +x gives r_ret = c·d/(c−v) directly ahead, c·d/(c+v) directly
    /// behind, and c·d/√(c²−v²) straight to the side.
    func testRetardedDistanceMatchesClosedForms() {
        let c = 0.5, v = 0.2, d = 0.6
        let source = WaveSource(position: .zero, velocity: SIMD3(v, 0, 0))
        let ahead = WaveField.retardedDistance(from: source, to: SIMD3(d, 0, 0), speed: c)
        let behind = WaveField.retardedDistance(from: source, to: SIMD3(-d, 0, 0), speed: c)
        let beside = WaveField.retardedDistance(from: source, to: SIMD3(0, d, 0), speed: c)
        XCTAssertEqual(ahead, c * d / (c - v), accuracy: 1e-9)
        XCTAssertEqual(behind, c * d / (c + v), accuracy: 1e-9)
        XCTAssertEqual(beside, c * d / (c * c - v * v).squareRoot(), accuracy: 1e-9)
        // And the Doppler ordering: the wave ahead came the long way round
        // (source has since approached), behind the short way.
        XCTAssertGreaterThan(ahead, behind)
    }

    /// The physical signature of Doppler: at a single instant a moving
    /// source's wavefronts are packed tighter ahead of it than behind —
    /// more crests per metre in front. Count the field's zero crossings
    /// along the axis of motion, both directions.
    func testMovingSourceBunchesWavefrontsAhead() {
        let source = WaveSource(position: .zero, velocity: SIMD3(0.2, 0, 0))
        func crossings(from x0: Double, to x1: Double) -> Int {
            var last = 0.0, count = 0
            let samples = 400
            for i in 0...samples {
                let x = x0 + (x1 - x0) * Double(i) / Double(samples)
                let u = WaveField.displacement(
                    at: SIMD3(x, 0, 0), time: 0.0,
                    sources: [source], frequency: frequency, speed: speed)
                if i > 0, u * last < 0 { count += 1 }
                last = u
            }
            return count
        }
        XCTAssertGreaterThan(crossings(from: 0.3, to: 1.3),
                             crossings(from: -0.3, to: -1.3),
                             "wavefronts must be denser ahead of the motion")
    }
}
