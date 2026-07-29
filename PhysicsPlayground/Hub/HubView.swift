//
//  HubView.swift
//  Physics Playground — Hub
//
//  The hub's window. While the Gallery is in the room this window is
//  deliberately empty — the space IS the menu, and the wordmark hangs
//  in the room itself. Before the space opens (or if opening fails),
//  the window is the real front door: the app's name, one button that
//  raises the Gallery, and a domain-grouped catalog with live progress,
//  so nothing about the app is unreachable from a plain window.
//

import SwiftUI

struct HubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var openFailed = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)

            if !appModel.isImmersiveSpaceOpen {
                VStack(spacing: 5) {
                    Text("Physics Playground")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    Text("Room-scale physics labs, in your actual room.")
                        .font(DesignTokens.TypeScale.label)
                        .foregroundStyle(.secondary)
                }

                if openFailed {
                    // The auto-open used to swallow its failure — the
                    // window just sat there with no explanation. Say
                    // what happened; retry only by hand, never a loop.
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
                }

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

                HubCatalogList()
            }

            Spacer(minLength: 12)
        }
        .padding(DesignTokens.Panel.outerPadding)
        .frame(minWidth: 440, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        // Bare type over passthrough needs its own separation from the room.
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
        .task {
            SoundPalette.warmUp()
            SoundPalette.masterVolume = appModel.settings.masterVolume
            // The Gallery is the menu — bring it up on arrival.
            if !appModel.isImmersiveSpaceOpen {
                await openGallery()
            }
        }
    }

    private func openGallery() async {
        openFailed = false
        let result = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
        if case .error = result { openFailed = true }
    }
}

/// The flat catalog, shown only when the Gallery is not in the room:
/// the modules grouped under their domains, each with its live
/// progress, mirroring the terraces the space shows as objects.
struct HubCatalogList: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let byID = Dictionary(uniqueKeysWithValues:
            ModuleCatalog.all(appModel: appModel).map { ($0.id, $0) })

        VStack(alignment: .leading, spacing: 14) {
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
        let entries = ExperimentCatalog.experiments(for: module.id,
                                                    appModel: appModel)
        let done = entries.filter {
            appModel.experiments.completed.contains($0.experiment.id)
        }.count

        Button {
            appModel.activeModuleID = module.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: module.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(module.accent)
                    .frame(width: 28, height: 28)
                    .background(module.accent.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 8,
                                                     style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.title)
                        .font(.callout)
                        .lineLimit(1)
                    if !entries.isEmpty {
                        Text("\(done) of \(entries.count) experiments")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(done == entries.count
                                             ? Color.yellow : Color.secondary)
                    }
                }
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
            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .hoverEffect()
        .accessibilityHint("Opens \(module.title)")
    }
}
