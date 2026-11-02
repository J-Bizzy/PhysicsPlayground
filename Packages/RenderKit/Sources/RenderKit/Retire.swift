//
//  Retire.swift
//  RenderKit
//
//  An object leaving the room — deleted, cleared, evicted — fades and
//  shrinks a little before it goes, instead of vanishing in one frame
//  while the halo and the ring around it ease away (2026-11-02). The
//  model is the truth: by the time a renderer retires an entity the
//  object no longer exists there, so the entity is renamed (nothing may
//  find it by name again), takes no hand and no VoiceOver focus, and is
//  removed once it has faded.
//

import RealityKit

@MainActor
public enum Retire {
    /// The house ramp for decoration, `Fade.duration`.
    public static let duration: Double = Fade.duration
    /// What a retiring entity's name ends with, so a lookup that walks the
    /// tree can tell it from a live one.
    public static let suffix = "-retiring"
    /// How small it shrinks as it fades; nothing shrinks under Reduce Motion.
    static let scale: Float = 0.85

    /// Fades `entity` out of its parent and removes it. Safe to call on an
    /// entity that has no parent (it is simply not drawn) or is already
    /// retiring.
    public static func entity(_ entity: Entity) {
        guard entity.parent != nil, !entity.name.hasSuffix(suffix) else { return }
        disarm(entity)

        let start = entity.components[OpacityComponent.self]?.opacity ?? 1
        entity.components.set(OpacityComponent(opacity: start))
        let ramp = FromToByAnimation<Float>(
            from: start, to: 0, duration: duration,
            timing: .easeIn, bindTarget: .opacity)
        if let resource = try? AnimationResource.generate(with: ramp) {
            entity.playAnimation(resource)
        }
        if !Motion.isReduced, let parent = entity.parent {
            var shrunk = entity.transform
            shrunk.scale *= scale
            entity.move(to: shrunk, relativeTo: parent, duration: duration,
                        timingFunction: .easeIn)
        }
        Task { @MainActor [weak entity] in
            try? await Task.sleep(for: .seconds(duration + 0.03))
            entity?.removeFromParent()
        }
    }

    /// For a renderer that draws from a pool, where the slot that showed
    /// the departed object is handed straight to the next: a copy of it,
    /// as it stood, fades in its place, and the slot carries on. Nothing
    /// if the slot was not drawn.
    public static func copy(of entity: Entity) {
        guard let parent = entity.parent, entity.isEnabled else { return }
        let ghost = entity.clone(recursive: true)
        parent.addChild(ghost)
        Retire.entity(ghost)
    }

    /// No hand may take it, VoiceOver must not land on it, and no lookup
    /// may find it or anything in it by name: it is gone.
    private static func disarm(_ entity: Entity) {
        if !entity.name.isEmpty, !entity.name.hasSuffix(suffix) { entity.name += suffix }
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(AccessibilityComponent.self)
        entity.components.remove(HoverEffectComponent.self)
        for child in entity.children { disarm(child) }
    }
}
