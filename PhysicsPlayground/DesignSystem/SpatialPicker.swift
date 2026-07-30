//
//  SpatialPicker.swift
//  Physics Playground — Design System
//
//  The app's only N-way picker: pinch a petal, a fan of labelled discs
//  unfolds in the room, pick one, it folds.
//
//  This is the Wind Tunnel's shape fan, made general. That fan was the
//  one place in the app where choosing among many things was a physical
//  act rather than a menu — and the interaction law (DECISIONS.md,
//  2026-07-29) makes it the only allowed form: a quantity without extent
//  is a discrete choice, and a discrete choice gets a labelled object in
//  the room. Every `Picker` in a window panel is due to become one of
//  these.
//
//  It sits in DesignSystem rather than RenderKit because it needs the
//  app's own vocabulary — `Bloom.symbolTexture`, `HubScene.namePlate`,
//  `SoundPalette` — the same reason `Bloom` and `Well` live here. Only the
//  geometry is shared, in `RenderKit.FanLayout`, where it is tested.
//
//  Taps resolve by entity IDENTITY, not by parsing the entity's name.
//  The fan it replaces round-tripped a name through `DragBody(rawValue:)`,
//  which silently selects nothing if an id ever contains the separator or
//  stops being a raw value.
//

import RealityKit
import RenderKit
import SwiftUI

/// One choice a picker offers.
struct PickerChoice: Identifiable, Equatable {
    /// Stable identifier handed back to `onSelect`.
    let id: String
    /// What the disc says.
    let label: String
    /// SF Symbol on the disc's face. A missing or unknown symbol just
    /// means a disc with only its label — never a crash.
    var symbol: String?

    init(id: String, label: String, symbol: String? = nil) {
        self.id = id
        self.label = label
        self.symbol = symbol
    }
}

@MainActor
final class SpatialPicker {
    let root = Entity()
    private(set) var isOpen = false
    /// Called with the chosen `PickerChoice.id`.
    var onSelect: ((String) -> Void)?

    /// Spoken before each choice's label, so a fan of shapes and a fan of
    /// materials don't both just announce "Cube".
    private let accessibilityNoun: String
    private let layout: FanLayout
    private var openness: Double = 0
    private var discs: [(id: String, entity: ModelEntity)] = []

    init(accessibilityNoun: String,
         choices: [PickerChoice] = [],
         layout: FanLayout = FanLayout()) {
        self.accessibilityNoun = accessibilityNoun
        self.layout = layout
        root.isEnabled = false
        setChoices(choices)
    }

    /// Replaces the offered choices. Safe to call as a module's available
    /// options change; the fan folds so it can't be left showing a stale
    /// set mid-unfold.
    func setChoices(_ choices: [PickerChoice]) {
        for (_, entity) in discs { entity.removeFromParent() }
        discs.removeAll()
        for choice in choices {
            let disc = makeDisc(choice)
            root.addChild(disc)
            discs.append((choice.id, disc))
        }
        isOpen = false
        openness = 0
        root.isEnabled = false
    }

    var isEmpty: Bool { discs.isEmpty }

    func toggle() { isOpen.toggle() }
    func open() { isOpen = true }
    func close() { isOpen = false }

    /// Per frame: hang over `anchor`, face the viewer, unfold or fold.
    func update(anchor: SIMD3<Float>, viewer: SIMD3<Float>?, dt: Double) {
        openness = FanLayout.ease(openness, toward: isOpen ? 1 : 0, dt: dt)
        root.isEnabled = openness > 0.02 && !discs.isEmpty
        guard root.isEnabled else { return }
        root.position = anchor

        // Yaw only — a fan that pitched to face a viewer looking down at
        // it would tip its discs edge-on to the room.
        if let viewer {
            let flat = SIMD3<Float>(viewer.x - anchor.x, 0, viewer.z - anchor.z)
            if simd_length(flat) > 1e-4 {
                root.orientation = simd_quatf(from: [0, 0, 1],
                                              to: simd_normalize(flat))
            }
        }

        for (index, disc) in discs.enumerated() {
            let placement = layout.placement(index: index, count: discs.count,
                                             openness: openness)
            disc.entity.position = SIMD3<Float>(placement.offset)
            disc.entity.scale = SIMD3(repeating: Float(placement.scale))
            disc.entity.isEnabled = placement.isVisible
        }
    }

    /// True when the tap chose something — the fan folds itself, so the
    /// caller does not have to remember to.
    func handleTap(_ entity: Entity) -> Bool {
        guard root.isEnabled else { return false }
        var current: Entity? = entity
        while let candidate = current {
            if let match = discs.first(where: { $0.entity === candidate }) {
                onSelect?(match.id)
                SoundPalette.play(.chime, on: candidate, volume: 0.5)
                isOpen = false
                return true
            }
            if candidate === root { return false }
            current = candidate.parent
        }
        return false
    }

    private func makeDisc(_ choice: PickerChoice) -> ModelEntity {
        var casing = PhysicallyBasedMaterial()
        casing.baseColor = .init(tint: UIColor(white: 0.06, alpha: 1))
        casing.roughness = 0.28
        casing.clearcoat = .init(floatLiteral: 1.0)
        casing.blending = .transparent(opacity: .init(floatLiteral: 0.92))
        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.005, radius: 0.026),
            materials: [casing])
        disc.name = "picker-\(choice.id)"
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])

        if let symbol = choice.symbol, let texture = Bloom.symbolTexture(symbol) {
            var iconMaterial = UnlitMaterial()
            iconMaterial.color = .init(tint: .white, texture: .init(texture))
            iconMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
            let icon = ModelEntity(
                mesh: .generatePlane(width: 0.028, height: 0.028),
                materials: [iconMaterial])
            icon.position = [0, 0.004, 0]
            icon.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            disc.addChild(icon)
        }

        let label = HubScene.namePlate(choice.label,
                                       accent: UIColor(white: 0.95, alpha: 1),
                                       size: 0.009)
        label.position = [0, 0.005, 0.042]
        label.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        disc.addChild(label)

        disc.components.set(InputTargetComponent())
        // Collider matched to the visual, per the collider-≤-visual rule:
        // an oversized one here would shield whatever the fan hangs over.
        disc.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: 0.034)]))
        disc.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(accessibilityNoun): \(choice.label)")
        disc.components.set(accessibility)
        disc.isEnabled = false
        return disc
    }
}
