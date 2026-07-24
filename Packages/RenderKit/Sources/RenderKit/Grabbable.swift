//
//  Grabbable.swift
//  RenderKit
//
//  Everything about making entities grabbable with visionOS 26's
//  ManipulationComponent, in one place:
//
//  · Grabbable.configure — one call makes an entity pinch/touch-draggable
//    (installs input-target, collision, and hover-effect components itself).
//  · ManipulationRouter — subscribes to manipulation lifecycle events on a
//    RealityView's content and routes them to closures keyed by entity
//    name, so simulations write plain callbacks instead of event plumbing.
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
    /// Makes an entity grabbable with gaze+pinch or direct touch. The
    /// collision shape is bigger than the visible mesh so it's easy to grab.
    public static func configure(_ entity: Entity, collisionRadius: Float) {
        ManipulationComponent.configureEntity(
            entity,
            collisionShapes: [.generateSphere(radius: collisionRadius)]
        )
        if var manipulation = entity.components[ManipulationComponent.self] {
            // Stay where dropped instead of animating back to the origin,
            // and don't let two-handed gestures resize physics objects.
            manipulation.releaseBehavior = .stay
            manipulation.dynamics.scalingBehavior = .none
            // No springy settle on release: in every module the MODEL owns
            // motion, so the system's inertia only fights it — parts should
            // stop dead exactly where the hand leaves them.
            manipulation.dynamics.inertia = .zero
            entity.components.set(manipulation)
        }
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

/// Routes manipulation events to per-entity callbacks. Positions are in
/// scene (immersive-space) coordinates.
@MainActor
public final class ManipulationRouter {
    public var onBegin: ((_ entityName: String, _ position: SIMD3<Float>) -> Void)?
    public var onMove: ((_ entityName: String, _ position: SIMD3<Float>) -> Void)?
    public var onEnd: ((_ entityName: String, _ position: SIMD3<Float>) -> Void)?

    public init() {}

    /// Subscribes to the three lifecycle events; retain the returned
    /// subscriptions for as long as the scene lives.
    public func subscriptions(for content: RealityViewContent) -> [EventSubscription] {
        [
            content.subscribe(to: ManipulationEvents.WillBegin.self) { [weak self] event in
                self?.onBegin?(event.entity.name, event.entity.position(relativeTo: nil))
            },
            content.subscribe(to: ManipulationEvents.DidUpdateTransform.self) { [weak self] event in
                self?.onMove?(event.entity.name, event.entity.position(relativeTo: nil))
            },
            content.subscribe(to: ManipulationEvents.WillEnd.self) { [weak self] event in
                self?.onEnd?(event.entity.name, event.entity.position(relativeTo: nil))
            },
        ]
    }
}
