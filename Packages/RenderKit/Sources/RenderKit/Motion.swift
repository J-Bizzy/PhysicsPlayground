//
//  Motion.swift
//  RenderKit
//
//  One authority for "should this animate", and one ease that obeys it.
//
//  Reduce Motion reached TWO of the app's eight animated primitives.
//  `Fade` and `PickupPulse` honour it; `Bloom`, `SpatialPicker`, both
//  banks, `Well` (a perpetual breath, in every lab) and `FrozenVectors`
//  did not. The symptom that gives it away is in one file and one frame:
//  the hub's terrace hairlines freeze mid-shimmer while the door signs
//  directly above them park correctly, because the signs were written
//  after somebody remembered and the hairlines before.
//
//  It is the SYSTEM setting and only the system setting. The in-app
//  duplicate was deleted on 2026-07-31 and must not come back — two
//  switches for one preference is how a user ends up with motion they
//  turned off.
//
//  Read here rather than passed down from SwiftUI because the primitives
//  are RealityKit objects ticked from `SceneEvents.Update`, not views:
//  the ones that took `stillness` as a parameter got it right exactly as
//  often as their caller remembered to pass it, which is the failure
//  this file exists to end. `UIAccessibility` is the same value SwiftUI's
//  `\.accessibilityReduceMotion` reads.
//

import Foundation
import UIKit

@MainActor
public enum Motion {
    /// The system Reduce Motion switch.
    public static var isReduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// The house ease: exponential approach, frame-rate independent,
    /// snapping when close enough so nothing sits fractionally open.
    ///
    /// Under Reduce Motion it JUMPS. That is the whole contract, and it
    /// is why callers should reach for this rather than rolling
    /// `value += (target - value) * rate * dt` — which is what six
    /// primitives did, correctly, and unaccountably.
    public static func ease(_ value: Float, toward target: Float,
                            dt: Double, rate: Double = 9) -> Float {
        guard !isReduced else { return target }
        var next = value + (target - value) * Float(min(dt * rate, 1))
        if abs(next - target) < 0.004 { next = target }
        return min(max(next, min(value, target)), max(value, target))
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
