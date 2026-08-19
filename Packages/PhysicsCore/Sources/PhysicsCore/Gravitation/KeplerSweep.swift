//  KeplerSweep.swift — Kepler's second law: swept area = Σ ½|rᵢ × rᵢ₊₁| over time-stamped
//  positions RELATIVE TO THE PRIMARY; exact for the sampled polygon, valid in any orbit plane.

import Foundation
import simd

public struct KeplerSweep: Sendable, Equatable {
    public struct Sample: Sendable, Equatable {
        /// Simulation time, seconds (any consistent clock).
        public let time: Double
        /// Body position relative to the primary, metres.
        public let position: SIMD3<Double>

        public init(time: Double, position: SIMD3<Double>) {
            self.time = time
            self.position = position
        }
    }

    private(set) public var samples: [Sample] = []
    /// Oldest history kept, seconds. Recording drops anything older.
    public var horizon: Double

    public init(horizon: Double) {
        self.horizon = horizon
    }

    /// Appends and prunes past the horizon. An out-of-order sample (time reset, body
    /// replaced) clears history — a sweep stitched across a discontinuity reports nonsense area.
    public mutating func record(time: Double, position: SIMD3<Double>) {
        if let last = samples.last, time <= last.time {
            samples.removeAll(keepingCapacity: true)
        }
        samples.append(Sample(time: time, position: position))
        if let cutoff = samples.last.map({ $0.time - horizon }) {
            samples.removeAll { $0.time < cutoff }
        }
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    /// Area swept between two times, m². Linear interpolation at the
    /// window edges, triangle sum inside.
    public func area(from start: Double, to end: Double) -> Double {
        let arc = arc(from: start, to: end)
        guard arc.count >= 2 else { return 0 }
        var total = 0.0
        for index in 0..<(arc.count - 1) {
            total += simd_length(simd_cross(arc[index], arc[index + 1])) / 2
        }
        return total
    }

    /// Polyline of relative positions spanning [start, end], interpolated endpoints —
    /// ready to fan into a sector mesh with the primary at the apex.
    public func arc(from start: Double, to end: Double) -> [SIMD3<Double>] {
        guard end > start, samples.count >= 2 else { return [] }
        var points: [SIMD3<Double>] = []
        for (index, sample) in samples.enumerated() {
            if sample.time < start {
                if index + 1 < samples.count, samples[index + 1].time > start {
                    points.append(interpolate(samples[index], samples[index + 1], at: start))
                }
            } else if sample.time > end {
                if index > 0, samples[index - 1].time < end {
                    points.append(interpolate(samples[index - 1], sample, at: end))
                }
                break
            } else {
                if points.isEmpty, index > 0, samples[index - 1].time < start {
                    points.append(interpolate(samples[index - 1], sample, at: start))
                }
                points.append(sample.position)
            }
        }
        return points
    }

    private func interpolate(_ a: Sample, _ b: Sample, at time: Double) -> SIMD3<Double> {
        let span = b.time - a.time
        guard span > 1e-12 else { return b.position }
        let t = (time - a.time) / span
        return a.position + (b.position - a.position) * t
    }
}
