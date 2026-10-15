//
//  GlowSprite.swift
//  Physics Playground — Design System
//
//  A soft round glow that always faces the wearer: the light round a lamp
//  that is on. A billboarded square whose opacity is read from a radial
//  mask (a colour texture's alpha draws a pale square in RealityKit), and
//  which writes no depth, because light is not a surface — a sprite that
//  wrote depth cut its square out of the room's dimming shell.
//

import RealityKit
import RenderKit
import UIKit

@MainActor
enum GlowSprite {
    /// A glow `size` metres across, unpainted.
    static func make(size: Float) -> ModelEntity {
        let sprite = ModelEntity(mesh: Primitives.plane(width: size, height: size, cornerRadius: 0),
                                 materials: [])
        sprite.components.set(BillboardComponent())
        return sprite
    }

    /// Paints a glow in a colour at a strength, 0…1. Strengths are
    /// quantised to eighths, so the materials a glow can wear stay few.
    static func paint(_ sprite: ModelEntity, _ colour: UIColor, strength: Float) {
        let level = max(1, min(8, Int((strength * 8).rounded())))
        let key = "\(colour.description)|\(level)"
        let material: UnlitMaterial
        if let cached = cache[key] {
            material = cached
        } else {
            var made = UnlitMaterial(color: colour)
            let opacity = Float(level) / 8
            if let mask {
                made.blending = .transparent(opacity: .init(scale: opacity, texture: .init(mask)))
            } else {
                made.blending = .transparent(opacity: .init(floatLiteral: opacity * 0.5))
            }
            made.writesDepth = false
            if cache.count > 64 { cache.removeAll() }
            cache[key] = made
            material = made
        }
        sprite.model?.materials = [material]
    }

    private static var cache: [String: UnlitMaterial] = [:]

    /// White at the centre falling to nothing at the edge: a hot core in a
    /// soft halo.
    private static let mask: TextureResource? = {
        let size = 96
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
            .image { context in
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: size, height: size))
                let stops: [(CGFloat, CGFloat)] = [(0, 1), (0.12, 0.85), (0.35, 0.28), (0.65, 0.07), (1, 0)]
                guard let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceGray(),
                    colors: stops.map { UIColor(white: $0.1, alpha: 1).cgColor } as CFArray,
                    locations: stops.map(\.0)) else { return }
                let centre = CGPoint(x: size / 2, y: size / 2)
                context.cgContext.drawRadialGradient(
                    gradient, startCenter: centre, startRadius: 0,
                    endCenter: centre, endRadius: CGFloat(size) / 2, options: [])
            }
        guard let cg = image.cgImage else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .raw))
    }()
}
