//
//  SpatialActionBank.swift
//  Physics Playground — Design System
//
//  The standing one-shot VERB. The vocabulary already had a plate for a
//  latching state (`SpatialLayerBank`), a disc for an N-way choice
//  (`SpatialPicker`), a rail for a quantity (`SpatialTrackControl`), a
//  well for creation (`Well`) and a petal for a per-object action
//  (`Bloom`). It had nothing for "do this now" that wasn't attached to
//  an object — and when the module panels were deleted (DECISIONS.md,
//  2026-08-01) seven capabilities came looking for exactly that. Five
//  of them have no object to hang a petal on: clearing a bench is an
//  action on the room, not on any part in it.
//
//  IT MUST NOT LOOK LIKE A LAYER BANK, and that is a correctness
//  property rather than a style note. A layer plate LATCHES: lit means
//  the layer is on, and the plate is a readout you can also press. An
//  action plate is MOMENTARY: it fires and nothing about the world it
//  reports on has a lit-or-dark answer. Standing the two side by side
//  in the same livery is the "lying by arrangement" failure already
//  recorded against Magnetism's top plate — the arrangement claims a
//  shared grammar the behaviour doesn't honour. So an action plate is
//  dark machined stock, not glass, and it FLASHES its accent for a beat
//  when it fires rather than staying lit.
//
//  Destructive actions take `confirms: true` and arm instead of firing:
//  the first tap lights the plate and swaps its nameplate to "Tap
//  again", a timer disarms it, the second tap fires. This is not the
//  two-pinch arming dance that was removed from Reset in July — that
//  one guarded a RAIL against a stray gaze-pinch, and its replacement
//  was a window `confirmationDialog`. There is no window left to put a
//  dialog in, and Circuit Workshop's bench survives launches, so the
//  guard has to exist somewhere. It exists here.
//
//  The arm timer is the one piece of state this class owns, and
//  `disarm()` exists so `reset()` can clear it. An armed Clear plate
//  that outlived a reset would be the same defect that has now bitten
//  four modules in a different costume.
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
    /// happen goes dim and stops accepting taps, the way the panel
    /// buttons used `.disabled`.
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

    /// Whether `id` is currently armed — for tests and for a caller that
    /// wants to show the armed state somewhere else.
    func isArmed(_ id: String) -> Bool { armed?.id == id }

    /// Clear any armed plate.
    func disarm() {
        armed = nil
    }

    /// Put a plate into its armed state without a tap.
    ///
    /// This exists for the debug launch arguments and nothing else. The
    /// armed state is the only part of this control that is not visible
    /// at rest, the simulator has no hands to produce it, and a plate
    /// photographed only in its resting state proves the plate rendered
    /// and nothing about the confirmation behind it — which is exactly
    /// the "bead parked at its default" mistake CLAUDE.md records. It
    /// sets the same state the first tap sets.
    ///
    /// `holds` defeats the arm timer, and a debug caller wants it: the
    /// window is four seconds, a `simctl` screenshot lands twenty after
    /// launch, and an argument whose effect has already expired by the
    /// time the shutter opens is an argument that photographs the
    /// resting state and calls it proof.
    func arm(_ id: String, holds: Bool = false) {
        guard plates.contains(where: { $0.action.id == id && $0.action.confirms })
        else { return }
        armed = (id: id, remaining: holds ? .infinity : Self.armWindow)
    }

    /// Per frame: hang beside `anchor`, face the viewer, run the arm
    /// timer and the fire flash, and repaint only what changed.
    /// The last `resetNonce` this bank saw. Starts at nil so the first
    /// frame adopts whatever the app is on rather than firing a disarm.
    private var seenResetNonce: Int?

    /// - Parameter resetNonce: `AppModel.resetNonce`. When it changes,
    ///   the bank disarms itself.
    ///
    ///   THIS IS `disarm()`'s ONLY PRODUCTION CALLER, and until
    ///   2026-08-03 there was none — the method, its test, and the
    ///   paragraph in this file's header explaining why it exists all
    ///   shipped without anything invoking it. A module's reset reaches
    ///   its MODEL (`ModuleDescriptor.reset` is `{ model.reset() }` in
    ///   all six), and an armed plate is the one piece of state a module
    ///   keeps in its SpaceView instead. So Reset came back with the lamp
    ///   still lit and the nameplate still reading "Tap again" — one
    ///   pinch from wiping a bench the user had just restored.
    ///
    ///   Taking the nonce here rather than having each SpaceView compare
    ///   it means the rule cannot be adopted by two of three modules,
    ///   which is how `contrastLine` and `SpatialTrackControl` both went.
    /// `nearestHand` drives recession — see `Recession`.
    func update(anchor: SIMD3<Float>, viewer: SIMD3<Float>?, dt: Double,
                resetNonce: Int = 0, nearestHand: SIMD3<Float>? = nil) {
        if let seen = seenResetNonce, seen != resetNonce { disarm() }
        seenResetNonce = resetNonce
        reveal = Motion.ease(reveal, toward: plates.isEmpty ? 0 : 1, dt: dt)
        root.isEnabled = reveal > 0.02 && !plates.isEmpty
        guard root.isEnabled else { return }
        root.position = anchor

        // Yaw only — a bank that pitched to meet a viewer looking down
        // on it would turn its plates edge-on.
        if let viewer, let facing = yaw(facing: viewer, from: anchor) {
            root.orientation = facing
        }

        // The arm window. It runs down in real time, so a plate armed
        // and forgotten is disarmed by the time a hand comes back.
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

            // The lamp eases between its states and still repaints only
            // while moving — `approach` returns the target exactly once
            // settled, so a resting lamp rebuilds nothing. Accessibility
            // keeps the change-gated path: VoiceOver wants the state, not
            // the ease.
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
            // built once — never a mesh rebuild, which the per-frame
            // path forbids outright.
            plates[index].label.isEnabled = !isArmedNow
            plates[index].armedLabel.isEnabled = isArmedNow
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

    /// True when the tap hit one of these plates — armed it, or fired it.
    /// A tap that lands on a plate's CHILD resolves to the plate, the
    /// walk-up contract every station in this app keeps.
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

    /// Returns true when the tap was CONSUMED — which includes arming.
    /// An unavailable plate consumes nothing, so a tap on a dim plate
    /// falls through to whatever is behind it rather than being eaten.
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

    /// Dark machined stock at rest; accent while armed or flashing; and
    /// dimmer still when the action cannot currently happen.
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
        // The value carries the ARMED state, because a plate that is one
        // tap from wiping a bench and a plate that is two must not read
        // the same to someone who cannot see it light up.
        let state = !available ? "unavailable"
            : (armed ? "armed — tap again to confirm" : "button")
        component.value = LocalizedStringResource(stringLiteral: state)
        // Advertised only while the action can actually happen: a plate
        // that refuses the tap must refuse it to VoiceOver too, or the
        // one user who cannot see it go dim is the one who is told it
        // will work.
        component.systemActions = available ? [.activate] : []
        return component
    }

    /// Plate geometry comes from `PlateStyle` — the two banks hang in
    /// the same rooms, and a different silhouette would read as a
    /// different design system rather than as a different KIND of
    /// control. The material is where a verb differs from a state.
    private static let plateWidth = PlateStyle.width
    private static let plateHeight = PlateStyle.height
    private static let plateCorner = PlateStyle.corner
    private static let labelSize = PlateStyle.labelSize
    private static let labelGap = PlateStyle.labelGap

    /// How far this bank's widest label reaches from a plate's centre —
    /// what a caller needs to keep the bank clear of its apparatus.
    /// `FieldInstrumentLayout` asserts against it rather than guessing.
    ///
    /// An action that `confirms` also has to fit "Tap again", so the
    /// caller must pass that string too — a bank sized to its resting
    /// labels grows on arming, straight into whatever it was cleared of.
    static func reach(forLabels labels: [String]) -> Float {
        let widest = labels
            .map { HubScene.namePlateWidth($0, size: labelSize) }
            .max() ?? 0
        return plateWidth / 2 + labelGap + widest
    }

    /// The nameplate an armed plate shows. Exposed so a caller sizing a
    /// bank can include it in `reach(forLabels:)`.
    static let armedLabel = "Tap again"

    private func makePlate(_ action: SpatialAction) -> Plate {
        // Machined stock, not the layer bank's frosted glass. A verb and
        // a state must not be the same object in two colours.
        let plate = ModelEntity(
            mesh: .generateBox(size: [Self.plateWidth, Self.plateHeight,
                                      PlateStyle.depth],
                               cornerRadius: Self.plateCorner),
            materials: [Materials.machined(UIColor(white: 0.24, alpha: 1))])
        plate.name = "action-\(action.id)"
        // Same contact shadow the layer bank's plates carry — presence,
        // not decoration.
        plate.components.set(GroundingShadowComponent(castsShadow: true))

        // The edge hairline, taken from the layer bank verbatim.
        //
        // Without it the plate photographed as a dark smudge on the
        // furniture rather than as an instrument — machined stock has no
        // silhouette against a bright wall, which is the whole reason
        // the glass plates carry a lit border. Family resemblance is
        // carried by the EDGE; the difference between a verb and a state
        // is carried by the face material and by what the lamp does.
        //
        // Its radius takes the same inset the box does, or the two
        // outlines stop being concentric — grow a rounded rectangle by a
        // constant on every side and its corner radius grows by exactly
        // that constant too.
        let edge = Materials.glassEdgeInset
        let border = ModelEntity(
            mesh: .generateBox(
                size: [Self.plateWidth + edge * 2,
                       Self.plateHeight + edge * 2, PlateStyle.edgeDepth],
                cornerRadius: Self.plateCorner + edge),
            materials: [Materials.glassEdge()])
        border.position = [0, 0, -0.0008]
        plate.addChild(border)

        // The lamp, in the same place the layer bank puts its own, so
        // the eye finds the state indicator without relearning where to
        // look. What DIFFERS is the behaviour it reports.
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

        // Both nameplates are built ONCE and swapped by isEnabled. The
        // alternative — regenerating the text mesh on arming — is a mesh
        // rebuild on the interaction path, which this project bans.
        let label = Self.namePlate(action.label, white: 0.94)
        plate.addChild(label)
        let armedLabel = Self.namePlate(Self.armedLabel, white: 1.0)
        armedLabel.isEnabled = false
        plate.addChild(armedLabel)

        plate.components.set(InputTargetComponent())
        // Collider matched to the plate, per the collider-≤-visual rule.
        // An oversized one here would shield the apparatus the bank
        // hangs beside — the `SpatialScaleHandle` failure, which made
        // whole modules silently non-interactive.
        let labelSpan = HubScene.namePlateWidth(action.label, size: Self.labelSize)
        plate.components.set(CollisionComponent(shapes: [
            .generateBox(size: [0.092, 0.056, 0.018]),
            // The label is part of the target — see the twin of this in
            // `SpatialLayerBank`. The pill sits `labelGap` past the
            // plate's edge and carried no collider, so the word naming
            // the verb was scenery you could pinch through.
            .generateBox(size: [labelSpan + 0.010, Self.plateHeight * 0.8, 0.018])
                .offsetBy(translation: [
                    Self.plateWidth / 2 + Self.labelGap + labelSpan / 2, 0, 0,
                ]),
        ]))
        plate.components.set(HoverEffectComponent())
        plate.components.set(accessibility(for: action, armed: false,
                                           available: action.isAvailable()))
        // VoiceOver's press goes through the SAME arm-then-fire path a
        // pinch does, so a destructive verb still confirms rather than
        // firing on the first activation.
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
    /// the plate ends instead of straddling the icon it names — the bug
    /// that put half of "Parallel plates" on top of its own switch.
    private static func namePlate(_ text: String, white: CGFloat) -> Entity {
        let width = HubScene.namePlateWidth(text, size: labelSize)
        let plate = HubScene.namePlate(text,
                                       accent: UIColor(white: white, alpha: 1),
                                       size: labelSize)
        plate.position = [plateWidth / 2 + labelGap + width / 2, 0, 0.006]
        return plate
    }
}
