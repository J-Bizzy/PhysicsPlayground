//
//  SpatialAction.swift
//  RenderKit
//
//  How a control in the room gets operated without hands. A component
//  rather than a registry: it is carried by the entity, found by walking
//  up from whatever VoiceOver activated (the same walk every
//  `handleTap` does), and dies with the entity. `attach` writes both the
//  advertised `systemActions` and the action itself, so the two cannot
//  drift.
//

import RealityKit
import SwiftUI
import Foundation

/// What a spatial control does when something other than a hand asks.
public struct SpatialActionComponent: Component {
    /// Press it. The same effect a pinch has.
    public var activate: (() -> Void)?
    /// Nudge a continuous value. `+1` is one increment, `−1` one
    /// decrement; the primitive decides what a step means, because only
    /// it knows the range.
    public var adjust: ((Double) -> Void)?

    public init(activate: (() -> Void)? = nil,
                adjust: ((Double) -> Void)? = nil) {
        self.activate = activate
        self.adjust = adjust
    }
}

@MainActor
public enum SpatialActions {
    /// Makes `entity` operable by VoiceOver, and announces that it is.
    ///
    /// One call so the two halves cannot drift: the accessibility
    /// component advertises the action, this component performs it.
    public static func attach(to entity: Entity,
                       label: String,
                       value: String? = nil,
                       activate: (() -> Void)? = nil,
                       adjust: ((Double) -> Void)? = nil) {
        var accessibility = entity.components[AccessibilityComponent.self]
            ?? AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: label)
        if let value {
            accessibility.value = LocalizedStringResource(stringLiteral: value)
        }
        var actions: AccessibilityComponent.SupportedActions = []
        if activate != nil { actions.insert(.activate) }
        if adjust != nil { actions.formUnion([.increment, .decrement]) }
        accessibility.systemActions = actions
        entity.components.set(accessibility)
        entity.components.set(SpatialActionComponent(activate: activate,
                                                     adjust: adjust))
    }

    /// Says what `entity` is to VoiceOver without touching what it can
    /// do. The only way to write a label after `attach`: a fresh
    /// `AccessibilityComponent` drops the `systemActions` it advertised,
    /// and the object goes on being read out but stops answering Activate
    /// — which is how ten objects in seven labs lost their rings until
    /// 2026-10-27. `AccessibilityWriteCriterionTests` holds it.
    public static func describe(_ entity: Entity, label: String, value: String? = nil) {
        var accessibility = entity.components[AccessibilityComponent.self]
            ?? AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: label)
        if let value {
            accessibility.value = LocalizedStringResource(stringLiteral: value)
        }
        entity.components.set(accessibility)
    }

    /// The label a caller already wrote, if any — so `attach` from a
    /// touch target keeps a name instead of reading out the entity's.
    public static func existingLabel(of entity: Entity) -> String? {
        guard let label = entity.components[AccessibilityComponent.self]?.label else { return nil }
        let text = String(localized: label)
        return text.isEmpty ? nil : text
    }

    /// Re-publishes just the spoken value. Separate from `attach` because
    /// it is called on every state change, not at construction — a plate
    /// that publishes once reads its launch state forever.
    public static func republish(value: String, on entity: Entity) {
        guard var accessibility = entity.components[AccessibilityComponent.self]
        else { return }
        accessibility.value = LocalizedStringResource(stringLiteral: value)
        entity.components.set(accessibility)
    }

    /// Walks up from whatever was activated to the nearest control that
    /// knows what to do, exactly as the gesture chains do — VoiceOver
    /// lands on the entity carrying the accessibility component, but a
    /// primitive may well have put its collider on a child.
    @discardableResult
    public static func activate(_ entity: Entity) -> Bool {
        perform(from: entity) { $0.activate?() ; return $0.activate != nil }
    }

    @discardableResult
    public static func adjust(_ entity: Entity, by delta: Double) -> Bool {
        perform(from: entity) { $0.adjust?(delta) ; return $0.adjust != nil }
    }

    private static func perform(from entity: Entity,
                                _ body: (SpatialActionComponent) -> Bool) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if let action = candidate.components[SpatialActionComponent.self],
               body(action) {
                return true
            }
            current = candidate.parent
        }
        return false
    }
}
