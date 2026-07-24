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

/// A small single-purpose glass card: an accent-chipped title header
/// over a hairline rule, then the few controls that belong to exactly
/// that idea. The header reads as a labelled instrument, not a stock
/// card — the icon sits in its own tinted chip, the title carries the
/// weight, and a thin accent rule separates label from controls.
struct ControlPod<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    var width: CGFloat = 252
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)
                        .background(tint.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                // A hairline that starts in the accent and fades out — a
                // designed underline, not a full-width divider.
                LinearGradient(
                    colors: [tint.opacity(0.55), tint.opacity(0.05)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 1)
            }
            content
        }
        .padding(16)
        .frame(width: width)
        .glassBackgroundEffect(
            in: RoundedRectangle(cornerRadius: DesignTokens.Panel.cornerRadius, style: .continuous)
        )
    }
}

/// Mounts a pod attachment in the scene: a slim grabbable glass bar
/// with the card hanging beneath a billboard pivot — movable like a
/// window, readable from anywhere.
@MainActor
enum PodMount {
    /// The root every module hangs its pods from, named so parked
    /// positions persist per module ("the user owns the layout" —
    /// including across sessions).
    static func makeRoot(module: String) -> Entity {
        let root = Entity()
        root.name = module
        return root
    }

    private static func layoutKey(_ module: String, _ name: String) -> String {
        "podLayout.\(module).\(name)"
    }

    /// Call once per frame with the module's pod root: any pod the
    /// hand has parked somewhere new gets its position remembered.
    private static var savedPositions: [String: SIMD3<Float>] = [:]
    static func persistIfMoved(_ root: Entity) {
        for holder in root.children {
            let key = layoutKey(root.name, holder.name)
            let position = holder.position
            if let last = savedPositions[key], simd_distance(last, position) < 0.01 {
                continue
            }
            savedPositions[key] = position
            UserDefaults.standard.set(
                [Double(position.x), Double(position.y), Double(position.z)],
                forKey: key)
        }
    }

    @discardableResult
    static func mount(
        _ attachment: Entity?, name: String,
        at position: SIMD3<Float>, drop: Float = 0.16,
        in parent: Entity
    ) -> Entity? {
        guard let attachment else { return nil }
        let holder = Entity()
        holder.name = "pod-\(name)"
        // A previously parked spot wins over the default.
        if let saved = UserDefaults.standard.array(forKey: layoutKey(parent.name, "pod-\(name)"))
            as? [Double], saved.count == 3 {
            holder.position = SIMD3(Float(saved[0]), Float(saved[1]), Float(saved[2]))
        } else {
            holder.position = position
        }
        savedPositions[layoutKey(parent.name, "pod-\(name)")] = holder.position

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
