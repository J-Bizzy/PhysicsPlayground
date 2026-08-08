//
//  SummonHandle.swift
//  Physics Playground — DesignSystem
//
//  A tab that is both the summary and the door.
//
//  THE PROBLEM IT SOLVES. `SpatialLayerBank`'s own argument for never
//  folding is correct as far as it goes: *a bank is a readout as well as
//  a control* — which layers are showing, which clock speed is running,
//  is information you need WHILE looking at the physics, and a control
//  that hides its state is not a readout. That argument holds at four
//  plates and fails at seven, where nobody reads seven lamps as a state;
//  they read a wall of switches. Gravity Lab stands sixteen objects in
//  the room and the owner's verdict on 2026-08-07 was "way too
//  cluttered".
//
//  A plain fold does not answer it, because a plain fold takes the
//  readout away with the control. THIS does: the tab keeps a live
//  one-line `summary` of whatever it hides. "Clock · 5×" is the same
//  fact the six-disc fan was carrying, in one object instead of six, and
//  pinching it unfolds the fan to change it. Fold and readout at once.
//
//  WHAT IT IS NOT. It is not for a control you need CONTINUOUSLY: a
//  quantity you drag while watching the result stays a rail, and a
//  destructive verb stays a plate you can see. It is for the things a
//  room accumulates — a second row of analysis overlays, a ten-preset
//  fan, a clock you set once and read often.
//
//  It wears the action bank's machined stock rather than the layer
//  bank's frosted glass, because it is a DOOR — a thing you press to
//  make something happen — and the two banks' material split ("a verb
//  and a state must not be the same object in two colours") makes that
//  distinction the app's own. Its geometry is `PlateStyle`, so it is
//  visibly the same family as the plates it hides.
//

import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class SummonHandle {
    let root = Entity()

    /// The tab's own name, e.g. "Clock" or "Analysis".
    private let title: String
    private let accent: UIColor

    /// The live one-line state of whatever this hides — the half that
    /// makes folding legitimate. Read every frame, like every other
    /// readout in this app; a stored string would go stale the moment
    /// the model moved underneath it.
    var summary: (() -> String)?

    /// Whether what it summons is currently unfolded.
    private(set) var isOpen = false

    /// Called when the tab is pressed, with the new state.
    var onToggle: ((Bool) -> Void)?

    private let tab = ModelEntity()
    private var titleLabel: Entity?
    private var summaryLabel: Entity?
    private var lastSummary: String?
    private var reveal: Float = 0

    /// The whole tab, for a carrier that needs to lay this out without
    /// collisions. Includes the labels, which is the point — a footprint
    /// that measures only the slab is how labels come to straddle their
    /// neighbours.
    var footprint: BoundingBox { root.visualBounds(relativeTo: root) }

    init(title: String, symbol: String, accent: UIColor) {
        self.title = title
        self.accent = accent
        root.isEnabled = false
        buildTab(symbol: symbol)
    }

    // MARK: Per frame

    /// `nearestHand` drives recession — see `Recession`. Nothing ticks
    /// itself; the carrier calls this.
    func update(anchor: SIMD3<Float>, viewer: SIMD3<Float>?, dt: Double,
                nearestHand: SIMD3<Float>? = nil) {
        reveal = Motion.ease(reveal, toward: 1, dt: dt)
        root.isEnabled = reveal > 0.02
        guard root.isEnabled else { return }
        root.position = anchor
        if let viewer, let facing = yaw(facing: viewer, from: anchor) {
            root.orientation = facing
        }

        // The summary is a READOUT, so it is repainted only when the
        // string actually changes — the same discipline every bank and
        // callout in this app keeps, because regenerating a text mesh
        // per frame is the classic way to tank a scene.
        let text = summary?() ?? ""
        if text != lastSummary {
            lastSummary = text
            summaryLabel?.removeFromParent()
            guard !text.isEmpty else { summaryLabel = nil; return }
            let plate = HubScene.namePlate(text, accent: accent,
                                           size: PlateStyle.labelSize)
            plate.position = [0, -PlateStyle.height / 2 - PlateStyle.labelGap
                                 - Float(PlateStyle.labelSize), PlateStyle.faceLift]
            root.addChild(plate)
            summaryLabel = plate
        }

        // ANCHOR IN WORLD SPACE, NOT THE ARGUMENT. `anchor` is expressed
        // in the parent's frame — labs place their apparatus under a root
        // carrying a placement offset, and Gravity Lab's carries a scale
        // too — while a fingertip from `RoomModel` is world space.
        // Comparing the two directly measures a distance that does not
        // exist. `root.position(relativeTo: nil)` is the same point in
        // the frame the hand is already in.
        Recession.apply(to: root, anchor: root.position(relativeTo: nil),
                        nearestHand: nearestHand)
    }

    // MARK: Tap

    /// Returns true if this handle consumed the tap.
    func handleTap(_ entity: Entity) -> Bool {
        guard entity === tab || entity.isDescendant(of: tab) || entity === root
                || entity.isDescendant(of: root) else { return false }
        isOpen.toggle()
        // Open keeps the pop; close answers with the gentler tick, so the
        // pair reads as unfold/fold rather than as two unfolds — the
        // rule `SoundPalette.releaseTick` was added for.
        SoundPalette.play(isOpen ? .pop : .releaseTick, on: tab, volume: 0.4)
        applyLook()
        onToggle?(isOpen)
        return true
    }

    /// Folds it without a tap — a reset, or another handle opening.
    func close() {
        guard isOpen else { return }
        isOpen = false
        applyLook()
        onToggle?(false)
    }

    // MARK: Build

    private func buildTab(symbol: String) {
        tab.name = "summon-\(title.lowercased())"
        tab.model = ModelComponent(
            mesh: .generateBox(width: PlateStyle.width,
                               height: PlateStyle.height,
                               depth: PlateStyle.depth,
                               cornerRadius: PlateStyle.corner),
            materials: [Materials.machined(UIColor(white: 0.30, alpha: 1))])
        root.addChild(tab)

        if let texture = Bloom.symbolTexture(symbol) {
            var material = UnlitMaterial()
            material.color = .init(tint: accent, texture: .init(texture))
            let icon = ModelEntity(
                mesh: .generatePlane(width: 0.016, height: 0.016),
                materials: [material])
            icon.position = [-PlateStyle.width / 2 + 0.016, 0, PlateStyle.faceLift]
            tab.addChild(icon)
        }

        let name = HubScene.namePlate(title, accent: UIColor(white: 0.95, alpha: 1),
                                      size: PlateStyle.labelSize)
        name.position = [0.010, 0, PlateStyle.faceLift]
        tab.addChild(name)
        titleLabel = name

        // THE LABEL IS PART OF THE TARGET. Bank and picker labels are
        // placed outside their plate and carry no collider, so the word
        // itself is a hole you can pinch through — `DESIGN_SYSTEM.md`'s
        // own complaint. This one is a second box over the label extent.
        let span = HubScene.namePlateWidth(title, size: PlateStyle.labelSize)
        tab.components.set(InputTargetComponent())
        tab.components.set(CollisionComponent(shapes: [
            .generateBox(width: max(PlateStyle.width, span + 0.020),
                         height: PlateStyle.height + 0.014,
                         depth: PlateStyle.depth + 0.014),
        ]))
        tab.components.set(HoverEffectComponent())

        applyLook()
    }

    private func applyLook() {
        // Open reads as pressed-in and lit; closed as raised stock. The
        // accent only appears when something is unfolded, so a room of
        // closed handles is quiet.
        tab.model?.materials = [
            isOpen
                ? Materials.energized(accent, glow: 0.35)
                : Materials.machined(UIColor(white: 0.30, alpha: 1)),
        ]
        tab.position.z = isOpen ? -0.002 : 0
        // RE-PUBLISHED ON EVERY CHANGE, and wired to the same toggle the
        // pinch takes.
        //
        // This declared `.activate` and had nothing behind it for its
        // first hour — advertising an action it could not perform, which
        // is worse than declaring none. `SpatialActionCriterionTests`
        // caught it on its own first run, which is the argument for
        // asserting "hit-testable and announced implies operable"
        // rather than "declares systemActions".
        SpatialActions.attach(
            to: tab, label: title,
            value: isOpen ? "showing" : "hidden",
            activate: { [weak self] in _ = self?.handleTap(self?.tab ?? Entity()) })
    }
}
