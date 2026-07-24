//
//  HubView.swift
//  Physics Playground — Hub
//
//  The window IS the app title at the hub: bare floating type (the
//  window style is .plain, so there is no glass slab), movable and
//  closable from the window bar beneath it. The exhibits form a ring
//  around this title (HubSpaceView) and are VoiceOver elements
//  in-space, so selection stays accessible.
//

import SwiftUI

struct HubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)

            // The name floats in 3-D as bubble letters above the exhibit
            // ring (HubSpaceView); this window keeps only the hint and
            // the button so it never crowds the title.
            Text("Look at any exhibit in the ring and pinch to step inside.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Button {
                appModel.studioMode.toggle()
            } label: {
                Label(appModel.studioMode ? "Leave the studio" : "Studio Mode",
                      systemImage: appModel.studioMode ? "moon.stars.fill" : "moon.stars")
                    .font(.subheadline)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.podQuiet)
            .fixedSize()
            .accessibilityHint("Replaces your room with a dark studio so every exhibit glows at full contrast")

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
                .buttonStyle(.podProminent)
                .accessibilityHint("Places the exhibit ring in your room")
            }

            Spacer(minLength: 12)
        }
        .padding(DesignTokens.Panel.outerPadding)
        .frame(minWidth: 440, maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
        // Bare type over passthrough needs its own separation from the room.
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
        .task {
            SoundPalette.warmUp()
            // The spatial ring is the menu — bring it up on arrival.
            if !appModel.isImmersiveSpaceOpen {
                _ = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
            }
        }
    }
}
