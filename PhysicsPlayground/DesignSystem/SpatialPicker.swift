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
//  the room. Every `Picker` that was ever in a window panel is one of
//  these now — the last of them on 2026-08-01, when the panels
//  themselves were deleted and `makeControls` went with them.
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
    /// The lateral span of one disc's TOUCH TARGET, and therefore the
    /// number a fan has to space its discs by.
    ///
    /// The disc's face is 0.052 m across; the target is deliberately
    /// wider, because a fan is something you reach for. Two discs
    /// closer together than this cannot be aimed at separately, no
    /// matter how clearly they read — which is exactly what happened
    /// when Gravity Lab's clock grew from four scales to six and
    /// `FanLayoutTests` checked the clearance against the 0.052 m FACE
    /// instead. Named here so the layout and its test can never again
    /// disagree with the collider about how big a disc is.
    static let colliderSpan: Float = 0.068

    let root = Entity()
    private(set) var isOpen = false
    /// Called with the chosen `PickerChoice.id`.
    var onSelect: ((String) -> Void)?

    /// Which choice is current, read every frame.
    ///
    /// Without this a standing picker renders N identical discs and shows
    /// **nothing** about the value it is picking — which flatly contradicts
    /// the doc comment below claiming a standing bank exists so you can
    /// "SEE the current value of" a setting, and fails the replacement
    /// standard's "visible without being looked for". A control that cannot
    /// be read is not a readout; it is a row of buttons.
    ///
    /// A closure rather than a stored id, for the same reason
    /// `SpatialLayerBank.Layer.isOn` is one: the model is the truth, and a
    /// reset or a launch argument must move the lit disc without anybody
    /// remembering to tell the picker.
    var selectedID: (() -> String?)?

    /// Spoken before each choice's label, so a fan of shapes and a fan of
    /// materials don't both just announce "Cube".
    private let accessibilityNoun: String
    private let layout: FanLayout
    /// A permanent switch bank rather than a menu: it starts open, and
    /// choosing does not fold it away.
    ///
    /// Both shapes are legitimate and the law tells them apart. A momentary
    /// fan suits a choice you make occasionally from many options — nine
    /// drag bodies, four balls — where showing them all permanently would
    /// be clutter. A standing bank suits a small set you change often and
    /// need to SEE the current value of, which the anti-regression standard
    /// requires be "visible without being looked for": Gravity Lab's clock
    /// speed is the difference between an orbit you can watch and one you
    /// cannot, so hiding it behind a pinch would be hiding the module.
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
        var dim = UnlitMaterial(color: UIColor(white: 0.30, alpha: 1))
        dim.blending = .transparent(opacity: 0.55)
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
    func update(anchor: SIMD3<Float>, viewer: SIMD3<Float>?, dt: Double) {
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

            // Repaint only on change. `update` runs every frame, and a
            // material write per disc per frame is exactly the defect this
            // codebase has been sweeping out of its renderers.
            guard selectedID != nil else { continue }
            let selected = disc.id == current
            if disc.wasSelected != selected {
                discs[index].wasSelected = selected
                disc.rim.model?.materials = [selected ? litRim : dimRim]
                // REPUBLISH RATHER THAN REBUILD: a fresh component here
                // would carry empty `systemActions` and silently strip
                // Activate from whichever disc was just chosen — the
                // selected one, i.e. the one most likely to be visited
                // next.
                SpatialActions.republish(
                    value: selected ? "selected" : "not selected", on: disc.entity)
            }
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
            mesh: .generateCylinder(height: 0.005, radius: 0.026),
            materials: [Materials.frostedGlass()])
        disc.name = "picker-\(choice.id)"
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        disc.components.set(GroundingShadowComponent(castsShadow: true))

        // The glass edge, proud of the face all the way round. It sits
        // UNDER the selection ring below, which is brighter and coloured
        // — the hairline says "this is a pane", the ring says "this one
        // is chosen", and they must not be the same cue.
        let border = ModelEntity(
            mesh: .generateCylinder(height: 0.0042,
                                    radius: 0.026 + Materials.glassEdgeInset),
            materials: [Materials.glassEdge()])
        disc.addChild(border)

        // The selection ring, behind the face. Starts dim; `update` lights
        // whichever disc the model says is current.
        let rim = ModelEntity(
            mesh: .generateCylinder(height: 0.003, radius: 0.0302),
            materials: [dimRim])
        rim.position = [0, -0.002, 0]
        disc.addChild(rim)

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
        // A DISC IS FLAT, and this was a ball. The lateral 0.068 m is
        // deliberate reach over a 0.052 m face — it is also the number
        // `FanLayout` must space these by, and the one `FanLayoutTests`
        // failed to use. But the same radius applied VERTICALLY made a
        // 68 mm-thick slab out of a disc 10.5 mm thick, hanging 3 cm
        // above and below the fan over whatever the fan was drawn in
        // front of.
        disc.components.set(CollisionComponent(shapes: [
            .generateBox(size: [Self.colliderSpan, 0.038, Self.colliderSpan]),
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
