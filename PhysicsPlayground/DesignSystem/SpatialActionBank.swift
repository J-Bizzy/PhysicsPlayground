//
//  SpatialActionBank.swift
//  Physics Playground — Design System
//
//  The standing one-shot verb plate. It must not look like a layer bank —
//  a layer plate latches, an action plate is momentary — so it is machined
//  stock, not glass, and flashes its accent on fire rather than staying
//  lit. Destructive actions take `confirms: true`: first tap arms ("Tap
//  again"), a timer disarms, second tap fires. `disarm()` exists so a
//  reset can clear an armed plate.
//

import RealityKit
import RenderKit
import SwiftUI

/// One thing the user can do, once, by pressing a plate.
struct SpatialAction: Identifiable {
    let id: String
    let label: String
    var symbol: String?
    /// Read every frame — a plate for an action that cannot currently
    /// happen goes dim and stops accepting taps.
    var isAvailable: () -> Bool = { true }
    /// Destructive: arm on the first tap, fire on the second.
    var confirms: Bool = false
    let fire: () -> Void

    init(id: String, label: String, symbol: String? = nil,
         isAvailable: @escaping () -> Bool = { true },
         confirms: Bool = false,
         fire: @escaping () -> Void) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.isAvailable = isAvailable
        self.confirms = confirms
        self.fire = fire
    }
}

@MainActor
final class SpatialActionBank {
    let root = Entity()

    /// How long an armed plate stays armed. Long enough to read the
    /// nameplate and decide, short enough that walking away disarms it.
    static let armWindow: Double = ControlMetrics.armWindow

    private let layout: StackLayout
    private var reveal: Double = 0

    private struct Plate {
        let action: SpatialAction
        let entity: Entity
        let control: RoomControl
    }

    private var plates: [Plate] = []

    /// Which plate is armed, and how long it has left. Nil when none is.
    private var armed: (id: String, remaining: Double)?

    /// `accent` is kept for callers; a verb is the family's button, and
    /// a destructive one goes red while armed.
    init(accent: UIColor, actions: [SpatialAction] = [],
         layout: StackLayout = StackLayout()) {
        self.layout = layout
        root.isEnabled = false
        setActions(actions)
    }

    func setActions(_ actions: [SpatialAction]) {
        for plate in plates { plate.entity.removeFromParent() }
        plates.removeAll()
        armed = nil
        for action in actions {
            plates.append(makePlate(action))
            root.addChild(plates[plates.count - 1].entity)
        }
        reveal = 0
        root.isEnabled = false
    }

    var isEmpty: Bool { plates.isEmpty }

    /// Whether `id` is currently armed.
    func isArmed(_ id: String) -> Bool { armed?.id == id }

    /// What the plate for `id` is showing — for tests, which cannot read
    /// the glass.
    func control(for id: String) -> RoomControl? {
        plates.first { $0.action.id == id }?.control
    }

    /// Clear any armed plate.
    func disarm() {
        armed = nil
    }

    /// Put a plate into its armed state without a tap — for the debug
    /// launch arguments only; sets the same state the first tap sets.
    /// `holds` defeats the arm timer so a screenshot landing after the
    /// four-second window still shows the armed state.
    func arm(_ id: String, holds: Bool = false) {
        guard plates.contains(where: { $0.action.id == id && $0.action.confirms })
        else { return }
        armed = (id: id, remaining: holds ? .infinity : Self.armWindow)
    }

    /// The last `resetNonce` this bank saw. Starts at nil so the first
    /// frame adopts whatever the app is on rather than firing a disarm.
    private var seenResetNonce: Int?

    /// Per frame: hang beside `anchor`, face the viewer, run the arm timer,
    /// write only what changed. On a `resetNonce` change the bank disarms
    /// itself — armed state lives here, not in the model. `nearestHand`
    /// drives recession.
    func update(anchor: SIMD3<Float>, viewer: SIMD3<Float>?, dt: Double,
                resetNonce: Int = 0, nearestHand: SIMD3<Float>? = nil) {
        if let seen = seenResetNonce, seen != resetNonce { disarm() }
        seenResetNonce = resetNonce
        reveal = Motion.ease(reveal, toward: plates.isEmpty ? 0 : 1, dt: dt)
        root.isEnabled = reveal > 0.02 && !plates.isEmpty
        guard root.isEnabled else { return }
        root.position = anchor

        // Yaw only — pitching to meet a viewer looking down would turn
        // the plates edge-on.
        if let viewer, let facing = yaw(facing: viewer, from: anchor) {
            root.orientation = facing
        }

        // The arm window runs down in real time.
        if var current = armed {
            current.remaining -= dt
            armed = current.remaining <= 0 ? nil : current
        }

        for index in plates.indices {
            let placement = layout.placement(index: index, count: plates.count,
                                             reveal: reveal)
            // Left-aligned on the column: the control's leading edge stands
            // where a plate's did, so a long name runs away from the apparatus.
            plates[index].entity.position = SIMD3<Float>(placement.offset)
                + SIMD3(Self.leadingInset(for: plates[index].action.label), 0, 0)
            plates[index].entity.scale = SIMD3(repeating: Float(placement.scale))
            plates[index].entity.isEnabled = placement.isVisible
            plates[index].control.setArmed(armed?.id == plates[index].action.id)
            plates[index].control.setEnabled(plates[index].action.isAvailable())
        }

        // Anchor in world space: `anchor` is in the parent's (possibly
        // scaled) frame while the hand is world space — `position(relativeTo: nil)`
        // puts both in the same frame.
        guard recedes else { return }
        Recession.apply(to: root, anchor: root.position(relativeTo: nil),
                        nearestHand: nearestHand)
    }

    /// False for a bank whose owner fades its root itself (the Time
    /// Capsule's plates, drawn out with the tape): `Recession` writes the
    /// same opacity, and with no hand near it wiped the owner's fade, so
    /// the plates slid out at full strength and vanished in a frame.
    var recedes = true

    /// True when the tap hit one of these plates — armed it, or fired it.
    /// A tap on a plate's child resolves to the plate (the walk-up contract).
    @discardableResult
    func handleTap(_ entity: Entity) -> Bool {
        guard root.isEnabled else { return false }
        var current: Entity? = entity
        while let candidate = current {
            if let index = plates.firstIndex(where: { $0.entity === candidate }) {
                return press(index: index, on: candidate)
            }
            if candidate === root { return false }
            current = candidate.parent
        }
        return false
    }

    /// True when the tap was consumed (including arming). An unavailable
    /// plate consumes nothing — the tap falls through to what is behind it.
    private func press(index: Int, on entity: Entity) -> Bool {
        let action = plates[index].action
        guard action.isAvailable() else { return false }

        if action.confirms && armed?.id != action.id {
            armed = (id: action.id, remaining: Self.armWindow)
            plates[index].control.setArmed(true)
            SoundPalette.play(.pop, on: entity, volume: 0.25)
            return true
        }

        armed = nil
        plates[index].control.setArmed(false)
        SoundPalette.play(.pop, on: entity, volume: 0.4)
        action.fire()
        return true
    }

    /// How far the widest label reaches from a plate's centre — for keeping
    /// the bank clear of the apparatus. A `confirms` action must also pass
    /// "Tap again": a bank sized only to resting labels grows on arming.
    /// How far right of the anchor a control's centre stands so its
    /// leading edge is the plate's old left edge.
    static func leadingInset(for label: String) -> Float {
        RoomControlFootprint.halfWidth(forLongestOf: [label]) - PlateStyle.width / 2
    }

    static func reach(forLabels labels: [String]) -> Float {
        2 * RoomControlFootprint.halfWidth(forLongestOf: labels) - PlateStyle.width / 2
    }

    /// What an armed plate says — include it in `reach(forLabels:)`.
    static let armedLabel = ControlMetrics.armedTitle

    private func makePlate(_ action: SpatialAction) -> Plate {
        let control = RoomControl(title: action.label,
                                  systemImage: action.symbol ?? "hand.tap",
                                  isEnabled: action.isAvailable())
        // Found again by id when pressed: the view's closure must not hold
        // the entity that holds the view. VoiceOver's press is the button's
        // own, through the same arm-then-fire path a pinch takes.
        let entity = ControlAttachment.control(
            control,
            kind: .button(action.confirms ? .destructive : .standard, iconOnly: false),
            name: "action-\(action.id)",
            press: { [weak self] in
                guard let self,
                      let index = self.plates.firstIndex(where: { $0.action.id == action.id })
                else { return }
                _ = self.press(index: index, on: self.plates[index].entity)
            })
        entity.isEnabled = false
        return Plate(action: action, entity: entity, control: control)
    }
}
