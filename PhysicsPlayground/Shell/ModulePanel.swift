//
//  ModulePanel.swift
//  Physics Playground — Shell
//
//  PanelSection, the material card the settings window builds from.
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
