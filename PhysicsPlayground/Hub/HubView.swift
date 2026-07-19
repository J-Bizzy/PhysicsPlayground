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

            Image(systemName: "atom")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityHidden(true)

            Text("Physics Playground")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("The exhibits circle this title.\nLook at one and pinch to step inside.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            if !appModel.challenges.completed.isEmpty {
                Label(
                    "\(appModel.challenges.completed.count) of \(ChallengeCatalog.total(appModel: appModel)) challenges",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.footnote)
                .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.4))
            }

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
