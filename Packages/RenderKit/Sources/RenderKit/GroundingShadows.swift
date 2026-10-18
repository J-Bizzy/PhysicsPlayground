//
//  GroundingShadows.swift
//  RenderKit
//
//  The grounding shadow, set where RealityKit reads it: on the meshes. A
//  `GroundingShadowComponent` on a plain `Entity` holder casts nothing —
//  which is how Circuit Workshop's parts went shadowless while their holders
//  carried the component — so these walk the tree and set it on every
//  `ModelEntity` under the one given. (The wells did this privately first.)
//

import RealityKit

@MainActor
public enum GroundingShadows {
    /// Every mesh under `entity` casts a grounding shadow.
    public static func cast(on entity: Entity) {
        apply(GroundingShadowComponent(castsShadow: true), to: entity)
    }

    /// Every mesh under `entity` takes the shadows cast onto it and casts
    /// none of its own — a surface things hover over.
    public static func receive(on entity: Entity) {
        apply(GroundingShadowComponent(castsShadow: false, receivesShadow: true), to: entity)
    }

    private static func apply(_ shadow: GroundingShadowComponent, to entity: Entity) {
        if entity is ModelEntity {
            entity.components.set(shadow)
        }
        for child in entity.children { apply(shadow, to: child) }
    }
}
