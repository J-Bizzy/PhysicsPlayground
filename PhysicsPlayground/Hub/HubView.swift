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

            // The lab notebook's spine: overall experiment progress.
            let totalExperiments = ExperimentCatalog.total(appModel: appModel)
            let doneExperiments = ExperimentCatalog.completedCount(appModel: appModel)
            if totalExperiments > 0 {
                Label("\(doneExperiments) of \(totalExperiments) experiments complete",
                      systemImage: doneExperiments == totalExperiments
                          ? "flask.fill" : "flask")
                    .font(.footnote)
                    .foregroundStyle(doneExperiments == totalExperiments
                        ? AnyShapeStyle(.green) : AnyShapeStyle(.white.opacity(0.75)))
                    .accessibilityLabel(
                        "\(doneExperiments) of \(totalExperiments) experiments complete")
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
                .buttonStyle(.podProminent)
                .accessibilityHint("Places the exhibit ring in your room")
            }

            // The catalog list is NOT shown beside the ring.
            //
            // It used to be: a two-column grid of every module, floating
            // in the middle of the exhibit ring that already showed every
            // module. Two menus for one catalog, the flat one landing
            // right on top of the spatial one, and the ring — the whole
            // reason this app is worth wearing — reduced to decoration
            // around a list. The ring is the menu. The list survives only
            // as the fallback for when the space is closed, and as the
            // accessible path, which the in-space exhibits also provide
            // as VoiceOver elements.
            if !appModel.isImmersiveSpaceOpen {
                HubCatalogList()
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

/// The flat catalog, shown only when the exhibit ring is not in the room.
/// In space, the ring IS this list — rendered as objects you can look at.
struct HubCatalogList: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            ForEach(ModuleCatalog.all(appModel: appModel)) { module in
                Button {
                    appModel.activeModuleID = module.id
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: module.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(module.accent)
                            .frame(width: 27, height: 27)
                            .background(module.accent.opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 8,
                                                             style: .continuous))
                        Text(module.title)
                            .font(.callout)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .hoverEffect()
                .accessibilityHint("Opens \(module.title)")
            }
        }
        .frame(maxWidth: 500)
    }
}
