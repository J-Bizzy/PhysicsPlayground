//
//  HubView.swift
//  Physics Playground — Hub
//
//  The window half of the hub, kept deliberately minimal: the real menu
//  is the carousel of exhibits orbiting the user (HubSpaceView). This
//  window opens that space on launch, names the app, and offers the
//  reopen affordance if the space was closed. The exhibits themselves
//  are VoiceOver elements, so selection remains accessible in-space.
//

import SwiftUI

struct HubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "atom")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Physics Playground")
                .font(DesignTokens.TypeScale.screenTitle)

            Text("The exhibits are drifting around you.\nLook at one and pinch to step inside.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !appModel.isImmersiveSpaceOpen {
                Button {
                    Task {
                        _ = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
                    }
                } label: {
                    Label("Show the exhibits", systemImage: "sparkles")
                        .font(.title3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Places the exhibit carousel in your room")
            }

            Spacer()
        }
        .padding(DesignTokens.Panel.outerPadding)
        .task {
            SoundPalette.warmUp()
            // The spatial menu is the hub — bring it up on arrival.
            if !appModel.isImmersiveSpaceOpen {
                _ = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
            }
        }
    }
}
