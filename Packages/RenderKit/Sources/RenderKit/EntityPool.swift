//
//  EntityPool.swift
//  RenderKit
//
//  Pooling contract: a fixed budget of entities built once; updates only
//  toggle isEnabled and touch transforms — nothing created per frame.
//  The budget is the degrade knob (extra data is simply not shown), and
//  each slot's Payload holds handles so updates never search the hierarchy.
//

import Foundation
import RealityKit

@MainActor
public final class EntityPool<Payload> {
    public struct Slot {
        /// The pooled container, a child of `root`. Position/orient/scale
        /// this; toggle `isEnabled` to show or hide the slot.
        public let entity: Entity
        public let payload: Payload
    }

    /// Add this to the scene once; every pooled entity lives under it.
    public let root = Entity()
    public let budget: Int
    public private(set) var slots: [Slot] = []

    /// Builds all `budget` slots up front, each disabled until used.
    /// `makeSlot` receives the container entity and attaches whatever the
    /// visualization needs, returning the per-slot payload.
    public init(budget: Int, makeSlot: (Entity) -> Payload) {
        self.budget = budget
        slots = (0..<budget).map { _ in
            let entity = Entity()
            entity.isEnabled = false
            root.addChild(entity)
            return Slot(entity: entity, payload: makeSlot(entity))
        }
    }

    /// Enables the first `count` slots and disables the rest — the common
    /// case for visualizations whose items are all-or-nothing in order.
    /// (Callers with per-item visibility rules set `isEnabled` themselves.)
    public func setActiveCount(_ count: Int) {
        for (index, slot) in slots.enumerated() {
            slot.entity.isEnabled = index < count
        }
    }

    public func hideAll() {
        setActiveCount(0)
    }
}
