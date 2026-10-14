//
//  SpatialTrackControl.swift
//  RenderKit — a labelled rail with a bead for a continuous quantity.
//
//  The value lives in the model; `refresh()` reads it but nothing here
//  ticks — a mounting view must call `refresh()` in its own update loop or
//  the bead shows a stale value after a reset.
//
//  `adjust(hand:)` takes the hand in the track's parent space with no
//  scale term. A scale on an ancestor cancels, but scaling the root itself
//  stretches the rail without stretching the range it maps. Do not scale a
//  track.

import Foundation
import RealityKit
import SwiftUI
import simd

@MainActor
public final class SpatialTrackControl {
    public let root = Entity()
    public let name: String

    private let layout: TrackLayout
    private let range: ClosedRange<Double>
    private let read: () -> Double
    private let write: (Double) -> Void
    private let format: (Double) -> String
    /// A second, quieter line under the rail — for a rail whose value
    /// Derives something (the ΔV rail's E = V/d). Re-evaluated every
    /// refresh, since the derived quantity can move without the value
    /// moving. Most rails pass nothing.
    private let subtitle: ((Double) -> String)?
    private var subtitleLabel: BackedLabel?
    /// Value plus subtitle merged, so the spoken reading never drops the
    /// derived line when only the value changed.
    private var lastSpokenValue = ""

    private let bead = ModelEntity()
    private let filled = ModelEntity()
    private let valueText = ModelEntity()
    /// The dark plate behind the value — rebuilt with the label, sized
    /// to the glyph run it backs.
    private var valueBacking: ModelEntity?
    private let valueMaterial: UnlitMaterial
    private var labelCache: [String: MeshResource] = [:]
    private var lastLabel = ""
    private var isDragging = false

    /// - center: position within the entity this track is added to.
    /// - normal: which way the rail faces — the reader's side.
    public init(name: String,
                center: SIMD3<Float>,
                normal: SIMD3<Float>,
                accent: UIColor,
                range: ClosedRange<Double>,
                layout: TrackLayout = TrackLayout(),
                read: @escaping () -> Double,
                write: @escaping (Double) -> Void,
                format: @escaping (Double) -> String,
                subtitle: ((Double) -> String)? = nil,
                spokenName: String? = nil) {
        self.name = name
        self.layout = layout
        self.range = range
        self.read = read
        self.write = write
        self.format = format
        self.subtitle = subtitle
        self.valueMaterial = UnlitMaterial(color: accent)

        root.name = name
        root.position = center
        root.orientation = Self.facing(normal)

        let length = Float(layout.length)

        // The rail: a dark frosted-glass casing so the lit fill reads
        // against it (casings beat glows indoors).
        let rail = ModelEntity(
            mesh: Primitives.box(size: [length, 0.010, 0.010], cornerRadius: 0.005),
            materials: [Materials.frostedGlass(opacity: 0.64)])
        root.addChild(rail)

        // The travelled part, lit: how far along the range you are.
        let lit = Materials.unlit(accent, opacity: 0.85)
        filled.model = ModelComponent(
            mesh: Primitives.box(size: [1, 0.011, 0.011], cornerRadius: 0.005),
            materials: [lit])
        root.addChild(filled)

        // End ticks.
        let tickMaterial = Materials.unlit(.white, opacity: 0.45)
        for side in [-1, 1] as [Float] {
            let tick = ModelEntity(
                mesh: Primitives.box(size: [0.003, 0.022, 0.003]),
                materials: [tickMaterial])
            tick.position = [side * length / 2, 0, 0]
            root.addChild(tick)
        }

        // The bead: the value as an object.
        bead.model = ModelComponent(mesh: Primitives.sphere(radius: 0.016),
                                    materials: [Materials.grip(accent,
                                                               roughness: 0.18)])
        root.addChild(bead)

        let textPivot = Entity()
        textPivot.components.set(BillboardComponent())
        textPivot.position = [0, 0.040, 0]
        textPivot.addChild(valueText)
        root.addChild(textPivot)

        // The derived line hangs under the rail — the one direction clear
        // of both the rail and the apparatus above it.
        if subtitle != nil {
            let pivot = Entity()
            pivot.components.set(BillboardComponent())
            pivot.position = [0, -0.036, 0]
            let label = BackedLabel(size: 0.02)
            pivot.addChild(label.root)
            root.addChild(pivot)
            subtitleLabel = label
        }

        // Whole-track target so grabbing anywhere on the rail sets a value.
        // A box, not a sphere: a sphere covering a 26 cm rail is a 29 cm
        // ball that (hit-testing uses colliders, not visible geometry)
        // shields the apparatus behind it. An input-targetable collider
        // must be no larger than the thing it represents — generous along
        // the rail, never across it.
        root.components.set(InputTargetComponent())
        root.components.set(CollisionComponent(shapes: [
            Primitives.collisionBox(size: [length + 0.03, 0.05, 0.05])
        ]))
        root.components.set(HoverEffectComponent())
        root.components.set(GroundingShadowComponent(castsShadow: true))

        // VoiceOver adjust: a twentieth of the range per step, written
        // through `write` — the same function the drag calls — so a hand
        // and a keystroke cannot disagree about the ends.
        SpatialActions.attach(
            // `spokenName` when the entity name is an identifier: the Physics
            // box's rails were read aloud as "physics-gravity" until 2026-10-14.
            to: root, label: "\(spokenName ?? name). Drag the bead along the rail to set it.",
            value: format(read()),
            adjust: { [weak self] steps in self?.nudge(by: steps) })

        refresh()
    }

    /// Whether the track is present and live. Guards a drag already in
    /// Flight when the apparatus is switched off: the gesture keeps
    /// delivering `onChanged`, so without this the track writes to a model
    /// nobody is looking at.
    public var isEnabled: Bool {
        get { root.isEnabled }
        set {
            root.isEnabled = newValue
            if !newValue { isDragging = false }
        }
    }

    public func owns(_ entity: Entity) -> Bool {
        guard root.isEnabled else { return false }
        var current: Entity? = entity
        while let candidate = current {
            if candidate === root { return true }
            current = candidate.parent
        }
        return false
    }

    public var isAdjusting: Bool { isDragging }

    /// Where the bead currently sits, in the track's own frame. The bead's
    /// place is the value.
    public var beadOffset: SIMD3<Float> { bead.position }

    /// Sets the value from a hand position in the track's parent space.
    /// Absolute: wherever along the rail the hand is, that is the value —
    /// no start offset, so a drag beginning mid-rail does not shift the map.
    @discardableResult
    public func adjust(hand: SIMD3<Double>) -> Bool {
        guard root.isEnabled else { return false }
        isDragging = true
        let local = root.orientation.inverse.act(
            SIMD3<Float>(hand) - root.position)
        let fraction = layout.fraction(forHandInTrackSpace: SIMD3<Double>(local))
        write(layout.value(forFraction: fraction, in: range))
        refresh()
        return true
    }

    public func endAdjust() { isDragging = false }

    /// One VoiceOver increment or decrement, in the value's own units.
    public func nudge(by steps: Double) {
        let span = range.upperBound - range.lowerBound
        let next = read() + steps * span / 20
        write(min(max(next, range.lowerBound), range.upperBound))
        refresh()
    }

    /// Moves the bead and the fill to the model's current value.
    public func refresh() {
        let fraction = layout.fraction(forValue: read(), in: range)
        bead.position = SIMD3<Float>(layout.offset(forFraction: fraction))

        // The fill grows from the low end: scaled and shifted, not redrawn.
        let length = Float(layout.length)
        let travelled = max(length * Float(fraction), 1e-4)
        filled.scale = [travelled, 1, 1]
        filled.position = [-length / 2 + travelled / 2, 0, 0]

        setLabel(format(read()))

        // The spoken reading, whether or not there is a derived line.
        let spoken = subtitle.map { "\(lastLabel), \($0(read()))" } ?? lastLabel
        if let subtitle {
            subtitleLabel?.setText(subtitle(read()),
                                   color: UIColor(white: 0.95, alpha: 1))
        }
        if spoken != lastSpokenValue {
            lastSpokenValue = spoken
            // Republish, never rebuild: a fresh `AccessibilityComponent`
            // carries empty `systemActions` and would strip the increment.
            SpatialActions.republish(value: spoken, on: root)
        }
    }

    /// Rewrites the value text, only when it changed — `refresh()` runs
    /// every frame and the mesh and accessibility component are too
    /// expensive to rebuild at 90 Hz for an unchanged number.
    private func setLabel(_ string: String) {
        guard string != lastLabel else { return }
        lastLabel = string

        // VoiceOver reads the setting, not just the name.
        if var accessibility = root.components[AccessibilityComponent.self] {
            accessibility.value = LocalizedStringResource(stringLiteral: string)
            root.components.set(accessibility)
        }

        let mesh: MeshResource
        if let cached = labelCache[string] {
            mesh = cached
        } else {
            if labelCache.count > 240 { labelCache.removeAll() }
            mesh = MeshResource.generateText(
                string, extrusionDepth: 0.002,
                font: .systemFont(ofSize: 0.028, weight: .semibold))
            labelCache[string] = mesh
        }
        valueText.model = ModelComponent(mesh: mesh, materials: [valueMaterial])
        let bounds = mesh.bounds
        valueText.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]

        // Dark plate behind the number. A sibling of the glyphs, lifted to
        // the run's vertical centre (the text is x-centred only).
        valueBacking?.removeFromParent()
        let plate = BackedLabel.backing(behind: bounds, size: 0.028)
        plate.position.y = (bounds.min.y + bounds.max.y) / 2
        valueText.parent?.addChild(plate)
        valueBacking = plate
    }

    /// A quaternion whose local +Z maps to `normal`, +Y kept upright, so the
    /// rail runs horizontally across the reader's view.
    private static func facing(_ normal: SIMD3<Float>) -> simd_quatf {
        let z = simd_length(normal) > 1e-6 ? simd_normalize(normal) : SIMD3(0, 0, 1)
        let reference: SIMD3<Float> = abs(z.y) < 0.95 ? [0, 1, 0] : [1, 0, 0]
        let x = simd_normalize(simd_cross(reference, z))
        let y = simd_cross(z, x)
        return simd_quatf(simd_float3x3(columns: (x, y, z)))
    }
}
