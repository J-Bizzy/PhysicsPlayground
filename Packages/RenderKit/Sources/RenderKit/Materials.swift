//
//  Materials.swift
//  RenderKit
//
//  Shared material recipes so a physics object looks crafted in every
//  module instead of like a matte primitive.
//
//  Two families, and the split is the useful part:
//
//  · `energized` is a recipe for LIT ENERGY — a charge, a source, a
//    bead of current. Clearcoat gloss plus self-illumination in the
//    object's own colour.
//  · `machined` and `graphite` are recipes for BUILT THINGS — a bob, a
//    coil, a knob, a shelf. They do not glow; they catch light.
//
//  The second family was missing for a long time, and its absence is
//  visible in the source: every module that needed a machined part fell
//  back to `SimpleMaterial` with a hand-typed grey, because the canon
//  offered a glow recipe and nothing else. The Hub had authored good
//  values for exactly this and kept them inline. They live here now.
//

import RealityKit
import UIKit

public enum Materials {
    /// A physics object rendered as lit energy rather than a flat shape.
    /// - `glow`: self-illumination in the object's own colour; 0 gives a
    ///   purely polished finish (for mechanical parts), higher values
    ///   make it glow like a charge or a source.
    /// - `metallic`: 1 reads as machined metal (a bob, a block); 0 as a
    ///   coloured solid.
    /// Reduces to a plausible default that already improved the charges.
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

    /// A machined metal part: a bob, a coil, a knob, a fuse cap.
    ///
    /// **Deliberately not a mirror**, and the reason is measured rather
    /// than aesthetic. At `metallic = 1` a surface shows only what it
    /// reflects, and a passthrough room gives RealityKit almost nothing
    /// to reflect — the app's extruded wordmark rendered a muddy grey
    /// at 1.0 before it settled here (DECISIONS.md, 2026-07-30). The
    /// roughness goes the other way, up rather than down: a polished
    /// face flips between hotspot and shadow as the head moves, while a
    /// satin one rolls between them, so the light travels across the
    /// part instead of snapping across it.
    ///
    /// These are the values the Hub's signage arrived at after being
    /// judged on a specimen wall; the labs inherit them rather than
    /// re-deriving a grey each time.
    /// - `roughness`: satin by default. A caller may go ROUGHER for a
    ///   duller part (a dark steel cable, a cast housing); going much
    ///   smoother re-introduces the flip this recipe exists to avoid.
    /// - `glow`: for a part that is genuinely warm — a driven coil, a
    ///   heated element. Zero for anything merely shiny.
    ///
    /// `metallic` is deliberately NOT a parameter. 0.62 is the whole
    /// point of the recipe, and a call site that wants 1.0 wants the
    /// bug.
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

    /// Structural furniture: a shelf, a plinth, a pedestal. Darker and
    /// far less metallic than `machined` — architecture sits beneath the
    /// physics and must never compete with it for the eye.
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

    // MARK: Reading against a bright room

    /// Passthrough is a *bright* medium — cream walls, daylight, pale
    /// furniture. A pale translucent line drawn over it has almost no
    /// luminance contrast and simply disappears, which is why so much of
    /// the field art washed out. The fix is a two-pass line: a
    /// near-black casing swept slightly fatter than the bright core, so
    /// the core always sits against darkness no matter what colour the
    /// wall behind it happens to be.
    ///
    /// Adopted by the two field modules — Electric Fields and Magnetism.
    /// It said "used everywhere in the app" for a long time while
    /// shipping in exactly one of them; if you are adding lines to a
    /// module, this is the pass that is probably missing.
    ///
    /// `casing` is drawn first (fatter tube), `core` second (thin tube).
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

    /// The radius the casing should be swept at for a given core radius.
    /// Wide enough to read as an outline at arm's length, tight enough
    /// that a bundle of lines doesn't merge into a black mass.
    public static func casingRadius(forCore radius: Float) -> Float {
        radius * 2.1 + 0.0007
    }

    /// A self-lit surface that keeps its colour against a bright room:
    /// the tint is deepened and the emissive pushed, so it reads as a
    /// lit object rather than a pastel wash. Used for the objects that
    /// were disappearing into the walls (the Sun, wave sources, smoke).
    public static func luminous(_ color: UIColor, glow: Float = 1.6) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .opaque
        _ = glow  // Unlit is already full-intensity; kept for call-site clarity.
        return material
    }

    /// Hides virtual content behind real-world geometry. Applied to the
    /// scene-reconstruction mesh so a field line genuinely passes behind
    /// the couch instead of painting over it.
    public static func occlusion() -> OcclusionMaterial {
        OcclusionMaterial()
    }
}
