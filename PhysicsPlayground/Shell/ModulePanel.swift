//
//  ModulePanel.swift
//  Physics Playground — Shell
//
//  The shared panel building blocks every module's controls are built from:
//
//  · PanelSection — the standard material card (one look for every module).
//  · CollapsedSection — a card that shows only its header until opened,
//    so a panel stays one glance tall with depth on demand.
//  · LegendView — a module's legend items in the house legend style,
//    rendered by the shell so no module can restyle it.
//
//  Modules compose sections inside makeControls; the shell renders the
//  first-run hint above and appends the legend below.
//

import SwiftUI

/// The standard rounded material card used for every group of controls.
struct PanelSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Panel.padding) {
            if let title {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(DesignTokens.TypeScale.sectionHeader)
                        .accessibilityAddTraits(.isHeader)
                    // A quiet hairline under every section header — the
                    // same designed underline the pods use, so the flat
                    // panel and the spatial pods read as one system.
                    LinearGradient(
                        colors: [.secondary.opacity(0.35), .secondary.opacity(0.04)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 1)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Panel.padding)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DesignTokens.Panel.cornerRadius, style: .continuous)
        )
    }
}

/// A card that shows only its header until opened — the panel stays
/// one glance tall, and depth is there when asked for.
struct CollapsedSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        PanelSection {
            DisclosureGroup {
                VStack(alignment: .leading,
                       spacing: DesignTokens.Panel.rowSpacing) {
                    content
                }
                .padding(.top, 10)
            } label: {
                Text(title)
                    .font(DesignTokens.TypeScale.sectionHeader)
                    .accessibilityAddTraits(.isHeader)
            }
            .tint(.secondary)
        }
    }
}

/// A module's legend, rendered by the shell in the one house style.
/// Swatch shapes match how each concept is actually drawn in the scene,
/// so the legend reads as a key, not prose.
struct LegendView: View {
    let items: [LegendItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    swatch(item.swatch)
                        .frame(width: 22, height: 16)
                    Text(item.text)
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func swatch(_ swatch: LegendItem.Swatch) -> some View {
        switch swatch {
        case .fill(let color):
            Circle().fill(color).frame(width: 14, height: 14)
        case .translucent(let color):
            Circle().fill(color.opacity(0.35))
                .overlay(Circle().stroke(color.opacity(0.6), lineWidth: 1))
                .frame(width: 14, height: 14)
        case .stroke(let color):
            Circle().stroke(color, lineWidth: 2).frame(width: 13, height: 13)
        case .line(let color):
            Capsule().fill(color).frame(width: 22, height: 3)
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}
