//  OrbitTrail.swift — where a body has been over the trailing part of its own orbit. Samples are
//  kept a degree apart about a reference body (so Mercury's path and Neptune's are drawn to the
//  same angular density at any clock speed), pruned to a time window, and unwound when time runs
//  backwards. Pure arithmetic, so the rules are unit tests rather than a headset session.

import Foundation
import simd

public struct OrbitTrail: Sendable, Equatable {
    public struct Sample: Sendable, Equatable {
        /// Simulated seconds.
        public let time: Double
        /// Absolute sim metres.
        public let position: SIMD3<Double>

        public init(time: Double, position: SIMD3<Double>) {
            self.time = time
            self.position = position
        }
    }

    /// Ascending in time.
    public private(set) var samples: [Sample] = []
    /// Bumped by every change to `samples` — a renderer's rebuild key.
    public private(set) var generation: UInt32 = 0

    /// How much of its own period a body trails.
    public static let fraction = 0.75
    /// The chord between samples, as an angle about the reference: one degree.
    public static let angularStep = Double.pi / 180
    /// That degree as a chord fraction of the radius, 2·sin(θ/2), eased by a
    /// rounding hair so a sample landing exactly a degree on still counts.
    static let chordFraction = 2 * sin(angularStep / 2) * (1 - 1e-9)
    /// A hard cap; 270 one-degree samples fill a window with room for chords.
    public static let capacity = 512

    public init() {}

    public var isEmpty: Bool { samples.isEmpty }
    public var newest: Sample? { samples.last }
    public var oldest: Sample? { samples.first }

    /// Appends when the chord from the last sample is at least `angularStep`
    /// times the smaller of the two radii about `reference` — a degree of
    /// orbit, or 1.7 % of the radius on a radial fall. `floorRadius` stands
    /// in for the radius when the body is the reference itself or inside it.
    /// Nothing is recorded out of time order: a rewind prunes, it never draws.
    @discardableResult
    public mutating func record(time: Double, position: SIMD3<Double>,
                                reference: SIMD3<Double>, floorRadius: Double) -> Bool {
        if let last = samples.last {
            guard time > last.time else { return false }
            let radius = max(min(simd_distance(position, reference),
                                 simd_distance(last.position, reference)),
                             floorRadius)
            guard simd_distance(position, last.position) >= Self.chordFraction * radius else {
                return false
            }
        }
        samples.append(Sample(time: time, position: position))
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
        generation &+= 1
        return true
    }

    /// Keeps exactly the samples with `now − window ≤ time ≤ now`. Running
    /// forward the tail falls away; running backwards the head does, so the
    /// trail unwinds from the body.
    public mutating func prune(now: Double, window: Double) {
        let lower = now - window
        let before = samples.count
        samples.removeAll { $0.time < lower || $0.time > now }
        if samples.count != before { generation &+= 1 }
    }

    public mutating func clear() {
        guard !samples.isEmpty else { return }
        samples.removeAll()
        generation &+= 1
    }

    /// 0 at the tail of the window, 1 at the body.
    public func age(_ sample: Sample, now: Double, window: Double) -> Double {
        guard window > 0 else { return 1 }
        return min(max((sample.time - (now - window)) / window, 0), 1)
    }

    /// The angle the trail subtends about `reference`, summed over its
    /// chords — the measure of "how much of its orbit" a body trails.
    public func angularSpan(about reference: SIMD3<Double>) -> Double {
        guard samples.count > 1 else { return 0 }
        var total = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) {
            let u = a.position - reference, v = b.position - reference
            let cosine = simd_dot(u, v) / max(simd_length(u) * simd_length(v), 1e-300)
            total += acos(min(max(cosine, -1), 1))
        }
        return total
    }
}
