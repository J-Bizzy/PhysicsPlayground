//
//  ModulePanel.swift
//  Physics Playground — Shell
//
//  Two shared building blocks: PanelSection, the material card the
//  notebook and the settings window build from, and LegendView, a
//  module's legend in the house style.
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
                    // A quiet hairline under every section header.
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

/// A module's legend in the one house style; swatch shapes match how
/// each concept is drawn in the scene.
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
