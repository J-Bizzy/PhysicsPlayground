//
//  ModulePanel.swift
//  Physics Playground — Shell
//
//  Two shared building blocks. There used to be three, and there used to
//  be module panels to build out of them.
//
//  · PanelSection — the standard material card. Its callers are now the
//    NOTEBOOK and the settings window; no module has one.
//  · LegendView — a module's legend items in the house legend style,
//    rendered by the shell (from the title bar's Key popover) so that no
//    module can restyle or forget it.
//
//  CollapsedSection is deleted, and it is worth saying which kind of
//  corpse it is: a GRAVE, not a missing door. The disclosure card was not
//  abandoned half-built — the surface it existed for was decided against
//  (DECISIONS.md, 2026-08-01), and every one of the fourteen dropdowns it
//  drew is either standing in the room now or was prose describing where
//  a control had gone.
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
