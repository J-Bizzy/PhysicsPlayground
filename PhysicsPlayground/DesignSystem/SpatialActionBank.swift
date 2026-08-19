//
//  SpatialActionBank.swift
//  Physics Playground — Design System
//
//  The standing one-shot VERB plate. It must not look like a layer bank —
//  a layer plate LATCHES, an action plate is MOMENTARY — so it is machined
//  stock, not glass, and FLASHES its accent on fire rather than staying
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
    static let armWindow: Double = 4.0

    /// How long the plate holds its accent after firing.
    private static let flashDuration: Double = 0.25

    private let accent: UIColor
    private let layout: StackLayout
    private var reveal: Double = 0

    private struct Plate {
        let action: SpatialAction
        let entity: ModelEntity
        let face: ModelEntity
        let label: Entity
        let armedLabel: Entity
        var flash: Double = 0
        var wasAvailable: Bool?
        var wasLit: Bool?
        /// The lamp's last painted (r, g, b, opacity) — eased toward its
        /// target by `Fade.approach`, nil until the first paint.
        var paint: SIMD4<Float>?
    }

    private var plates: [Plate] = []

    /// Which plate is armed, and how long it has left. Nil when none is.
    private var armed: (id: String, remaining: Double)?

    init(accent: UIColor, actions: [SpatialAction] = [],
         layout: StackLayout = StackLayout()) {
        self.accent = accent
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

    /// Per frame: hang beside `anchor`, face the viewer, run the arm timer
    /// and the fire flash, repaint only what changed.
    /// - Parameter resetNonce: `AppModel.resetNonce`; on change the bank
    ///   disarms itself — armed state lives HERE, not in the model, so a
    ///   model reset alone cannot clear it. Taken here so the rule cannot
    ///   be adopted by only some modules.
    /// `nearestHand` drives recession — see `Recession`.
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
            plates[index].entity.position = SIMD3<Float>(placement.offset)
            plates[index].entity.scale = SIMD3(repeating: Float(placement.scale))
            plates[index].entity.isEnabled = placement.isVisible

            if plates[index].flash > 0 {
                plates[index].flash = max(0, plates[index].flash - dt)
            }

            // The lamp eases yet repaints only while moving — `approach`
            // returns the target once settled, so a resting lamp rebuilds
            // nothing. Accessibility stays change-gated: VoiceOver wants
            // the state, not the ease.
            let isArmedNow = armed?.id == plates[index].action.id
            let available = plates[index].action.isAvailable()
            let lit = isArmedNow || plates[index].flash > 0
            let target = Fade.paint(lit ? accent : UIColor(white: 0.34, alpha: 1),
                                    opacity: lit ? 0.95 : (available ? 0.55 : 0.20))
            let painted = plates[index].paint
            let next = painted.map { Fade.approach($0, toward: target, dt: dt) }
                ?? target
            if next != painted {
                plates[index].paint = next
                plates[index].face.model?.materials = [Fade.unlit(next)]
            }
            if plates[index].wasLit != lit || plates[index].wasAvailable != available {
                plates[index].wasLit = lit
                plates[index].wasAvailable = available
                plates[index].entity.components.set(
                    accessibility(for: plates[index].action,
                                  armed: isArmedNow, available: available))
            }
            // The nameplate swap is an isEnabled flip between two plates
            // built once — never a mesh rebuild on the per-frame path.
            plates[index].label.isEnabled = !isArmedNow
            plates[index].armedLabel.isEnabled = isArmedNow
        }

        // Anchor in WORLD space: `anchor` is in the parent's (possibly
        // scaled) frame while the hand is world space — `position(relativeTo: nil)`
        // puts both in the same frame.
        Recession.apply(to: root, anchor: root.position(relativeTo: nil),
                        nearestHand: nearestHand)
    }

    /// True when the tap hit one of these plates — armed it, or fired it.
    /// A tap on a plate's CHILD resolves to the plate (the walk-up contract).
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

    /// True when the tap was CONSUMED (including arming). An unavailable
    /// plate consumes nothing — the tap falls through to what is behind it.
    private func press(index: Int, on entity: Entity) -> Bool {
        let action = plates[index].action
        guard action.isAvailable() else { return false }

        if action.confirms && armed?.id != action.id {
            armed = (id: action.id, remaining: Self.armWindow)
            SoundPalette.play(.pop, on: entity, volume: 0.25)
            return true
        }

        armed = nil
        plates[index].flash = Self.flashDuration
        SoundPalette.play(.pop, on: entity, volume: 0.4)
        action.fire()
        return true
    }

    /// Dark stock at rest; accent while armed/flashing; dimmer when unavailable.
    private func material(lit: Bool, available: Bool) -> UnlitMaterial {
        let color = lit ? accent : UIColor(white: 0.34, alpha: 1)
        var material = UnlitMaterial(color: color)
        let opacity: Float = lit ? 0.95 : (available ? 0.55 : 0.20)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    private func accessibility(for action: SpatialAction,
                               armed: Bool, available: Bool) -> AccessibilityComponent {
        var component = AccessibilityComponent()
        component.isAccessibilityElement = true
        component.label = LocalizedStringResource(stringLiteral: action.label)
        // The value carries the ARMED state — one tap from firing must not
        // read the same as two to someone who cannot see the lamp.
        let state = !available ? "unavailable"
            : (armed ? "armed — tap again to confirm" : "button")
        component.value = LocalizedStringResource(stringLiteral: state)
        // Advertised only while available: refuse the tap to VoiceOver too.
        component.systemActions = available ? [.activate] : []
        return component
    }

    /// Geometry from `PlateStyle` — one silhouette for both banks; the
    /// material is where a verb differs from a state.
    private static let plateWidth = PlateStyle.width
    private static let plateHeight = PlateStyle.height
    private static let plateCorner = PlateStyle.corner
    private static let labelSize = PlateStyle.labelSize
    private static let labelGap = PlateStyle.labelGap

    /// How far the widest label reaches from a plate's centre — for keeping
    /// the bank clear of the apparatus. A `confirms` action must also pass
    /// "Tap again": a bank sized only to resting labels grows on arming.
    static func reach(forLabels labels: [String]) -> Float {
        let widest = labels
            .map { HubScene.namePlateWidth($0, size: labelSize) }
            .max() ?? 0
        return plateWidth / 2 + labelGap + widest
    }

    /// The nameplate an armed plate shows — include it in `reach(forLabels:)`.
    static let armedLabel = "Tap again"

    private func makePlate(_ action: SpatialAction) -> Plate {
        // Machined stock, not glass — a verb and a state must not be the
        // same object in two colours.
        let plate = ModelEntity(
            mesh: .generateBox(size: [Self.plateWidth, Self.plateHeight,
                                      PlateStyle.depth],
                               cornerRadius: Self.plateCorner),
            materials: [Materials.machined(UIColor(white: 0.24, alpha: 1))])
        plate.name = "action-\(action.id)"
        plate.components.set(GroundingShadowComponent(castsShadow: true))

        // The edge hairline — without it machined stock has no silhouette
        // against a bright wall. Its radius takes the SAME inset the box
        // does, or the two outlines stop being concentric.
        let edge = Materials.glassEdgeInset
        let border = ModelEntity(
            mesh: .generateBox(
                size: [Self.plateWidth + edge * 2,
                       Self.plateHeight + edge * 2, PlateStyle.edgeDepth],
                cornerRadius: Self.plateCorner + edge),
            materials: [Materials.glassEdge()])
        border.position = [0, 0, -0.0008]
        plate.addChild(border)

        // The lamp, in the same place the layer bank puts its own.
        let face = ModelEntity(
            mesh: .generateBox(size: [0.011, 0.034, 0.002], cornerRadius: 0.004),
            materials: [material(lit: false, available: action.isAvailable())])
        face.position = [-0.032, 0, PlateStyle.faceLift]
        plate.addChild(face)

        if let symbol = action.symbol, let texture = Bloom.symbolTexture(symbol) {
            var iconMaterial = UnlitMaterial()
            iconMaterial.color = .init(tint: .white, texture: .init(texture))
            iconMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.9))
            let icon = ModelEntity(
                mesh: .generatePlane(width: 0.024, height: 0.024),
                materials: [iconMaterial])
            icon.position = [-0.002, 0, PlateStyle.faceLift]
            plate.addChild(icon)
        }

        // Both nameplates built ONCE and swapped by isEnabled — a text
        // mesh rebuild on the interaction path is banned.
        let label = Self.namePlate(action.label, white: 0.94)
        plate.addChild(label)
        let armedLabel = Self.namePlate(Self.armedLabel, white: 1.0)
        armedLabel.isEnabled = false
        plate.addChild(armedLabel)

        plate.components.set(InputTargetComponent())
        // Collider matched to the plate (collider-≤-visual rule) — an
        // oversized one would shield the apparatus the bank hangs beside.
        let labelSpan = HubScene.namePlateWidth(action.label, size: Self.labelSize)
        plate.components.set(CollisionComponent(shapes: [
            .generateBox(size: [0.092, 0.056, 0.018]),
            // The label is part of the target — twin of `SpatialLayerBank`'s.
            .generateBox(size: [labelSpan + 0.010, Self.plateHeight * 0.8, 0.018])
                .offsetBy(translation: [
                    Self.plateWidth / 2 + Self.labelGap + labelSpan / 2, 0, 0,
                ]),
        ]))
        plate.components.set(HoverEffectComponent())
        plate.components.set(accessibility(for: action, armed: false,
                                           available: action.isAvailable()))
        // VoiceOver's press goes through the SAME arm-then-fire path a
        // pinch does, so a destructive verb still confirms.
        plate.components.set(SpatialActionComponent(activate: { [weak plate] in
            guard let plate,
                  let index = self.plates.firstIndex(where: { $0.entity === plate })
            else { return }
            _ = self.press(index: index, on: plate)
        }))
        plate.isEnabled = false

        return Plate(action: action, entity: plate, face: face,
                     label: label, armedLabel: armedLabel)
    }

    /// A label placed by its own LEFT edge, so a long word starts where
    /// the plate ends instead of straddling the icon it names.
    private static func namePlate(_ text: String, white: CGFloat) -> Entity {
        let width = HubScene.namePlateWidth(text, size: labelSize)
        let plate = HubScene.namePlate(text,
                                       accent: UIColor(white: white, alpha: 1),
                                       size: labelSize)
        plate.position = [plateWidth / 2 + labelGap + width / 2, 0, 0.006]
        return plate
    }
}
