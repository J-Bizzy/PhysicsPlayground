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

    private let layout: StackLayout
    private var reveal: Double = 0
    private var plates: [(layer: LayerSwitch, entity: Entity,
                          control: RoomControl)] = []

    /// `accent` is kept for callers; a switch's on state is the system's
    /// selected platter, never a colour.
    init(accent: UIColor, layers: [LayerSwitch] = [],
         layout: StackLayout = StackLayout()) {
        self.layout = layout
        root.isEnabled = false
        setLayers(layers)
    }

    func setLayers(_ layers: [LayerSwitch]) {
        for plate in plates { plate.entity.removeFromParent() }
        plates.removeAll()
        for layer in layers {
            let (plate, control) = makePlate(layer)
            root.addChild(plate)
            plates.append((layer, plate, control))
        }
        reveal = 0
        root.isEnabled = false
    }

    var isEmpty: Bool { plates.isEmpty }

    /// What the plate for `id` is showing — for tests, which cannot read
    /// the glass.
    func control(for id: String) -> RoomControl? {
        plates.first { $0.layer.id == id }?.control
    }

    /// Per frame: hang beside `anchor`, face the viewer, follow the model.
    /// `nearestHand` drives recession — a readout recedes to 0.45 rather
    /// than disappearing, so the state stays legible across the room.
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
            // Left-aligned on the column: the control's leading edge stands
            // where a plate's did, so a long name runs away from the apparatus.
            plates[index].entity.position = SIMD3<Float>(placement.offset)
                + SIMD3(Self.leadingInset(for: plates[index].layer.label), 0, 0)
            plates[index].entity.scale = SIMD3(repeating: Float(placement.scale))
            plates[index].entity.isEnabled = placement.isVisible
            // The switch follows the model, not the last tap; written only on
            // change, so a resting bank costs SwiftUI nothing.
            plates[index].control.setOn(plates[index].layer.isOn())
        }

        // Anchor in world space: `anchor` is in the parent's (possibly
        // scaled) frame while the hand is world space — `position(relativeTo: nil)`
        // puts both in the same frame.
        Recession.apply(to: root, anchor: root.position(relativeTo: nil),
                        nearestHand: nearestHand)
    }

    /// True when the tap flipped a layer. A pinch on the glass arrives as
    /// the SwiftUI toggle's own action; this is the same press for any
    /// caller holding an entity.
    func handleTap(_ entity: Entity) -> Bool {
        guard root.isEnabled else { return false }
        var current: Entity? = entity
        while let candidate = current {
            if let match = plates.first(where: { $0.entity === candidate }) {
                press(match.layer, on: candidate)
                return true
            }
            if candidate === root { return false }
            current = candidate.parent
        }
        return false
    }

    private func press(_ layer: LayerSwitch, on entity: Entity) {
        layer.toggle()
        SoundPalette.play(.pop, on: entity, volume: 0.35)
    }

    /// How far the widest switch reaches from a plate's centre — for
    /// keeping the bank clear of the apparatus; `FieldInstrumentLayout`
    /// asserts on it. The switch is centred on its anchor, so half of it.
    /// How far right of the anchor a control's centre stands so its
    /// leading edge is the plate's old left edge.
    static func leadingInset(for label: String) -> Float {
        RoomControlFootprint.halfWidth(forLongestOf: [label]) - PlateStyle.width / 2
    }

    static func reach(forLabels labels: [String]) -> Float {
        2 * RoomControlFootprint.halfWidth(forLongestOf: labels) - PlateStyle.width / 2
    }

    private func makePlate(_ layer: LayerSwitch) -> (Entity, RoomControl) {
        let control = RoomControl(title: layer.label,
                                  systemImage: layer.symbol ?? "circle.lefthalf.filled",
                                  isOn: layer.isOn())
        // Found again by id when pressed: the view's closure must not hold
        // the entity that holds the view.
        let entity = ControlAttachment.control(
            control, kind: .toggle(iconOnly: false),
            name: "layer-\(layer.id)",
            press: { [weak self] in
                guard let self,
                      let plate = self.plates.first(where: { $0.layer.id == layer.id })
                else { return }
                self.press(plate.layer, on: plate.entity)
            })
        entity.isEnabled = false
        return (entity, control)
    }
}
