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
//  The value lives in the model. `refresh()` reads it every frame, so a
//  reset or an experiment moves the bead too.
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

        // The rail: a dark casing so the lit part reads against it, per the
        // house rule that casings beat glows indoors.
        var casing = PhysicallyBasedMaterial()
        casing.baseColor = .init(tint: UIColor(white: 0.06, alpha: 1))
        casing.roughness = 0.35
        casing.clearcoat = .init(floatLiteral: 0.8)
        let rail = ModelEntity(
            mesh: .generateBox(size: [length, 0.010, 0.010], cornerRadius: 0.005),
            materials: [casing])
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

        // The bead: the value, as an object.
        var beadMaterial = PhysicallyBasedMaterial()
        beadMaterial.baseColor = .init(tint: accent)
        beadMaterial.roughness = 0.18
        beadMaterial.clearcoat = .init(floatLiteral: 1.0)
        bead.model = ModelComponent(mesh: .generateSphere(radius: 0.016),
                                    materials: [beadMaterial])
        root.addChild(bead)

        let textPivot = Entity()
        textPivot.components.set(BillboardComponent())
        textPivot.position = [0, 0.040, 0]
        textPivot.addChild(valueText)
        root.addChild(textPivot)

        // Whole-track target: grabbing anywhere on the rail is a legitimate
        // way to set a value, and hunting for a 1.6 cm bead is not.
        Grabbable.configureTouchTarget(root, collisionRadius: layout.length > 0
                                       ? Float(layout.length) * 0.55 : 0.1)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(name). Drag the bead along the rail to set it.")
        root.components.set(accessibility)

        refresh()
    }

    public func owns(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === root { return true }
            current = candidate.parent
        }
        return false
    }

    public var isAdjusting: Bool { isDragging }

    /// Sets the value from a hand position in the track's PARENT space.
    ///
    /// Absolute: wherever along the rail the hand is, that is the value —
    /// no start offset, nothing to accumulate, so a drag that begins in the
    /// middle of the rail does not shift the mapping.
    @discardableResult
    public func adjust(hand: SIMD3<Double>) -> Bool {
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

    private func setLabel(_ string: String) {
        guard string != lastLabel else { return }
        lastLabel = string
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
