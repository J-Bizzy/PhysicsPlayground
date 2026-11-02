//
//  Grasp.swift
//  Physics Playground
//
//  The house answer to a hand, for the objects that had none (2026-11-02):
//  taken, an object wears `LiveGlow` and ticks; let go, the glow leaves and
//  it ticks again. The renderers that already answered keep their own code;
//  this is the one call for every grab that was silent.
//

import RealityKit
import RenderKit

@MainActor
enum Grasp {
    /// A hand has just taken `entity`. `glow` false for something too large
    /// to wear the aura (a turntable); `tick` false when something already
    /// spoke for the grab (a well's pop as it hands an object over).
    static func take(_ entity: Entity, glow: Bool = true, tick: Bool = true) {
        if glow { LiveGlow.set(true, on: entity) }
        if tick { SoundPalette.play(.grabTick, on: entity, volume: 0.2) }
    }

    /// The hand has let `entity` go.
    static func letGo(_ entity: Entity) {
        LiveGlow.set(false, on: entity)
        SoundPalette.play(.releaseTick, on: entity, volume: 0.2)
    }

    /// One thing a view's drag carries, named rather than held: an object
    /// a well has just made has no entity until its renderer next draws,
    /// so it is looked up by name each frame (`find`) until it is found.
    /// Naming another, or nil, lets go of the last.
    @MainActor
    final class Carried {
        private(set) var name: String?
        private var fromWell = false
        private weak var entity: Entity?

        /// `fromWell` mutes the grab's tick: the well's pop spoke for it.
        func carry(_ name: String?, fromWell: Bool = false) {
            guard name != self.name else { return }
            if let entity { Grasp.letGo(entity) }
            entity = nil
            self.name = name
            self.fromWell = fromWell
        }

        /// Per frame, under the renderer's root.
        func find(under root: Entity) {
            guard let name, entity == nil,
                  let found = root.findEntity(named: name) else { return }
            entity = found
            Grasp.take(found, tick: !fromWell)
        }
    }
}
