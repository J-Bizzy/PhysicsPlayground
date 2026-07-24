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

/// The house legend: one row per LegendItem, swatch shapes matching how
/// each concept is drawn in the scene.
struct LegendView: View {
    let items: [LegendItem]

    var body: some View {
        PanelSection("Legend") {
            VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
                ForEach(items) { item in
                    HStack(spacing: DesignTokens.Panel.rowSpacing) {
                        swatch(item.swatch)
                            .frame(width: 22, alignment: .center)
                        Text(item.text)
                            .font(DesignTokens.TypeScale.label)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func swatch(_ swatch: LegendItem.Swatch) -> some View {
        switch swatch {
        case .fill(let color):
            Circle().fill(color).frame(width: 18, height: 18)
        case .translucent(let color):
            Circle().fill(color.opacity(0.35)).frame(width: 18, height: 18)
        case .stroke(let color):
            Circle().stroke(color, lineWidth: 2).frame(width: 18, height: 18)
        case .line(let color):
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 18, height: 3)
        case .symbol(let name, let color):
            Image(systemName: name).foregroundStyle(color)
        }
    }
}
