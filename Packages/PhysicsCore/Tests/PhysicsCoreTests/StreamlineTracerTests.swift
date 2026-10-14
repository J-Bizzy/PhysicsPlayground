//
//  StreamlineTracerTests.swift
//  PhysicsCoreTests
//
//  The seeding and splicing the electric and magnetic tracers share. A
//  bug here draws both field pictures wrong, so the contract is pinned
//  directly. The fields are analytic and trivial on purpose (uniform and
//  inverse-square monopole): under test is the seeding, the direction
//  handling and the splice, not the RK4.
//

import XCTest
import simd
@testable import PhysicsCore

final class StreamlineTracerTests: XCTestCase {

    /// Straight up, everywhere.
    private let uniformUp: (SIMD3<Double>) -> SIMD3<Double> = { _ in SIMD3(0, 1, 0) }

    private func config(stepSize: Double = 0.01, maxSteps: Int = 50,
                        boundsRadius: Double = 10) -> StreamlineTracer.Config {
        var config = StreamlineTracer.Config()
        config.stepSize = stepSize
        config.maxSteps = maxSteps
        config.boundsRadius = boundsRadius
        config.stopRadius = 0
        return config
    }

    // MARK: Seeding

    /// Every seed becomes a line, and the count is what was asked for.
    func testEachSeedBecomesOneDirectedLine() {
        let lines = StreamlineTracer.directedLines(
            from: [StreamlineTracer.Seeded(position: .zero, seeds: 7)],
            seedRadius: 0.05, stopCenters: [], config: config(), field: uniformUp)
        XCTAssertEqual(lines.count, 7)
    }

    /// Two sources contribute independently.
    func testSeedsAccumulateAcrossSources() {
        let lines = StreamlineTracer.directedLines(
            from: [StreamlineTracer.Seeded(position: SIMD3(-1, 0, 0), seeds: 3),
                   StreamlineTracer.Seeded(position: SIMD3(1, 0, 0), seeds: 5)],
            seedRadius: 0.05, stopCenters: [], config: config(), field: uniformUp)
        XCTAssertEqual(lines.count, 8)
    }

    /// Seeds sit on a sphere of `seedRadius` about the source — that is
    /// what keeps a line from starting inside the object drawing it.
    func testSeedsStartOnTheSeedSphere() {
        let centre = SIMD3<Double>(0.3, 1.2, -0.4)
        let lines = StreamlineTracer.directedLines(
            from: [StreamlineTracer.Seeded(position: centre, seeds: 12)],
            seedRadius: 0.07, stopCenters: [], config: config(), field: uniformUp)
        for line in lines {
            XCTAssertEqual(simd_distance(line.first!, centre), 0.07, accuracy: 1e-12)
        }
    }

    // MARK: Direction

    /// A positive source's lines run with the field; a negative source's
    /// run against it. In the electric picture this is the whole reason
    /// lines leave positives and arrive at negatives.
    func testSignReversesTheDirectionOfTravel() {
        let out = StreamlineTracer.directedLines(
            from: [StreamlineTracer.Seeded(position: .zero, seeds: 1, sign: 1)],
            seedRadius: 0.05, stopCenters: [], config: config(), field: uniformUp)[0]
        let into = StreamlineTracer.directedLines(
            from: [StreamlineTracer.Seeded(position: .zero, seeds: 1, sign: -1)],
            seedRadius: 0.05, stopCenters: [], config: config(), field: uniformUp)[0]

        XCTAssertGreaterThan(out.last!.y, out.first!.y, "+1 climbs with the field")
        XCTAssertLessThan(into.last!.y, into.first!.y, "−1 runs back down it")
    }

    // MARK: The splice — the magnetic case

    /// A looped line is one continuous curve through its seed, not two
    /// lines meeting at it. The seed must appear exactly once: splicing
    /// without dropping it leaves a duplicated point, which a tube mesh
    /// renders as a kink or a zero-length segment.
    func testLoopedLineContainsItsSeedExactlyOnce() {
        let seedRadius = 0.05
        // Derived, not assumed: a single Fibonacci seed points along +x,
        // not +y — worth stating, since guessing it wrong is what made
        // the first draft of this test pass for the wrong reason.
        let seed = StreamlineTracer.fibonacciSphere(count: 1)[0] * seedRadius
        let lines = StreamlineTracer.loopedLines(
            from: [StreamlineTracer.Seeded(position: .zero, seeds: 1)],
            seedRadius: seedRadius, stopCenters: [], config: config(), field: uniformUp)
        let occurrences = lines[0].filter { simd_distance($0, seed) < 1e-9 }
        XCTAssertEqual(occurrences.count, 1, "the shared seed point must not be duplicated")
    }

    /// The spliced curve runs monotonically from the backward half through
    /// the seed into the forward half — i.e. it was joined in order, not
    /// concatenated head-to-head.
    func testLoopedLineIsOrderedThroughTheSeed() {
        let lines = StreamlineTracer.loopedLines(
            from: [StreamlineTracer.Seeded(position: .zero, seeds: 1)],
            seedRadius: 0.05, stopCenters: [], config: config(), field: uniformUp)
        let ys = lines[0].map(\.y)
        for (a, b) in zip(ys, ys.dropFirst()) {
            XCTAssertLessThan(a, b, "a spliced line must not double back on itself")
        }
    }

    /// A looped trace covers both halves, so it is about twice the length
    /// of a directed one from the same seed and step budget.
    func testLoopedLineIsAboutTwiceADirectedOne() {
        let seeded = [StreamlineTracer.Seeded(position: .zero, seeds: 1)]
        let directed = StreamlineTracer.directedLines(
            from: seeded, seedRadius: 0.05, stopCenters: [],
            config: config(maxSteps: 40), field: uniformUp)[0]
        let looped = StreamlineTracer.loopedLines(
            from: seeded, seedRadius: 0.05, stopCenters: [],
            config: config(maxSteps: 40), field: uniformUp)[0]
        // Forward + backward, minus the seed counted once.
        XCTAssertEqual(looped.count, directed.count * 2 - 1)
    }

    // MARK: Termination

    /// `stopCenters` end a line — for charges, this is what makes field
    /// lines terminate on the opposite charge instead of tunnelling past.
    func testLinesStopAtAStopCentre() {
        var config = self.config(stepSize: 0.01, maxSteps: 500)
        config.stopRadius = 0.02
        let seedRadius = 0.05
        // The stop has to sit on the line's path, so it is placed above
        // the actual seed rather than above the source.
        let seed = StreamlineTracer.fibonacciSphere(count: 1)[0] * seedRadius
        let stop = seed + SIMD3(0, 0.5, 0)
        let lines = StreamlineTracer.directedLines(
            from: [StreamlineTracer.Seeded(position: .zero, seeds: 1)],
            seedRadius: seedRadius,
            stopCenters: [stop],
            config: config, field: uniformUp)
        // Without the stop this would climb 500 × 0.01 = 5 m.
        XCTAssertEqual(lines[0].last!.y, stop.y, accuracy: 0.05)
    }

    /// Leaving the room ends a line, so a field that never terminates
    /// cannot spend the whole step budget wandering out of the region.
    func testLinesStopAtTheBoundsRadius() {
        let lines = StreamlineTracer.directedLines(
            from: [StreamlineTracer.Seeded(position: .zero, seeds: 1)],
            seedRadius: 0.05, stopCenters: [],
            config: config(stepSize: 0.05, maxSteps: 500, boundsRadius: 1.0),
            field: uniformUp)
        XCTAssertLessThan(simd_length(lines[0].last!), 1.1)
    }

    // MARK: Degenerate input

    func testNoSourcesGivesNoLines() {
        XCTAssertTrue(StreamlineTracer.directedLines(
            from: [], seedRadius: 0.05, stopCenters: [],
            config: config(), field: uniformUp).isEmpty)
        XCTAssertTrue(StreamlineTracer.loopedLines(
            from: [], seedRadius: 0.05, stopCenters: [],
            config: config(), field: uniformUp).isEmpty)
    }

    /// A field that vanishes everywhere has no streamlines to draw — the
    /// tangent is undefined, so lines die at birth and are filtered out
    /// rather than emitted as single points a tube mesh cannot build.
    func testAVanishingFieldDrawsNothing() {
        let dead: (SIMD3<Double>) -> SIMD3<Double> = { _ in .zero }
        XCTAssertTrue(StreamlineTracer.directedLines(
            from: [StreamlineTracer.Seeded(position: .zero, seeds: 6)],
            seedRadius: 0.05, stopCenters: [], config: config(), field: dead).isEmpty)
        XCTAssertTrue(StreamlineTracer.loopedLines(
            from: [StreamlineTracer.Seeded(position: .zero, seeds: 6)],
            seedRadius: 0.05, stopCenters: [], config: config(), field: dead).isEmpty)
    }

    func testZeroSeedsGivesNoLines() {
        XCTAssertTrue(StreamlineTracer.directedLines(
            from: [StreamlineTracer.Seeded(position: .zero, seeds: 0)],
            seedRadius: 0.05, stopCenters: [], config: config(), field: uniformUp).isEmpty)
    }
}
