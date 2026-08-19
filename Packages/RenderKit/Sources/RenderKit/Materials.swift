//
//  Materials.swift
//  RenderKit
//
//  Shared material recipes: `energized` for LIT ENERGY (glow), and
//  `machined`/`graphite` for BUILT THINGS that catch light instead.
//

import RealityKit
import UIKit

public enum Materials {
    /// Lit energy (a charge, a source): clearcoat gloss + self-illumination.
    /// `glow` 0 is purely polished; `metallic` 1 reads as machined metal.
    public static func energized(_ color: UIColor,
                                 roughness: Float = 0.18,
                                 metallic: Float = 0,
                                 glow: Float = 0.4) -> PhysicallyBasedMaterial {
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

    // MARK: Built things — metal that survives a passthrough room

    /// A machined metal part — deliberately not a mirror: passthrough gives
    /// RealityKit almost nothing to reflect, and satin roughness rolls the
    /// highlight instead of snapping it. `metallic` is fixed at 0.62 on
    /// purpose; a call site that wants 1.0 wants the bug.
    public static func machined(_ color: UIColor = UIColor(white: 0.78, alpha: 1),
                                roughness: Float = 0.42,
                                glow: Float = 0) -> PhysicallyBasedMaterial {
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

    /// Structural furniture: darker and barely metallic — architecture
    /// must never compete with the physics for the eye.
    public static func graphite(_ color: UIColor = UIColor(white: 0.17, alpha: 1))
    -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: 0.30)
        material.metallic = .init(floatLiteral: 0.10)
        material.clearcoat = .init(floatLiteral: 0.60)
        material.clearcoatRoughness = .init(floatLiteral: 0.25)
        return material
    }

    /// Wet-looking lacquer for display type and nameplates: no metal, a
    /// full clearcoat, and an emissive floor so letters stay legible
    /// against a wall of any brightness.
    public static func glossy(_ color: UIColor, glow: Float = 0.3)
    -> PhysicallyBasedMaterial {
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

    /// A value bead or pull grip: the handle ITSELF, bright and solid,
    /// never glass. `emissive`/`glow` is the one per-control parameter.
    public static func grip(_ tint: UIColor = UIColor(white: 0.98, alpha: 1),
                            roughness: Float = 0.16,
                            emissive: UIColor? = nil,
                            glow: Float = 0) -> PhysicallyBasedMaterial {
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

    // MARK: Glass — the platform's own surface, for the app's own controls

    /// Frosted glass for operable instruments: a DARK light-scattering
    /// scrim (`frost` = roughness) under a full-clearcoat skin — both
    /// halves load-bearing; a pale pane over a cream wall disappears.
    /// Keep `tint` dark; lower `opacity` needs more `frost`. Deliberately
    /// NOT `.glassBackgroundEffect()`: these are ModelEntities, not SwiftUI views.
    public static func frostedGlass(_ tint: UIColor = UIColor(white: 0.09, alpha: 1),
                                    opacity: Float = 0.58,
                                    frost: Float = 0.68) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint)
        material.metallic = .init(floatLiteral: 0)
        material.roughness = .init(floatLiteral: frost)
        material.clearcoat = .init(floatLiteral: 1.0)
        material.clearcoatRoughness = .init(floatLiteral: 0.06)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    /// The bright hairline rim that sells a glass pane, swept as slightly
    /// larger geometry. Unlit on purpose — it must hold its brightness
    /// under any room IBL.
    public static func glassEdge(_ color: UIColor = UIColor(white: 0.92, alpha: 1),
                                 opacity: Float = 0.34) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    /// How far proud of a panel its edge hairline sits — a border, not a halo.
    public static let glassEdgeInset: Float = 0.0016

    /// A colour pulled toward black for tinting a glass scrim — deepen
    /// an accent rather than substituting grey.
    public static func deepened(_ color: UIColor, by fraction: CGFloat = 0.72)
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
    public static func casingRadius(forCore radius: Float) -> Float {
        radius * 2.1 + 0.0007
    }

    /// Glow radius for a core — STRICTLY INSIDE the casing, and derived
    /// rather than typed: a halo outside the outline buries the darkness
    /// the contrast recipe depends on.
    public static func glowRadius(forCore radius: Float) -> Float {
        casingRadius(forCore: radius) * 0.88
    }

    /// A self-lit surface that keeps its colour against a bright room.
    /// No glow parameter: an UnlitMaterial is already at full intensity
    /// and has no dimmer.
    public static func luminous(_ color: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .opaque
        return material
    }

    /// Hides virtual content behind real-world geometry (applied to the
    /// scene-reconstruction mesh).
    public static func occlusion() -> OcclusionMaterial {
        OcclusionMaterial()
    }
}
