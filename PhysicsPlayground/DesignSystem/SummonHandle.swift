//
//  SummonHandle.swift
//  Physics Playground — DesignSystem
//
//  A tab that is both the summary and the door: it keeps a live one-line
//  `summary` of whatever it hides, and a pinch unfolds that. For the
//  things a room accumulates — a second row of overlays, a ten-preset
//  fan, a clock set once and read often — never for a control used
//  continuously or a destructive verb. It wears the action bank's
//  machined stock, because it is a door, at `PlateStyle` geometry.
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

    /// The live one-line state of whatever this hides, read every frame
    /// like every other readout.
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

    /// The whole tab, labels included, for a carrier laying it out clear of
    /// its neighbours.
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

        // The summary is a readout: repainted only when the string changes,
        // since a text mesh per frame tanks a scene.
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

        // Anchor in world space, not the argument: `anchor` is in the parent's
        // (possibly scaled) frame while a fingertip is world space.
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

    /// Unfolds or folds it without a tap — for the debug launch arguments
    /// and for tests, which have no hands either.
    func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        applyLook()
        onToggle?(open)
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
            mesh: Primitives.box(width: PlateStyle.width,
                               height: PlateStyle.height,
                               depth: PlateStyle.depth,
                               cornerRadius: PlateStyle.corner),
            materials: [Materials.machined(UIColor(white: 0.30, alpha: 1))])
        root.addChild(tab)

        if let texture = Bloom.symbolTexture(symbol) {
            var material = UnlitMaterial()
            material.color = .init(tint: accent, texture: .init(texture))
            let icon = ModelEntity(
                mesh: Primitives.plane(width: 0.016, height: 0.016),
                materials: [material])
            icon.position = [-PlateStyle.width / 2 + 0.016, 0, PlateStyle.faceLift]
            tab.addChild(icon)
        }

        let name = HubScene.namePlate(title, accent: UIColor(white: 0.95, alpha: 1),
                                      size: PlateStyle.labelSize)
        name.position = [0.010, 0, PlateStyle.faceLift]
        tab.addChild(name)
        titleLabel = name

        // The label is part of the target: a second box over the label extent,
        // or the word is a hole you can pinch through.
        let span = HubScene.namePlateWidth(title, size: PlateStyle.labelSize)
        tab.components.set(InputTargetComponent())
        tab.components.set(CollisionComponent(shapes: [
            Primitives.collisionBox(width: max(PlateStyle.width, span + 0.020),
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
        // Re-published on every change, and wired to the same toggle the pinch
        // takes.
        SpatialActions.attach(
            to: tab, label: title,
            value: isOpen ? "showing" : "hidden",
            activate: { [weak self] in _ = self?.handleTap(self?.tab ?? Entity()) })
    }
}
