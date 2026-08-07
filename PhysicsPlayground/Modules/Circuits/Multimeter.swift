//
//  Multimeter.swift
//  Physics Playground — Circuit Workshop
//
//  The bench's meter: a real instrument, with a rotary dial you turn and
//  two probes on leads you carry to the terminals.
//
//  It was a `Toggle` in a collapsed panel section, then a lit slab you
//  armed with a tap and aimed by tapping two terminals. Both were the
//  same compromise — a meter shaped like a control rather than like a
//  meter. A multimeter is a TOOL: the one thing on this bench you use to
//  ASK the circuit a question instead of building it, and the asking is
//  physical. You turn the dial to choose what you want to know, and you
//  put the probes where you want to know it.
//
//  THE MESH IS BUILT IN BLENDER, from `Tools/multimeter.py` — case,
//  holster, recessed LCD, eight-detent dial, two banana jacks — and the
//  probe is a second asset with a tapered handle, a finger guard and 44
//  mm of steel. Real dimensions: the body is 86 × 168 × 32 mm, which is
//  a handheld DMM, because this app is 1:1 everywhere else.
//
//  THE FOUR MODES ARE NOT FOUR FORMATS OF ONE NUMBER. `CircuitsModel`
//  carries the physics and the reasoning; the short version is that a
//  voltmeter goes ACROSS and an ammeter goes IN SERIES, and a simulated
//  meter that quietly printed a current for probes placed across a live
//  component would be teaching one of the most common mistakes in an
//  introductory lab.
//
//  A NOTE ON THE COLLIDERS, because this object stands among terminals
//  1 cm apart. Every one here is matched to what it represents: the
//  dial's is the dial, each probe's is its HANDLE, and the case's is the
//  CASE. An oversized grab box would shield the very terminals you are
//  trying to probe — the `SpatialScaleHandle` failure, in the module
//  where it would be hardest to notice.
//
//  The case had no collider at all for a while, which honoured that rule
//  by giving up something the rule never asked for: the meter could not
//  be picked up. A tool you cannot put where you want it is furniture.
//  The box below is the case's own 86 × 168 × 32 mm and not a millimetre
//  more, and the meter stands 15 cm clear of the nearest terminal, so it
//  shields nothing. The dial keeps its own collider and protrudes 3 cm in
//  front of the case, so it still wins the taps aimed at it.
//

import QuartzCore
import RealityKit
import RenderKit
import SwiftUI

@MainActor
final class Multimeter {
    let root = Entity()

    /// Where the two probe tips currently are, in `root`'s frame — which
    /// is the renderer's own frame, and which nothing moves. Not the
    /// bench's space, which this said until 2026-08-03, and not the
    /// case's: the case is a separate object that goes where it is put.
    ///
    /// Owned HERE rather than in a `@State`: the render loop reads them
    /// every frame, and a `@State` read from inside a RealityKit closure
    /// comes back stale — the same reason `RingState` is a class.
    private(set) var probeTip: [CircuitsModel.ProbeSlot: SIMD3<Float>] = [:]

    private let accent: UIColor
    /// The instrument itself — case, dial, face, nameplate. It carries
    /// BOTH of the meter's own movements: the anchor a hand drags it to,
    /// and the yaw that turns its face toward whoever is reading it.
    ///
    /// `root` carries neither. It sits at the identity of the renderer's
    /// frame and exists only to hold the meter's two halves side by side,
    /// so that everything under it — the probes — is expressed in a frame
    /// nothing moves.
    ///
    /// THIS IS THE WHOLE DESIGN. A probe is not part of the meter; it is
    /// a thing on the end of a lead, and the only thing in the world that
    /// moves it is a hand holding it. Two rounds of this bug came from
    /// the probes living under an entity that had a job of its own:
    ///
    ///   • the case turned to face the viewer, and the probes turned with
    ///     it, so turning your head slid a placed probe off its terminal;
    ///   • the case moved when you dragged it, and the probes moved with
    ///     it, so tidying the instrument dragged your measurement along.
    ///
    /// Both times the reading went on claiming the terminal it had
    /// latched — the latch is by terminal id, not by position — so the
    /// meter reported a measurement at a contact it was visibly no longer
    /// touching. Nothing that a hand can place may live in a frame that
    /// something else moves or turns.
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
    /// Where a probe hangs when nobody has picked it up: below its jack
    /// and a little proud of the case, in the METER's frame.
    ///
    /// Far enough below that the handles do not cross the dial — the
    /// probe is drawn from its tip back toward the jack, so a short park
    /// length lays both handles straight over the one control on the
    /// front of the instrument.
    private static let park = SIMD3<Float>(0, -0.125, 0.03)
    /// How near a probe tip must get before it latches onto a terminal.
    ///
    /// Generous, because a 3 mm terminal is not a target anyone hits
    /// exactly in mid-air — and still unambiguous, because the two
    /// terminals of one component are further apart than this.
    static let snapRadius: Double = 0.035

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

        if let mesh = try? Entity.load(named: "Multimeter") {
            // STOOD UP. The Blender script builds the case in the XY
            // plane with its face along +Z, and the exporter's Z-up →
            // Y-up conversion turns that +Z into RealityKit's +Y — so
            // the meter arrives lying on its back with the screen
            // pointing at the ceiling, which is exactly how it first
            // photographed. Rotating −90° about X puts the face back on
            // +Z, which is what every hard-coded offset in this file
            // (jacks, dial, screen) is written against.
            //
            // Done here rather than in the exporter because the probe
            // asset wants the OTHER convention: it is built along +Z so
            // that it arrives pointing along +Y, which is what
            // `rotationFromYAxis` aims. One asset per convention, each
            // stated where it is used.
            // +90°, not −90°. Rotating about X by θ sends (0,1,0) to
            // (0, cos θ, sin θ), so +90° is what brings the face from +Y
            // round to +Z; −90° sends it to −Z and points the meter's
            // BACK at the reader, which is a flat grey slab and reads as
            // a missing texture rather than as a wrong angle.
            mesh.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            body.addChild(mesh)
        } else {
            // The asset is generated by a checked-in script, so a missing
            // one is a build problem rather than a runtime condition —
            // but a meter that vanished silently would be worse than a
            // plain one.
            body.addChild(ModelEntity(
                mesh: .generateBox(size: [0.086, 0.168, 0.032], cornerRadius: 0.006),
                materials: [Materials.machined(UIColor(white: 0.24, alpha: 1))]))
        }
        // The case, as something a hand can take hold of.
        body.name = Self.bodyName
        body.components.set(InputTargetComponent())
        body.components.set(CollisionComponent(shapes: [
            .generateBox(size: [0.086, 0.168, 0.032]),
        ]))
        body.components.set(HoverEffectComponent())
        var bodyAccess = AccessibilityComponent()
        bodyAccess.isAccessibilityElement = true
        bodyAccess.label = "Multimeter. Drag to move it."
        body.components.set(bodyAccess)
        root.addChild(chassis)
        chassis.addChild(body)

        // The dial is its own entity so it can TURN — what the user sees
        // rotate is this pointer riding the case's moulded knob.
        //
        // IT HAS TO CLEAR THE KNOB. At z = 0 the pointer sat at
        // 0.0174…0.0196 while the mesh's knob occupies 0.0155…0.0235 at
        // the same radius — so the one moving part of this instrument was
        // buried four millimetres inside the one static part, and the
        // dial read as dead. Turning it worked the whole time; the mode
        // changed, the reading changed, and nothing appeared to move.
        dial.name = "meter-dial"
        dial.position = [0, -0.020, 0.0185]
        let pointer = ModelEntity(
            mesh: .generateBox(size: [0.0038, 0.026, 0.0022], cornerRadius: 0.001),
            materials: [UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))])
        pointer.position = [0, 0.009, 0.0072]
        dial.addChild(pointer)
        dial.components.set(InputTargetComponent())
        dial.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: 0.030)]))
        dial.components.set(HoverEffectComponent())
        chassis.addChild(dial)

        // The reading, sitting in the bezel the mesh already provides.
        screen.position = [0, 0.044, 0.019]
        chassis.addChild(screen)
        noteText.position = [0, 0.026, 0.019]
        chassis.addChild(noteText)

        for slot in [CircuitsModel.ProbeSlot.red, .black] {
            let probe = Entity()
            if let mesh = try? Entity.load(named: "MeterProbe") {
                let tinted = mesh
                probe.addChild(tinted)
            }
            probe.name = slot == .red ? "meter-probe-red" : "meter-probe-black"
            probe.components.set(InputTargetComponent())
            // Matched to the HANDLE, not to the whole probe: the needle
            // has to reach in among terminals its own grab box must not
            // cover.
            probe.components.set(CollisionComponent(shapes: [
                .generateCapsule(height: 0.09, radius: 0.013)
                    .offsetBy(translation: SIMD3(0, 0.05, 0)),
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
                mesh: .generateCylinder(height: 1, radius: 0.0022),
                materials: [Materials.machined(
                    Self.probeColour[slot] ?? .black, roughness: 0.85)])
            root.addChild(lead)
            leads[slot] = lead

            // Parked hanging below the jacks until a hand takes one.
            // `update` keeps re-parking it there — following the case
            // wherever it is put and however it is turned — for as long
            // as it stays uncarried.
            probeTip[slot] = anchor + (Self.jack[slot] ?? .zero) + Self.park
        }

        let plate = HubScene.namePlate("Multimeter", accent: accent, size: 0.0108)
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

    /// Carries a probe to a point and latches it onto whatever terminal
    /// is within reach.
    ///
    /// The latch happens DURING the drag rather than on release, so the
    /// reading appears while you are still holding the probe there —
    /// which is what a real meter does, and which is the difference
    /// between an instrument and a form you submit.
    /// TWO points, and they are in different spaces on purpose. The
    /// meter stands under the renderer's `root` — unscaled, because an
    /// instrument that grew with an 8× Electron View would be useless —
    /// while the bench's terminals live under `viewRoot`, which is the
    /// zoom. So the probe is DRAWN at `local` in the meter's own `root`
    /// frame and LATCHED against `bench` in the terminals' frame. Using
    /// one for both would put the tip where the terminal looks rather
    /// than where it is, and the error would grow with the zoom.
    func moveProbe(_ slot: CircuitsModel.ProbeSlot,
                   local: SIMD3<Float>, bench: SIMD3<Double>,
                   model: CircuitsModel) {
        probeTip[slot] = local
        // From here on this probe is somewhere a hand chose, and nothing
        // but another hand moves it. Before this flag existed there was
        // nothing to distinguish "hanging in its holster" from "placed on
        // a terminal", so re-parking had to be either always or never —
        // and it was never, which is why a placed probe had to ride the
        // case's facing to stay attached to its own lead.
        carried.insert(slot)
        model.setProbe(slot, to: model.nearestTerminal(
            to: bench, within: Self.snapRadius))
    }

    /// Probes a hand has taken off the case. The rest hang in the
    /// holster and follow the instrument wherever it goes.
    private var carried: Set<CircuitsModel.ProbeSlot> = []

    // MARK: Render

    /// Where the case stands, in the renderer's own (unscaled) frame.
    ///
    /// Owned HERE for the same reason `probeTip` is: `update` runs every
    /// frame, so anything it writes unconditionally cannot be dragged.
    /// The anchor used to be a `private static let` in the view and was
    /// re-applied sixty times a second, which is why a drag on the case
    /// would have had no visible effect even once the case had a
    /// collider to be dragged BY.
    private(set) var anchor: SIMD3<Float>

    func place(at position: SIMD3<Float>) {
        anchor = position
    }

    func update(viewer: SIMD3<Float>?, model: CircuitsModel) {
        let anchor = self.anchor
        // ON THE CHASSIS, NOT ON `root` — see `chassis`. Both of these
        // are the CASE moving. `root` stays at identity so that the
        // probes hanging off it are unmoved by either.
        chassis.position = anchor

        // Yaw only: a meter that pitched to meet a viewer looking down on
        // it would turn its own face edge-on.
        if let viewer, let facing = yaw(facing: viewer, from: anchor) {
            chassis.orientation = facing
        }

        // The dial POINTS at the selected mode, over the same 250° arc
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

        for slot in [CircuitsModel.ProbeSlot.red, .black] {
            guard let probe = probes[slot], let lead = leads[slot] else { continue }
            // The jack is a point ON THE CASE, so it goes wherever the
            // case has been put and turns however the case is turned.
            // The tip is in `root`'s frame — the renderer's — and the
            // lead is drawn between them, so it is the LEAD that absorbs
            // every move of the instrument. That is the right object to
            // absorb it: a lead is the slack between a fixed jack and a
            // hand-held point, and it is the only part of this assembly
            // that is supposed to change shape.
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

            // A straight run. A real lead sags, and a catenary would be
            // honest decoration — but it would also be a mesh rebuilt
            // every frame while a probe is moving, which is the one thing
            // the per-frame path may not do.
            lead.position = (jack + tip) / 2
            lead.orientation = VectorFieldArrows.rotationFromYAxis(to: direction)
            lead.scale = SIMD3(1, span, 1)
        }
    }

    // MARK: Display

    /// How often the face may redraw. A live meter reading changes in
    /// its last digit every frame, and every change bought a fresh
    /// `generateText` plus a material — ninety of each per second while
    /// probing, in the module that already carries the app's heaviest
    /// renderer.
    ///
    /// `Callout` solved exactly this and says why: eight updates a
    /// second is faster than anyone can read a changing number and a
    /// tenth of the work. A real bench meter samples a few times a
    /// second too, so this reads as an instrument rather than a
    /// compromise.
    private static let minimumInterval: Double = 1.0 / 8
    private var lastScreenTime: Double = 0

    private func setScreen(_ display: String, note: String, fault: Bool) {
        let colour = fault
            ? UIColor(red: 0.95, green: 0.45, blue: 0.2, alpha: 1) : accent
        // A FAULT IS NOT RATE-LIMITED. Everything else here is a number
        // ticking; a fault is the meter telling you it is being misused,
        // and that has to land on the frame it happens.
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

    /// Text meshes cached by (size, string): a live reading changes every
    /// frame and `generateText` builds a whole mesh on the main thread.
    /// Bounded, because a changing number generates unbounded strings.
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
