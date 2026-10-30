//
//  Motion.swift
//  RenderKit
//
//  One authority for "should this animate", and one ease that obeys it.
//  The system Reduce Motion setting only — there is no in-app duplicate.
//  Read here rather than passed down from SwiftUI because the primitives
//  are RealityKit objects ticked from `SceneEvents.Update`, not views.
//

import Foundation
import UIKit

@MainActor
public enum Motion {
    /// The system Reduce Motion switch.
    public static var isReduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// The house ease: exponential approach, frame-rate independent,
    /// snapping when close enough so nothing sits fractionally open. Under
    /// Reduce Motion it jumps, which is why callers must not roll their own.
    public static func ease(_ value: Float, toward target: Float,
                            dt: Double, rate: Double = 9) -> Float {
        guard !isReduced else { return target }
        var next = value + (target - value) * Float(min(dt * rate, 1))
        if abs(next - target) < 0.004 { next = target }
        return min(max(next, min(value, target)), max(value, target))
    }

    /// The lerp factor itself, for a caller easing several values against
    /// one clock. Returns 1 under Reduce Motion, which lands everything
    /// this frame.
    public static func rate(dt: Double, _ perSecond: Double = 9) -> Float {
        isReduced ? 1 : Float(min(dt * perSecond, 1))
    }

    /// `Double` overload, for the primitives whose openness is one.
    public static func ease(_ value: Double, toward target: Double,
                            dt: Double, rate: Double = 9) -> Double {
        guard !isReduced else { return target }
        var next = value + (target - value) * min(dt * rate, 1)
        if abs(next - target) < 0.004 { next = target }
        return min(max(next, min(value, target)), max(value, target))
    }

    /// The house throw (2026-10-30): a damped spring, for a part that is
    /// flung rather than eased — a switch's blade swings past where it stops
    /// and settles. At the defaults (7 Hz, damping 0.45) it overshoots by a
    /// fifth and settles in about 0.2 s. Stepped at 240 Hz inside each frame
    /// so its shape does not depend on the frame rate; under Reduce Motion
    /// it lands at once.
    public struct Spring: Equatable, Sendable {
        public var value: Float
        public var velocity: Float = 0

        public init(_ value: Float, velocity: Float = 0) {
            self.value = value
            self.velocity = velocity
        }

        public var isSettled: Bool { velocity == 0 }

        @MainActor
        public mutating func step(toward target: Float, dt: Double,
                                  frequency: Float = 7, damping: Float = 0.45) {
            guard !Motion.isReduced else {
                value = target
                velocity = 0
                return
            }
            let omega = 2 * Float.pi * frequency
            var remaining = Float(max(0, Swift.min(dt, 0.1)))
            while remaining > 0 {
                let h = Swift.min(remaining, 1 / 240)
                let pull = -omega * omega * (value - target) - 2 * damping * omega * velocity
                velocity += pull * h
                value += velocity * h
                remaining -= h
            }
            if abs(value - target) < 1e-4, abs(velocity) < 1e-3 {
                value = target
                velocity = 0
            }
        }
    }
}
