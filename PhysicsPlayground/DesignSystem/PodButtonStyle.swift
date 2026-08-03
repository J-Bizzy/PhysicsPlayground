//
//  PodButtonStyle.swift
//  Physics Playground — DesignSystem
//
//  The house button styles the shell windows share, so the few flat
//  buttons that remain read as one crafted set rather than stock iOS
//  capsules. Two roles:
//
//  · .podProminent — a filled accent capsule with a soft top sheen, for
//    a window's one primary action ("Show in room", Capture, Enter).
//  · .podQuiet — a tinted glass capsule with a hairline border, for
//    secondary actions (the notebook's per-row Delete…).
//
//  A caller that wants the active module's colour passes it explicitly
//  to .podProminent(_:); with no argument the button wears the system
//  accent. (These styles once read a `podAccent` environment value set
//  by ControlPod — deleted with the panels on 2026-08-01. The key
//  outlived its only writers, so every button was already rendering
//  the default; it is gone now.) Destructive buttons colour themselves
//  red from the button role.
//

import SwiftUI

// MARK: Prominent — the one filled primary action

struct PodProminentButtonStyle: ButtonStyle {
    /// An explicit colour (the module's accent, a semantic red/blue);
    /// nil means the system accent.
    var color: Color?

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = color ?? .accentColor
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
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        let key = destructive ? Color.red : Color.accentColor
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
    /// Filled in the system accent.
    static var podProminent: PodProminentButtonStyle { .init(color: nil) }
    /// Filled in a specific colour (a module accent, a semantic red/blue).
    static func podProminent(_ color: Color) -> PodProminentButtonStyle { .init(color: color) }
}

extension ButtonStyle where Self == PodQuietButtonStyle {
    static var podQuiet: PodQuietButtonStyle { .init() }
}
