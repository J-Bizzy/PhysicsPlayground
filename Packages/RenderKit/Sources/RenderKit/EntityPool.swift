//
//  EntityPool.swift
//  RenderKit
//
//  The pooling contract behind every "many identical things" visualization:
//  a fixed budget of container entities is built ONCE under a shared root,
//  and updates only enable/disable slots and touch their transforms —
//  nothing is created or destroyed per frame. Arrow grids, particle trace
//  points, and orbit bodies all pool through this.
//
//  The budget is the degrade-gracefully knob: callers size it to what the
//  frame rate comfortably supports and thin out their data to fit (extra
//  data beyond the budget is simply not shown), rather than dropping frames.
//
//  Each slot carries a caller-defined Payload — whatever per-slot handles
//  the visualization needs (e.g. the shaft and head ModelEntities of an
//  arrow) so updates never search the entity hierarchy.
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
