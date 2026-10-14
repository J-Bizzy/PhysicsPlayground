//
//  ControlButton.swift
//  RenderKit — Controls
//
//  The one button. A stock visionOS bordered button — glass platter,
//  system hover — at extra-large size, so the target clears 60 pt, with
//  an SF Symbol and a name. Three emphases: standard, prominent (one per
//  surface, the stock white platter) and destructive. A destructive button can
//  arm first: the first press says "Tap again", a second within
//  `ControlMetrics.armWindow` fires, and the window running out disarms.
//  The arming lives in the button (window controls) or is handed in by
//  an owner that keeps its own (a room bank that a reset must disarm).
//

import SwiftUI

public struct ControlButton: View {
    public enum Emphasis {
        case standard
        /// The surface's one primary action: the stock prominent platter,
        /// white with dark type. Never tinted — a lab's accent under white
        /// type is unreadable for half the accents in the house.
        case prominent
        case destructive
    }

    private let title: String
    private let systemImage: String
    private let emphasis: Emphasis
    private let iconOnly: Bool
    private let fillsWidth: Bool
    private let confirms: Bool
    /// Arming owned by the caller; nil means the button keeps its own.
    private let externalArmed: Bool?
    private let action: () -> Void

    @State private var armed = false

    /// - Parameters:
    ///   - fillsWidth: one row of a list — the label runs the width of its
    ///     column, leading-aligned.
    ///   - confirms: arm on the first press, fire on the second.
    ///   - armed: when the owner keeps the arming state, what it is now.
    ///     The owner then decides what a press does; `action` is called
    ///     on every press.
    public init(_ title: String,
                systemImage: String,
                emphasis: Emphasis = .standard,
                iconOnly: Bool = false,
                fillsWidth: Bool = false,
                confirms: Bool = false,
                armed: Bool? = nil,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.emphasis = emphasis
        self.iconOnly = iconOnly
        self.fillsWidth = fillsWidth
        self.confirms = confirms
        self.externalArmed = armed
        self.action = action
    }

    private var isArmed: Bool { externalArmed ?? armed }

    public var body: some View {
        Button(role: isDestructive ? .destructive : nil) {
            press()
        } label: {
            Label(isArmed ? ControlMetrics.armedTitle : title,
                  systemImage: isArmed ? "checkmark" : systemImage)
                .labelStyle(.controlLabel(iconOnly: iconOnly && !isArmed,
                                          fillsWidth: fillsWidth))
        }
        .modifier(ControlEmphasisStyle(emphasis: emphasis, armed: isArmed))
        .buttonBorderShape(iconOnly && !isArmed ? .circle : .capsule)
        .controlSize(.extraLarge)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(isArmed ? "armed — tap again to confirm" : "")
        .task(id: armed) {
            // The button's own arming runs down here; an owner's runs down
            // wherever the owner keeps it.
            guard armed else { return }
            try? await Task.sleep(for: .seconds(ControlMetrics.armWindow))
            armed = false
        }
    }

    private var isDestructive: Bool {
        if case .destructive = emphasis { return true }
        return false
    }

    private func press() {
        guard externalArmed == nil, confirms else {
            action()
            return
        }
        if armed {
            armed = false
            action()
        } else {
            armed = true
        }
    }
}

/// Standard is the bordered platter; prominent and an armed destructive
/// button are filled. Shared by every control in the family.
struct ControlEmphasisStyle: ViewModifier {
    let emphasis: ControlButton.Emphasis
    var armed: Bool = false

    func body(content: Content) -> some View {
        switch emphasis {
        case .prominent:
            content.buttonStyle(.borderedProminent)
        case .destructive where armed:
            content.buttonStyle(.borderedProminent).tint(.red)
        case .destructive, .standard:
            content.buttonStyle(.bordered)
        }
    }
}

/// The family's label: a symbol and a name, or the symbol alone with the
/// name kept for VoiceOver and the hover tooltip. Icon-only labels are
/// square, so a circle border shape stays round.
public struct ControlLabelStyle: LabelStyle {
    let iconOnly: Bool
    var fillsWidth: Bool = false

    public func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
                .font(.title3.weight(.medium))
                .frame(width: ControlMetrics.minimumTarget - 16,
                       height: ControlMetrics.minimumTarget - 16)
        } else {
            HStack(spacing: 10) {
                configuration.icon
                    .font(.body.weight(.semibold))
                configuration.title
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if fillsWidth { Spacer(minLength: 0) }
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil,
                   minHeight: ControlMetrics.minimumTarget - 16)
        }
    }
}

public extension LabelStyle where Self == ControlLabelStyle {
    static func controlLabel(iconOnly: Bool,
                             fillsWidth: Bool = false) -> ControlLabelStyle {
        ControlLabelStyle(iconOnly: iconOnly, fillsWidth: fillsWidth)
    }
}
