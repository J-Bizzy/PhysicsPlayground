//
//  Lighting.swift
//  RenderKit
//
//  A shared warm key light supplementing passthrough IBL, never replacing it.
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
        // Light travels along −Z; aim down from the upper front-left.
        light.look(at: .zero, from: SIMD3(-0.6, 1.0, 0.7), relativeTo: nil)
        return light
    }
}
