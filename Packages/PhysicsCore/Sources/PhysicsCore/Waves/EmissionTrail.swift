//
//  EmissionTrail.swift
//  PhysicsCore — Waves
//
//  Wavefronts remember where they were born. A moving source emits a
//  crest every period; each crest then expands from its EMISSION
//  point at the medium's wave speed, indifferent to where the source
//  went next. That single rule IS the Doppler effect: crests bunch to
//  (c−v)/f ahead of a moving source and stretch to (c+v)/f behind —
//  the tests pin both exactly.
//

import Foundation
import simd

public struct EmissionTrail: Sendable {
    public struct Event: Sendable, Equatable {
        public var position: SIMD3<Double>
        public var time: Double
    }

    public private(set) var events: [Event] = []
    public var period: Double
    public var capacity: Int

    private var lastTime: Double?
    private var lastPosition: SIMD3<Double>?
    private var nextEmission: Double = 0

    public init(period: Double, capacity: Int = 12) {
        self.period = period
        self.capacity = capacity
    }

    /// Advances the source clock. Emissions between calls land at
    /// their exact times, at positions linearly interpolated along the
    /// source's path — so constant velocity gives exact crest spacing
    /// no matter the call cadence.
    public mutating func advance(to time: Double, sourcePosition: SIMD3<Double>) {
        defer {
            lastTime = time
            lastPosition = sourcePosition
        }
        guard let lastTime, let lastPosition, time > lastTime else {
            nextEmission = time
            return
        }
        while nextEmission <= time {
            let fraction = (nextEmission - lastTime) / (time - lastTime)
            let position = lastPosition + fraction * (sourcePosition - lastPosition)
            events.append(Event(position: position, time: nextEmission))
            if events.count > capacity {
                events.removeFirst(events.count - capacity)
            }
            nextEmission += period
        }
    }

    /// The live wavefronts: each event's crest has grown to
    /// r = speed · (now − emitted).
    public func shells(at time: Double, speed: Double) -> [(center: SIMD3<Double>, radius: Double)] {
        events.compactMap { event in
            let radius = speed * (time - event.time)
            guard radius > 0 else { return nil }
            return (event.position, radius)
        }
    }

    /// Restart (source parameters changed discontinuously).
    public mutating func reset() {
        events.removeAll()
        lastTime = nil
        lastPosition = nil
    }
}
