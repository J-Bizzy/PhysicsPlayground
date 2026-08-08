//
//  SpatialAction.swift
//  RenderKit
//
//  MOVED DOWN A LAYER on 2026-08-08, from the app target's DesignSystem.
//  It lived up there because that is where the primitives that needed it
//  first happened to live — and the consequence was that the two files
//  in RenderKit which stand input targets could not reach it.
//  `SpatialTrackControl` — the app's one continuous control, and the
//  file whose own header wrote the complaint this mechanism answers —
//  was announced, adjustable-looking and inoperable for that reason
//  alone. A shared RealityKit primitive belongs in the shared RealityKit
//  layer.
//
//  HOW A CONTROL IN THE ROOM GETS OPERATED WITHOUT HANDS.
//
//  `grep -rn "systemActions\|AccessibilityEvents"` returned ZERO matches
//  across this whole project. Twenty files set `isAccessibilityElement`
//  and populate `label` and `value`, so every plate, petal, disc, rail,
//  well and grip is announced and readable — and not one of them could
//  be operated. Since the window panels were deleted there is no
//  fallback surface either, so for a VoiceOver user this app was six
//  rooms of readouts with no controls at all. The file that should know
//  best says so itself:
//
//      // SpatialTrackControl.swift — a track replaces a `Slider`, and a
//      // slider is already an adjustable element that speaks its value.
//      // Migrating without this trades a control someone could operate
//      // blind for one they cannot.
//
//  The `value` was added. The adjustability was not.
//
//  WHY A COMPONENT AND NOT A REGISTRY. The obvious shape is a table
//  mapping entity to closure, and it is wrong twice: it needs weak
//  references and pruning to avoid holding pooled entities alive, and it
//  needs every primitive to remember to deregister. A component is
//  carried BY the entity, so it is found by walking up from whatever
//  VoiceOver activated — the same walk every `handleTap` in this app
//  already does — and it dies with the entity it belongs to. Nothing to
//  leak and nothing to remember.
//
//  Setting it is HALF the job. `AccessibilityComponent.systemActions`
//  is what makes VoiceOver offer the action at all, and this is what
//  happens when it is taken; a primitive needs both, which is why
//  `attach` writes both and nobody should be writing either by hand.
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

    /// Re-publishes just the spoken value.
    ///
    /// SEPARATE FROM `attach` BECAUSE IT IS CALLED FROM A DIFFERENT
    /// PLACE — on every state change, not at construction — and that is
    /// exactly the distinction `SpatialLayerBank` got wrong. It sets its
    /// accessibility component once when the plate is built and never
    /// again, so VoiceOver reads the LAUNCH state of thirty-five display
    /// toggles for the rest of the session; toggle "Field lines" and it
    /// still says "hidden". `SpatialActionBank` does this correctly and
    /// has a test for it.
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
