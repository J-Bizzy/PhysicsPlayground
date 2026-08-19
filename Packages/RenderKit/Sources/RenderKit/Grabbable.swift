//
//  Grabbable.swift
//  RenderKit
//
//  Touch targets + RelativeDrag (move by the hand's displacement, never
//  lurch toward the hand). The system ManipulationComponent path is a
//  deliberate grave: here the MODEL owns motion, and a component that
//  writes the transform is a second author of the same number
//  (DECISIONS.md 2026-07-30/08-03).
//

import Foundation
import RealityKit
import SwiftUI
import simd

@MainActor
public enum Grabbable {
    /// The one allowance a touch target gets over what it stands for:
    /// 15 mm per side, asserted by `ColliderCriterionTests`. Prefer `box:`
    /// or `matchingVisualBoundsOf:` — a sphere enclosing a flat thing
    /// shields everything near it from every pinch.
    public static let reach: Float = 0.015

    /// Gesture target WITHOUT the system ManipulationComponent — no
    /// system-owned motion. Pair with a DragGesture and RelativeDrag.
    public static func configureTouchTarget(_ entity: Entity, collisionRadius: Float,
                                            activate: (() -> Void)? = nil) {
        apply(.generateSphere(radius: collisionRadius), to: entity, activate: activate)
    }

    /// A box target, for the things that are not balls — plates, bars,
    /// slabs, cylinders. `size` is the full extent on each axis.
    public static func configureTouchTarget(_ entity: Entity,
                                            box size: SIMD3<Float>,
                                            offset: SIMD3<Float> = .zero,
                                            activate: (() -> Void)? = nil) {
        apply(.generateBox(size: size).offsetBy(translation: offset), to: entity,
              activate: activate)
    }

    /// A box target measured from what is actually drawn plus `padding`.
    /// `source` may be one child when the rest is decoration the target
    /// should not swell to cover.
    public static func configureTouchTarget(_ entity: Entity,
                                            matchingVisualBoundsOf source: Entity,
                                            padding: Float = reach,
                                            activate: (() -> Void)? = nil) {
        let bounds = source.visualBounds(relativeTo: entity)
        let extents = bounds.extents
        guard extents.x.isFinite, extents.y.isFinite, extents.z.isFinite,
              simd_length(extents) > 1e-6 else {
            // Nothing drawn yet — a padding-sized sphere cannot shield anything.
            return configureTouchTarget(entity, collisionRadius: max(padding, 1e-3),
                                        activate: activate)
        }
        configureTouchTarget(entity,
                             box: extents + SIMD3<Float>(repeating: 2 * padding),
                             offset: bounds.center, activate: activate)
    }

    /// The LOCAL radius giving a per-instance-scaled sphere target the
    /// same reach in the ROOM: 15% of the object or 15 mm, whichever is
    /// kinder, divided by the scale (the entity multiplies it back).
    public static func sphereTargetRadius(baseRadius: Float, scale: Float) -> Float {
        guard scale > 1e-4 else { return baseRadius }
        // A hair under the flat allowance, so a boundary-sized target
        // cannot fail the criterion on a rounding bit.
        return max(baseRadius * 1.14, baseRadius + (reach * 0.98) / scale)
    }

    /// `activate` is what VoiceOver does with this object — optional
    /// because only the caller knows the meaning. Passing nothing leaves
    /// a grabbable hands can move and VoiceOver cannot.
    private static func apply(_ shape: ShapeResource, to entity: Entity,
                              activate: (() -> Void)? = nil) {
        entity.components.set(InputTargetComponent())
        entity.components.set(CollisionComponent(shapes: [shape]))
        entity.components.set(HoverEffectComponent())
        if let activate {
            SpatialActions.attach(to: entity, label: entity.name, activate: activate)
        }
        // Contact shadow grounds it against real surfaces (device-only;
        // the simulator has no room mesh to catch it).
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

    /// Carry distance from where THIS DRAG picked it up — measured
    /// against `startTarget`, which nothing overwrites; a per-frame
    /// reference makes the 12 mm tap threshold speed-dependent.
    public func travel(forHand hand: SIMD3<Double>) -> Double {
        simd_distance(position(forHand: hand), startTarget)
    }
}
