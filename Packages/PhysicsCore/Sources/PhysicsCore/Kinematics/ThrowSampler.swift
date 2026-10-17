//
//  ThrowSampler.swift
//  PhysicsCore — Kinematics
//
//  Your arm as an initial condition: a short history of hand positions,
//  and on release the displacement over the last fraction of a second
//  divided by elapsed time. Shared by every module that throws; callers
//  pass timestamps in, so it is testable at exact times. Deliberately an
//  endpoint difference, not a fit: fitting the whole path drags in the
//  wind-up and reads as a weaker throw than the one you made.
//

import Foundation
import simd

/// A short history of hand positions, and the velocity they imply.
public struct ThrowSampler: Sendable {
    /// How far back a release looks. Long enough to average out tracking
    /// jitter, short enough that only the throw itself is in the window
    /// and not the wind-up before it.
    public static let defaultWindow = 0.12
    /// Below this the hand hasn't travelled long enough to mean anything,
    /// and displacement over a near-zero interval is a divide-by-noise
    /// that flings objects at absurd speeds.
    public static let defaultMinimumSpan = 0.02
    /// A safety bound only. Age pruning already keeps the buffer at a
    /// frame's worth of samples; this stops a pathological caller that
    /// never advances its clock from growing it without limit.
    public static let capacity = 32

    public var window: Double
    public var minimumSpan: Double
    private var samples: [(time: Double, position: SIMD3<Double>)] = []

    public init(window: Double = ThrowSampler.defaultWindow,
                minimumSpan: Double = ThrowSampler.defaultMinimumSpan) {
        self.window = window
        self.minimumSpan = minimumSpan
    }

    public var isEmpty: Bool { samples.isEmpty }
    public var count: Int { samples.count }

    /// Records where the hand is now, dropping what has aged out.
    ///
    /// Always keeps the two newest samples whatever their age: a dropped
    /// frame or a stalled solver can leave every sample older than the
    /// window, and a throw that reports no velocity because the app
    /// stuttered reads as the release having been ignored.
    public mutating func record(_ position: SIMD3<Double>, at time: Double) {
        samples.append((time, position))
        while samples.count > 2, let oldest = samples.first,
              time - oldest.time > window {
            samples.removeFirst()
        }
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }

    public mutating func reset() { samples.removeAll() }

    /// The hand's velocity over the sampled window, or nil when the hand
    /// has not moved for long enough to have meant it.
    ///
    /// Endpoint difference over elapsed time — see the note above on why
    /// this is not fitted.
    public func velocity(at now: Double) -> SIMD3<Double>? {
        let window = samples.filter { now - $0.time <= self.window }
        // Fall back to the whole buffer rather than nothing: `record`
        // guarantees two samples exist, and a stuttered frame should
        // still throw.
        let usable = window.count >= 2 ? window : samples
        guard let first = usable.first, let last = usable.last else { return nil }
        let span = last.time - first.time
        guard span >= minimumSpan else { return nil }
        return (last.position - first.position) / span
    }

    /// How long a stretch of travel `releaseVelocity` fits a velocity to.
    public static let releaseSpan = 0.05

    /// The velocity the hand let go at, for a throw: the fastest
    /// `releaseSpan` of travel in the window before `now`, each stretch's
    /// velocity the least-squares slope of the samples inside it.
    ///
    /// WHY NOT THE ENDPOINT. A pinch is reported open after the fingers
    /// have opened, and a throwing hand is slowing by then — the
    /// follow-through. The endpoint difference averages that slowing into
    /// the throw and the ball leaves slower than it was thrown. A hand lets
    /// go near its fastest, so the fastest stretch just before the report
    /// is the release. A fit inside each stretch rather than two points:
    /// an event stamped a few milliseconds off swings a two-point slope,
    /// and taking the fastest would pick exactly that one.
    ///
    /// Falls back to `velocity(at:)` when no stretch fits in what was
    /// recorded, so a short flick still throws.
    public func releaseVelocity(at now: Double) -> SIMD3<Double>? {
        let recent = samples.filter { now - $0.time <= window + 1e-9 }
        var fastest: SIMD3<Double>?
        for end in recent.indices {
            let stretch = recent[...end].filter { recent[end].time - $0.time <= Self.releaseSpan + 1e-9 }
            guard stretch.count >= 3,
                  let first = stretch.first,
                  recent[end].time - first.time >= 0.8 * Self.releaseSpan else { continue }
            let meanTime = stretch.reduce(0) { $0 + $1.time } / Double(stretch.count)
            let meanPosition = stretch.reduce(SIMD3<Double>.zero) { $0 + $1.position }
                / Double(stretch.count)
            var spread = 0.0
            var covariance = SIMD3<Double>.zero
            for sample in stretch {
                let dt = sample.time - meanTime
                spread += dt * dt
                covariance += dt * (sample.position - meanPosition)
            }
            guard spread > 1e-12 else { continue }
            let slope = covariance / spread
            if fastest.map({ simd_length(slope) > simd_length($0) }) ?? true {
                fastest = slope
            }
        }
        return fastest ?? velocity(at: now)
    }
}
