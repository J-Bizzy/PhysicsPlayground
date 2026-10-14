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
}
