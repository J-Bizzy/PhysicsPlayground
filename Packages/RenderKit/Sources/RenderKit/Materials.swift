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
}
