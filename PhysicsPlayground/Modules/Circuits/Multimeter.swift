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
//  dial's is the dial, each probe's is its HANDLE, and the body has none
//  at all. An oversized grab box would shield the very terminals you are
//  trying to probe — the `SpatialScaleHandle` failure, in the module
//  where it would be hardest to notice.
//

import RealityKit
import RenderKit
import SwiftUI

@MainActor
final class Multimeter {
    let root = Entity()

    /// Where the two probe tips currently are, in the bench's space.
    ///
    /// Owned HERE rather than in a `@State`: the render loop reads them
    /// every frame, and a `@State` read from inside a RealityKit closure
    /// comes back stale — the same reason `RingState` is a class.
    private(set) var probeTip: [CircuitsModel.ProbeSlot: SIMD3<Float>] = [:]

    private let accent: UIColor
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
    /// How near a probe tip must get before it latches onto a terminal.
    ///
    /// Generous, because a 3 mm terminal is not a target anyone hits
    /// exactly in mid-air — and still unambiguous, because the two
    /// terminals of one component are further apart than this.
    static let snapRadius: Double = 0.035

    init(accent: UIColor) {
        self.accent = accent

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
        root.addChild(body)

        // The dial is its own entity so it can TURN — what the user sees
        // rotate is this pointer riding the case's moulded dial.
        dial.name = "meter-dial"
        dial.position = [0, -0.020, 0.0185]
        let pointer = ModelEntity(
            mesh: .generateBox(size: [0.0038, 0.026, 0.0022], cornerRadius: 0.001),
            materials: [UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))])
        pointer.position = [0, 0.009, 0]
        dial.addChild(pointer)
        dial.components.set(InputTargetComponent())
        dial.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: 0.030)]))
        dial.components.set(HoverEffectComponent())
        root.addChild(dial)

        // The reading, sitting in the bezel the mesh already provides.
        screen.position = [0, 0.044, 0.019]
        root.addChild(screen)
        noteText.position = [0, 0.026, 0.019]
        root.addChild(noteText)

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

            // Parked hanging BELOW the jacks until a hand takes one.
            //
            // Far enough below that the handles do not cross the dial:
            // the probe is drawn from its tip back toward the jack, so a
            // short park length lays both handles straight over the one
            // control on the front of the instrument.
            probeTip[slot] = (Self.jack[slot] ?? .zero) + SIMD3(0, -0.125, 0.03)
        }

        let plate = HubScene.namePlate("Multimeter", accent: accent, size: 0.0108)
        plate.position = [0, 0.108, 0]
        root.addChild(plate)

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
    /// zoom. So the probe is DRAWN at `local` in the meter's own frame
    /// and LATCHED against `bench` in the terminals' frame. Using one for
    /// both would put the tip where the terminal looks rather than where
    /// it is, and the error would grow with the zoom.
    func moveProbe(_ slot: CircuitsModel.ProbeSlot,
                   local: SIMD3<Float>, bench: SIMD3<Double>,
                   model: CircuitsModel) {
        probeTip[slot] = local
        model.setProbe(slot, to: model.nearestTerminal(
            to: bench, within: Self.snapRadius))
    }

    // MARK: Render

    func update(anchor: SIMD3<Float>, viewer: SIMD3<Float>?,
                model: CircuitsModel) {
        root.position = anchor

        // Yaw only: a meter that pitched to meet a viewer looking down on
        // it would turn its own face edge-on.
        if let viewer {
            let flat = SIMD3<Float>(viewer.x - anchor.x, 0, viewer.z - anchor.z)
            if simd_length(flat) > 1e-4 {
                root.orientation = simd_quatf(from: [0, 0, 1],
                                              to: simd_normalize(flat))
            }
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
            let jack = Self.jack[slot] ?? .zero
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

    private func setScreen(_ display: String, note: String, fault: Bool) {
        let colour = fault
            ? UIColor(red: 0.95, green: 0.45, blue: 0.2, alpha: 1) : accent
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
