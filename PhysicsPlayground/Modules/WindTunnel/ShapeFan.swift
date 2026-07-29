//
//  ShapeFan.swift
//  Physics Playground — Wind Tunnel module
//
//  The test-body picker, in the palette bead's own grammar: pinch the
//  Shapes petal and a fan of every available body unfolds above the
//  test section — each a labelled disc — pick one and the fan folds.
//  This replaces a blind "next shape" cycle petal, which walked the
//  user through the flat disc and the spinning cylinder with no
//  warning of either: it read as the model glitching, not a choice.
//

import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI

@MainActor
final class ShapeFan {
    let root = Entity()
    private var discs: [(body: DragBody, entity: ModelEntity)] = []
    private(set) var isOpen = false
    private var openness: Float = 0
    var onSelect: ((DragBody) -> Void)?

    /// The icon each body wears. A missing symbol just means a disc
    /// with only its label — never a crash.
    private static let symbols: [DragBody: String] = [
        .cylinder: "capsule.portrait.fill",
        .sphere: "circle.fill",
        .teardrop: "drop.fill",
        .cube: "cube.fill",
        .flatDisc: "smallcircle.filled.circle",
        .cone: "cone.fill",
        .car: "car.fill",
        .truck: "box.truck.fill",
        .plane: "airplane",
    ]

    init() {
        root.isEnabled = false
        for body in DragBody.allCases {
            let disc = Self.makeDisc(body)
            root.addChild(disc)
            discs.append((body, disc))
        }
    }

    func toggle() { isOpen.toggle() }
    func close() { isOpen = false }

    /// Per frame: anchor over the test body, face the viewer, unfold.
    func update(anchor: SIMD3<Float>, viewer: SIMD3<Float>?, dt: Double) {
        let target: Float = isOpen ? 1 : 0
        let rate = Float(min(dt * 9, 1))
        openness += (target - openness) * rate
        if abs(openness - target) < 0.004 { openness = target }
        root.isEnabled = openness > 0.02
        guard root.isEnabled else { return }
        root.position = anchor

        if let viewer {
            let flat = SIMD3<Float>(viewer.x - anchor.x, 0, viewer.z - anchor.z)
            if simd_length(flat) > 1e-4 {
                root.orientation = simd_quatf(from: [0, 0, 1],
                                              to: simd_normalize(flat))
            }
        }

        // A 150° fan opening upward, the palette ring's own gesture.
        let span: Float = 150 * .pi / 180
        let count = max(discs.count - 1, 1)
        for (index, item) in discs.enumerated() {
            let delay = Float(index) * 0.045
            let own = max(0, min((openness - delay) / max(1 - delay, 0.01), 1))
            let angle = -span / 2 + span * Float(index) / Float(count)
            let reach = 0.27 * own
            item.entity.position = SIMD3(sin(angle) * reach,
                                         cos(angle) * reach * 0.8 + 0.06,
                                         0)
            let pop = 1 + 0.14 * Float(sin(own * .pi))
            item.entity.scale = SIMD3(repeating: max(own, 0.001) * pop)
            item.entity.isEnabled = own > 0.02
        }
    }

    /// True when the tap chose a shape (the fan folds itself).
    func handleTap(_ entity: Entity) -> Bool {
        guard root.isEnabled else { return false }
        var current: Entity? = entity
        while let candidate = current {
            if candidate.parent === root, candidate.name.hasPrefix("shape-"),
               let body = DragBody(rawValue: String(candidate.name.dropFirst(6))) {
                onSelect?(body)
                SoundPalette.play(.chime, on: candidate, volume: 0.5)
                isOpen = false
                return true
            }
            if candidate === root { return false }
            current = candidate.parent
        }
        return false
    }

    private static func makeDisc(_ body: DragBody) -> ModelEntity {
        var casing = PhysicallyBasedMaterial()
        casing.baseColor = .init(tint: UIColor(white: 0.06, alpha: 1))
        casing.roughness = 0.28
        casing.clearcoat = .init(floatLiteral: 1.0)
        casing.blending = .transparent(opacity: .init(floatLiteral: 0.92))
        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.005, radius: 0.026),
            materials: [casing])
        disc.name = "shape-\(body.rawValue)"
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])

        if let symbol = symbols[body], let texture = Bloom.symbolTexture(symbol) {
            var iconMaterial = UnlitMaterial()
            iconMaterial.color = .init(tint: .white, texture: .init(texture))
            iconMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
            let icon = ModelEntity(
                mesh: .generatePlane(width: 0.028, height: 0.028),
                materials: [iconMaterial])
            icon.position = [0, 0.004, 0]
            icon.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            disc.addChild(icon)
        }

        let label = HubScene.namePlate(body.displayName,
                                       accent: UIColor(white: 0.95, alpha: 1),
                                       size: 0.009)
        label.position = [0, 0.005, 0.042]
        label.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        disc.addChild(label)

        disc.components.set(InputTargetComponent())
        disc.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: 0.034)]))
        disc.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "Test body: \(body.displayName)")
        disc.components.set(accessibility)
        disc.isEnabled = false
        return disc
    }
}
