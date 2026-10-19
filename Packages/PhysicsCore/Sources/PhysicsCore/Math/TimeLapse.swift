//
//  TimeLapse.swift
//  PhysicsCore — Math
//
//  A playback clock whose rate varies smoothly: knots of (wall time, rate)
//  joined by smoothsteps, so the rate is continuous with a continuous first
//  derivative (zero at every knot). Simulated time is the rate's exact
//  integral — a smoothstep integrates in closed form — so anything driven
//  by `simTime` is an exact solution of its own physics at every frame,
//  merely watched faster or slower. A rate falling to zero at a knot brings
//  a moving body to rest there with no ease of its own.
//

import Foundation

public struct TimeLapse: Sendable, Equatable {
    public struct Knot: Sendable, Equatable {
        public var time: Double
        public var rate: Double
        public init(time: Double, rate: Double) {
            self.time = time
            self.rate = rate
        }
    }

    public let knots: [Knot]

    /// Knots in increasing time, rates non-negative. Simulated time is zero
    /// at the first knot.
    public init(knots: [Knot]) {
        precondition(!knots.isEmpty, "a time-lapse needs at least one knot")
        precondition(zip(knots, knots.dropFirst()).allSatisfy { $0.time < $1.time },
                     "knots must increase in time")
        precondition(knots.allSatisfy { $0.rate >= 0 }, "a time-lapse never runs backwards")
        self.knots = knots
    }

    /// Smoothstep and its integral from 0.
    private static func step(_ x: Double) -> Double { x * x * (3 - 2 * x) }
    private static func stepIntegral(_ x: Double) -> Double { x * x * x - x * x * x * x / 2 }

    /// The rate, simulated seconds per wall second, at wall time `t`.
    public func rate(at t: Double) -> Double {
        guard t > knots[0].time else { return knots[0].rate }
        guard let last = knots.last, t < last.time else { return knots[knots.count - 1].rate }
        let i = segment(containing: t)
        let a = knots[i], b = knots[i + 1]
        return a.rate + (b.rate - a.rate) * Self.step((t - a.time) / (b.time - a.time))
    }

    /// Simulated time at wall time `t`: the rate's exact integral from the
    /// first knot.
    public func simTime(at t: Double) -> Double {
        let first = knots[0]
        guard t > first.time else { return first.rate * (t - first.time) }
        var total = 0.0
        for i in 0..<(knots.count - 1) {
            let a = knots[i], b = knots[i + 1]
            let span = b.time - a.time
            let x = min((t - a.time) / span, 1)
            total += span * (a.rate * x + (b.rate - a.rate) * Self.stepIntegral(x))
            if t <= b.time { return total }
        }
        let last = knots[knots.count - 1]
        return total + last.rate * (t - last.time)
    }

    /// The earliest wall time at which simulated time reaches `tau`, by
    /// bisection (simulated time never decreases). Nil if it never does.
    public func wallTime(reaching tau: Double) -> Double? {
        var low = knots[0].time
        if simTime(at: low) >= tau { return knots[0].rate > 0 ? low + (tau - simTime(at: low)) / knots[0].rate : low }
        var high = knots[knots.count - 1].time
        if simTime(at: high) < tau {
            let last = knots[knots.count - 1]
            guard last.rate > 0 else { return nil }
            return last.time + (tau - simTime(at: last.time)) / last.rate
        }
        for _ in 0..<100 {
            let middle = (low + high) / 2
            if simTime(at: middle) < tau { low = middle } else { high = middle }
        }
        return high
    }

    private func segment(containing t: Double) -> Int {
        var i = 0
        while i < knots.count - 2, t >= knots[i + 1].time { i += 1 }
        return i
    }
}
