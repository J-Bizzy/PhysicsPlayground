//
//  ControlPod.swift
//  Physics Playground — DesignSystem
//
//  The spatial control-pod system. Instead of one tall panel holding
//  every control, a module scatters small single-purpose glass cards
//  around its exhibit — a pod for the wind, a pod for the capacitor,
//  a pod for the presets. Three rules:
//
//  1. One pod, one idea — at most a handful of controls; a new
//     concern gets a new pod, never a new section.
//  2. Placed where the physics is — the wind pod floats by the fan,
//     the capacitor pod beside the plates.
//  3. The user owns the layout — every pod hangs from a grabbable
//     glass bar (park it anywhere; the card always turns to face
//     you), and the shared pods orb clears them all away.
//
//  The 2D window keeps the full stacked controls as the flat,
//  VoiceOver-friendly path; pods are the spatial primary.
//

import SwiftUI
import RealityKit
import RenderKit

/// A small single-purpose glass card: icon + title header, then the
/// few controls that belong to exactly that idea.
struct ControlPod<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    var width: CGFloat = 252
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(DesignTokens.TypeScale.label)
                .foregroundStyle(tint)
            content
        }
        .padding(14)
        .frame(width: width)
        .glassBackgroundEffect()
    }
}

/// Mounts a pod attachment in the scene: a slim grabbable glass bar
/// with the card hanging beneath a billboard pivot — movable like a
/// window, readable from anywhere.
@MainActor
enum PodMount {
    @discardableResult
    static func mount(
        _ attachment: Entity?, name: String,
        at position: SIMD3<Float>, drop: Float = 0.16,
        in parent: Entity
    ) -> Entity? {
        guard let attachment else { return nil }
        let holder = Entity()
        holder.name = "pod-\(name)"
        holder.position = position

        let pivot = Entity()
        pivot.components.set(BillboardComponent())
        holder.addChild(pivot)

        var barMaterial = PhysicallyBasedMaterial()
        barMaterial.baseColor = .init(tint: .white)
        barMaterial.roughness = 0.15
        barMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.42))
        let bar = ModelEntity(
            mesh: .generateBox(size: [0.085, 0.011, 0.011], cornerRadius: 0.0055),
            materials: [barMaterial])
        pivot.addChild(bar)

        attachment.position = [0, -drop, 0]
        pivot.addChild(attachment)

        // The grab sphere hugs the bar, well clear of the card's own
        // touch targets hanging below.
        Grabbable.configure(holder, collisionRadius: 0.05)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(name) pod. Grab the bar to park it anywhere.")
        holder.components.set(accessibility)

        parent.addChild(holder)
        return holder
    }
}
