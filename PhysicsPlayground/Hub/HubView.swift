//
//  HubView.swift
//  Physics Playground — Hub
//
//  The window half of the hub. The real menu floats in the room
//  (HubSpaceView): this window opens that space on launch, explains the
//  gesture, and keeps a plain list of the exhibits — the path for
//  VoiceOver users and anyone who'd rather tap a button than pinch a
//  bubble.
//

import SwiftUI

struct HubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Panel.sectionSpacing) {
                VStack(spacing: 6) {
                    Text("Physics Playground")
                        .font(DesignTokens.TypeScale.screenTitle)
                    Text("The exhibits are floating around you — look at a bubble and pinch to step inside.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)

                if !appModel.isImmersiveSpaceOpen {
                    Button {
                        Task {
                            _ = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
                        }
                    } label: {
                        Label("Show the exhibits", systemImage: "sparkles")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Places the menu bubbles in your room")
                }

                PanelSection("Exhibits") {
                    ForEach(ModuleCatalog.all(appModel: appModel)) { module in
                        Button {
                            appModel.activeModuleID = module.id
                        } label: {
                            HStack(spacing: DesignTokens.Panel.rowSpacing) {
                                Image(systemName: module.icon)
                                    .font(.title3)
                                    .foregroundStyle(module.accent)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(module.title)
                                        .font(DesignTokens.TypeScale.sectionHeader)
                                    Text(module.blurb)
                                        .font(DesignTokens.TypeScale.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(module.title). \(module.blurb)")
                        .accessibilityHint("Opens this exhibit")
                    }
                }
            }
            .padding(DesignTokens.Panel.outerPadding)
        }
        .task {
            // The spatial menu is the hub — bring it up on arrival.
            if !appModel.isImmersiveSpaceOpen {
                _ = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
            }
        }
    }
}