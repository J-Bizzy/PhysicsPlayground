//
//  PodButtonStyle.swift
//  Physics Playground — DesignSystem
//
//  The house button styles the pods and panels share, so the controls
//  read as one crafted set of instruments rather than stock iOS
//  capsules. Two roles:
//
//  · .podProminent — a filled accent capsule with a soft top sheen, for
//    the one primary action in a pod (Add, Fire, Strike…).
//  · .podQuiet — an accent-tinted glass capsule with a hairline border,
//    for the many secondary actions (presets, modes, remove…).
//
//  Both pick up the module's colour from the `podAccent` environment
//  value — set once by ControlPod and the module window — so a button
//  never has to name its own colour. The rare semantically-coloured
//  button (red = positive charge, blue = negative) passes an explicit
//  colour to .podProminent(_:). Destructive buttons colour themselves
//  red from the button role.
//

import SwiftUI

// MARK: Accent handed down to the buttons

private struct PodAccentKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    /// The tint every house button in this subtree fills or strokes with.
    var podAccent: Color {
        get { self[PodAccentKey.self] }
        set { self[PodAccentKey.self] = newValue }
    }
}

// MARK: Prominent — the one filled primary action

struct PodProminentButtonStyle: ButtonStyle {
    /// An explicit colour overrides the inherited accent (the red/blue
    /// charge buttons); nil means "use the module's accent".
    var color: Color?

    @Environment(\.podAccent) private var accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = color ?? accent
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .background(Capsule(style: .continuous).fill(fill.gradient))
            .overlay(
                // A thin top-lit rim so the capsule reads as a solid,
                // lit key rather than a flat swatch.
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.75)
            )
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule(style: .continuous))
            .hoverEffect()
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: Quiet — the many secondary actions

struct PodQuietButtonStyle: ButtonStyle {
    @Environment(\.podAccent) private var accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        let key = destructive ? Color.red : accent
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .background(
                Capsule(style: .continuous)
                    .fill(key.opacity(configuration.isPressed ? 0.24 : 0.13))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(key.opacity(0.42), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule(style: .continuous))
            .hoverEffect()
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: Call-site sugar

extension ButtonStyle where Self == PodProminentButtonStyle {
    /// Filled in the module's accent.
    static var podProminent: PodProminentButtonStyle { .init(color: nil) }
    /// Filled in a specific colour (the semantic charge buttons).
    static func podProminent(_ color: Color) -> PodProminentButtonStyle { .init(color: color) }
}

extension ButtonStyle where Self == PodQuietButtonStyle {
    static var podQuiet: PodQuietButtonStyle { .init() }
}
