//
//  KeplerSweep.swift
//  PhysicsCore
//
//  Kepler's second law, as geometry you can hand to a renderer: the
//  radius vector from the primary to an orbiting body sweeps out equal
//  areas in equal times. Near perihelion the sector is short and fat;
//  near aphelion, long and thin; the AREAS match — that is angular
//  momentum conservation wearing its seventeenth-century clothes.
//
//  This type records time-stamped positions RELATIVE TO THE PRIMARY
//  and answers two questions: what area has the radius vector swept
//  over a window, and what arc of points bounds that sector. The area
//  is the sum of the triangle areas ½|rᵢ × rᵢ₊₁| between consecutive
//  samples — exact for the sampled polygon, converging on the true
//  sector as the sampling tightens, and valid for any orbit plane
//  because the cross product does not care which plane the ellipse
//  lies in.
//

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

    /// Appends a sample and prunes history past the horizon. Samples
    /// must arrive in time order; an out-of-order sample (time reset,
    /// body replaced) clears the history and starts over — a sweep
    /// stitched across a discontinuity would report nonsense area.
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

    /// The polyline of relative positions spanning [start, end], with
    /// interpolated endpoints — ready to fan into a sector mesh with
    /// the primary at the apex.
    public func arc(from start: Double, to end: Double) -> [SIMD3<Double>] {
        guard end > start, samples.count >= 2 else { return [] }
        var points: [SIMD3<Double>] = []
        for (index, sample) in samples.enumerated() {
            if sample.time < start {
                // Interpolate the entry point when the window opens
                // between this sample and the next.
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
