//
//  LiveGlow.swift
//  RenderKit — Controls
//
//  The app's one glow, and it has one meaning: this is live. It sits
//  around whatever a hand is holding — a charge, a bob, a planet, a part
//  — and around a slider while it is being dragged, and nowhere else. One
//  hue, the app's champagne accent, so it reads as the same signal in
//  every lab. Lit state, selection and "open" are told by other means
//  (the system's selected platter, the white selection halo); none of
//  them glows.
//
//  In the room it is an aura of light, never geometry the body owns: a
//  sphere drawn from the inside only, so the body occludes its near half
//  and what shows is a soft rim around the silhouette. A body never
//  changes size in the hand.
//

import RealityKit
import SwiftUI
import UIKit

@MainActor
public enum LiveGlow {
    /// The one hue: the app's accent, champagne.
    public static let colorUI = UIColor(red: 1.0, green: 0.88, blue: 0.70, alpha: 1)
    public static let color = Color(uiColor: colorUI)

    /// The aura's entity name, so a caller (or a test) can find it.
    public static let auraName = "live-glow"

    /// How strongly the aura shows: enough to read against passthrough,
    /// not enough to hide what is held.
    static let opacity: Float = 0.30

    /// Shows or hides the glow around `entity`. Idempotent: calling it
    /// with the state the entity already has does nothing.
    public static func set(_ live: Bool, on entity: Entity) {
        let existing = entity.children.first { $0.name == auraName }
        if live {
            guard existing == nil else { return }
            guard let aura = makeAura(for: entity) else { return }
            entity.addChild(aura)
            fade(aura, from: 0, to: 1)
        } else if let existing {
            existing.name = auraName + "-leaving"
            fade(existing, from: 1, to: 0)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                existing.removeFromParent()
            }
        }
    }

    /// Whether `entity` is wearing the glow right now.
    public static func isLive(_ entity: Entity) -> Bool {
        entity.children.contains { $0.name == auraName }
    }

    private static func makeAura(for entity: Entity) -> ModelEntity? {
        let bounds = entity.visualBounds(relativeTo: entity)
        let radius = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            * 0.66 + 0.010
        guard radius.isFinite, radius > 0.010 else { return nil }
        var material = Materials.unlit(colorUI, opacity: opacity)
        // Inside faces only: the near half is culled, so the glow sits
        // behind and around the body instead of veiling it.
        material.faceCulling = .front
        let aura = ModelEntity(mesh: Primitives.sphere(radius: radius),
                               materials: [material])
        aura.name = auraName
        aura.position = bounds.center
        // Light, never a target: no collider, no input, no hover.
        return aura
    }

    private static func fade(_ aura: Entity, from: Float, to: Float) {
        guard !Motion.isReduced else {
            aura.components.set(OpacityComponent(opacity: to))
            return
        }
        aura.components.set(OpacityComponent(opacity: from))
        let ramp = FromToByAnimation<Float>(
            from: from, to: to, duration: 0.15,
            timing: .easeOut, bindTarget: .opacity)
        if let resource = try? AnimationResource.generate(with: ramp) {
            aura.playAnimation(resource)
        }
    }
}

/// Keeps the glow on exactly one thing: hand it whatever is held this
/// frame (or nil) and it moves the glow when that changes. One per
/// renderer.
@MainActor
public final class LiveGlowTracker {
    private weak var current: Entity?

    public init() {}

    /// The entity currently glowing, if any.
    public var live: Entity? { current }

    public func update(_ entity: Entity?) {
        guard entity !== current else { return }
        if let current { LiveGlow.set(false, on: current) }
        if let entity { LiveGlow.set(true, on: entity) }
        current = entity
    }
}

public extension View {
    /// The window twin of the room's aura: a soft champagne light around a
    /// control while it is live (a slider under a hand). Nothing else in
    /// a window glows.
    func liveGlow(_ isLive: Bool) -> some View {
        shadow(color: LiveGlow.color.opacity(isLive ? 0.9 : 0),
               radius: isLive ? 14 : 0)
            .animation(.easeOut(duration: 0.15), value: isLive)
    }
}
