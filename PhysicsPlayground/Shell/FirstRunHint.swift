//
//  FirstRunHint.swift
//  Physics Playground — Shell
//
//  The one-tooltip first-run hint, identical in style across modules: an
//  icon, one sentence from the module's descriptor, and a dismiss button.
//  Dismissal is remembered per module, so each module hints exactly once.
//

import SwiftUI

struct FirstRunHint: View {
    private let text: String
    @AppStorage private var dismissed: Bool

    init(module: ModuleDescriptor) {
        text = module.firstRunHint
        _dismissed = AppStorage(wrappedValue: false, "hint.dismissed.\(module.id)")
    }

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: DesignTokens.Panel.rowSpacing) {
                Image(systemName: "hand.pinch")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(text)
                    .font(DesignTokens.TypeScale.label)
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss hint")
            }
            .padding(16)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: DesignTokens.Panel.hintCornerRadius)
            )
        }
    }
}
