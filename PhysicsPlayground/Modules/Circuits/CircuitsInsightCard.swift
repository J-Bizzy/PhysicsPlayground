//
//  CircuitsInsightCard.swift
//  Physics Playground — Circuits module
//
//  THE RUNNING COMMENTARY, WHICH HAD TWELVE WRITERS AND NO READERS.
//
//  `CircuitsModel.insightText` is set in twelve places — the capacitor's
//  charge curve as a percentage, which component is dissipating the most
//  power right now, what Electron View is actually showing you, why a
//  fuse blew, and one paragraph for each of the five presets. Every one
//  of them was written to be read by somebody standing at the bench, and
//  `grep insightText` found not a single reader anywhere in the app.
//
//  They were written for the window panel deleted on 2026-08-01 and
//  never given a surface. This is that surface.
//
//  ── WHY THIS IS NOT THE TEXT BOX THAT WAS JUST DELETED ──
//
//  The owner removed `FirstRunHint` on 2026-08-08 — a card at head
//  height naming the module — with the verdict that it was unnecessary
//  and in the way, and putting a different card in the same room a day
//  later needs an answer.
//
//  The answer is that the hint said the same thing every time you
//  entered, about the app, and this says a different thing about the
//  circuit you have just built. It is absent whenever there is nothing
//  to say — an empty bench has no insight, so there is no card — and it
//  changes when the physics changes, which is the difference between a
//  readout and a sign. If it ever repeats itself it is behaving like the
//  hint and should go the same way.
//
//  NO COLLIDER, ON PURPOSE. It stands above the bench, inside the volume
//  a part can be dragged into, and a readout with an input target there
//  would shield components from every pinch — the failure the clearance
//  rules exist to prevent. Nothing about a sentence needs to be
//  pinchable, so nothing here is.
//

import Foundation
import RealityKit
import RenderKit
import SwiftUI

@MainActor
final class CircuitsInsightCard {
    let root = Entity()

    /// How wide the paragraph is allowed to run before it wraps.
    ///
    /// Slightly narrower than the bench, so the card reads as belonging
    /// to the apparatus rather than as a banner over the room. Two
    /// sentences at this width and size come out around three lines.
    static let wrapWidth: CGFloat = 0.62
    static let textSize: CGFloat = 0.030

    private var label: ModelEntity?
    private var backing: ModelEntity?
    private var lastText = ""
    private var reveal: Float = 0

    init() {
        root.isEnabled = false
        root.components.set(BillboardComponent())
    }

    /// `text` empty means there is nothing to say, and the card goes.
    func update(text: String, anchor: SIMD3<Float>, dt: Double) {
        root.position = anchor
        reveal = Motion.ease(reveal, toward: text.isEmpty ? 0 : 1, dt: dt)
        root.isEnabled = reveal > 0.02
        if reveal < 0.999 {
            root.components.set(OpacityComponent(opacity: reveal))
        } else {
            root.components.remove(OpacityComponent.self)
        }
        guard !text.isEmpty, text != lastText else { return }
        lastText = text
        rebuild(text)
    }

    /// REBUILT ONLY WHEN THE STRING CHANGES, like every other text
    /// surface in this app. `update` runs every frame and a text mesh is
    /// the most expensive thing here by an order of magnitude.
    private func rebuild(_ text: String) {
        label?.removeFromParent()
        backing?.removeFromParent()

        let mesh = Callout.textMesh(text, size: Self.textSize,
                                    wrapWidth: Self.wrapWidth)
        var material = UnlitMaterial(color: UIColor(white: 0.96, alpha: 1))
        material.blending = .opaque
        let model = ModelEntity(mesh: mesh, materials: [material])
        let bounds = mesh.bounds
        model.position = [-(bounds.min.x + bounds.max.x) / 2,
                          -(bounds.min.y + bounds.max.y) / 2, 0]

        // A SIBLING of the centred glyphs, never a child — the model
        // above is shifted to centre its run on the pivot, so a plate
        // parented to it would land off the text by exactly the centring
        // shift. `Callout` records having made that mistake.
        let plate = BackedLabel.backing(behind: bounds, size: Self.textSize)
        root.addChild(plate)
        root.addChild(model)
        backing = plate
        label = model

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: text)
        root.components.set(accessibility)
    }
}
