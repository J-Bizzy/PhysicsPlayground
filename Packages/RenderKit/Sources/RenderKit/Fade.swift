//
//  Fade.swift
//  RenderKit
//
//  Opacity ramps for appearing decoration. `tick` ramps OpacityComponent
//  (component dropped at full light so a settled entity is on the fast
//  path); `approach` eases a painted colour and settles exactly. Both
//  snap under the SYSTEM Reduce Motion switch — no in-app duplicate.
//  `tick`'s clock lives in a component ON the entity, so pooled reuse starts clean.
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

        // THE CLOCK SURVIVES AN UNFINISHED RAMP: the first call has dt 0,
        // and deleting the clock at an endpoint means no fade ever starts.
        let now = CACurrentMediaTime()
        let dt = min(max(now - (entity.components[Clock.self]?.lastTick ?? now),
                         0), 0.1)
        entity.components.set(Clock(lastTick: now))

        let step = Float(dt / max(duration, 1e-3))
        let next = current < target
            ? min(current + step, target)
            : max(current - step, target)

        // Arrived is `next == target` exactly (the clamps return target),
        // never "next is at an endpoint" — that reads not-yet-moved as done.
        if next == target {
            entity.isEnabled = target > 0
            entity.components.remove(OpacityComponent.self)
            entity.components.remove(Clock.self)
        } else {
            // Enabled even at opacity 0: present and carrying a
            // timestamp, so the next frame has a real dt.
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
