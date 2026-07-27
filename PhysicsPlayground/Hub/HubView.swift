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

            // The name floats in 3-D above the arcs (HubSpaceView), and
            // the detail card under whichever exhibit you are facing now
            // says what it is and how to enter it. So this window keeps
            // only what neither of those covers — and stays small, since
            // it sits in the gap the lower arc leaves dead ahead.
            Text("Turn toward an exhibit to read it. Pinch to step inside.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
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

            // WHERE TO GO NEXT, not just how far you have come.
            //
            // "4 of 24 complete" is a score, and a score is only useful
            // once you already know what to do. The single next unfinished
            // experiment — named, explained, and one pinch from the module
            // it lives in — is what makes home somewhere you return TO
            // rather than a launcher you pass through.
            HubNextStep()

            // The notebook, reachable from HOME.
            //
            // Captured measurements only existed inside a per-module pod,
            // which is the one place you are NOT when you want to look
            // back over what you found. A notebook you cannot open at
            // home is a notebook you never read.
            HubNotebookButton()

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

/// The one thing to do next, anywhere in the app — and a way straight to
/// it. Home stops being a launcher and starts being a place you return to.
struct HubNextStep: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let total = ExperimentCatalog.total(appModel: appModel)
        let done = ExperimentCatalog.completedCount(appModel: appModel)

        VStack(spacing: 7) {
            if let next = ExperimentCatalog.nextStep(appModel: appModel) {
                Button {
                    appModel.activeModuleID = next.module.id
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: next.module.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(next.module.accent)
                            .frame(width: 28, height: 28)
                            .background(next.module.accent.opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 8,
                                                             style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(next.experiment.title)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(next.experiment.step.isEmpty
                                 ? next.experiment.detail : next.experiment.step)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .hoverEffect()
                .accessibilityLabel("Next: \(next.experiment.title) in \(next.module.title)")
                .accessibilityHint(next.experiment.step)
            }

            if total > 0 {
                HStack(spacing: 8) {
                    ProgressView(value: Double(done), total: Double(total))
                        .tint(done == total ? .green : .accentColor)
                        .frame(width: 120)
                    Text("\(done) of \(total) experiments")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(done) of \(total) experiments complete")
            }
        }
        .frame(maxWidth: 420)
    }
}

/// Opens the whole lab notebook from home.
struct HubNotebookButton: View {
    @Environment(AppModel.self) private var appModel
    @State private var showing = false

    var body: some View {
        let count = appModel.notebook.entries.count
        Button {
            showing = true
        } label: {
            Label(count == 0 ? "Lab notebook" : "Lab notebook · \(count)",
                  systemImage: "book.closed")
                .font(.subheadline)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .buttonStyle(.podQuiet)
        .fixedSize()
        .accessibilityHint("Everything you have recorded, across every module")
        .sheet(isPresented: $showing) {
            HubNotebookView()
                .environment(appModel)
        }
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
