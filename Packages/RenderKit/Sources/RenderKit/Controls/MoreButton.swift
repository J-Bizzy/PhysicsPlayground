//
//  MoreButton.swift
//  RenderKit — Controls
//
//  The one way in to whatever is secondary. Every surface that hides
//  something hides it behind this: an ellipsis that reads as selected
//  while what it opened is showing, and a glass panel that holds what it
//  opened. Nothing else in the app folds or unfolds a set of controls.
//

import SwiftUI

public struct MoreButton: View {
    @Binding private var isExpanded: Bool
    private let title: String

    public init(isExpanded: Binding<Bool>, title: String = "More") {
        self._isExpanded = isExpanded
        self.title = title
    }

    public var body: some View {
        ControlToggle(title, systemImage: "ellipsis", iconOnly: true,
                      isOn: $isExpanded)
            .accessibilityHint(isExpanded ? "Hides the extra controls"
                                          : "Shows the extra controls")
    }
}

/// The glass a set of controls stands on: one panel, rounded, padded the
/// same everywhere — the title bar's More, a room's More, the Physics box.
public struct ControlPanel<Content: View>: View {
    private let title: String?
    private let content: Content

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ControlMetrics.spacing) {
            if let title {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(ControlMetrics.panelPadding)
        .glassBackgroundEffect(
            in: RoundedRectangle(cornerRadius: ControlMetrics.panelRadius,
                                 style: .continuous))
    }
}

/// A titled group inside a panel: a quiet caption over its controls.
public struct ControlSection<Content: View>: View {
    private let title: String
    private let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ControlMetrics.spacing) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}
