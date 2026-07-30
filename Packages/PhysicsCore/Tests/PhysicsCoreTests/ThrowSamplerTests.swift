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
}
