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
    /// The one allowance a touch target gets over the thing it stands
    /// for: 15 mm of reach on each side. Stated once here and asserted
    /// by `ColliderCriterionTests`, which measures every collider in
    /// every built scene against its entity's own visual bounds.
    ///
    /// The sphere overload below is why the rule kept being broken. For
    /// most of this app's life it was the ONLY overload, so every author
    /// with a plate, a bar or a cylinder to make grabbable had to pick a
    /// radius that enclosed it — which for a 0.5 m plate 12 mm thick
    /// means a 0.26 m ball, and that ball shielded every charge inside
    /// the capacitor from every pinch. Reach for `box:` or
    /// `matchingVisualBoundsOf:` unless the thing really is a ball.
    public static let reach: Float = 0.015

    /// Makes an entity a gesture target WITHOUT the system
    /// ManipulationComponent — no attraction toward the hand, no
    /// system-owned motion. Pair with a DragGesture and RelativeDrag:
    /// the model moves by the hand's displacement, and the renderer
    /// (ticking per frame) moves the entity and everything attached
    /// to it as one body.
    public static func configureTouchTarget(_ entity: Entity, collisionRadius: Float) {
        apply(.generateSphere(radius: collisionRadius), to: entity)
    }

    /// A box target, for the things that are not balls — plates, bars,
    /// slabs, cylinders. `size` is the full extent on each axis.
    public static func configureTouchTarget(_ entity: Entity,
                                            box size: SIMD3<Float>,
                                            offset: SIMD3<Float> = .zero) {
        apply(.generateBox(size: size).offsetBy(translation: offset), to: entity)
    }

    /// A box target measured from what is actually drawn, plus `padding`
    /// of reach on every side.
    ///
    /// MEASURE, rather than assume: the caller building the miniature is
    /// rarely the caller sizing the target, and a magnet is not a
    /// sphere. `source` is usually the entity itself, but may be one
    /// child of it when the rest — a hanging name plate, a callout — is
    /// decoration the target should not swell to cover.
    /// (`Well.makeSource` has done exactly this by hand since the wells
    /// shipped; this is that pattern, named.)
    public static func configureTouchTarget(_ entity: Entity,
                                            matchingVisualBoundsOf source: Entity,
                                            padding: Float = reach) {
        let bounds = source.visualBounds(relativeTo: entity)
        let extents = bounds.extents
        guard extents.x.isFinite, extents.y.isFinite, extents.z.isFinite,
              simd_length(extents) > 1e-6 else {
            // Nothing drawn yet — a sphere of the padding is the most
            // honest target available, and it cannot shield anything.
            return configureTouchTarget(entity, collisionRadius: max(padding, 1e-3))
        }
        configureTouchTarget(entity,
                             box: extents + SIMD3<Float>(repeating: 2 * padding),
                             offset: bounds.center)
    }

    /// The LOCAL radius a sphere target needs on an entity that is
    /// scaled per instance, so that its reach in the ROOM is the same
    /// whatever size the instance is.
    ///
    /// Pooled objects — Gravity Lab's bodies, Projectiles' balls — are
    /// one authored mesh of `baseRadius` on an entity whose scale is set
    /// per instance, from about 0.26× for a comet to well over 2× for a
    /// star. A single authored factor therefore means completely
    /// different things at the two ends: ×1.5 is 6 mm of reach on the
    /// comet and 5 cm of shielding on the star, and ×1.15 — which is
    /// what this app briefly shipped — is 2 mm on the comet, which is
    /// no target at all.
    ///
    /// The fix is to ask for the same answer the collider criterion
    /// asks for, in metres: 15% of the object, or 15 mm of reach,
    /// whichever is kinder. Divided by the scale, because the entity
    /// will multiply it back.
    public static func sphereTargetRadius(baseRadius: Float, scale: Float) -> Float {
        guard scale > 1e-4 else { return baseRadius }
        // A hair under the flat allowance, so a target sized to exactly
        // the criterion's boundary cannot fail it on a rounding bit.
        return max(baseRadius * 1.14, baseRadius + (reach * 0.98) / scale)
    }

    private static func apply(_ shape: ShapeResource, to entity: Entity) {
        entity.components.set(InputTargetComponent())
        entity.components.set(CollisionComponent(shapes: [shape]))
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

    /// How far the target has been carried from where THIS DRAG picked
    /// it up — the quantity a press-versus-drag discriminator needs.
    ///
    /// It lives here because both call sites got it wrong in the same
    /// way, and the mistake is easy to make in three lines of gesture
    /// handler. `LabAnchorView` and the gallery bar each wrote
    ///
    ///     travelled = max(travelled, distance(next, placement.offset))
    ///     placement.move(to: next)
    ///
    /// which measures against a reference the very next line overwrites.
    /// The number tested against the 12 mm tap threshold was therefore
    /// ONE FRAME's hand displacement, so only a drag faster than about
    /// 1.08 m/s ever registered: carry a lab 60 cm at a normal 0.3 m/s
    /// and `onEnded` took the tap branch and recentred it, discarding
    /// the whole placement. Measured against `startTarget`, which
    /// nothing overwrites, the same test means what it says.
    public func travel(forHand hand: SIMD3<Double>) -> Double {
        simd_distance(position(forHand: hand), startTarget)
    }
}
