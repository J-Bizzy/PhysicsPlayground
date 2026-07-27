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

            // Coaching, one mark at a time, each dismissed by DOING the
            // thing it teaches — look, enter, open the notebook. A user
            // who has done all three never sees any of this again.
            HubCoachMark()

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
                .accessibilityHint("Places the exhibit arc in your room")

                // The fallback catalog, only while the spatial menu is
                // not in the room. In space, the arc IS the menu.
                HubCatalogList()
            }

            Spacer(minLength: 12)
        }
        .padding(DesignTokens.Panel.outerPadding)
        .frame(minWidth: 440, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        // Bare type over passthrough needs its own separation from the room.
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
        // The dock: the app's system surface, always in the same place.
        // Notebook, progress, challenge, search, studio, settings — the
        // six things that used to be scattered across the window, a
        // toast over the TV, and nowhere.
        .ornament(attachmentAnchor: .scene(.bottom)) {
            HubDock()
                .environment(appModel)
        }
        .task {
            SoundPalette.warmUp()
            SoundPalette.masterVolume = appModel.settings.masterVolume
            // The spatial arc is the menu — bring it up on arrival.
            if !appModel.isImmersiveSpaceOpen {
                _ = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
            }
        }
    }
}

/// The current onboarding tip, or nothing once the sequence is done.
struct HubCoachMark: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let stage = appModel.settings.coachStage
        if stage < 3 {
            let (icon, text): (String, String) = switch stage {
            case 0: ("eye", "Turn toward a module to preview it")
            case 1: ("hand.pinch", "Pinch to step inside — or use its Enter button")
            default: ("book.closed", "Everything you measure lands in your Lab Notebook, below")
            }
            Label(text, systemImage: icon)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassBackgroundEffect(in: Capsule())
                .transition(.opacity)
                .id(stage)
                .accessibilityAddTraits(.isHeader)
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

/// Every recorded observation, newest first, with export.
struct HubNotebookView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var exporting: (title: String, text: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Lab notebook", systemImage: "book.closed")
                    .font(.title2.bold())
                Spacer()
                if !appModel.notebook.entries.isEmpty {
                    Button("CSV") {
                        exporting = ("Notebook — CSV", appModel.notebook.csv)
                    }
                    .buttonStyle(.podQuiet)
                    Button("Markdown") {
                        exporting = ("Notebook — Markdown", appModel.notebook.markdown)
                    }
                    .buttonStyle(.podQuiet)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.podProminent)
            }

            if appModel.notebook.entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing recorded yet.")
                        .font(.headline)
                    Text("Inside any module, pinch the Note bead on the control rail to write down every live reading at that instant — the numbers saved are exactly what the physics said.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(appModel.notebook.entries) { entry in
                            NotebookEntryRow(entry: entry)
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(minWidth: 560, minHeight: 460)
        .sheet(item: Binding(
            get: { exporting.map { NotebookExport(title: $0.title, text: $0.text) } },
            set: { _ in exporting = nil })) { export in
            NotebookExportView(title: export.title, text: export.text)
        }
    }
}

/// A wrapper so the export sheet can be presented by item.
struct NotebookExport: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

private struct NotebookEntryRow: View {
    let entry: NotebookEntry
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.moduleTitle)
                    .font(.callout.weight(.semibold))
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Button(role: .destructive) {
                    appModel.notebook.remove(entry.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete this entry")
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                ForEach(entry.readings.indices, id: \.self) { index in
                    let reading = entry.readings[index]
                    GridRow {
                        Text(reading.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(reading.value)
                            .font(.caption.monospacedDigit())
                            .gridColumnAlignment(.trailing)
                        Text(reading.unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
