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
                          face: ModelEntity, paint: SIMD4<Float>?)] = []

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
        if let viewer, let facing = yaw(facing: viewer, from: anchor) {
            root.orientation = facing
        }

        for index in plates.indices {
            let placement = layout.placement(index: index, count: plates.count,
                                             reveal: reveal)
            plates[index].entity.position = SIMD3<Float>(placement.offset)
            plates[index].entity.scale = SIMD3(repeating: Float(placement.scale))
            plates[index].entity.isEnabled = placement.isVisible

            // The lamp EASES between its lit and dark paint rather than
            // snapping, and still repaints only while moving: `approach`
            // returns the target exactly once settled, so a resting lamp
            // rebuilds nothing — the same 90-times-a-second discipline
            // the instant repaint kept.
            let on = plates[index].layer.isOn()
            let target = Fade.paint(on ? accent : UIColor(white: 0.30, alpha: 1),
                                    opacity: on ? 0.95 : 0.42)
            let painted = plates[index].paint
            let next = painted.map { Fade.approach($0, toward: target, dt: dt) }
                ?? target
            if next != painted {
                plates[index].paint = next
                plates[index].face.model?.materials = [Fade.unlit(next)]
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

    /// Plate geometry comes from `PlateStyle` — one silhouette for both
    /// banks; the lozenge derivation and the drift story live there.
    /// The label is placed relative to the width, so the two must not
    /// be able to disagree.
    private static let plateWidth = PlateStyle.width
    private static let plateHeight = PlateStyle.height
    private static let plateCorner = PlateStyle.corner
    private static let labelSize = PlateStyle.labelSize
    private static let labelGap = PlateStyle.labelGap

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
        // A pane of frosted glass, dark enough to hold its shape against
        // a lit wall — the plate still reads as one object when every
        // layer on it is switched off.
        let plate = ModelEntity(
            mesh: .generateBox(size: [Self.plateWidth, Self.plateHeight,
                                      PlateStyle.depth],
                               cornerRadius: Self.plateCorner),
            materials: [Materials.frostedGlass()])
        plate.name = "layer-\(layer.id)"
        // The contact shadow every grabbable already casts, so a floating
        // plate reads as present in the room rather than pasted onto it.
        plate.components.set(GroundingShadowComponent(castsShadow: true))

        // The edge hairline: a slightly larger pane behind this one, so
        // its border shows all the way round. This is the part that
        // makes the pane read as glass rather than as a dark tile.
        //
        // Its radius takes the SAME inset the box does, or the two
        // outlines stop being concentric: grow a rounded rectangle by a
        // constant on every side and its corner radius grows by exactly
        // that constant too. Add the inset to the size and not to the
        // radius and the border pinches in at the corners while bulging
        // along the flats, which reads as a bad drop shadow rather than
        // as an edge.
        let edge = Materials.glassEdgeInset
        let border = ModelEntity(
            mesh: .generateBox(
                size: [Self.plateWidth + edge * 2,
                       Self.plateHeight + edge * 2, PlateStyle.edgeDepth],
                cornerRadius: Self.plateCorner + edge),
            materials: [Materials.glassEdge()])
        border.position = [0, 0, -0.0008]
        plate.addChild(border)

        // The lamp: the strip that lights when the layer is on.
        let face = ModelEntity(
            mesh: .generateBox(size: [0.011, 0.034, 0.002], cornerRadius: 0.004),
            materials: [material(on: layer.isOn())])
        face.position = [-0.032, 0, PlateStyle.faceLift]
        plate.addChild(face)

        if let symbol = layer.symbol, let texture = Bloom.symbolTexture(symbol) {
            var iconMaterial = UnlitMaterial()
            iconMaterial.color = .init(tint: .white, texture: .init(texture))
            iconMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.9))
            let icon = ModelEntity(
                mesh: .generatePlane(width: 0.024, height: 0.024),
                materials: [iconMaterial])
            icon.position = [-0.002, 0, PlateStyle.faceLift]
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
