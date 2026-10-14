//
//  SpatialLayerBank.swift
//  Physics Playground — Design System
//
//  One bank of layer switches per module. Deliberately both control and
//  readout, so it never folds: a lit plate is on, a dark one is off.
//  State lives in the model — each switch reads a closure every frame, so
//  a reset or an experiment flipping a layer moves the plate too.
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
                          face: ModelEntity, paint: SIMD4<Float>?,
                          spokenOn: Bool?)] = []

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
            plates.append((layer, plate, face, nil, nil))
        }
        reveal = 0
        root.isEnabled = false
    }

    var isEmpty: Bool { plates.isEmpty }

    /// Per frame: hang beside `anchor`, face the viewer, repaint changed
    /// plates. `nearestHand` drives recession — a readout recedes to 0.45
    /// rather than disappearing, so the state stays legible across the room.
    func update(anchor: SIMD3<Float>, viewer: SIMD3<Float>?, dt: Double,
                nearestHand: SIMD3<Float>? = nil) {
        reveal = Motion.ease(reveal, toward: plates.isEmpty ? 0 : 1, dt: dt)
        root.isEnabled = reveal > 0.02 && !plates.isEmpty
        guard root.isEnabled else { return }
        root.position = anchor

        // Yaw only — pitching would turn the plates edge-on.
        if let viewer, let facing = yaw(facing: viewer, from: anchor) {
            root.orientation = facing
        }

        for index in plates.indices {
            let placement = layout.placement(index: index, count: plates.count,
                                             reveal: reveal)
            plates[index].entity.position = SIMD3<Float>(placement.offset)
            plates[index].entity.scale = SIMD3(repeating: Float(placement.scale))
            plates[index].entity.isEnabled = placement.isVisible

            // The lamp eases yet repaints only while moving — `approach`
            // returns the target once settled, so a resting lamp rebuilds
            // nothing.
            let on = plates[index].layer.isOn()
            // The spoken value follows the lamp — republished on change,
            // or VoiceOver reads the launch state forever.
            if plates[index].spokenOn != on {
                plates[index].spokenOn = on
                SpatialActions.republish(value: on ? "showing" : "hidden",
                                         on: plates[index].entity)
            }
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

        // Anchor in world space: `anchor` is in the parent's (possibly
        // scaled) frame while the hand is world space — `position(relativeTo: nil)`
        // puts both in the same frame.
        Recession.apply(to: root, anchor: root.position(relativeTo: nil),
                        nearestHand: nearestHand)
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
        let material = Materials.unlit(on ? accent : UIColor(white: 0.30, alpha: 1), opacity: on ? 0.95 : 0.42)
        return material
    }

    /// Geometry from `PlateStyle` — one silhouette for both banks. The
    /// label is placed relative to the width, so the two cannot disagree.
    private static let plateWidth = PlateStyle.width
    private static let plateHeight = PlateStyle.height
    private static let plateCorner = PlateStyle.corner
    private static let labelSize = PlateStyle.labelSize
    private static let labelGap = PlateStyle.labelGap

    /// How far the widest label reaches from a plate's centre — for keeping
    /// the bank clear of the apparatus; `FieldInstrumentLayout` asserts on it.
    static func reach(forLabels labels: [String]) -> Float {
        let widest = labels
            .map { HubScene.namePlateWidth($0, size: labelSize) }
            .max() ?? 0
        return plateWidth / 2 + labelGap + widest
    }

    private func makePlate(_ layer: LayerSwitch) -> (ModelEntity, ModelEntity) {
        let labelSpan = HubScene.namePlateWidth(layer.label, size: Self.labelSize)
        // Frosted glass, dark enough to hold its shape against a lit wall.
        let plate = ModelEntity(
            mesh: Primitives.box(size: [Self.plateWidth, Self.plateHeight,
                                      PlateStyle.depth],
                               cornerRadius: Self.plateCorner),
            materials: [Materials.frostedGlass()])
        plate.name = "layer-\(layer.id)"
        plate.components.set(GroundingShadowComponent(castsShadow: true))

        // The edge hairline: a slightly larger pane behind this one. Its
        // radius takes the same inset the box does, or the two outlines
        // stop being concentric and the border pinches at the corners.
        let edge = Materials.glassEdgeInset
        let border = ModelEntity(
            mesh: Primitives.box(
                size: [Self.plateWidth + edge * 2,
                       Self.plateHeight + edge * 2, PlateStyle.edgeDepth],
                cornerRadius: Self.plateCorner + edge),
            materials: [Materials.glassEdge()])
        border.position = [0, 0, -0.0008]
        plate.addChild(border)

        // The lamp: the strip that lights when the layer is on.
        let face = ModelEntity(
            mesh: Primitives.box(size: [0.011, 0.034, 0.002], cornerRadius: 0.004),
            materials: [material(on: layer.isOn())])
        face.position = [-0.032, 0, PlateStyle.faceLift]
        plate.addChild(face)

        if let symbol = layer.symbol, let texture = Bloom.symbolTexture(symbol) {
            var iconMaterial = UnlitMaterial()
            iconMaterial.color = .init(tint: .white, texture: .init(texture))
            iconMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.9))
            let icon = ModelEntity(
                mesh: Primitives.plane(width: 0.024, height: 0.024),
                materials: [iconMaterial])
            icon.position = [-0.002, 0, PlateStyle.faceLift]
            plate.addChild(icon)
        }

        // The label sits beside the switch, placed by its own left edge —
        // `namePlate` returns a pill centred on its origin, so a fixed
        // offset put half of every pill back on top of the switch.
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
            shapes: [
                Primitives.collisionBox(size: [0.092, 0.056, 0.016]),
                // The label is a pinch-through hole without its own box —
                // the pill sits `labelGap` past the plate's edge.
                Primitives.collisionBox(size: [labelSpan + 0.010,
                                    Self.plateHeight * 0.8, 0.016], offset: [
                        Self.plateWidth / 2 + Self.labelGap + labelSpan / 2, 0, 0,
                    ]),
            ]))
        plate.components.set(HoverEffectComponent())
        SpatialActions.attach(
            to: plate, label: layer.label,
            value: layer.isOn() ? "showing" : "hidden",
            activate: { [weak plate] in
                layer.toggle()
                if let plate { SoundPalette.play(.pop, on: plate, volume: 0.35) }
            })
        plate.isEnabled = false
        return (plate, face)
    }
}
