//
//  Fade.swift
//  RenderKit
//
//  Emphasis is opacity, light and sound — never geometry. This file is
//  the opacity half of that rule for things that APPEAR: a selection
//  halo, a decomposition arrow, a bank lamp. Before it, every one of
//  them toggled `isEnabled` and popped.
//
//  Two tools, matched to the two shapes the pop took:
//
//  · `tick` — for entities that come and go whole. Ramps an
//    `OpacityComponent` toward shown or hidden; the entity is disabled
//    only at full dark, and the component is dropped at full light so a
//    settled entity renders on the fast path with no per-frame cost.
//  · `approach` — for a painted colour that jumps between states (a
//    lamp's lit and dark). Exponentially eases an (r, g, b, opacity)
//    vector toward its target and reports when it has settled, so the
//    caller keeps its repaint-only-on-change discipline: a settled lamp
//    rebuilds nothing.
//
//  Both honour the SYSTEM Reduce Motion switch by snapping — the app
//  deliberately has no private duplicate of that setting (the in-app
//  toggle was deleted 2026-07-31).
//
//  `tick` keeps its clock in a component on the entity itself rather
//  than in a side table keyed by identity: the state dies with the
//  entity, and a pooled entity that is reused starts clean.
//

import QuartzCore
import RealityKit
import UIKit

@MainActor
public enum Fade {
    /// The house ramp for appearing/disappearing decoration.
    public static let duration: Double = 0.15

    /// The house time constant for a lamp's colour ease.
    public static let lampTau: Double = 0.12

    private struct Clock: Component {
        var lastTick: Double
    }
    private static var registered = false

    /// Steps `entity` toward `visible`. Call every frame; the frame's
    /// spacing is measured on the entity itself, so callers without a
    /// `dt` in hand need not thread one through.
    public static func tick(_ entity: Entity, visible: Bool,
                            duration: Double = Fade.duration) {
        if !registered { Clock.registerComponent(); registered = true }

        let current: Float = entity.isEnabled
            ? (entity.components[OpacityComponent.self]?.opacity ?? 1)
            : 0
        let target: Float = visible ? 1 : 0

        if current == target {
            entity.components.remove(Clock.self)
            if !visible { entity.isEnabled = false }
            else if entity.components[OpacityComponent.self] != nil {
                entity.components.remove(OpacityComponent.self)
            }
            return
        }

        if UIAccessibility.isReduceMotionEnabled {
            entity.isEnabled = visible
            entity.components.remove(OpacityComponent.self)
            entity.components.remove(Clock.self)
            return
        }

        let now = CACurrentMediaTime()
        let dt = min(max(now - (entity.components[Clock.self]?.lastTick ?? now),
                         0), 0.1)
        entity.components.set(Clock(lastTick: now))

        let step = Float(dt / max(duration, 1e-3))
        let next = current < target
            ? min(current + step, target)
            : max(current - step, target)

        if next <= 0 {
            entity.isEnabled = false
            entity.components.remove(OpacityComponent.self)
            entity.components.remove(Clock.self)
        } else if next >= 1 {
            entity.isEnabled = true
            entity.components.remove(OpacityComponent.self)
            entity.components.remove(Clock.self)
        } else {
            entity.isEnabled = true
            entity.components.set(OpacityComponent(opacity: next))
        }
    }

    /// Eases a painted (r, g, b, opacity) toward `target`. Returns the
    /// new paint; it EQUALS `target` (exactly) once settled, so a caller
    /// can compare and skip the repaint.
    public static func approach(_ paint: SIMD4<Float>,
                                toward target: SIMD4<Float>,
                                dt: Double,
                                tau: Double = Fade.lampTau) -> SIMD4<Float> {
        if UIAccessibility.isReduceMotionEnabled { return target }
        let k = Float(min(1, max(dt, 0) / max(tau, 1e-3)))
        let next = paint + (target - paint) * k
        // Under half a display step of colour left: call it arrived.
        return simd_length(target - next) < 0.002 ? target : next
    }

    /// The paint vector for a colour at an opacity.
    public static func paint(_ color: UIColor, opacity: Float) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), opacity)
    }

    /// An unlit material from a paint vector — the lamp's own format.
    public static func unlit(_ paint: SIMD4<Float>) -> UnlitMaterial {
        var material = UnlitMaterial(color: UIColor(red: CGFloat(paint.x),
                                                    green: CGFloat(paint.y),
                                                    blue: CGFloat(paint.z),
                                                    alpha: 1))
        material.blending = .transparent(opacity: .init(floatLiteral: paint.w))
        return material
    }
}
