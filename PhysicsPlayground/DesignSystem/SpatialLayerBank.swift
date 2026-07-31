//
//  SpatialLayerBank.swift
//  Physics Playground — Design System
//
//  One bank of layer switches per module: the physical home for the 35
//  display toggles that were living on the window panels.
//
//  It is deliberately BOTH a control and a readout, which is why it never
//  folds. Which layers are showing is information the user needs while
//  looking at the physics — "am I seeing the pressure skin or not" is a
//  question about what is in front of you — so a bank that hid its state
//  behind a pinch would fail the standard the interaction law sets:
//  visible without being looked for, operable without being discovered
//  (DECISIONS.md, 2026-07-29).
//
//  A lit plate is on, a dark one is off. That is the whole grammar, and it
//  is the one part of this app's control vocabulary that a real instrument
//  panel already taught everyone.
//
//  State lives in the MODEL, as everything here does: each switch reads a
//  closure every frame, so a reset or an experiment flipping a layer moves
//  the plate too.
//

import RealityKit
import RenderKit
import SwiftUI

/// One layer that can be shown or hidden.
struct LayerSwitch: Identifiable {
    let id: String
    let label: String
    var symbol: String?
    /// Read every frame — the plate follows the model, not the last tap.
    let isOn: () -> Bool
    let toggle: () -> Void

    init(id: String, label: String, symbol: String? = nil,
         isOn: @escaping () -> Bool, toggle: @escaping () -> Void) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.isOn = isOn
        self.toggle = toggle
    }
}

@MainActor
final class SpatialLayerBank {
    let root = Entity()

    private let accent: UIColor
    private let layout: StackLayout
    private var reveal: Double = 0
    private var plates: [(layer: LayerSwitch, entity: ModelEntity,
                          face: ModelEntity, wasOn: Bool?)] = []

    init(accent: UIColor, layers: [LayerSwitch] = [],
         layout: StackLayout = StackLayout()) {
        self.accent = accent
        self.layout = layout
        root.isEnabled = false
        setLayers(layers)
    }

    func setLayers(_ layers: [LayerSwitch]) {
        for plate in plates { plate.entity.removeFromParent() }
        plates.removeAll()
        for layer in layers {
            let (plate, face) = makePlate(layer)
            root.addChild(plate)
            plates.append((layer, plate, face, nil))
        }
        reveal = 0
        root.isEnabled = false
    }

    var isEmpty: Bool { plates.isEmpty }

    /// Per frame: hang beside `anchor`, face the viewer, and repaint any
    /// plate whose model state changed.
    func update(anchor: SIMD3<Float>, viewer: SIMD3<Float>?, dt: Double) {
        reveal = FanLayout.ease(reveal, toward: plates.isEmpty ? 0 : 1, dt: dt)
        root.isEnabled = reveal > 0.02 && !plates.isEmpty
        guard root.isEnabled else { return }
        root.position = anchor

        // Yaw only. A bank that pitched to meet a viewer looking down on it
        // would turn its plates edge-on.
        if let viewer {
            let flat = SIMD3<Float>(viewer.x - anchor.x, 0, viewer.z - anchor.z)
            if simd_length(flat) > 1e-4 {
                root.orientation = simd_quatf(from: [0, 0, 1],
                                              to: simd_normalize(flat))
            }
        }

        for index in plates.indices {
            let placement = layout.placement(index: index, count: plates.count,
                                             reveal: reveal)
            plates[index].entity.position = SIMD3<Float>(placement.offset)
            plates[index].entity.scale = SIMD3(repeating: Float(placement.scale))
            plates[index].entity.isEnabled = placement.isVisible

            // Repaint only on change: this runs every frame for every
            // module, and rebuilding a material 90 times a second for a
            // value that changes on a tap is pure waste.
            let on = plates[index].layer.isOn()
            if plates[index].wasOn != on {
                plates[index].wasOn = on
                plates[index].face.model?.materials = [material(on: on)]
            }
        }
    }

    /// True when the tap flipped a layer.
    func handleTap(_ entity: Entity) -> Bool {
        guard root.isEnabled else { return false }
        var current: Entity? = entity
        while let candidate = current {
            if let match = plates.first(where: { $0.entity === candidate }) {
                match.layer.toggle()
                SoundPalette.play(.pop, on: candidate, volume: 0.35)
                return true
            }
            if candidate === root { return false }
            current = candidate.parent
        }
        return false
    }

    private func material(on: Bool) -> UnlitMaterial {
        var material = UnlitMaterial(color: on ? accent : UIColor(white: 0.30, alpha: 1))
        material.blending = .transparent(opacity: on ? 0.95 : 0.42)
        return material
    }

    /// The switch plate's own width. The label is placed relative to it,
    /// so the two must not be able to disagree.
    private static let plateWidth: Float = 0.086
    private static let labelSize: CGFloat = 0.0104
    private static let labelGap: Float = 0.008

    /// How far this bank's widest label reaches from a plate's centre —
    /// what a caller needs to keep the bank clear of its apparatus.
    /// `FieldInstrumentLayout` asserts against it rather than guessing.
    static func reach(forLabels labels: [String]) -> Float {
        let widest = labels
            .map { HubScene.namePlateWidth($0, size: labelSize) }
            .max() ?? 0
        return plateWidth / 2 + labelGap + widest
    }

    private func makePlate(_ layer: LayerSwitch) -> (ModelEntity, ModelEntity) {
        // The casing: a dark slab that reads as hardware whatever the
        // layer's state, so the bank keeps its shape when everything is
        // switched off.
        var casing = PhysicallyBasedMaterial()
        casing.baseColor = .init(tint: UIColor(white: 0.07, alpha: 1))
        casing.roughness = 0.32
        casing.clearcoat = .init(floatLiteral: 0.9)
        casing.blending = .transparent(opacity: .init(floatLiteral: 0.92))
        let plate = ModelEntity(
            mesh: .generateBox(size: [Self.plateWidth, 0.050, 0.007],
                               cornerRadius: 0.010),
            materials: [casing])
        plate.name = "layer-\(layer.id)"

        // The lamp: the strip that lights when the layer is on.
        let face = ModelEntity(
            mesh: .generateBox(size: [0.011, 0.034, 0.002], cornerRadius: 0.004),
            materials: [material(on: layer.isOn())])
        face.position = [-0.032, 0, 0.005]
        plate.addChild(face)

        if let symbol = layer.symbol, let texture = Bloom.symbolTexture(symbol) {
            var iconMaterial = UnlitMaterial()
            iconMaterial.color = .init(tint: .white, texture: .init(texture))
            iconMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.9))
            let icon = ModelEntity(
                mesh: .generatePlane(width: 0.024, height: 0.024),
                materials: [iconMaterial])
            icon.position = [-0.002, 0, 0.005]
            plate.addChild(icon)
        }

        // The label sits BESIDE the switch, and has to be placed by its
        // own left edge rather than by a fixed offset. `namePlate` returns
        // a pill centred on its origin, so parking that origin 0.050 out —
        // just 0.007 clear of a plate 0.086 wide — put half of every pill
        // back on top of the switch it named. "Parallel plates" straddled
        // its own icon. The label now starts where the plate ends, however
        // long the words are.
        let labelWidth = HubScene.namePlateWidth(layer.label, size: Self.labelSize)
        let label = HubScene.namePlate(layer.label,
                                       accent: UIColor(white: 0.94, alpha: 1),
                                       size: Self.labelSize)
        label.position = [Self.plateWidth / 2 + Self.labelGap + labelWidth / 2, 0, 0.005]
        plate.addChild(label)

        plate.components.set(InputTargetComponent())
        // Collider matched to the plate, per the collider-≤-visual rule —
        // an oversized one would shield the apparatus the bank hangs beside.
        plate.components.set(CollisionComponent(
            shapes: [.generateBox(size: [0.092, 0.056, 0.016])]))
        plate.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: layer.label)
        accessibility.value = LocalizedStringResource(
            stringLiteral: layer.isOn() ? "showing" : "hidden")
        plate.components.set(accessibility)
        plate.isEnabled = false
        return (plate, face)
    }
}
