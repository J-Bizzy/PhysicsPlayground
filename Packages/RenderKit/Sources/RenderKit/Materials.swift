//
//  Materials.swift
//  RenderKit
//
//  Shared material recipes so a physics object looks crafted in every
//  module instead of like a matte primitive. `energized` gives a clear-
//  coat gloss (a crisp highlight riding over the colour) plus an
//  optional self-lit glow so the object reads as lit from within.
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

    // MARK: Reading against a bright room

    /// Passthrough is a *bright* medium — cream walls, daylight, pale
    /// furniture. A pale translucent line drawn over it has almost no
    /// luminance contrast and simply disappears, which is why so much of
    /// the field art washed out. The fix used everywhere in the app is a
    /// two-pass line: a near-black casing swept slightly fatter than the
    /// bright core, so the core always sits against darkness no matter
    /// what colour the wall behind it happens to be.
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
