//
//  Station.swift
//  Physics Playground — Design System
//
//  One apparatus inside a module that holds several.
//
//  A module used to be an apparatus: its own View, its own RealityView,
//  its own gestures. A world holds two or three of them, and a scene can
//  only have one set of gestures — so each apparatus becomes an object
//  that owns its renderer, its zoom rig and its drag state, and answers
//  the world's questions: is this entity mine, and what does a pinch on
//  it mean?
//
//  `tick` is deliberately NOT part of this protocol. The signatures
//  genuinely differ — the magnetic field's takes the circuit bench's
//  inductor current — and that is the point rather than an inconvenience:
//  the ORDER the solvers run in, and what one hands the next, belongs to
//  the world, in one place, where it can be read. Across a module
//  boundary that ordering was unknowable. A protocol'd `tick` would push
//  it back out into the stations and make it unknowable again.
//

import RealityKit
import RenderKit
import SwiftUI

/// One apparatus in a multi-station module.
@MainActor
protocol Station: AnyObject {
    /// Everything this station draws hangs beneath here. The world
    /// routes a gesture to a station by walking the hit entity up to
    /// whichever station root it sits under, and emphasises a station by
    /// setting opacity here.
    var root: Entity { get }

    /// This station's two-handed zoom, or nil for an apparatus that
    /// must not be scaled. Projectiles is the standing example: its
    /// physics space IS the user's room, so scaling the display would
    /// make every wall bounce a fiction.
    var scaleRig: SpatialScaleRig? { get }

    func install(into content: RealityViewContent)

    /// Returns whether the tap meant something here — a station that
    /// doesn't recognise the entity folds its own rings away.
    @discardableResult
    func handleTap(_ entity: Entity) -> Bool

    func dragChanged(_ value: EntityTargetValue<DragGesture.Value>)

    /// Called on EVERY station when any drag ends, wherever the hand
    /// finished, so a drag that starts on a magnet and ends over the
    /// bench still releases the magnet. Must be a no-op when this
    /// station has no drag in flight.
    func dragEnded(_ value: EntityTargetValue<DragGesture.Value>)
}
