//
//  HubView.swift
//  Physics Playground — Hub
//
//  The hub's window. Two states: with the gallery not in the room, the
//  full front door (the app's name, one button that raises the gallery,
//  and the domain-grouped catalog); with the gallery in the room, the
//  same catalog compactly. The flat catalog is the accessibility path —
//  nothing may be reachable only in space — so this window never blanks.
//

import SwiftUI

struct HubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var openFailed = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)

            if !appModel.isImmersiveSpaceOpen {
                VStack(spacing: 5) {
                    Text("Physics Playground")
                        .font(DesignTokens.TypeScale.wordmark())
                    Text("Room-scale physics labs, in your actual room.")
                        .font(DesignTokens.TypeScale.label)
                        .foregroundStyle(.secondary)
                }

                if openFailed {
                    // Say what happened; retry only by hand, never a loop.
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("The Gallery couldn't open.")
                            .font(DesignTokens.TypeScale.footnote)
                        Button("Try Again") { Task { await openGallery() } }
                            .font(DesignTokens.TypeScale.footnote.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // The way back, not the way in: the app launches into the gallery, so
                // this is reached by putting the gallery away or by the Digital Crown,
                // and it must reopen what the catalog lists.
                Button {
                    Task { await openGallery() }
                } label: {
                    Label("Enter the Gallery", systemImage: "sparkles")
                        .font(.title3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.podProminent)
                .accessibilityHint("Places the Gallery — the exhibit terraces — in your room")

                RoomSensingNote()
                HubCatalogList()
            } else {
                // The compact state: the same catalog without the ceremony, since the
                // gallery already has its own sign over the door.
                RoomSensingNote()
                HubCatalogList(isCompact: true)

                // The way out of the room entirely — the only `dismissImmersiveSpace`
                // in the app. The palette's home petal leaves a lab; this leaves the
                // room. Seen when the window is asked for while the gallery is up.
                Button {
                    Task {
                        appModel.closeForDismissal()
                        await dismissImmersiveSpace()
                    }
                } label: {
                    Label("Put the Gallery away", systemImage: "xmark.circle")
                        .font(DesignTokens.TypeScale.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityHint("Closes the room and returns to this window")
            }

            Spacer(minLength: 12)
        }
        .padding(DesignTokens.Panel.outerPadding)
        .frame(minWidth: 440, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        // Bare type over passthrough needs its own separation from the room.
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
        .task {
            // Cheap and idempotent; this view can appear without the space ever
            // having opened.
            SoundPalette.warmUp()
            SoundPalette.masterVolume = appModel.settings.masterVolume
        }
    }

    /// Whether a UI test is driving the app. Not `#if DEBUG`-gated: the UI
    /// test target runs the shipping configuration. Signed off for release:
    /// it only makes the app a window app showing the flat catalog, and a
    /// shipped app launched from the Home View is handed no arguments. Read
    /// by `PlaygroundSpaceView.retreatForUITesting`.
    static var isUITesting: Bool {
        UserDefaults.standard.bool(forKey: "uiTesting")
    }

    private func openGallery() async {
        withAnimation(.easeOut(duration: 0.2)) { openFailed = false }
        // Assets first, then the door: the gallery parses every prop it cannot
        // find in the cache synchronously on the main thread.
        await PropCache.warmUp()
        let result = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
        if case .error = result {
            withAnimation(.easeOut(duration: 0.2)) { openFailed = true }
        }
    }
}

/// What the app is about to ask for, or what it lost when the ask was
/// refused. Pre-explained here because the ARKit session starts from
/// the gallery about a second after launch, before any lab. The
/// sentences are `RoomModel.Sensing`'s.
struct RoomSensingNote: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let sensing = appModel.room.sensing
        Group {
            if sensing == .fine {
                Label(RoomModel.Sensing.preExplanation, systemImage: "arkit")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Label(sensing.headline, systemImage: "exclamationmark.triangle.fill")
                        .font(DesignTokens.TypeScale.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(sensing.detail)
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: 500, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }
}

/// The flat catalog: the modules grouped under their domains, mirroring
/// the terraces the space shows as objects. Shown in both window states.
struct HubCatalogList: View {
    /// Shown beside a gallery already in the room: the domain headers stay,
    /// the vertical rhythm tightens.
    var isCompact = false

    @Environment(AppModel.self) private var appModel

    var body: some View {
        let byID = Dictionary(uniqueKeysWithValues:
            ModuleCatalog.all(appModel: appModel).map { ($0.id, $0) })

        VStack(alignment: .leading, spacing: isCompact ? 10 : 14) {
            ForEach(HubDomain.allCases) { domain in
                let modules = domain.moduleIDs.compactMap { byID[$0] }
                if !modules.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(domain.color)
                                .frame(width: 7, height: 7)
                            Text(domain.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 4)

                        ForEach(modules) { module in
                            HubCatalogRow(module: module)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 500)
    }
}

private struct HubCatalogRow: View {
    let module: ModuleDescriptor
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Button {
            appModel.go(to: module.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: module.icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(module.accent)
                    .frame(width: 28, height: 28)
                    .background(module.accent.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: DesignTokens.Panel.chipRadius,
                                                     style: .continuous))
                // One line: the name. The promise survives as the row's spoken hint.
                Text(module.title)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DesignTokens.Panel.cardRadius, style: .continuous))
        .hoverEffect()
        // Named as one control, or VoiceOver reads the row as four things and a
        // UI test cannot address it by name.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lab.\(module.id)")
        .accessibilityLabel(module.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens \(module.title). \(HubDomain.promise(for: module.id))")
    }
}
