//
//  SpatialTrackControl.swift
//  RenderKit
//
//  The app's instrument for a continuous quantity: a labelled rail with a
//  bead you put where you want it.
//
//  Replaces `SpatialDial`, which the owner rejected (2026-07-29). See
//  `TrackLayout` for why an absolute control beats a relative one — the
//  short version is that a bead's position shows the setting and a
//  needle's rotation does not.
//
//  Clears the same bar the interaction law sets for anything replacing a
//  slider: visible without being looked for (it is always there, and its
//  value is legible from across the room), operable without being
//  discovered (a bead on a rail affords dragging with no instruction), and
//  reachable in the simulator (a mouse drag along the rail is exactly the
//  gesture).
//
//  The value lives in the model, and `refresh()` reads it — but note that
//  is a promise about the CALLER: nothing here ticks. A mounting view must
//  call `refresh()` in its own update loop or the bead will keep showing
//  the value it was last dragged to while a reset moves the model out from
//  under it.
//
//  `adjust(hand:)` takes the hand in the track's PARENT space and applies
//  no scale term, which is correct as long as nothing scales the track's
//  own `root`. A scale on an ANCESTOR cancels — the hand and
//  `root.position` are both expressed in the parent's frame, so they shrink
//  together — but scaling the root itself would stretch the rail on screen
//  without stretching the range it maps, and the far half of a visibly 2×
//  rail would clamp at the top of the range. Do not scale a track.
//

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

    private let bead = ModelEntity()
    private let filled = ModelEntity()
    private let valueText = ModelEntity()
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
                format: @escaping (Double) -> String) {
        self.name = name
        self.layout = layout
        self.range = range
        self.read = read
        self.write = write
        self.format = format
        self.valueMaterial = UnlitMaterial(color: accent)

        root.name = name
        root.position = center
        root.orientation = Self.facing(normal)

        let length = Float(layout.length)

        // The rail: a dark glass casing so the lit fill reads against it,
        // per the house rule that casings beat glows indoors. Frosted
        // rather than lacquered — same dark scrim, now scattering, so it
        // belongs to the same family as the plates and discs it stands
        // beside.
        let rail = ModelEntity(
            mesh: .generateBox(size: [length, 0.010, 0.010], cornerRadius: 0.005),
            materials: [Materials.frostedGlass(opacity: 0.64)])
        root.addChild(rail)

        // The travelled part, lit: how far along the range you are, readable
        // without finding the bead first.
        var lit = UnlitMaterial(color: accent)
        lit.blending = .transparent(opacity: 0.85)
        filled.model = ModelComponent(
            mesh: .generateBox(size: [1, 0.011, 0.011], cornerRadius: 0.005),
            materials: [lit])
        root.addChild(filled)

        // End ticks — the range has ends, and they should look like ends.
        var tickMaterial = UnlitMaterial(color: .white)
        tickMaterial.blending = .transparent(opacity: 0.45)
        for side in [-1, 1] as [Float] {
            let tick = ModelEntity(
                mesh: .generateBox(size: [0.003, 0.022, 0.003]),
                materials: [tickMaterial])
            tick.position = [side * length / 2, 0, 0]
            root.addChild(tick)
        }

        // The bead: the value, as an object, in the shared grip recipe.
        bead.model = ModelComponent(mesh: .generateSphere(radius: 0.016),
                                    materials: [Materials.grip(accent,
                                                               roughness: 0.18)])
        root.addChild(bead)

        let textPivot = Entity()
        textPivot.components.set(BillboardComponent())
        textPivot.position = [0, 0.040, 0]
        textPivot.addChild(valueText)
        root.addChild(textPivot)

        // Whole-track target: grabbing anywhere on the rail is a legitimate
        // way to set a value, and hunting for a 1.6 cm bead is not.
        //
        // A BOX, not a sphere, and this is the part that took a bug to
        // learn. `Grabbable.configureTouchTarget` only makes spheres, and
        // the radius that covers a 26 cm rail end-to-end is 14 cm — a 29 cm
        // ball around an object 1 cm thick. Hit-testing uses colliders and
        // not visible geometry, so that ball shields everything within a
        // hand's width of the rail in EVERY direction, including the
        // apparatus it is bolted to. That is the `SpatialScaleHandle`
        // failure (DECISIONS, 2026-07-29 "the invisible scale plate is
        // banned") at one-eighth the size, and the rule it left behind is
        // absolute: an input-targetable collider must be no larger than the
        // thing it represents. Generous ALONG the rail is the affordance;
        // generous across it is a trap.
        root.components.set(InputTargetComponent())
        root.components.set(CollisionComponent(shapes: [
            .generateBox(size: [length + 0.03, 0.05, 0.05])
        ]))
        root.components.set(HoverEffectComponent())
        root.components.set(GroundingShadowComponent(castsShadow: true))

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(name). Drag the bead along the rail to set it.")
        root.components.set(accessibility)

        refresh()
    }

    /// Whether the track is present and live.
    ///
    /// An instrument that belongs to an apparatus disappears with it, and
    /// `root.isEnabled` alone is not enough: hit-testing stops, but `owns`
    /// and `adjust` are plain function calls a caller can still make. The
    /// case that bites is a drag already IN FLIGHT when the apparatus is
    /// switched off — the gesture keeps delivering `onChanged`, and without
    /// this guard the track keeps writing to a model nobody is looking at.
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
    /// place IS the value — this is the claim the whole control rests on,
    /// so it is worth being able to ask, both for a caller wanting to hang
    /// something off the bead and for a test wanting to check it.
    public var beadOffset: SIMD3<Float> { bead.position }

    /// Sets the value from a hand position in the track's PARENT space.
    ///
    /// Absolute: wherever along the rail the hand is, that is the value —
    /// no start offset, nothing to accumulate, so a drag that begins in the
    /// middle of the rail does not shift the mapping.
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

    /// Moves the bead and the fill to the model's current value.
    public func refresh() {
        let fraction = layout.fraction(forValue: read(), in: range)
        bead.position = SIMD3<Float>(layout.offset(forFraction: fraction))

        // The fill grows from the low end, so it is scaled and shifted
        // rather than redrawn.
        let length = Float(layout.length)
        let travelled = max(length * Float(fraction), 1e-4)
        filled.scale = [travelled, 1, 1]
        filled.position = [-length / 2 + travelled / 2, 0, 0]

        setLabel(format(read()))
    }

    /// Rewrites the value text, and only when it has actually changed —
    /// `refresh()` runs every frame, and both the text mesh and the
    /// accessibility component are far too expensive to rebuild at 90 Hz
    /// for a number that reads the same.
    private func setLabel(_ string: String) {
        guard string != lastLabel else { return }
        lastLabel = string

        // VoiceOver reads the setting, not just the name. This matters more
        // than it looks: a track replaces a `Slider`, and a slider is
        // already an adjustable element that speaks its value. Migrating
        // without this trades a control someone could operate blind for one
        // they cannot — a capability lost rather than moved.
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
