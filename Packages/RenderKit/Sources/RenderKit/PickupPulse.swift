//
//  PickupPulse.swift
//  RenderKit
//
//  The grab acknowledgement: a brief soft glow around a body the hand
//  has just taken, gone in a quarter second.
//
//  Light, not geometry — a scale pop was considered and rejected in the
//  same decision (2026-08-05): the app's standing rule is that emphasis
//  is opacity, light and sound, and a body that changes size in the
//  hand is a body lying about its size. The glow is an aura entity
//  rather than a material edit because the grabbables wear every
//  material in the canon (textured planets, machined bobs, energized
//  charges) and a pulse that needed to understand each recipe would be
//  adopted by half of them — the VectorFieldArrows/contrastLine lesson.
//
//  Self-driving and self-removing: the fade rides RealityKit's own
//  animation system, and the aura removes itself when done, so a
//  renderer fires it and forgets it. Suppressed entirely under the
//  system Reduce Motion switch.
//

import RealityKit
import UIKit

@MainActor
public enum PickupPulse {
    /// One flash around `entity`, sized to what it looks like.
    public static func flash(on entity: Entity, tint: UIColor = .white) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let bounds = entity.visualBounds(relativeTo: entity)
        let radius = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            * 0.72 + 0.008
        guard radius.isFinite, radius > 0.008 else { return }

        var material = UnlitMaterial(color: tint)
        material.blending = .transparent(opacity: 0.32)
        let aura = ModelEntity(mesh: .generateSphere(radius: radius),
                               materials: [material])
        aura.position = bounds.center
        // Decoration, never a target — no collider is ever added, and
        // the aura must not inherit hover from its parent's components.
        entity.addChild(aura)

        aura.components.set(OpacityComponent(opacity: 1))
        let fade = FromToByAnimation<Float>(
            from: 1, to: 0, duration: 0.25,
            timing: .easeOut, bindTarget: .opacity)
        if let resource = try? AnimationResource.generate(with: fade) {
            aura.playAnimation(resource)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            aura.removeFromParent()
        }
    }
}
