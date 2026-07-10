//
//  RealWorldPanel.swift
//  Physics Playground — Shell
//
//  The shared "where this shows up in the real world" presentation: a
//  tagline plus 2–4 application cards, identical in layout for every
//  module. The shell shows the button; the module only supplies the story.
//

import SwiftUI

/// The prominent button the shell places under every module's controls.
struct RealWorldButton: View {
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Where this shows up in the real world", systemImage: "globe.americas.fill")
                .font(DesignTokens.TypeScale.control)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .accessibilityHint("Real applications of this physics, from everyday devices to natural phenomena")
    }
}

struct RealWorldPanel: View {
    let moduleTitle: String
    let story: RealWorldStory
    let accent: Color

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Panel.sectionSpacing) {
                    Text(story.tagline)
                        .font(DesignTokens.TypeScale.cardTitle)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(story.applications) { application in
                        applicationCard(application)
                    }
                }
                .padding(DesignTokens.Panel.outerPadding)
            }
            .navigationTitle("\(moduleTitle) in the Real World")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close real-world panel")
                }
            }
        }
    }

    private func applicationCard(_ application: RealWorldStory.Application) -> some View {
        PanelSection {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: application.icon)
                    .font(.system(size: 30))
                    .foregroundStyle(accent)
                    .frame(width: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(application.title)
                        .font(DesignTokens.TypeScale.sectionHeader)
                    Text(application.body)
                        .font(DesignTokens.TypeScale.label)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
