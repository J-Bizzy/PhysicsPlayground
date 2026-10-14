//
//  Recession.swift
//  RenderKit
//
//  Instruments stand back until a hand comes near. Emphasis is opacity,
//  never geometry: nothing moves, resizes or hides, and a receded
//  instrument is still readable and still pinchable, so a user who
//  knows where a control is can go straight to it.
//

import RealityKit
import simd

@MainActor
public enum Recession {
    /// How faint an instrument goes when no hand is near — still readable,
    /// because a bank is a state display as much as a control.
    public static let restingOpacity: Float = 0.45

    /// How close a hand has to be, in metres, for full brightness.
    public static let nearDistance: Float = 0.8

    /// Where it starts responding — beyond this it is fully receded. The
    /// gap between the two is what makes it a fade rather than a switch.
    public static let farDistance: Float = 1.4

    /// The opacity an instrument at `anchor` should wear. With no hand
    /// tracked at all (the simulator, or hands out of view) this returns
    /// full brightness: an instrument that dims because tracking dropped
    /// is one that flickers.
    public static func opacity(anchor: SIMD3<Float>,
                               nearestHand: SIMD3<Float>?) -> Float {
        guard let nearestHand else { return 1 }
        let distance = simd_distance(anchor, nearestHand)
        if distance <= nearDistance { return 1 }
        if distance >= farDistance { return restingOpacity }
        let t = (distance - nearDistance) / (farDistance - nearDistance)
        return 1 - (1 - restingOpacity) * t
    }

    /// Applies it. A no-op under Reduce Motion — the recession is an
    /// animation, and someone who has asked for less of that should get
    /// a room that simply holds still at full brightness.
    public static func apply(to entity: Entity, anchor: SIMD3<Float>,
                             nearestHand: SIMD3<Float>?) {
        guard !Motion.isReduced else {
            entity.components.remove(OpacityComponent.self)
            return
        }
        let target = opacity(anchor: anchor, nearestHand: nearestHand)
        // Dropped at full light, per `Fade`'s rule: a settled entity
        // renders on the fast path with no per-frame component cost.
        if target > 0.995 {
            entity.components.remove(OpacityComponent.self)
        } else {
            entity.components.set(OpacityComponent(opacity: target))
        }
    }
}
