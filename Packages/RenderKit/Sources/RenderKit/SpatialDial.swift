//
//  SpatialDial.swift
//  RenderKit
//
//  A diegetic control: a physical gauge you reach out and TWIST, not a
//  slider in a glass box. A ring of tick marks with a glowing pointer
//  and the value rendered as 3D text on the dial itself. Turning it is
//  the control — the hand's angle around the dial's face drives a
//  value, accumulated across the whole gesture so it survives multiple
//  turns.
//
//  Built once in a LOCAL frame (face normal = +Z, up = +Y) and
//  oriented into the room, so the twist math is a plain atan2 in the
//  face plane. The MODEL owns the value (like every control in this
//  app); the renderer calls setValueFraction each frame to point the
//  needle, and the space view feeds hand angles through DialDrag.
//

import Foundation
import RealityKit
import SwiftUI
import simd

/// The pure twist math, split out so it can be unit-tested without a
/// scene: accumulate the signed, wrap-safe change in hand angle into a
/// value, clamped to range.
public struct DialDrag: Sendable {
    public let name: String
    private let range: ClosedRange<Double>
    private let valuePerRadian: Double
    private var lastAngle: Double
    private(set) public var value: Double

    /// `turnsForFullSweep`: how much of a full turn moves the value
    /// across its whole range (0.75 = three-quarter turn, gauge-like).
    public init(name: String, startValue: Double, startAngle: Double,
                range: ClosedRange<Double>, turnsForFullSweep: Double = 0.75) {
        self.name = name
        self.range = range
        self.value = min(max(startValue, range.lowerBound), range.upperBound)
        self.lastAngle = startAngle
        let span = range.upperBound - range.lowerBound
        self.valuePerRadian = span / (2 * .pi * max(turnsForFullSweep, 1e-6))
    }

    /// Feeds the current hand angle; returns the new value. The frame's
    /// angle change is unwrapped to (−π, π] so a needle never jumps a
    /// full turn when atan2 rolls over.
    @discardableResult
    public mutating func advance(toAngle angle: Double) -> Double {
        var delta = angle - lastAngle
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        lastAngle = angle
        value = min(max(value + delta * valuePerRadian, range.lowerBound), range.upperBound)
        return value
    }
}

@MainActor
public final class SpatialDial {
    public let root = Entity()
    public let name: String

    /// The gauge sweeps ±150° (300° total) like a real instrument.
    private static let sweep = Float.pi * 300 / 180

    private let center: SIMD3<Float>
    private let orientation: simd_quatf
    private let needlePivot = Entity()
    private let valueText = ModelEntity()
    private let valueMaterial: UnlitMaterial
    private var labelCache: [String: MeshResource] = [:]
    private var lastLabel = ""

    /// - normal: the face direction (the twist axis), pointing at the
    ///   viewer. - accent: the dial's glow color.
    public init(name: String, center: SIMD3<Float>, normal: SIMD3<Float>,
                radius: Float = 0.05, accent: UIColor) {
        self.name = name
        self.center = center
        self.orientation = Self.facing(normal)
        self.valueMaterial = UnlitMaterial(color: accent)

        root.name = name
        root.position = center
        root.orientation = orientation

        // The ring: a torus built from a closed circle via TubeMesh.
        let segments = 48
        let circle: [SIMD3<Float>] = (0...segments).map { i in
            let a = 2 * Float.pi * Float(i) / Float(segments)
            return SIMD3(cos(a), sin(a), 0) * radius
        }
        var ringMaterial = UnlitMaterial(color: accent)
        ringMaterial.blending = .transparent(opacity: 0.9)
        if let ring = TubeMesh.tube(lines: [circle], radius: 0.0035, sides: 6) {
            root.addChild(ModelEntity(mesh: ring, materials: [ringMaterial]))
        }
        // A faint larger halo ring — the glow that reads as light, not line.
        var haloMaterial = UnlitMaterial(color: accent)
        haloMaterial.blending = .transparent(opacity: 0.16)
        let halo: [SIMD3<Float>] = (0...segments).map { i in
            let a = 2 * Float.pi * Float(i) / Float(segments)
            return SIMD3(cos(a), sin(a), 0) * (radius + 0.006)
        }
        if let haloMesh = TubeMesh.tube(lines: [halo], radius: 0.0075, sides: 6) {
            root.addChild(ModelEntity(mesh: haloMesh, materials: [haloMaterial]))
        }

        // Tick marks around the 300° arc — the gauge face.
        var tickMaterial = UnlitMaterial(color: .white)
        tickMaterial.blending = .transparent(opacity: 0.4)
        let tickMesh = MeshResource.generateBox(size: [0.002, 0.011, 0.002])
        for step in 0...10 {
            let fraction = Float(step) / 10
            let angle = -Self.sweep / 2 + Self.sweep * fraction
            let holder = Entity()
            holder.orientation = simd_quatf(angle: angle, axis: [0, 0, 1])
            let tick = ModelEntity(mesh: tickMesh, materials: [tickMaterial])
            tick.position = [0, radius, 0]
            holder.addChild(tick)
            root.addChild(holder)
        }

        // The needle: a bright bar with a glowing bead at the rim.
        let needle = ModelEntity(
            mesh: .generateBox(size: [0.004, radius * 0.9, 0.004], cornerRadius: 0.002),
            materials: [UnlitMaterial(color: accent)])
        needle.position = [0, radius * 0.45, 0.002]
        let bead = ModelEntity(
            mesh: .generateSphere(radius: 0.008),
            materials: [UnlitMaterial(color: accent)])
        bead.position = [0, radius, 0.002]
        needlePivot.addChild(needle)
        needlePivot.addChild(bead)
        root.addChild(needlePivot)

        // Center hub.
        var hubMaterial = PhysicallyBasedMaterial()
        hubMaterial.baseColor = .init(tint: UIColor(white: 0.16, alpha: 1))
        hubMaterial.roughness = 0.3
        hubMaterial.metallic = 0.8
        let hub = ModelEntity(
            mesh: .generateCylinder(height: 0.006, radius: radius * 0.34),
            materials: [hubMaterial])
        hub.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        root.addChild(hub)

        // The value, in 3D, billboarded so the number always faces you.
        let textPivot = Entity()
        textPivot.components.set(BillboardComponent())
        textPivot.position = [0, -radius - 0.028, 0.01]
        textPivot.addChild(valueText)
        root.addChild(textPivot)

        Grabbable.configureTouchTarget(root, collisionRadius: radius + 0.025)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(name) dial. Twist it to change the value.")
        root.components.set(accessibility)
    }

    /// Points the needle to a 0…1 fraction of the gauge sweep.
    public func setValueFraction(_ fraction: Double) {
        let f = Float(min(max(fraction, 0), 1))
        needlePivot.orientation = simd_quatf(
            angle: -Self.sweep / 2 + Self.sweep * f, axis: [0, 0, 1])
    }

    /// Sets the 3D value label (string-cached; call every frame freely).
    public func setLabel(_ string: String) {
        guard string != lastLabel else { return }
        lastLabel = string
        let mesh: MeshResource
        if let cached = labelCache[string] {
            mesh = cached
        } else {
            if labelCache.count > 240 { labelCache.removeAll() }
            mesh = MeshResource.generateText(
                string, extrusionDepth: 0.002,
                font: .systemFont(ofSize: 0.03, weight: .semibold))
            labelCache[string] = mesh
        }
        valueText.model = ModelComponent(mesh: mesh, materials: [valueMaterial])
        let bounds = mesh.bounds
        valueText.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
    }

    /// The hand's angle around the dial's face, in the local frame —
    /// the quantity DialDrag accumulates.
    public func handAngle(_ handWorld: SIMD3<Double>) -> Double {
        let local = orientation.inverse.act(SIMD3<Float>(handWorld) - center)
        return Double(atan2(local.y, local.x))
    }

    /// A quaternion whose local +Z maps to `normal`, local +Y kept as
    /// upright as possible.
    private static func facing(_ normal: SIMD3<Float>) -> simd_quatf {
        let z = simd_length(normal) > 1e-6 ? simd_normalize(normal) : SIMD3(0, 0, 1)
        let reference: SIMD3<Float> = abs(z.y) < 0.95 ? [0, 1, 0] : [1, 0, 0]
        let x = simd_normalize(simd_cross(reference, z))
        let y = simd_cross(z, x)
        return simd_quatf(simd_float3x3(columns: (x, y, z)))
    }
}
