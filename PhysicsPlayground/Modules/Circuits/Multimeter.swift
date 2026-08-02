//
//  Multimeter.swift
//  Physics Playground — Circuit Workshop
//
//  The bench's meter, as an object you pick up rather than a switch in a
//  card.
//
//  It was a `Toggle` labelled "Multimeter" in a collapsed panel section,
//  with its reading printed underneath. Both halves were wrong for what
//  this is. A multimeter is not a display layer — it does not change what
//  the bench draws — so it had no business on the layers bank either,
//  which is where the module's other four switches went. It is a TOOL:
//  the one thing on this bench you use to ASK the circuit a question
//  instead of building it.
//
//  So it is a meter, standing on the bench, with its own lit face. Tap it
//  to arm it, tap two terminals, and the answer appears ON THE METER —
//  which is where you were already looking, and which is where a real
//  bench meter puts it.
//
//  (The interaction law, DECISIONS.md 2026-07-29: a quantity without
//  extent is a discrete choice and gets a labelled object in the room.
//  Armed-or-not is as discrete as a choice gets.)
//

import RealityKit
import RenderKit
import SwiftUI

@MainActor
final class Multimeter {
    let root = Entity()

    private let accent: UIColor
    private let face = ModelEntity()
    private let readingText = ModelEntity()
    private let readingMaterial: UnlitMaterial
    private var textCache: [String: MeshResource] = [:]
    private var lastReading = ""
    private var wasArmed: Bool?

    /// The casing. Deliberately dark and matte-metallic rather than
    /// glass: this is a built instrument, and the material canon says
    /// built things are `machined` while energy is `energized`.
    private static let bodySize = SIMD3<Float>(0.13, 0.085, 0.032)
    private static let faceSize = SIMD3<Float>(0.098, 0.034, 0.004)

    init(accent: UIColor) {
        self.accent = accent
        self.readingMaterial = UnlitMaterial(color: accent)

        let body = ModelEntity(
            mesh: .generateBox(size: Self.bodySize, cornerRadius: 0.012),
            materials: [Materials.machined(UIColor(white: 0.26, alpha: 1))])
        body.name = "multimeter-body"
        root.addChild(body)

        // The lit strip: dark when the meter is off, accent when armed.
        // A casing with a lit face on it, per the house rule that casings
        // beat glows indoors — the strip only reads as lit because
        // something dark sits behind it.
        face.model = ModelComponent(
            mesh: .generateBox(size: Self.faceSize, cornerRadius: 0.006),
            materials: [faceMaterial(armed: false)])
        face.position = [0, 0.012, Self.bodySize.z / 2 + 0.001]
        root.addChild(face)

        // The reading, billboarded so it is legible from wherever you
        // happen to be standing when you touch the second terminal.
        let textPivot = Entity()
        textPivot.components.set(BillboardComponent())
        textPivot.position = [0, -0.030, Self.bodySize.z / 2 + 0.004]
        textPivot.addChild(readingText)
        root.addChild(textPivot)

        let plate = HubScene.namePlate("Multimeter", accent: accent, size: 0.0108)
        plate.position = [0, Self.bodySize.y / 2 + 0.026, 0]
        root.addChild(plate)

        root.components.set(InputTargetComponent())
        // Collider matched to the casing, per the collider-≤-visual rule.
        // An oversized one here would shield the bench's own terminals —
        // and this meter stands among them by design, so it is exactly
        // the case that rule exists for.
        root.components.set(CollisionComponent(shapes: [
            .generateBox(size: Self.bodySize + SIMD3(0.01, 0.03, 0.01))
        ]))
        root.components.set(HoverEffectComponent())
        root.components.set(GroundingShadowComponent(castsShadow: true))

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Multimeter"
        root.components.set(accessibility)
    }

    /// Per frame: face the viewer, repaint on a state change, and show
    /// whatever the bench is currently able to tell you.
    ///
    /// `armed` and `reading` are read from the model every frame rather
    /// than remembered from the last tap — same contract as the layer
    /// bank, so a reset or an experiment disarming the meter moves the
    /// lamp too.
    func update(anchor: SIMD3<Float>, viewer: SIMD3<Float>?,
                armed: Bool, reading: CircuitsModel.MultimeterReading?) {
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

        if wasArmed != armed {
            wasArmed = armed
            face.model?.materials = [faceMaterial(armed: armed)]
            if var accessibility = root.components[AccessibilityComponent.self] {
                accessibility.value = LocalizedStringResource(
                    stringLiteral: armed ? "armed" : "off")
                root.components.set(accessibility)
            }
        }

        setReading(Self.text(armed: armed, reading: reading))
    }

    /// What the face says. An armed meter with nothing probed yet says so
    /// rather than showing a confident 0.00 V.
    private static func text(armed: Bool,
                             reading: CircuitsModel.MultimeterReading?) -> String {
        guard armed else { return "" }
        guard let reading else { return "tap two terminals" }
        let volts = String(format: "%.2f V", reading.deltaVolts)
        guard let amps = reading.inlineAmps else { return volts }
        return volts + String(format: "   %.1f mA", abs(amps) * 1000)
    }

    /// True when the tap armed or disarmed the meter.
    func handleTap(_ entity: Entity) -> Bool {
        guard root.isEnabled else { return false }
        var current: Entity? = entity
        while let candidate = current {
            if candidate === root {
                SoundPalette.play(.pop, on: root, volume: 0.35)
                return true
            }
            current = candidate.parent
        }
        return false
    }

    private func faceMaterial(armed: Bool) -> UnlitMaterial {
        var material = UnlitMaterial(
            color: armed ? accent : UIColor(white: 0.30, alpha: 1))
        material.blending = .transparent(opacity: armed ? 0.95 : 0.42)
        return material
    }

    /// Rewrites the face text, and only when it changed — this runs every
    /// frame, and a text mesh is far too expensive to rebuild at 90 Hz
    /// for a number that reads the same.
    private func setReading(_ string: String) {
        guard string != lastReading else { return }
        lastReading = string
        guard !string.isEmpty else {
            readingText.model = nil
            return
        }
        let mesh: MeshResource
        if let cached = textCache[string] {
            mesh = cached
        } else {
            if textCache.count > 240 { textCache.removeAll() }
            mesh = MeshResource.generateText(
                string, extrusionDepth: 0.0015,
                font: .systemFont(ofSize: 0.020, weight: .semibold))
            textCache[string] = mesh
        }
        readingText.model = ModelComponent(mesh: mesh, materials: [readingMaterial])
        let bounds = mesh.bounds
        readingText.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
    }
}
