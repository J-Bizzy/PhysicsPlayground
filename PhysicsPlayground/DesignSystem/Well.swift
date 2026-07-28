//
//  Well.swift
//  Physics Playground — Design System
//
//  Creation, as a physical act. Every lab has one or two of these: a
//  small source you reach into and PULL something out of. The new
//  object is born at your fingertips and follows your hand until you
//  let go of it, which means placing a charge and moving a charge are
//  the same gesture — you never learn a second one.
//
//  This replaces "Add +" and "Add −" buttons on a floating card. A
//  button tells you a thing exists somewhere; a well hands it to you.
//
//  The well breathes gently so it reads as a source rather than a
//  decoration, and dips when it gives something up.
//

import RealityKit
import SwiftUI
import RenderKit
import simd

@MainActor
final class Well {
    /// One source: what it looks like, and what it makes.
    struct Spec {
        let name: String
        let tint: UIColor
        /// The label under the mouth ("+", "−", "Magnet"…).
        let glyph: String
        let position: SIMD3<Float>
        /// Makes the object at a world point and returns its id, so the
        /// caller can hand the new thing straight to the drag it was
        /// born from.
        let spawn: (SIMD3<Double>) -> UUID?
    }

    let root = Entity()
    private var specs: [Spec] = []
    private var mouths: [ModelEntity] = []
    private var haloes: [ModelEntity] = []
    private var dip: [Float] = []
    private var time: Double = 0

    private static let mouthRadius: Float = 0.032

    init(_ specs: [Spec]) {
        self.specs = specs
        dip = Array(repeating: 0, count: specs.count)
        for spec in specs {
            let mouth = Self.makeMouth(spec)
            mouth.position = spec.position
            root.addChild(mouth)
            mouths.append(mouth)
            if let halo = mouth.children.compactMap({ $0 as? ModelEntity })
                .first(where: { $0.name == "well-halo" }) {
                haloes.append(halo)
            }
        }
    }

    /// Per frame: the idle breath, and the recoil after a spawn.
    func update(dt: Double) {
        time += dt
        for (index, mouth) in mouths.enumerated() {
            dip[index] = max(0, dip[index] - Float(dt) * 2.6)
            let breath = 1 + 0.035 * Float(sin(time * 1.4 + Double(index) * 1.1))
            // The dip is a recoil: it shrinks on giving, then swells back.
            mouth.scale = SIMD3(repeating: breath * (1 - 0.42 * dip[index]))
            if index < haloes.count {
                let glow = 0.18 + 0.5 * dip[index]
                haloes[index].components.set(
                    OpacityComponent(opacity: glow))
            }
        }
    }

    /// If `entity` is a well mouth, makes its object at `hand` and
    /// returns the new id — the caller then drags it like anything else.
    func pull(_ entity: Entity, at hand: SIMD3<Double>) -> UUID? {
        guard let name = Self.mouthName(of: entity, under: root),
              let index = mouths.firstIndex(where: { $0.name == name })
        else { return nil }
        dip[index] = 1
        SoundPalette.play(.pop, on: mouths[index], volume: 0.5)
        return specs[index].spawn(hand)
    }

    private static func mouthName(of entity: Entity, under root: Entity) -> String? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.parent === root { return candidate.name }
            if candidate === root { return nil }
            current = candidate.parent
        }
        return nil
    }

    private static func makeMouth(_ spec: Spec) -> ModelEntity {
        var shell = PhysicallyBasedMaterial()
        shell.baseColor = .init(tint: spec.tint)
        shell.roughness = 0.18
        shell.metallic = 0.0
        shell.clearcoat = .init(floatLiteral: 1.0)
        shell.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        shell.emissiveColor = .init(color: spec.tint)
        shell.emissiveIntensity = 0.5

        let mouth = ModelEntity(mesh: .generateSphere(radius: mouthRadius),
                                materials: [shell])
        mouth.name = "well-\(spec.name)"

        // A soft outer halo that flares when the well gives something up.
        var haloMaterial = UnlitMaterial(color: spec.tint)
        haloMaterial.blending = .transparent(opacity: 0.18)
        let halo = ModelEntity(
            mesh: .generateSphere(radius: mouthRadius * 1.75),
            materials: [haloMaterial])
        halo.name = "well-halo"
        mouth.addChild(halo)

        // The sign, floating just inside the mouth.
        let glyph = HubScene.bubbleText(spec.glyph, size: 0.030,
                                        color: .white, emissive: 0.8)
        glyph.position = [0, 0, mouthRadius * 0.55]
        glyph.components.set(BillboardComponent())
        mouth.addChild(glyph)

        mouth.components.set(InputTargetComponent())
        mouth.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: mouthRadius * 1.5)]))
        mouth.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(spec.name) source. Pinch and pull to make one.")
        mouth.components.set(accessibility)
        return mouth
    }
}
