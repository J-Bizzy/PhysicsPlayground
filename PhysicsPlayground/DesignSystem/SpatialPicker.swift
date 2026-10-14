//
//  SpatialPicker.swift
//  Physics Playground — Design System
//
//  The app's only N-way picker: pinch a petal, a fan of the family's
//  toggles unfolds in the room — the current choice reads as selected —
//  pick one, it folds. Geometry is shared in `RenderKit.FanLayout`, where
//  it is tested; the fan widens itself until no two choices touch.
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
    /// The narrowest a choice's footprint is allowed to be in a fan, and
    /// the number `FanLayout`'s tests space discs by.
    static let colliderSpan: Float = 0.068

    let root = Entity()
    private(set) var isOpen = false
    /// Called with the chosen `PickerChoice.id`.
    var onSelect: ((String) -> Void)?

    /// Which choice is current, read every frame — a closure, not a stored
    /// id, so the model stays the truth and a reset moves the lit choice.
    var selectedID: (() -> String?)?

    private let requestedLayout: FanLayout
    private var layout: FanLayout
    /// A permanent switch bank rather than a menu: it starts open and
    /// choosing does not fold it away. For a small set changed often whose
    /// current value must stay visible (Orbital Mechanics' clock speed).
    private let staysOpen: Bool
    private var openness: Double = 0

    private struct Disc {
        let id: String
        let label: String
        let entity: Entity
        let control: RoomControl
    }
    private var discs: [Disc] = []

    /// `accessibilityNoun` and `accent` are kept for callers; the choice's
    /// own name is what VoiceOver reads, and selection is the system's
    /// selected platter.
    init(accessibilityNoun: String,
         choices: [PickerChoice] = [],
         staysOpen: Bool = false,
         accent: UIColor = .white,
         layout: FanLayout = FanLayout()) {
        self.requestedLayout = layout
        self.layout = layout
        self.staysOpen = staysOpen
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
            let (entity, control) = makeDisc(choice)
            root.addChild(entity)
            discs.append(Disc(id: choice.id, label: choice.label,
                              entity: entity, control: control))
        }
        // As wide as the widest choice needs, never narrower than asked.
        let itemSpan = Double(max(
            2 * RoomControlFootprint.halfWidth(forLongestOf: choices.map(\.label)),
            Self.colliderSpan))
        let spread = FanLayout.spread(
            count: choices.count, itemSpan: itemSpan,
            reach: requestedLayout.reach,
            verticalScale: requestedLayout.verticalScale,
            lift: requestedLayout.lift, stagger: requestedLayout.stagger,
            clearance: 0.08,
            maxSpan: max(requestedLayout.span, 150 * .pi / 180))
        layout = spread.span < requestedLayout.span && spread.reach <= requestedLayout.reach
            ? requestedLayout : spread
        isOpen = staysOpen
        openness = staysOpen ? 1 : 0
        root.isEnabled = staysOpen && !choices.isEmpty
    }

    var isEmpty: Bool { discs.isEmpty }

    /// What the choice `id` is showing — for tests, which cannot read the
    /// glass.
    func control(for id: String) -> RoomControl? {
        discs.first { $0.id == id }?.control
    }

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
        // it would tip its choices edge-on to the room.
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
            disc.control.setOn(selectedID != nil && disc.id == current)
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
                choose(match.id, on: candidate)
                return true
            }
            if candidate === root { return false }
            current = candidate.parent
        }
        return false
    }

    private func choose(_ id: String, on entity: Entity) {
        onSelect?(id)
        SoundPalette.play(.chime, on: entity, volume: 0.5)
        if !staysOpen { isOpen = false }
    }

    private func makeDisc(_ choice: PickerChoice) -> (Entity, RoomControl) {
        let control = RoomControl(title: choice.label,
                                  systemImage: choice.symbol ?? "circle")
        // Found again by id when pressed: the view's closure must not hold
        // the entity that holds the view.
        let entity = ControlAttachment.control(
            control, kind: .toggle(iconOnly: false),
            name: "picker-\(choice.id)",
            press: { [weak self] in
                guard let self, self.root.isEnabled,
                      let disc = self.discs.first(where: { $0.id == choice.id })
                else { return }
                self.choose(disc.id, on: disc.entity)
            })
        entity.isEnabled = false
        return (entity, control)
    }
}
