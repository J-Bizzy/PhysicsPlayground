//
//  ModulePanel.swift
//  Physics Playground — Shell
//
//  The shared panel building blocks every module's controls are built from:
//
//  · PanelSection — the standard material card (one look for every module).
//  · LegendView — a module's legend items in the house legend style,
//    rendered by the shell so no module can restyle it.
//
//  Modules compose PanelSections inside makeControls; the shell adds the
//  hint above and the legend + real-world button below.
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
