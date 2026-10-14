//
//  SpatialPicker.swift
//  Physics Playground — Design System
//
//  The app's only N-way picker: pinch a petal, a fan of labelled discs
//  unfolds in the room, pick one, it folds. Geometry is shared in
//  `RenderKit.FanLayout`, where it is tested.
//
//  Taps resolve by entity identity, not by parsing the entity's name.
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
    /// The lateral span of one disc's touch target (wider than the 0.052 m
    /// face), and the number a fan must space its discs by — named here so
    /// `FanLayout` and its tests cannot disagree with the collider.
    static let colliderSpan: Float = 0.068

    let root = Entity()
    private(set) var isOpen = false
    /// Called with the chosen `PickerChoice.id`.
    var onSelect: ((String) -> Void)?

    /// Which choice is current, read every frame — a closure, not a stored
    /// id, so the model stays the truth and a reset moves the lit disc.
    var selectedID: (() -> String?)?

    /// Spoken before each choice's label, so a fan of shapes and a fan of
    /// materials don't both just announce "Cube".
    private let accessibilityNoun: String
    private let layout: FanLayout
    /// A permanent switch bank rather than a menu: it starts open and
    /// choosing does not fold it away. For a small set changed often whose
    /// current value must stay visible (Orbital Mechanics' clock speed).
    private let staysOpen: Bool
    private var openness: Double = 0

    private struct Disc {
        let id: String
        let label: String
        let entity: ModelEntity
        /// The ring behind the face, lit when this choice is the current
        /// one — the same device Bloom's petals use to carry meaning.
        let rim: ModelEntity
        /// Last painted state, so an unchanged fan writes no materials.
        var wasSelected: Bool?
    }
    private var discs: [Disc] = []

    private let litRim: UnlitMaterial
    private let dimRim: UnlitMaterial

    init(accessibilityNoun: String,
         choices: [PickerChoice] = [],
         staysOpen: Bool = false,
         accent: UIColor = .white,
         layout: FanLayout = FanLayout()) {
        self.accessibilityNoun = accessibilityNoun
        self.layout = layout
        self.staysOpen = staysOpen
        self.litRim = UnlitMaterial(color: accent)
        let dim = Materials.unlit(UIColor(white: 0.30, alpha: 1), opacity: 0.55)
        self.dimRim = dim
        root.isEnabled = false
        setChoices(choices)
    }

    /// Replaces the offered choices. Safe to call as a module's available
    /// options change; the fan folds so it can't be left showing a stale
    /// set mid-unfold.
    func setChoices(_ choices: [PickerChoice]) {
        for disc in discs { disc.entity.removeFromParent() }
        discs.removeAll()
        for choice in choices {
            let (disc, rim) = makeDisc(choice)
            root.addChild(disc)
            discs.append(Disc(id: choice.id, label: choice.label,
                              entity: disc, rim: rim))
        }
        isOpen = staysOpen
        openness = staysOpen ? 1 : 0
        root.isEnabled = staysOpen && !choices.isEmpty
    }

    var isEmpty: Bool { discs.isEmpty }

    func toggle() { isOpen.toggle() }
    func open() { isOpen = true }
    func close() { isOpen = false }

    /// Per frame: hang over `anchor`, face the viewer, unfold or fold.
    /// `nearestHand` drives recession — see `Recession`.
    func update(anchor: SIMD3<Float>, viewer: SIMD3<Float>?, dt: Double,
                nearestHand: SIMD3<Float>? = nil) {
        openness = Motion.ease(openness, toward: isOpen ? 1 : 0, dt: dt)
        root.isEnabled = openness > 0.02 && !discs.isEmpty
        guard root.isEnabled else { return }
        root.position = anchor

        // Yaw only — a fan that pitched to face a viewer looking down at
        // it would tip its discs edge-on to the room.
        if let viewer, let facing = yaw(facing: viewer, from: anchor) {
            root.orientation = facing
        }

        let current = selectedID?()
        for index in discs.indices {
            let placement = layout.placement(index: index, count: discs.count,
                                             openness: openness)
            let disc = discs[index]
            disc.entity.position = SIMD3<Float>(placement.offset)
            disc.entity.scale = SIMD3(repeating: Float(placement.scale))
            disc.entity.isEnabled = placement.isVisible

            // Repaint only on change — a material write per disc per frame
            // is the defect this codebase sweeps out of its renderers.
            guard selectedID != nil else { continue }
            let selected = disc.id == current
            if disc.wasSelected != selected {
                discs[index].wasSelected = selected
                disc.rim.model?.materials = [selected ? litRim : dimRim]
                // Republish rather than rebuild: a fresh component carries
                // empty systemActions and strips Activate from the disc.
                SpatialActions.republish(
                    value: selected ? "selected" : "not selected", on: disc.entity)
            }
        }

        // Anchor in world space, not the argument: `anchor` is in the
        // parent's (possibly scaled) frame while the hand is world space —
        // `position(relativeTo: nil)` puts both in the same frame.
        Recession.apply(to: root, anchor: root.position(relativeTo: nil),
                        nearestHand: nearestHand)
    }

    /// True when the tap chose something — the fan folds itself.
    func handleTap(_ entity: Entity) -> Bool {
        guard root.isEnabled else { return false }
        var current: Entity? = entity
        while let candidate = current {
            if let match = discs.first(where: { $0.entity === candidate }) {
                onSelect?(match.id)
                SoundPalette.play(.chime, on: candidate, volume: 0.5)
                if !staysOpen { isOpen = false }
                return true
            }
            if candidate === root { return false }
            current = candidate.parent
        }
        return false
    }

    private func makeDisc(_ choice: PickerChoice) -> (ModelEntity, ModelEntity) {
        let disc = ModelEntity(
            mesh: Primitives.cylinder(height: 0.005, radius: 0.026),
            materials: [Materials.frostedGlass()])
        disc.name = "picker-\(choice.id)"
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        disc.components.set(GroundingShadowComponent(castsShadow: true))

        // The glass edge, proud of the face all round. It sits under the
        // brighter coloured selection ring — the hairline and the ring must
        // not be the same cue.
        let border = ModelEntity(
            mesh: Primitives.cylinder(height: 0.0042,
                                    radius: 0.026 + Materials.glassEdgeInset),
            materials: [Materials.glassEdge()])
        disc.addChild(border)

        // The selection ring, behind the face. Starts dim; `update` lights
        // whichever disc the model says is current.
        let rim = ModelEntity(
            mesh: Primitives.cylinder(height: 0.003, radius: 0.0302),
            materials: [dimRim])
        rim.position = [0, -0.002, 0]
        disc.addChild(rim)

        if let symbol = choice.symbol, let texture = Bloom.symbolTexture(symbol) {
            var iconMaterial = UnlitMaterial()
            iconMaterial.color = .init(tint: .white, texture: .init(texture))
            iconMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
            let icon = ModelEntity(
                mesh: Primitives.plane(width: 0.028, height: 0.028),
                materials: [iconMaterial])
            icon.position = [0, 0.004, 0]
            icon.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            disc.addChild(icon)
        }

        let label = HubScene.namePlate(choice.label,
                                       accent: UIColor(white: 0.95, alpha: 1),
                                       size: PlateStyle.labelSize)
        label.position = [0, 0.005, 0.042]
        label.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        disc.addChild(label)

        disc.components.set(InputTargetComponent())
        // A disc is flat: the collider box is thin in Y so it does not
        // become a slab hanging above and below the fan. The label is part
        // Of the target (a second box), clamped to `colliderSpan` laterally
        // so a long name does not push neighbouring targets into each other.
        let labelSpan = min(HubScene.namePlateWidth(choice.label, size: PlateStyle.labelSize),
                            Self.colliderSpan)
        disc.components.set(CollisionComponent(shapes: [
            Primitives.collisionBox(size: [Self.colliderSpan, 0.038, Self.colliderSpan]),
            Primitives.collisionBox(size: [labelSpan, 0.020, 0.026], offset: [0, 0.005, 0.042]),
        ]))
        disc.components.set(HoverEffectComponent())
        SpatialActions.attach(
            to: disc, label: "\(accessibilityNoun): \(choice.label)",
            activate: { [weak self, weak disc] in
                guard let self, let disc else { return }
                _ = self.handleTap(disc)
            })
        disc.isEnabled = false
        return (disc, rim)
    }
}
