//
//  StudioEnvironment.swift
//  Physics Playground — Shell
//
//  Studio Mode's stage: a fully immersive dark gallery that replaces the
//  passthrough room. A star-dusted night sky wraps the user, a matte
//  charcoal floor grounds them, and two faint glowing rings mark the
//  stage the exhibits stand on — a planetarium for physics, where the
//  glowing charges, beams, and smoke read at full contrast instead of
//  fighting a sunlit living room.
//
//  Everything is procedural (no assets): the sky is a generated gradient
//  + starfield texture on an inside-out sphere.
//

import RealityKit
import RenderKit
import SwiftUI

struct StudioEnvironmentView: View {
    var body: some View {
        RealityView { content in
            content.add(Self.makeEnvironment())
        }
    }

    @MainActor
    static func makeEnvironment() -> Entity {
        let root = Entity()

        // The night sky: an inside-out sphere far past every exhibit.
        var sky = UnlitMaterial(color: .black)
        if let texture = skyTexture() {
            sky.color = .init(tint: .white, texture: .init(texture))
        }
        let dome = ModelEntity(mesh: .generateSphere(radius: 45), materials: [sky])
        dome.scale = SIMD3(-1, 1, 1)   // view it from the inside
        dome.position = [0, 1.4, 0]
        root.addChild(dome)

        // The floor: a wide matte-charcoal disc at the real floor height,
        // so the user keeps their footing when the room disappears.
        var floorMaterial = PhysicallyBasedMaterial()
        floorMaterial.baseColor = .init(tint: UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1))
        floorMaterial.roughness = 0.95
        floorMaterial.metallic = 0.0
        let floor = ModelEntity(
            mesh: .generateCylinder(height: 0.02, radius: 8),
            materials: [floorMaterial])
        floor.position = [0, -0.01, 0]
        root.addChild(floor)

        // Two faint glowing rings mark the stage — gallery lighting.
        addRing(to: root, radius: 2.6, y: 0.012,
                color: UIColor(red: 0.25, green: 0.75, blue: 0.75, alpha: 1), opacity: 0.55)
        addRing(to: root, radius: 5.8, y: 0.012,
                color: UIColor(red: 0.35, green: 0.45, blue: 0.65, alpha: 1), opacity: 0.3)

        return root
    }

    @MainActor
    private static func addRing(to root: Entity, radius: Float, y: Float,
                                color: UIColor, opacity: Float) {
        let points: [SIMD3<Float>] = (0...96).map { index in
            let angle = Float(index) / 96 * 2 * .pi
            return SIMD3(cos(angle) * radius, y, sin(angle) * radius)
        }
        guard let mesh = TubeMesh.tube(lines: [points], radius: 0.008, sides: 8) else { return }
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        root.addChild(ModelEntity(mesh: mesh, materials: [material]))
    }

    /// A deep-night gradient with a seeded scatter of stars — brighter and
    /// denser overhead, fading toward a faintly warmer horizon band.
    private static func skyTexture() -> TextureResource? {
        let width = 1536, height = 768
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let cg = context.cgContext
            // Vertical gradient: near-black zenith → deep blue horizon.
            let colors = [
                UIColor(red: 0.010, green: 0.012, blue: 0.030, alpha: 1).cgColor,
                UIColor(red: 0.022, green: 0.032, blue: 0.070, alpha: 1).cgColor,
                UIColor(red: 0.050, green: 0.060, blue: 0.105, alpha: 1).cgColor,
                UIColor(red: 0.016, green: 0.018, blue: 0.034, alpha: 1).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 0.42, 0.55, 1]) {
                cg.drawLinearGradient(gradient,
                                      start: .zero,
                                      end: CGPoint(x: 0, y: height),
                                      options: [])
            }
            // Stars: seeded so the sky is the same on every visit.
            var state: UInt64 = 0x9E3779B97F4A7C15
            func random() -> Double {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Double(state >> 11) / Double(UInt64.max >> 11)
            }
            for _ in 0..<520 {
                let x = random() * Double(width)
                // Keep stars in the upper 60% (the "sky" half of the dome).
                let y = pow(random(), 1.6) * Double(height) * 0.6
                let r = 0.4 + pow(random(), 3) * 1.8
                let brightness = 0.25 + random() * 0.75
                cg.setFillColor(UIColor(white: 1, alpha: brightness).cgColor)
                cg.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource.generate(from: cgImage, options: .init(semantic: .color))
    }
}
