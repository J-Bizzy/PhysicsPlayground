//
//  Lighting.swift
//  RenderKit
//
//  A shared, subtle key light so virtual objects catch a consistent
//  highlight and read with form — a supplement to the room's own
//  image-based light in passthrough, never a replacement. Warm and
//  gentle so it flatters the glossy / metallic energized materials
//  without fighting the real room.
//

import RealityKit
import UIKit

public enum Lighting {
    /// A soft, warm directional key light shining down from the upper
    /// front-left. Add it to a scene root; low intensity by design.
    @MainActor
    public static func keyLight(intensity: Float = 2200) -> Entity {
        let light = Entity()
        light.components.set(DirectionalLightComponent(
            color: UIColor(red: 1.0, green: 0.96, blue: 0.9, alpha: 1),
            intensity: intensity))
        // The light travels along the entity's −Z; aim that down and in
        // from the upper front-left.
        light.look(at: .zero, from: SIMD3(-0.6, 1.0, 0.7), relativeTo: nil)
        return light
    }
}
