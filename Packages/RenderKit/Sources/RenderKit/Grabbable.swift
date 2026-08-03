//
//  Grabbable.swift
//  RenderKit
//
//  Making entities grabbable, the way this app decided to do it:
//
//  · Grabbable.configureTouchTarget — input target, collider, hover
//    effect and contact shadow. No system-owned motion.
//  · RelativeDrag — the grabbed thing moves by the hand's DISPLACEMENT
//    from the pinch, so it never jumps or lurches toward the hand.
//
//  TWO GRAVES WERE DUG OUT OF THIS FILE ON 2026-08-03, and what they
//  were is worth keeping because the alternative they represent looks
//  attractive every time somebody reads Apple's documentation.
//
//  `Grabbable.configure` wrapped visionOS 26's `ManipulationComponent`:
//  one call, and the system carries the entity for you. `ManipulationRouter`
//  routed its lifecycle events to per-entity callbacks. Both were public,
//  both were written before the modules were, and NEITHER HAD A SINGLE
//  CALLER ANYWHERE IN THE APP — while two SpaceView headers claimed their
//  entities routed through the router, which is the doc-rot this project
//  keeps catching.
//
//  They have no callers because the system component is the wrong shape
//  for this app, not because nobody got round to adopting it. In every
//  module the MODEL owns motion: the physics decides where a body is and
//  the renderer follows it. A component that attracts an entity toward
//  the hand, applies its own inertia, and writes the entity transform is
//  a second author of the same number — which is why `configure` had to
//  switch off `scalingBehavior`, `inertia` and `releaseBehavior` just to
//  stop it fighting the solver. Turning off everything a component does
//  is the signal to stop using the component.
//
//  `RelativeDrag` is what replaced it, and it is four lines. It also has
//  a property the system path does not: a CONSTANT translation leaves it
//  untouched, which is precisely why `LabPlacement.offset` and the
//  station seats are safe (DECISIONS.md, 2026-07-30).
//
//  So: a grave, not a missing door. Restoring either means arguing that
//  the system should own motion in a module whose whole claim is that
//  the physics does.
//

import Foundation
import RealityKit
import SwiftUI
import simd

@MainActor
public enum Grabbable {
    /// Makes an entity a gesture target WITHOUT the system
    /// ManipulationComponent — no attraction toward the hand, no
    /// system-owned motion. Pair with a DragGesture and RelativeDrag:
    /// the model moves by the hand's displacement, and the renderer
    /// (ticking per frame) moves the entity and everything attached
    /// to it as one body.
    public static func configureTouchTarget(_ entity: Entity, collisionRadius: Float) {
        entity.components.set(InputTargetComponent())
        entity.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: collisionRadius)]))
        entity.components.set(HoverEffectComponent())
        // Ground it: a soft contact shadow onto the real surfaces below,
        // so the floating object feels present in the room rather than
        // pasted on. (Renders against detected real-world geometry — a
        // device behaviour; the simulator has no room mesh to catch it.)
        entity.components.set(GroundingShadowComponent(castsShadow: true))
    }
}

/// A relative drag: the grabbed thing moves by the hand's displacement
/// from the pinch, never jumping or lurching toward the hand.
public struct RelativeDrag: Sendable {
    public let name: String
    private let startTarget: SIMD3<Double>
    private let startHand: SIMD3<Double>

    public init(name: String, target: SIMD3<Double>, hand: SIMD3<Double>) {
        self.name = name
        self.startTarget = target
        self.startHand = hand
    }

    /// Where the target belongs for the given hand position.
    public func position(forHand hand: SIMD3<Double>) -> SIMD3<Double> {
        startTarget + (hand - startHand)
    }
}
