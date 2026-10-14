//
//  ControlAttachment.swift
//  RenderKit — Controls
//
//  How a control stands in the room: the family's own SwiftUI view, on
//  its own glass, carried by an entity through `ViewAttachmentComponent`.
//  The owner positions, turns and folds the entity; SwiftUI draws it,
//  hit-tests it, hovers it and reads it to VoiceOver. So the entity has
//  no collider and no input target of its own — a pinch is the button's,
//  and nothing invisible stands in front of the apparatus.
//
//  `RoomControl` is the state such a control shows. The owner writes it
//  only when something changed (the per-frame path must not churn
//  SwiftUI), and the view reads it.
//

import RealityKit
import SwiftUI
import UIKit

/// What one control standing in the room shows right now.
@MainActor
@Observable
public final class RoomControl {
    public var title: String
    public var systemImage: String
    /// A toggle's state, or a picker choice being the current one.
    public var isOn: Bool
    /// A confirming button between its first and second press.
    public var isArmed: Bool
    /// Off, the control dims and refuses the press.
    public var isEnabled: Bool
    /// One quiet line under the control: a folding tab's live summary.
    public var detail: String?

    public init(title: String, systemImage: String, isOn: Bool = false,
                isArmed: Bool = false, isEnabled: Bool = true,
                detail: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.isArmed = isArmed
        self.isEnabled = isEnabled
        self.detail = detail
    }

    // Change-gated writers: assigning an @Observable property always
    // notifies, so the per-frame path goes through these.

    public func setOn(_ value: Bool) { if isOn != value { isOn = value } }
    public func setArmed(_ value: Bool) { if isArmed != value { isArmed = value } }
    public func setEnabled(_ value: Bool) { if isEnabled != value { isEnabled = value } }
    public func setDetail(_ value: String?) { if detail != value { detail = value } }
}

/// The shapes a room control can take. All of them are the window's
/// controls; only the glass they stand on is added here.
public enum RoomControlKind {
    /// A momentary action. `.destructive` arms through `RoomControl.isArmed`.
    case button(ControlButton.Emphasis, iconOnly: Bool)
    /// A latching switch — a display layer, a mode, an open tab.
    case toggle(iconOnly: Bool)
}

/// The view a room control renders: the family's button or toggle on a
/// capsule of glass, with its detail line beneath.
public struct RoomControlView: View {
    let control: RoomControl
    let kind: RoomControlKind
    let press: () -> Void

    public init(control: RoomControl, kind: RoomControlKind,
                press: @escaping () -> Void) {
        self.control = control
        self.kind = kind
        self.press = press
    }

    public var body: some View {
        VStack(spacing: 6) {
            Group {
                switch kind {
                case .button(let emphasis, let iconOnly):
                    ControlButton(control.title, systemImage: control.systemImage,
                                  emphasis: emphasis, iconOnly: iconOnly,
                                  armed: control.isArmed, action: press)
                case .toggle(let iconOnly):
                    ControlToggle(control.title, systemImage: control.systemImage,
                                  iconOnly: iconOnly,
                                  isOn: { control.isOn }, set: { _ in press() })
                }
            }
            .disabled(!control.isEnabled)
            .padding(6)
            .glassBackgroundEffect(in: Capsule())

            if let detail = control.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassBackgroundEffect(in: Capsule())
                    .accessibilityHidden(true)
            }
        }
        .fixedSize()
        .accessibilityValue(control.detail ?? "")
    }
}

@MainActor
public enum ControlAttachment {
    /// An entity carrying `view`, named so a walk-up from a tap (or a test)
    /// can find it. No collider, no input target: SwiftUI owns the input.
    public static func entity<V: View>(_ view: V, name: String) -> Entity {
        let entity = Entity()
        entity.name = name
        entity.components.set(ViewAttachmentComponent(rootView: view))
        return entity
    }

    /// A room control: the state, the shape and what a press does.
    public static func control(_ control: RoomControl, kind: RoomControlKind,
                               name: String,
                               press: @escaping () -> Void) -> Entity {
        entity(RoomControlView(control: control, kind: kind, press: press),
               name: name)
    }

    /// Whether `entity` is a control drawn by the family.
    public static func isControl(_ entity: Entity) -> Bool {
        entity.components[ViewAttachmentComponent.self] != nil
    }
}

/// How much room a control standing in the room takes, in metres, for an
/// owner keeping a bank clear of the apparatus. Measured from the label's
/// own type, so a longer name is a wider control, not a guess.
public enum RoomControlFootprint {
    /// The platter's padding around its label, both sides, plus the glass
    /// around the platter, in points.
    static let chromeWidth: CGFloat = 2 * 22 + 2 * 6
    /// Symbol plus the gap to the title, in points.
    static let iconWidth: CGFloat = 22 + 10
    /// A control's height on its glass, in metres.
    public static let height: Float =
        ControlMetrics.meters(ControlMetrics.minimumTarget + 2 * 6)

    /// Half the width of the widest of these labels as a button or toggle
    /// with a symbol — the control is centred on its anchor.
    public static func halfWidth(forLongestOf labels: [String]) -> Float {
        let font = UIFont.systemFont(ofSize: 17, weight: .medium)
        let widest = labels
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return ControlMetrics.meters(chromeWidth + iconWidth + ceil(widest)) / 2
    }

    /// An icon-only control's half width, in metres.
    public static let iconOnlyHalfWidth: Float =
        ControlMetrics.meters(ControlMetrics.minimumTarget + 2 * 6) / 2
}
