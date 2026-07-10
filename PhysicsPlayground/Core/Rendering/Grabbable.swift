//
//  Grabbable.swift
//  Physics Playground — Core kernel
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
enum Grabbable {
    /// Makes an entity grabbable with gaze+pinch or direct touch. The
    /// collision shape is bigger than the visible mesh so it's easy to grab.
    static func configure(_ entity: ModelEntity, collisionRadius: Float) {
        ManipulationComponent.configureEntity(
            entity,
            collisionShapes: [.generateSphere(radius: collisionRadius)]
        )
        if var manipulation = entity.components[ManipulationComponent.self] {
            // Stay where dropped instead of animating back to the origin,
            // and don't let two-handed gestures resize physics objects.
            manipulation.releaseBehavior = .stay
            manipulation.dynamics.scalingBehavior = .none
            entity.components.set(manipulation)
        }
    }
}

/// Routes manipulation events to per-entity callbacks. Positions are in
/// scene (immersive-space) coordinates.
@MainActor
final class ManipulationRouter {
    var onBegin: ((_ entityName: String, _ position: SIMD3<Float>) -> Void)?
    var onMove: ((_ entityName: String, _ position: SIMD3<Float>) -> Void)?
    var onEnd: ((_ entityName: String, _ position: SIMD3<Float>) -> Void)?

    /// Subscribes to the three lifecycle events; retain the returned
    /// subscriptions for as long as the scene lives.
    func subscriptions(for content: RealityViewContent) -> [EventSubscription] {
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
