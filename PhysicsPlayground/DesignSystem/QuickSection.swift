//
//  QuickSection.swift
//  Physics Playground — Design system
//
//  A collapsible section for the in-space quick panels: a tappable
//  header with a chevron, content folded away until wanted. Panels
//  stay small; depth appears on demand.
//

import SwiftUI

struct QuickSection<Content: View>: View {
    let title: String
    @State private var isExpanded: Bool
    @ViewBuilder let content: Content

    init(_ title: String, expanded: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        _isExpanded = State(initialValue: expanded)
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.top, 6)
        } label: {
            Text(title)
                .font(DesignTokens.TypeScale.label)
                .foregroundStyle(.primary)
        }
        .disclosureGroupStyle(.automatic)
    }
}
