//
//  SummonHandle.swift
//  Physics Playground — DesignSystem
//
//  A tab that is both the summary and the door: it keeps a live one-line
//  `summary` of whatever it hides, and a pinch unfolds that. For the
//  things a room accumulates — a second row of overlays, a ten-preset
//  fan, a clock set once and read often — never for a control used
//  continuously or a destructive verb. It is the family's toggle — open
//  reads as the system's selected platter — with the summary on its own
//  glass beneath.
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

    /// The live one-line state of whatever this hides, read every frame
    /// like every other readout.
    var summary: (() -> String)?

    /// Whether what it summons is currently unfolded.
    private(set) var isOpen = false

    /// Called when the tab is pressed, with the new state.
    var onToggle: ((Bool) -> Void)?

    private let control: RoomControl
    private var tab = Entity()
    private var reveal: Float = 0

    /// The whole tab, summary included, for a carrier laying it out clear
    /// of its neighbours. Measured from the label's type, since the glass
    /// is drawn by SwiftUI after layout.
    var footprint: BoundingBox {
        let half = RoomControlFootprint.halfWidth(forLongestOf: [title])
        let height = RoomControlFootprint.height
        return BoundingBox(min: [-half, -height, -0.005],
                           max: [half, height / 2, 0.005])
    }

    /// `accent` is kept for callers; open is the system's selected platter.
    init(title: String, symbol: String, accent: UIColor) {
        self.title = title
        self.control = RoomControl(title: title, systemImage: symbol)
        root.isEnabled = false
        buildTab()
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

        // The summary is a readout, written only when the string changes.
        let text = summary?() ?? ""
        control.setDetail(text.isEmpty ? nil : text)
        control.setOn(isOpen)

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
        press()
        return true
    }

    private func press() {
        isOpen.toggle()
        control.setOn(isOpen)
        // Open keeps the pop; close answers with the gentler tick, so the
        // pair reads as unfold/fold rather than as two unfolds — the
        // rule `SoundPalette.releaseTick` was added for.
        SoundPalette.play(isOpen ? .pop : .releaseTick, on: tab, volume: 0.4)
        onToggle?(isOpen)
    }

    /// Unfolds or folds it without a tap — for the debug launch arguments
    /// and for tests, which have no hands either.
    func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        control.setOn(open)
        onToggle?(open)
    }

    /// Folds it without a tap — a reset, or another handle opening.
    func close() {
        guard isOpen else { return }
        isOpen = false
        control.setOn(false)
        onToggle?(false)
    }

    // MARK: Build

    private func buildTab() {
        tab = ControlAttachment.control(
            control, kind: .toggle(iconOnly: false),
            name: "summon-\(title.lowercased())",
            press: { [weak self] in self?.press() })
        root.addChild(tab)
    }
}
