//
//  ThrowSamplerTests.swift
//  PhysicsCoreTests
//
//  The throw is the one initial condition the user sets with their body,
//  so its arithmetic is worth pinning exactly — including the two cases
//  the three hand-rolled versions disagreed about: a hand that barely
//  moved, and a frame that arrived late.
//

import XCTest
import simd
@testable import PhysicsCore

final class ThrowSamplerTests: XCTestCase {

    /// A hand moving 1 m/s in +x for 0.1 s reports exactly 1 m/s.
    func testConstantVelocityIsRecoveredExactly() {
        var sampler = ThrowSampler()
        for step in 0...10 {
            let t = Double(step) * 0.01
            sampler.record(SIMD3(t * 1.0, 0, 0), at: t)
        }
        let velocity = sampler.velocity(at: 0.1)
        XCTAssertNotNil(velocity)
        XCTAssertEqual(velocity!.x, 1.0, accuracy: 1e-12)
        XCTAssertEqual(velocity!.y, 0, accuracy: 1e-12)
        XCTAssertEqual(velocity!.z, 0, accuracy: 1e-12)
    }

    /// Velocity is a vector, not a speed: direction survives.
    func testDiagonalThrowKeepsItsDirection() {
        var sampler = ThrowSampler()
        sampler.record(SIMD3(0, 0, 0), at: 0)
        sampler.record(SIMD3(0.3, 0.6, -0.3), at: 0.1)
        let velocity = sampler.velocity(at: 0.1)!
        XCTAssertEqual(velocity.x, 3, accuracy: 1e-12)
        XCTAssertEqual(velocity.y, 6, accuracy: 1e-12)
        XCTAssertEqual(velocity.z, -3, accuracy: 1e-12)
    }

    /// A hand held still for a moment then released is not a throw. This
    /// is the guard that keeps a released object from hovering *or*
    /// rocketing: displacement over a near-zero interval is noise.
    func testTooShortAnIntervalIsNotAThrow() {
        var sampler = ThrowSampler()
        sampler.record(SIMD3(0, 0, 0), at: 0)
        sampler.record(SIMD3(0.5, 0, 0), at: 0.005)
        XCTAssertNil(sampler.velocity(at: 0.005),
                     "5 ms is below the 20 ms minimum span")
    }

    func testASingleSampleIsNotAThrow() {
        var sampler = ThrowSampler()
        sampler.record(SIMD3(0, 0, 0), at: 0)
        XCTAssertNil(sampler.velocity(at: 0))
    }

    func testEmptySamplerReportsNothing() {
        XCTAssertNil(ThrowSampler().velocity(at: 1.0))
    }

    /// Only the last `window` counts. A slow wind-up followed by a fast
    /// flick reports the flick — this is why the estimate is not fitted
    /// over the whole path.
    func testWindUpIsExcludedFromTheThrow() {
        var sampler = ThrowSampler()
        // 0.5 s of creeping at 0.1 m/s...
        for step in 0...50 {
            let t = Double(step) * 0.01
            sampler.record(SIMD3(t * 0.1, 0, 0), at: t)
        }
        let creep = sampler.velocity(at: 0.5)!
        XCTAssertEqual(creep.x, 0.1, accuracy: 1e-9)

        // ...then a flick covering 0.6 m in the final 0.06 s.
        for step in 1...6 {
            let t = 0.5 + Double(step) * 0.01
            sampler.record(SIMD3(0.05 + Double(step) * 0.1, 0, 0), at: t)
        }
        let flick = sampler.velocity(at: 0.56)!
        XCTAssertGreaterThan(flick.x, 5, "the flick, not the creep, is the throw")
    }

    /// The buffer forgets: samples older than the window stop counting.
    func testStaleSamplesAreDroppedAsTheHandMoves() {
        var sampler = ThrowSampler()
        for step in 0...100 {
            sampler.record(SIMD3(Double(step) * 0.001, 0, 0), at: Double(step) * 0.01)
        }
        XCTAssertLessThanOrEqual(sampler.count, ThrowSampler.capacity)
        // 1 s of samples at a 0.12 s window: only the tail is retained.
        XCTAssertLessThanOrEqual(sampler.count, 15)
    }

    /// A stuttered frame must still throw. Every retained sample is older
    /// than the window here — the three hand-rolled versions would have
    /// returned zero or nil, which reads as the release being ignored.
    func testAStutteredFrameStillThrows() {
        var sampler = ThrowSampler()
        sampler.record(SIMD3(0, 0, 0), at: 0)
        sampler.record(SIMD3(0.4, 0, 0), at: 0.2)
        // Reading 0.3 s later: both samples are outside a 0.12 s window.
        let velocity = sampler.velocity(at: 0.3)
        XCTAssertNotNil(velocity, "a dropped frame is not a cancelled throw")
        XCTAssertEqual(velocity!.x, 2.0, accuracy: 1e-12)
    }

    func testResetForgetsEverything() {
        var sampler = ThrowSampler()
        sampler.record(SIMD3(0, 0, 0), at: 0)
        sampler.record(SIMD3(1, 0, 0), at: 0.1)
        XCTAssertFalse(sampler.isEmpty)
        sampler.reset()
        XCTAssertTrue(sampler.isEmpty)
        XCTAssertNil(sampler.velocity(at: 0.1))
    }

    /// Pendulums used a 0.14 s window where the others used 0.12; the
    /// window stays configurable so that difference can be a decision
    /// rather than a divergence.
    func testWindowIsConfigurable() {
        var sampler = ThrowSampler(window: 0.14)
        XCTAssertEqual(sampler.window, 0.14)
        sampler.record(SIMD3(0, 0, 0), at: 0)
        sampler.record(SIMD3(0.13, 0, 0), at: 0.13)
        XCTAssertEqual(sampler.velocity(at: 0.13)!.x, 1.0, accuracy: 1e-12)
    }

    // MARK: The release

    /// A hand at 90 Hz whose speed rises to `peak` and falls away again
    /// along +x, the pinch reported open `lag` seconds after the peak.
    private func throwing(peak: Double, lag: Double, jitter: Double = 0,
                          window: Double = 0.16) -> (ThrowSampler, Double) {
        var sampler = ThrowSampler(window: window)
        // speed(t) = peak · sin²(πt/T): a bell 0.3 s long, fastest at 0.15 s.
        let T = 0.3
        let release = 0.15 + lag
        var x = 0.0
        var t = 0.0
        let dt = 1.0 / 90.0
        var index = 0
        while t <= release + 1e-9 {
            // Stamped a little off where the event says it happened.
            let stamp = t + jitter * sin(Double(index) * 2.7)
            sampler.record(SIMD3(x, 0, 0), at: stamp)
            let s = sin(.pi * (t + dt / 2) / T)
            x += peak * s * s * dt
            t += dt
            index += 1
        }
        return (sampler, release)
    }

    func testReleaseVelocityRecoversAConstantVelocity() {
        var sampler = ThrowSampler(window: 0.16)
        for step in 0...14 {
            let t = Double(step) / 90
            sampler.record(SIMD3(t * 4, t * 2, 0), at: t)
        }
        let velocity = try! XCTUnwrap(sampler.releaseVelocity(at: 14.0 / 90))
        XCTAssertEqual(velocity.x, 4, accuracy: 1e-9)
        XCTAssertEqual(velocity.y, 2, accuracy: 1e-9)
    }

    /// The pinch is reported 60 ms after the hand's fastest: the endpoint
    /// estimate has averaged the follow-through in and throws short; the
    /// release estimate finds the peak and never overshoots it.
    func testTheReleaseIsThePeakNotTheFollowThrough() {
        let (sampler, release) = throwing(peak: 6, lag: 0.06)
        let endpoint = try! XCTUnwrap(sampler.velocity(at: release)).x
        let thrown = try! XCTUnwrap(sampler.releaseVelocity(at: release)).x
        XCTAssertLessThan(endpoint, 5.0, "the follow-through was not in the endpoint estimate")
        XCTAssertGreaterThan(thrown, 0.95 * 6, "the release lost the peak")
        XCTAssertLessThanOrEqual(thrown, 6 * 1.001, "the release overshot the fastest the hand went")
    }

    /// Events stamped up to 3 ms off where they happened: a two-point
    /// slope would swing by a fifth, and the fastest of those would be
    /// what threw. The fit holds it within a few percent.
    func testMisstampedEventsDoNotInflateTheRelease() {
        let (sampler, release) = throwing(peak: 6, lag: 0.03, jitter: 0.003)
        let thrown = try! XCTUnwrap(sampler.releaseVelocity(at: release)).x
        XCTAssertEqual(thrown, 6, accuracy: 6 * 0.06)
    }

    /// The direction is the fastest stretch's: a hand that turns down after
    /// letting go does not drag the throw down with it.
    func testTheReleaseKeepsTheDirectionTheHandWasMoving() {
        var sampler = ThrowSampler(window: 0.16)
        var position = SIMD3<Double>.zero
        for step in 0...14 {
            let t = Double(step) / 90
            sampler.record(position, at: t)
            // Up and forward at 5 m/s, then, for the last 40 ms, down at 2 m/s.
            let velocity: SIMD3<Double> = t < 0.115 ? SIMD3(3, 4, 0) : SIMD3(1, -2, 0)
            position += velocity / 90
        }
        let thrown = try! XCTUnwrap(sampler.releaseVelocity(at: 14.0 / 90))
        XCTAssertEqual(atan2(thrown.y, thrown.x), atan2(4.0, 3.0), accuracy: 0.05)
    }

    /// Too little recorded to fit a stretch: the endpoint estimate throws,
    /// and too little to mean anything is still no throw.
    func testAShortFlickStillThrowsAndATwitchDoesNot() {
        var flick = ThrowSampler(window: 0.16)
        flick.record(.zero, at: 0)
        flick.record(SIMD3(0.09, 0, 0), at: 0.03)
        XCTAssertEqual(try! XCTUnwrap(flick.releaseVelocity(at: 0.03)).x, 3, accuracy: 1e-12)
        var twitch = ThrowSampler(window: 0.16)
        twitch.record(.zero, at: 0)
        twitch.record(SIMD3(0.01, 0, 0), at: 0.005)
        XCTAssertNil(twitch.releaseVelocity(at: 0.005))
    }
}
