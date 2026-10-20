//
//  StudioEnvironment.swift
//  Physics Playground — Shell
//
//  Studio Mode's stage: a fully immersive dark gallery in place of the
//  passthrough room — a star-dusted night sky with a galactic band and
//  nebula pools, and a matte charcoal floor with a lit centre pool.
//  Nothing in it glows: in this app a glow means "live". Everything is
//  procedural: the sky is a generated gradient and starfield on an
//  inside-out sphere.
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

        // The night sky: the real one once it is built (`Sky`), else an
        // inside-out sphere with the procedural night.
        if let resources = SkyResources.shared {
            root.addChild(Sky.make(overRoom: false, resources: resources))
        } else {
            var sky = UnlitMaterial(color: .black)
            if let texture = skyTexture() {
                sky.color = .init(tint: .white, texture: .init(texture))
            }
            let dome = ModelEntity(mesh: Primitives.sphere(radius: 45), materials: [sky])
            dome.scale = SIMD3(-1, 1, 1)   // view it from the inside
            dome.position = [0, 1.4, 0]
            root.addChild(dome)
        }

        // The floor: a wide matte-charcoal disc at the real floor height,
        // so the user keeps their footing when the room disappears.
        var floorMaterial = PhysicallyBasedMaterial()
        floorMaterial.baseColor = .init(tint: UIColor(red: 0.05, green: 0.055, blue: 0.07, alpha: 1))
        floorMaterial.roughness = 0.95
        floorMaterial.metallic = 0.0
        let floor = ModelEntity(
            mesh: Primitives.cylinder(height: 0.02, radius: 8),
            materials: [floorMaterial])
        floor.position = [0, -0.01, 0]
        root.addChild(floor)

        // The stage pool: a soft champagne-lit centre fading to the charcoal
        // rim. Unlit, because it is the light.
        if let poolTexture = floorPoolTexture() {
            var pool = UnlitMaterial()
            pool.color = .init(tint: .white, texture: .init(poolTexture))
            pool.blending = .transparent(opacity: 0.55)
            let sheen = ModelEntity(
                mesh: Primitives.plane(width: 15.6, depth: 15.6, cornerRadius: 7.8),
                materials: [pool])
            sheen.position = [0, 0.004, 0]
            root.addChild(sheen)
        }

        return root
    }

    /// A deep-night gradient under a seeded sky. The galactic band completes
    /// whole sine cycles across the width, so the texture is seamless where
    /// the dome wraps.
    private static func skyTexture() -> TextureResource? {
        let width = 2048, height = 1024
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let cg = context.cgContext
            // Vertical gradient: near-black zenith → deep indigo → a
            // faintly violet horizon band → near-black below the floor.
            let colors = [
                UIColor(red: 0.008, green: 0.010, blue: 0.026, alpha: 1).cgColor,
                UIColor(red: 0.020, green: 0.026, blue: 0.066, alpha: 1).cgColor,
                UIColor(red: 0.052, green: 0.048, blue: 0.110, alpha: 1).cgColor,
                UIColor(red: 0.030, green: 0.022, blue: 0.052, alpha: 1).cgColor,
                UIColor(red: 0.012, green: 0.012, blue: 0.024, alpha: 1).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors,
                                         locations: [0, 0.38, 0.52, 0.62, 1]) {
                cg.drawLinearGradient(gradient,
                                      start: .zero,
                                      end: CGPoint(x: 0, y: height),
                                      options: [])
            }

            // Seeded, so the sky is the same on every visit.
            var state: UInt64 = 0x9E3779B97F4A7C15
            func random() -> Double {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Double(state >> 11) / Double(UInt64.max >> 11)
            }

            // Three nebula pools: broad radial washes, barely there.
            let nebulae: [(x: Double, y: Double, radius: Double, color: UIColor)] = [
                (0.22, 0.18, 0.16, UIColor(red: 0.25, green: 0.45, blue: 0.60, alpha: 0.05)),
                (0.63, 0.10, 0.20, UIColor(red: 0.42, green: 0.30, blue: 0.62, alpha: 0.06)),
                (0.86, 0.30, 0.13, UIColor(red: 0.55, green: 0.42, blue: 0.30, alpha: 0.04)),
            ]
            for nebula in nebulae {
                let center = CGPoint(x: nebula.x * Double(width),
                                     y: nebula.y * Double(height))
                let radius = nebula.radius * Double(width)
                let fade = [nebula.color.cgColor,
                            nebula.color.withAlphaComponent(0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: fade, locations: [0, 1]) {
                    cg.drawRadialGradient(gradient,
                                          startCenter: center, startRadius: 0,
                                          endCenter: center, endRadius: radius,
                                          options: [])
                }
            }

            // The galactic band's centreline: two whole sine cycles across the
            // width, so the texture's edges meet.
            func bandCenter(_ x: Double) -> Double {
                Double(height) * (0.20 + 0.075 * sin(x / Double(width) * 2 * .pi * 2))
            }
            // Many, large and very faint, so the band reads as one river of light
            // rather than a scatter of dots.
            for _ in 0..<1400 {
                let x = random() * Double(width)
                let spread = pow(random(), 1.7) * Double(height) * 0.085
                let y = bandCenter(x) + (random() < 0.5 ? -spread : spread)
                let radius = 8.0 + pow(random(), 2) * 26
                let warm = random() < 0.3
                let color = warm
                    ? UIColor(red: 0.85, green: 0.78, blue: 0.66, alpha: 0.004 + random() * 0.007)
                    : UIColor(red: 0.70, green: 0.78, blue: 0.92, alpha: 0.004 + random() * 0.007)
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                          width: radius * 2, height: radius * 2))
            }
            for _ in 0..<650 {
                let x = random() * Double(width)
                let spread = pow(random(), 1.5) * Double(height) * 0.07
                let y = bandCenter(x) + (random() < 0.5 ? -spread : spread)
                let radius = 0.3 + pow(random(), 3) * 1.1
                cg.setFillColor(UIColor(white: 1, alpha: 0.10 + random() * 0.35).cgColor)
                cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                          width: radius * 2, height: radius * 2))
            }

            // The wider field: stars in two colour temperatures, denser
            // toward the zenith, kept out of the below-floor half.
            for _ in 0..<820 {
                let x = random() * Double(width)
                let y = pow(random(), 1.6) * Double(height) * 0.6
                let radius = 0.4 + pow(random(), 3) * 1.8
                let brightness = 0.20 + random() * 0.70
                let warm = random() < 0.28
                let color = warm
                    ? UIColor(red: 1.0, green: 0.90, blue: 0.76, alpha: brightness)
                    : UIColor(red: 0.82, green: 0.89, blue: 1.0, alpha: brightness)
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                          width: radius * 2, height: radius * 2))
            }

            // A dozen bright stars with halos.
            for _ in 0..<12 {
                let x = random() * Double(width)
                let y = pow(random(), 1.4) * Double(height) * 0.5
                let core = 1.2 + random() * 1.6
                let halo = core * (4.5 + random() * 3.5)
                let warm = random() < 0.3
                let haloColor = warm
                    ? UIColor(red: 1.0, green: 0.9, blue: 0.75, alpha: 0.20)
                    : UIColor(red: 0.8, green: 0.88, blue: 1.0, alpha: 0.20)
                let center = CGPoint(x: x, y: y)
                let fade = [haloColor.cgColor,
                            haloColor.withAlphaComponent(0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: fade, locations: [0, 1]) {
                    cg.drawRadialGradient(gradient,
                                          startCenter: center, startRadius: 0,
                                          endCenter: center, endRadius: halo,
                                          options: [])
                }
                cg.setFillColor(UIColor(white: 1, alpha: 0.95).cgColor)
                cg.fillEllipse(in: CGRect(x: x - core, y: y - core,
                                          width: core * 2, height: core * 2))
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }

    /// The floor's lit centre: a champagne pool fading through charcoal to
    /// nothing at the rim, drawn as alpha over the disc beneath.
    private static func floorPoolTexture() -> TextureResource? {
        let size = 1024
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            let cg = context.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)
            let colors = [
                UIColor(red: 0.16, green: 0.145, blue: 0.115, alpha: 0.9).cgColor,
                UIColor(red: 0.075, green: 0.078, blue: 0.09, alpha: 0.5).cgColor,
                UIColor(red: 0.02, green: 0.022, blue: 0.03, alpha: 0).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 0.42, 1]) {
                cg.drawRadialGradient(gradient,
                                      startCenter: center, startRadius: 0,
                                      endCenter: center,
                                      endRadius: CGFloat(size) / 2,
                                      options: [])
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }
}
