//
//  OrbitTrailTests.swift
//  The trail's rules: a degree between samples about the reference, a window kept exactly,
//  an unwind when time runs backwards, a bounded record, and an age that runs tail to head.
//

import XCTest
import simd
@testable import PhysicsCore

final class OrbitTrailTests: XCTestCase {

    private let radius = 1.5e11
    private let floorRadius = 6e9

    /// A body on a circle, fed every tenth of a degree.
    private func circle(degrees: Double, step: Double = 0.1) -> OrbitTrail {
        var trail = OrbitTrail()
        var angle = 0.0
        var time = 0.0
        while angle <= degrees {
            let theta = angle * .pi / 180
            trail.record(time: time, position: SIMD3(radius * cos(theta), 0, -radius * sin(theta)),
                         reference: .zero, floorRadius: floorRadius)
            angle += step
            time += 1
        }
        return trail
    }

    func testSamplesAreOneDegreeApartOnACircle() {
        let trail = circle(degrees: 90)
        XCTAssertEqual(trail.samples.count, 91, "a quarter circle at a degree a sample")
        for (a, b) in zip(trail.samples, trail.samples.dropFirst()) {
            let gap = acos(simd_dot(simd_normalize(a.position), simd_normalize(b.position)))
            XCTAssertEqual(gap, .pi / 180, accuracy: 0.15 * .pi / 180)
        }
        XCTAssertEqual(trail.angularSpan(about: .zero), .pi / 2, accuracy: 0.02)
    }

    /// The same density whatever the radius: a degree is a degree.
    func testTheAngularDensityDoesNotDependOnTheRadius() {
        var near = OrbitTrail(), far = OrbitTrail()
        for step in 0...900 {
            let theta = Double(step) * 0.1 * .pi / 180
            near.record(time: Double(step), position: SIMD3(cos(theta), 0, sin(theta)) * 5e10,
                        reference: .zero, floorRadius: floorRadius)
            far.record(time: Double(step), position: SIMD3(cos(theta), 0, sin(theta)) * 4.5e12,
                       reference: .zero, floorRadius: floorRadius)
        }
        XCTAssertEqual(near.samples.count, far.samples.count)
    }

    /// Straight in: no angle, but the chord rule still records — every 1.7 % of the radius.
    func testARadialFallStillLeavesATrail() {
        var trail = OrbitTrail()
        var r = radius
        var time = 0.0
        while r > 1e10 {
            trail.record(time: time, position: SIMD3(r, 0, 0), reference: .zero,
                         floorRadius: floorRadius)
            r -= 1e8
            time += 1
        }
        XCTAssertGreaterThan(trail.samples.count, 100, "the fall left \(trail.samples.count) samples")
        XCTAssertLessThan(trail.samples.count, 200)
        XCTAssertEqual(trail.angularSpan(about: .zero), 0, accuracy: 1e-9)
    }

    /// Inside the floor the chord rule uses the floor: the reference body's own trail is bounded.
    func testTheReferenceBodyRecordsByTheFloor() {
        var trail = OrbitTrail()
        for step in 0..<10_000 {
            // A 1 m wobble: nothing to record against a 6e9 m floor.
            trail.record(time: Double(step), position: SIMD3(sin(Double(step)), 0, 0),
                         reference: .zero, floorRadius: floorRadius)
        }
        XCTAssertEqual(trail.samples.count, 1)
        trail.record(time: 10_000, position: SIMD3(2e8, 0, 0), reference: .zero,
                     floorRadius: floorRadius)
        XCTAssertEqual(trail.samples.count, 2, "a chord past the floor's degree records")
    }

    func testPruneKeepsExactlyTheWindow() {
        var trail = circle(degrees: 180)
        let newest = trail.newest!.time
        trail.prune(now: newest, window: 500)
        XCTAssertEqual(trail.oldest!.time, newest - 500, accuracy: 10)
        XCTAssertEqual(trail.newest!.time, newest)
        for sample in trail.samples {
            XCTAssertGreaterThanOrEqual(sample.time, newest - 500)
        }
        let generation = trail.generation
        trail.prune(now: newest, window: 500)
        XCTAssertEqual(trail.generation, generation, "a prune that changed nothing bumped the generation")
    }

    /// Time running backwards eats the trail from the body's end.
    func testReverseUnwindsFromTheHead() {
        var trail = circle(degrees: 180)
        let oldest = trail.oldest!
        let newest = trail.newest!.time
        trail.prune(now: newest - 600, window: 5000)
        XCTAssertEqual(trail.oldest!, oldest, "the tail moved when the head should have")
        XCTAssertLessThanOrEqual(trail.newest!.time, newest - 600)
        // Nothing older than "now" is drawn, ever.
        XCTAssertFalse(trail.record(time: newest - 700, position: .zero, reference: .zero,
                                    floorRadius: floorRadius),
                       "a sample out of time order was recorded")
    }

    func testCapacityIsBounded() {
        let trail = circle(degrees: 1080)
        XCTAssertEqual(trail.samples.count, OrbitTrail.capacity)
        XCTAssertGreaterThan(trail.oldest!.time, 0, "the cap dropped the newest instead of the oldest")
    }

    func testAgeRunsFromTailToHead() {
        let trail = circle(degrees: 90)
        let now = trail.newest!.time
        XCTAssertEqual(trail.age(trail.newest!, now: now, window: now), 1)
        XCTAssertEqual(trail.age(trail.oldest!, now: now, window: now), 0, accuracy: 1e-12)
        let middle = trail.samples[trail.samples.count / 2]
        XCTAssertEqual(trail.age(middle, now: now, window: now), 0.5, accuracy: 0.02)
    }

    func testClearBumpsTheGenerationOnce() {
        var trail = circle(degrees: 10)
        let generation = trail.generation
        trail.clear()
        XCTAssertTrue(trail.isEmpty)
        XCTAssertEqual(trail.generation, generation &+ 1)
        trail.clear()
        XCTAssertEqual(trail.generation, generation &+ 1, "clearing an empty trail is not a change")
    }
}
