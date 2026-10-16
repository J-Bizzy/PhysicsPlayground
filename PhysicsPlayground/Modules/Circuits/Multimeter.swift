//
//  Multimeter.swift
//  Physics Playground — Circuit Workshop
//
//  The bench's meter: a rotary dial you turn and two probes on leads you
//  carry to the terminals. Mesh from `Tools/multimeter.py` at real
//  dimensions (case 86 × 168 × 32 mm). Colliders match what they
//  represent (dial, probe handle, case): it stands among terminals 1 cm
//  apart.
//

import QuartzCore
import RealityKit
import RenderKit
import SwiftUI

@MainActor
final class Multimeter {
    let root = Entity()

    /// The probe tips, in `root`'s (the renderer's) frame, which nothing
    /// moves. Owned here, not in `@State`: the render loop reads them every
    /// frame.
    private(set) var probeTip: [CircuitsModel.ProbeSlot: SIMD3<Float>] = [:]

    private let accent: UIColor
    /// The instrument — case, dial, face, nameplate — carrying the meter's
    /// own movements. `root` stays at identity, so the probes under it live
    /// in a frame nothing moves: a probe is moved only by a hand.
    private let chassis = Entity()
    private let body = Entity()
    private let dial = Entity()
    private let screen = ModelEntity()
    private let noteText = ModelEntity()
    private var probes: [CircuitsModel.ProbeSlot: Entity] = [:]
    private var leads: [CircuitsModel.ProbeSlot: ModelEntity] = [:]
    private var textCache: [String: MeshResource] = [:]
    private var lastDisplay = ""
    private var lastNote = ""
    private var lastFault = false
    private var appliedMode: CircuitsModel.MeterMode?

    // MARK: The continuity beep

    private let beepEmitter = Entity()
    /// A steady A6 for as long as the probes find a path, the way a real
    /// meter beeps; Settings' effects volume scales it like any effect.
    private lazy var beep = ToneVoice(on: beepEmitter, tone: .beep,
                                      baseHz: SoundEffects.beepHz, range: (-44)...(-22))

    private func sound(beeping: Bool) {
        guard beep.start() else { return }
        // Quick enough to start and stop with the probe, slow enough
        // (about 60 ms) that neither edge clicks.
        beep.update(pitchHz: SoundEffects.beepHz,
                    loudness: beeping ? SoundPalette.masterVolume : 0,
                    smoothing: 0.35)
    }

    /// Where each jack sits on the case, in the meter's own frame —
    /// taken from the same numbers `Tools/multimeter.py` builds from.
    private static let jack: [CircuitsModel.ProbeSlot: SIMD3<Float>] = [
        .black: SIMD3(-0.019, -0.068, 0.017),
        .red: SIMD3(0.019, -0.068, 0.017),
    ]
    private static let probeColour: [CircuitsModel.ProbeSlot: UIColor] = [
        .red: UIColor(red: 0.80, green: 0.16, blue: 0.12, alpha: 1),
        .black: UIColor(white: 0.10, alpha: 1),
    ]
    /// Where a probe hangs uncarried, in the meter's frame: below its
    /// jack, far enough down that the handles do not cross the dial.
    private static let park = SIMD3<Float>(0, -0.125, 0.03)
    /// How near a probe tip must get to latch a terminal: generous, but
    /// under the spacing of one part's two terminals.
    static let snapRadius: Double = 0.035

    /// The SpaceView's tap router, so the dial, case and probes can be
    /// operated without hands.
    var onTap: ((Entity) -> Void)?

    /// The case's entity name, which the module's drag handler looks for.
    static let bodyName = "meter-body"

    /// True when this entity is part of the case — the handle, as opposed
    /// to the dial you turn or a probe you carry.
    func isBody(_ entity: Entity) -> Bool {
        isDescendant(entity, of: body) && !isDescendant(entity, of: dial)
    }

    init(accent: UIColor, anchor: SIMD3<Float>) {
        self.accent = accent
        self.anchor = anchor
        self.homeAnchor = anchor

        if let mesh = PropCache.instance(named: "Multimeter") {
            // Stand the case up: the export arrives face-up along +Y, and +90°
            // about X brings the face to +Z, which every offset here is written
            // against.
            mesh.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            body.addChild(mesh)
        } else {
            // Fallback so a missing (script-generated) asset is visible.
            body.addChild(ModelEntity(
                mesh: Primitives.box(size: [0.086, 0.168, 0.032], cornerRadius: 0.006),
                materials: [Materials.machined(UIColor(white: 0.24, alpha: 1))]))
        }
        // The case, as something a hand can take hold of.
        body.name = Self.bodyName
        body.components.set(InputTargetComponent())
        body.components.set(CollisionComponent(shapes: [
            Primitives.collisionBox(size: [0.086, 0.168, 0.032]),
        ]))
        body.components.set(HoverEffectComponent())
        SpatialActions.attach(
            to: body, label: "Multimeter",
            activate: { [weak self, weak body] in
                guard let body else { return }
                self?.onTap?(body)
            })
        var bodyAccess = AccessibilityComponent()
        bodyAccess.isAccessibilityElement = true
        bodyAccess.label = "Multimeter. Drag to move it."
        body.components.set(bodyAccess)
        root.addChild(chassis)
        chassis.addChild(body)

        // Its own entity so it can turn; the pointer sits proud of the moulded
        // knob so the rotation is visible.
        dial.name = "meter-dial"
        dial.position = [0, -0.020, 0.0185]
        let pointer = ModelEntity(
            mesh: Primitives.box(size: [0.0038, 0.026, 0.0022], cornerRadius: 0.001),
            materials: [UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))])
        pointer.position = [0, 0.009, 0.0072]
        dial.addChild(pointer)
        dial.components.set(InputTargetComponent())
        dial.components.set(CollisionComponent(
            shapes: [Primitives.collisionSphere(radius: 0.030)]))
        dial.components.set(HoverEffectComponent())
        // The dial cycles: activate steps one mode through `handleTap`.
        SpatialActions.attach(
            to: dial, label: "Meter mode",
            activate: { [weak self, weak dial] in
                guard let dial else { return }
                self?.onTap?(dial)
            })
        chassis.addChild(dial)

        // The reading, sitting in the bezel the mesh already provides.
        screen.position = [0, 0.044, 0.019]
        chassis.addChild(screen)
        noteText.position = [0, 0.026, 0.019]
        chassis.addChild(noteText)
        // The beep comes from the case, where a real meter's piezo is.
        beepEmitter.position = [0, 0.04, 0]
        chassis.addChild(beepEmitter)

        for slot in [CircuitsModel.ProbeSlot.red, .black] {
            let probe = Entity()
            if let mesh = PropCache.instance(named: "MeterProbe") {
                let tinted = mesh
                probe.addChild(tinted)
            }
            probe.name = slot == .red ? "meter-probe-red" : "meter-probe-black"
            probe.components.set(InputTargetComponent())
            SpatialActions.attach(
                to: probe, label: slot == .red ? "Red probe" : "Black probe",
                activate: { [weak self, weak probe] in
                    guard let probe else { return }
                    self?.onTap?(probe)
                })
            // Matched to the handle, not the whole probe: the needle reaches in
            // among terminals its grab box must not cover.
            probe.components.set(CollisionComponent(shapes: [
                Primitives.collisionCapsule(height: 0.09, radius: 0.013, offset: SIMD3(0, 0.05, 0)),
            ]))
            probe.components.set(HoverEffectComponent())
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = LocalizedStringResource(
                stringLiteral: slot == .red ? "Red probe" : "Black probe")
            probe.components.set(accessibility)
            root.addChild(probe)
            probes[slot] = probe

            let lead = ModelEntity(
                mesh: Primitives.cylinder(height: 1, radius: 0.0022),
                materials: [Materials.machined(
                    Self.probeColour[slot] ?? .black, roughness: 0.85)])
            root.addChild(lead)
            leads[slot] = lead

            // Parked below the jacks until a hand takes one; `update`
            // re-parks it there while it stays uncarried.
            probeTip[slot] = anchor + (Self.jack[slot] ?? .zero) + Self.park
        }

        let plate = HubScene.namePlate("Multimeter", accent: accent, size: PlateStyle.labelSize)
        plate.position = [0, 0.108, 0]
        chassis.addChild(plate)

        root.components.set(GroundingShadowComponent(castsShadow: true))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Multimeter"
        root.components.set(accessibility)
    }

    // MARK: Input

    /// True when the tap turned the dial. One tap is one detent, which is
    /// what turning a real dial by one click does.
    @discardableResult
    func handleTap(_ entity: Entity, model: CircuitsModel) -> Bool {
        guard isDescendant(entity, of: dial) else { return false }
        let modes = CircuitsModel.MeterMode.allCases
        let index = modes.firstIndex(of: model.meterMode) ?? 0
        model.meterMode = modes[(index + 1) % modes.count]
        SoundPalette.play(.pop, on: dial, volume: 0.35)
        return true
    }

    /// Which probe an entity belongs to, if any.
    func probeSlot(for entity: Entity) -> CircuitsModel.ProbeSlot? {
        for (slot, probe) in probes where isDescendant(entity, of: probe) {
            return slot
        }
        return nil
    }

    /// Carries a probe to a point and latches it onto a terminal within
    /// reach, during the drag rather than on release. `local` is the
    /// unscaled `root` frame the meter is drawn in; `bench` is the
    /// terminals' zoomed frame it latches against.
    func moveProbe(_ slot: CircuitsModel.ProbeSlot,
                   local: SIMD3<Float>, bench: SIMD3<Double>,
                   model: CircuitsModel) {
        probeTip[slot] = local
        // From here on a hand chose this probe's place; `carried`
        // distinguishes "placed" from "parked" so `update` stops re-parking it.
        carried.insert(slot)
        model.setProbe(slot, to: model.nearestTerminal(
            to: bench, within: Self.snapRadius))
    }

    /// Probes a hand has taken off the case. The rest hang in the
    /// holster and follow the instrument wherever it goes.
    private var carried: Set<CircuitsModel.ProbeSlot> = []

    // MARK: Render

    /// A small stand-in for the shelf slot; `handOver` moves the real
    /// instrument to the hand.
    @MainActor
    static func miniature() -> Entity {
        let holder = Entity()
        let body = ModelEntity(
            mesh: Primitives.box(width: 0.043, height: 0.084, depth: 0.016,
                               cornerRadius: 0.005),
            materials: [Materials.machined(UIColor(white: 0.24, alpha: 1))])
        holder.addChild(body)

        // The screen, so it reads as a meter rather than a block at this size.
        var screen = UnlitMaterial(color: UIColor(red: 0.10, green: 0.16,
                                                  blue: 0.13, alpha: 1))
        screen.blending = .opaque
        let face = ModelEntity(
            mesh: Primitives.plane(width: 0.031, height: 0.020,
                                 cornerRadius: 0.002),
            materials: [screen])
        face.position = [0, 0.022, 0.0085]
        holder.addChild(face)

        let dial = ModelEntity(
            mesh: Primitives.cylinder(height: 0.004, radius: 0.011),
            materials: [Materials.machined(UIColor(white: 0.34, alpha: 1))])
        dial.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        dial.position = [0, -0.016, 0.009]
        holder.addChild(dial)
        return holder
    }

    /// Where the case stands, in the renderer's own (unscaled) frame.
    private(set) var anchor: SIMD3<Float>

    /// Where it stood when built — the shelf slot it goes back to; `stow`
    /// is the only way back.
    private let homeAnchor: SIMD3<Float>

    func place(at position: SIMD3<Float>) {
        anchor = position
    }

    /// Back on the shelf: not drawn, probes re-holstered, the case at
    /// `homeAnchor`. Called on a reset only.
    func stow() {
        carried.removeAll()
        anchor = homeAnchor
        root.isEnabled = false
    }

    /// The last `resetNonce` this meter saw: the meter is a view object, so
    /// a model reset alone cannot reach it.
    private var seenResetNonce: Int?

    func update(viewer: SIMD3<Float>?, model: CircuitsModel, resetNonce: Int = 0) {
        // Starts nil so the first frame adopts the app's count rather than
        // stowing a meter the user just pulled out.
        if let seen = seenResetNonce, seen != resetNonce { stow() }
        seenResetNonce = resetNonce
        let anchor = self.anchor
        // On the chassis, not `root` (see `chassis`): the case moves, the
        // probes hanging off `root` do not.
        chassis.position = anchor

        // Yaw only: a meter that pitched to meet a viewer looking down on
        // it would turn its own face edge-on.
        if let viewer, let facing = yaw(facing: viewer, from: anchor) {
            chassis.orientation = facing
        }

        // The dial points at the selected mode, over the same 250° arc
        // the Blender script marks its detents across.
        if appliedMode != model.meterMode {
            appliedMode = model.meterMode
            let modes = CircuitsModel.MeterMode.allCases
            let index = modes.firstIndex(of: model.meterMode) ?? 0
            let sweep = 250.0 * .pi / 180
            let angle = -sweep / 2 + sweep * Double(index)
                / Double(max(modes.count - 1, 1))
            dial.orientation = simd_quatf(angle: Float(-angle), axis: [0, 0, 1])
        }

        let reading = model.multimeterReading
        setScreen(reading?.display ?? model.meterMode.label,
                  note: reading?.note ?? model.meterMode.longLabel,
                  fault: reading?.fault ?? false)
        sound(beeping: reading?.beeping == true && !model.isPaused)

        for slot in [CircuitsModel.ProbeSlot.red, .black] {
            guard let probe = probes[slot], let lead = leads[slot] else { continue }
            // The jack rides the case; the tip is in `root`'s frame. The
            // lead is drawn between them and absorbs every move of the
            // instrument — the one part meant to change shape.
            let jack = anchor + chassis.orientation.act(Self.jack[slot] ?? .zero)
            if !carried.contains(slot) {
                probeTip[slot] = jack + chassis.orientation.act(Self.park)
            }
            let tip = probeTip[slot] ?? jack

            probe.position = tip
            // The needle points back along the lead, so a probe parked on
            // a terminal leans away from the meter rather than through it.
            let toJack = jack - tip
            let span = simd_length(toJack)
            guard span > 1e-4 else { continue }
            let direction = toJack / span
            probe.orientation = VectorFieldArrows.rotationFromYAxis(to: direction)

            // A straight run: a sagging catenary would be a per-frame mesh
            // rebuild while a probe moves, which the render path may not do.
            lead.position = (jack + tip) / 2
            lead.orientation = VectorFieldArrows.rotationFromYAxis(to: direction)
            lead.scale = SIMD3(1, span, 1)
        }
    }

    // MARK: Display

    /// How often the face may redraw: 8 Hz is faster than a number can be
    /// read, for a tenth of the mesh work.
    private static let minimumInterval: Double = 1.0 / 8
    private var lastScreenTime: Double = 0

    private func setScreen(_ display: String, note: String, fault: Bool) {
        let colour = fault
            ? UIColor(red: 0.95, green: 0.45, blue: 0.2, alpha: 1) : accent
        // A fault is not rate-limited — it must land on the frame it happens.
        let changed = display != lastDisplay || note != lastNote
        if changed, fault == lastFault {
            let now = CACurrentMediaTime()
            guard now - lastScreenTime >= Self.minimumInterval else { return }
            lastScreenTime = now
        }
        if display != lastDisplay || fault != lastFault {
            lastDisplay = display
            screen.model = ModelComponent(
                mesh: mesh(display, size: 0.019),
                materials: [UnlitMaterial(color: colour)])
            centre(screen)
        }
        if note != lastNote || fault != lastFault {
            lastNote = note
            noteText.model = ModelComponent(
                mesh: mesh(note, size: 0.0062),
                materials: [UnlitMaterial(color: fault
                    ? colour : UIColor(white: 0.72, alpha: 1))])
            centre(noteText)
        }
        lastFault = fault
    }

    /// Text meshes cached by (size, string), bounded, because a live
    /// reading generates unbounded strings.
    private func mesh(_ text: String, size: CGFloat) -> MeshResource {
        let key = "\(size)|\(text)"
        if let cached = textCache[key] { return cached }
        if textCache.count > 240 { textCache.removeAll() }
        let generated = MeshResource.generateText(
            text, extrusionDepth: 0.0006,
            font: .monospacedDigitSystemFont(ofSize: size, weight: .semibold))
        textCache[key] = generated
        return generated
    }

    private func centre(_ entity: ModelEntity) {
        guard let bounds = entity.model?.mesh.bounds else { return }
        entity.position.x = -(bounds.min.x + bounds.max.x) / 2
    }

    private func isDescendant(_ entity: Entity, of ancestor: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === ancestor { return true }
            current = candidate.parent
        }
        return false
    }
}
