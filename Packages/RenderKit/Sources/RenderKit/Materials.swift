//
//  Materials.swift
//  RenderKit
//
//  Shared material recipes: `energized` for lit energy (glow), and
//  `machined`/`graphite` for built things that catch light instead.
//

import Metal
import RealityKit
import UIKit

@MainActor
public enum Materials {
    /// Lit energy (a charge, a source): clearcoat gloss + self-illumination.
    /// `glow` 0 is purely polished; `metallic` 1 reads as machined metal.
    public static func energized(_ color: UIColor,
                                 roughness: Float = 0.18,
                                 metallic: Float = 0,
                                 glow: Float = 0.4) -> PhysicallyBasedMaterial {
        memo(key("energized", colors: [color], [roughness, metallic, glow])) {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.roughness = .init(floatLiteral: roughness)
            material.metallic = .init(floatLiteral: metallic)
            material.clearcoat = .init(floatLiteral: 0.8)
            material.clearcoatRoughness = .init(floatLiteral: 0.15)
            material.emissiveColor = .init(color: color)
            material.emissiveIntensity = glow
            return material
        }
    }

    // MARK: Built things — metal that survives a passthrough room

    /// A machined metal part — deliberately not a mirror: passthrough gives
    /// RealityKit almost nothing to reflect, and satin roughness rolls the
    /// highlight instead of snapping it. `metallic` is fixed at 0.62 on
    /// purpose; a call site that wants 1.0 wants the bug.
    public static func machined(_ color: UIColor = UIColor(white: 0.78, alpha: 1),
                                roughness: Float = 0.42,
                                glow: Float = 0) -> PhysicallyBasedMaterial {
        memo(key("machined", colors: [color], [roughness, glow])) {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.metallic = .init(floatLiteral: 0.62)
            material.roughness = .init(floatLiteral: roughness)
            material.clearcoat = .init(floatLiteral: 0.55)
            material.clearcoatRoughness = .init(floatLiteral: 0.30)
            if glow > 0 {
                material.emissiveColor = .init(color: color)
                material.emissiveIntensity = glow
            }
            return material
        }
    }

    /// Structural furniture: darker and barely metallic — architecture
    /// must never compete with the physics for the eye.
    public static func graphite(_ color: UIColor = UIColor(white: 0.17, alpha: 1))
    -> PhysicallyBasedMaterial {
        memo(key("graphite", colors: [color], [])) {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.roughness = .init(floatLiteral: 0.30)
            material.metallic = .init(floatLiteral: 0.10)
            material.clearcoat = .init(floatLiteral: 0.60)
            material.clearcoatRoughness = .init(floatLiteral: 0.25)
            return material
        }
    }

    /// Wet-looking lacquer for display type and nameplates: no metal, a
    /// full clearcoat, and an emissive floor so letters stay legible
    /// against a wall of any brightness.
    public static func glossy(_ color: UIColor, glow: Float = 0.3)
    -> PhysicallyBasedMaterial {
        memo(key("glossy", colors: [color], [glow])) {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.roughness = .init(floatLiteral: 0.16)
            material.metallic = .init(floatLiteral: 0)
            material.clearcoat = .init(floatLiteral: 1.0)
            material.clearcoatRoughness = .init(floatLiteral: 0.12)
            material.emissiveColor = .init(color: color)
            material.emissiveIntensity = glow
            return material
        }
    }

    /// A value bead or pull grip: the handle itself, bright and solid,
    /// never glass. `emissive`/`glow` is the one per-control parameter.
    public static func grip(_ tint: UIColor = UIColor(white: 0.98, alpha: 1),
                            roughness: Float = 0.16,
                            emissive: UIColor? = nil,
                            glow: Float = 0) -> PhysicallyBasedMaterial {
        memo(key("grip", colors: [tint, emissive], [roughness, glow])) {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: tint)
            material.roughness = .init(floatLiteral: roughness)
            material.metallic = .init(floatLiteral: 0)
            material.clearcoat = .init(floatLiteral: 1.0)
            material.clearcoatRoughness = .init(floatLiteral: 0.12)
            if let emissive, glow > 0 {
                material.emissiveColor = .init(color: emissive)
                material.emissiveIntensity = glow
            }
            return material
        }
    }

    // MARK: Glass — the platform's own surface, for the app's own controls

    /// Frosted glass for operable instruments: a dark light-scattering
    /// scrim (`frost` = roughness) under a full-clearcoat skin — both
    /// halves load-bearing; a pale pane over a cream wall disappears.
    /// Keep `tint` dark; lower `opacity` needs more `frost`. Deliberately
    /// Not `.glassBackgroundEffect()`: these are ModelEntities, not SwiftUI views.
    public static func frostedGlass(_ tint: UIColor = UIColor(white: 0.09, alpha: 1),
                                    opacity: Float = 0.58,
                                    frost: Float = 0.68) -> PhysicallyBasedMaterial {
        memo(key("frostedGlass", colors: [tint], [opacity, frost])) {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: tint)
            material.metallic = .init(floatLiteral: 0)
            material.roughness = .init(floatLiteral: frost)
            material.clearcoat = .init(floatLiteral: 1.0)
            material.clearcoatRoughness = .init(floatLiteral: 0.06)
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
            return material
        }
    }

    /// The bright hairline rim that sells a glass pane, swept as slightly
    /// larger geometry. Unlit on purpose — it must hold its brightness
    /// under any room IBL.
    public static func glassEdge(_ color: UIColor = UIColor(white: 0.92, alpha: 1),
                                 opacity: Float = 0.34) -> UnlitMaterial {
        memo(key("glassEdge", colors: [color], [opacity])) {
            var material = UnlitMaterial(color: color)
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
            return material
        }
    }

    /// How far proud of a panel its edge hairline sits — a border, not a halo.
    nonisolated public static let glassEdgeInset: Float = 0.0016

    /// A colour pulled toward black for tinting a glass scrim — deepen
    /// an accent rather than substituting grey.
    nonisolated public static func deepened(_ color: UIColor, by fraction: CGFloat = 0.72)
    -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let keep = 1 - min(max(fraction, 0), 1)
        return UIColor(red: r * keep, green: g * keep, blue: b * keep, alpha: a)
    }

    // MARK: Reading against a bright room

    /// Two-pass line for bright passthrough: a near-black casing swept
    /// fatter than the bright core, so the core always sits against
    /// darkness. Draw `casing` first (fatter tube), `core` second.
    public static func contrastLine(_ color: UIColor,
                                    coreOpacity: Float = 1.0,
                                    casingOpacity: Float = 0.55) -> (casing: UnlitMaterial,
                                                                     core: UnlitMaterial) {
        var casing = UnlitMaterial(color: UIColor(white: 0.03, alpha: 1))
        casing.blending = .transparent(opacity: .init(floatLiteral: casingOpacity))
        var core = UnlitMaterial(color: color)
        if coreOpacity < 1 {
            core.blending = .transparent(opacity: .init(floatLiteral: coreOpacity))
        }
        return (casing, core)
    }

    /// Casing radius for a core: wide enough to read as an outline,
    /// tight enough that a bundle doesn't merge into a black mass.
    nonisolated public static func casingRadius(forCore radius: Float) -> Float {
        radius * 2.1 + 0.0007
    }

    /// Glow radius for a core — strictly inside the casing, and derived
    /// rather than typed: a halo outside the outline buries the darkness
    /// the contrast recipe depends on.
    nonisolated public static func glowRadius(forCore radius: Float) -> Float {
        casingRadius(forCore: radius) * 0.88
    }

    /// A self-lit surface that keeps its colour against a bright room.
    /// No glow parameter: an UnlitMaterial is already at full intensity
    /// and has no dimmer.
    public static func luminous(_ color: UIColor) -> UnlitMaterial {
        memo(key("luminous", colors: [color], [])) {
            var material = UnlitMaterial(color: color)
            material.blending = .opaque
            return material
        }
    }

    /// Hides virtual content behind real-world geometry (applied to the
    /// scene-reconstruction mesh).
    public static func occlusion() -> OcclusionMaterial {
        OcclusionMaterial()
    }

    // MARK: Memoisation — a recipe with the same arguments is one resource

    /// Every material creation is a round trip to the engine; a bench
    /// builds the same recipe hundreds of times. Materials are values, so
    /// a cached one can be handed out and recoloured by its caller.
    private struct Key: Hashable {
        let recipe: String
        let values: [Int64]
    }

    private static var cache: [Key: any RealityKit.Material] = [:]

    /// How many distinct recipes are held — for tests.
    public static var cachedCount: Int { cache.count }

    private static func key(_ recipe: String, colors: [UIColor?] = [],
                            _ values: [Float] = []) -> Key {
        var parts: [Int64] = []
        for color in colors {
            guard let color else { parts.append(-1); continue }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
                parts += [r, g, b, a].map { Int64(($0 * 10_000).rounded()) }
            } else {
                parts.append(Int64(color.description.hashValue))
            }
        }
        parts += values.map { Int64(($0 * 10_000).rounded()) }
        return Key(recipe: recipe, values: parts)
    }

    private static func memo<M: RealityKit.Material>(_ key: Key, _ make: () -> M) -> M {
        if let hit = cache[key] as? M { return hit }
        if cache.count >= 500 { cache.removeAll(keepingCapacity: true) }
        let made = make()
        cache[key] = made
        return made
    }

    /// A flat colour at an opacity: the app's commonest material. Opaque at
    /// 1, transparent below.
    public static func unlit(_ color: UIColor, opacity: Float = 1) -> UnlitMaterial {
        memo(key("unlit", colors: [color], [opacity])) {
            var material = UnlitMaterial(color: color)
            material.blending = opacity < 1
                ? .transparent(opacity: .init(floatLiteral: opacity))
                : .opaque
            return material
        }
    }

    // MARK: A line that fades along its length

    /// A flat colour whose opacity is read from `ramp` along the mesh's u —
    /// 0 at one end, 1 at the other — so a trail is bright at the body and
    /// nothing at its tail. Clamped, not repeated: u = 1 must not wrap round
    /// to the transparent end.
    public static func fadedLine(_ color: UIColor, ramp: TextureResource) -> UnlitMaterial {
        memo(key("fadedLine", colors: [color],
                 [Float(ObjectIdentifier(ramp).hashValue % 1_000_000)])) {
            var material = UnlitMaterial(color: color)
            let sampler = MTLSamplerDescriptor()
            sampler.sAddressMode = .clampToEdge
            sampler.tAddressMode = .clampToEdge
            sampler.minFilter = .linear
            sampler.magFilter = .linear
            material.blending = .transparent(opacity: .init(
                scale: 1,
                texture: .init(ramp, sampler: MaterialParameters.Texture.Sampler(sampler))))
            return material
        }
    }

    /// The one ramp every faded line reads: 256 grey levels from black to
    /// white along u — linear, "fading to nothing", one exponent in one
    /// place. Built through the async loader like every texture here.
    public static func fadeRamp() async -> TextureResource? {
        if let ramp = fadeRampResource { return ramp }
        let width = 256
        guard let context = CGContext(
            data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for x in 0..<width {
            let level = CGFloat(x) / CGFloat(width - 1)
            context.setFillColor(CGColor(red: level, green: level, blue: level, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: 1))
        }
        guard let image = context.makeImage(),
              let resource = try? await TextureResource(image: image, options: .init(semantic: .raw))
        else { return nil }
        fadeRampResource = resource
        return resource
    }

    private static var fadeRampResource: TextureResource?
}
