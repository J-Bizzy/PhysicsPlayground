//
//  Recession.swift
//  RenderKit
//
//  Instruments stand back until a hand comes near.
//
//  THE COMPLAINT IS VISUAL WEIGHT, NOT FEATURE COUNT. Counting the
//  standing objects per lab: Magnetism 6, Pendulums 6, Projectiles ~11,
//  Electric Fields ~12, Gravity Lab ~16, Circuits ~21. The first two
//  prove the vocabulary can produce a calm room, so the answer is not
//  fewer capabilities — it is that everything a module owns currently
//  stands at 100% brightness all of the time, whether you are using it
//  or looking past it at the physics.
//
//  The hub already knew better. Its focused exhibit lifts and lights
//  while the others recede, and DECISIONS.md 2026-07-30 states the rule
//  the labs never adopted: *"emphasis is opacity, light and sound —
//  never geometry."* Nothing moves here, nothing resizes, nothing is
//  hidden and no capability is removed; an instrument you are not
//  reaching for is simply quieter than the physics it serves.
//
//  IT IS OPACITY, NOT `isEnabled`. A receded instrument is still lit
//  enough to read — which matters because half of them are readouts —
//  and still fully pinchable, so a user who knows where a control is can
//  go straight to it without waving at the room first. The floor is
//  deliberately high for that reason.
//

import RealityKit
import simd

@MainActor
public enum Recession {
    /// How faint an instrument goes when no hand is near.
    ///
    /// 0.45 is a judgement, and the judgement is that a receded
    /// instrument must still be READABLE — the layer bank is a state
    /// display as much as a control, and a bank you have to reach toward
    /// before you can see what is on is worse than a bright one.
    public static let restingOpacity: Float = 0.45

    /// How close a hand has to be, in metres, for full brightness.
    public static let nearDistance: Float = 0.8

    /// Where it starts responding — beyond this it is fully receded. The
    /// gap between the two is what makes it a fade rather than a switch.
    public static let farDistance: Float = 1.4

    /// The opacity an instrument at `anchor` should wear.
    ///
    /// With no hand tracked at all — the simulator, and any device frame
    /// where the hands are out of view — this returns FULL brightness
    /// rather than the resting level. An instrument that fades out
    /// because the system briefly lost your hands is an instrument that
    /// flickers, and the failure mode of guessing wrong here is a room
    /// that dims itself while you are reading it.
    public static func opacity(anchor: SIMD3<Float>,
                               nearestHand: SIMD3<Float>?) -> Float {
        guard let nearestHand else { return 1 }
        let distance = simd_distance(anchor, nearestHand)
        if distance <= nearDistance { return 1 }
        if distance >= farDistance { return restingOpacity }
        let t = (distance - nearDistance) / (farDistance - nearDistance)
        return 1 - (1 - restingOpacity) * t
    }

    /// Applies it. A no-op under Reduce Motion — the recession IS an
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
