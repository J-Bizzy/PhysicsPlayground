//
//  NotebookView.swift
//  Physics Playground — Shell
//
//  The Lab Notebook's window: the take-away layer, finally visible.
//  Every capture is a timestamped row of exactly what the physics said
//  at that instant; here they read as cards, newest first, each opening
//  into its readings table. The whole book exports as CSV (for a
//  spreadsheet) or Markdown (for a lab report) via the share sheet.
//
//  Capture happens mid-experiment from the palette bead's pencil petal;
//  this window also carries a Capture button for the active module —
//  the simulator and accessibility path, per the house parity rule.
//

import SwiftUI

struct NotebookView: View {
    static let windowID = "notebook"

    @Environment(AppModel.self) private var appModel
    @State private var confirmingClear = false

    var body: some View {
        let notebook = appModel.notebook

        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Panel.sectionSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Lab Notebook")
                        .font(DesignTokens.TypeScale.cardTitle)
                    Spacer()
                    if !notebook.entries.isEmpty {
                        ShareLink(item: notebook.csv,
                                  preview: SharePreview("Lab notebook (CSV)")) {
                            Label("CSV", systemImage: "tablecells")
                                .font(DesignTokens.TypeScale.label)
                        }
                        .accessibilityLabel("Share as CSV")
                        ShareLink(item: notebook.markdown,
                                  preview: SharePreview("Lab notebook (Markdown)")) {
                            Label("Report", systemImage: "doc.richtext")
                                .font(DesignTokens.TypeScale.label)
                        }
                        .accessibilityLabel("Share as Markdown report")
                    }
                }

                if let module = appModel.activeModule {
                    Button {
                        appModel.captureNotebookEntry()
                    } label: {
                        Label("Capture \(module.title) now",
                              systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent(module.accent))
                    .accessibilityHint("Writes down exactly what the physics says right now")

                    // THE KEY, moved here from a popover on the module's
                    // title bar (2026-08-02).
                    //
                    // It could not simply be deleted with that button,
                    // and the reason is specific rather than sentimental:
                    // several of these entries are DISCLOSURES and nothing
                    // else in the app carries them. Magnetism's says that
                    // Earth's 50 µT runs 65° into the ground; Gravity
                    // Lab's says planet sizes are exaggerated, that the
                    // spacetime grid is an analogy rather than a
                    // solution, and that Mercury's extra 43″/century
                    // needs GR, which this lab does not model.
                    //
                    // DECISIONS 2026-07-31: a migration that drops those
                    // "turns a disclosed fiction into an undisclosed
                    // one". The notebook is the right home — it is
                    // already the app's reference surface, it already
                    // knows which module is open, and it is where someone
                    // reading their own recorded numbers would want the
                    // key to them.
                    if !module.legend.isEmpty {
                        DisclosureGroup {
                            LegendView(items: module.legend)
                                .padding(.top, 10)
                        } label: {
                            Text("Key — \(module.title)")
                                .font(DesignTokens.TypeScale.sectionHeader)
                                .accessibilityAddTraits(.isHeader)
                        }
                        .tint(.secondary)
                    }
                }

                if notebook.entries.isEmpty {
                    PanelSection {
                        Text("Nothing recorded yet. Inside a lab, pinch the "
                             + "pencil petal on the palette bead — or the button "
                             + "above — and the moment's numbers are written down.")
                            .font(DesignTokens.TypeScale.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ForEach(notebook.entries) { entry in
                        NotebookEntryCard(entry: entry)
                    }

                    Button("Clear notebook…", role: .destructive) {
                        confirmingClear = true
                    }
                    .buttonStyle(.podQuiet)
                    .confirmationDialog("Clear the whole notebook?",
                                        isPresented: $confirmingClear,
                                        titleVisibility: .visible) {
                        Button("Clear everything", role: .destructive) {
                            notebook.clear()
                        }
                        Button("Keep my notes", role: .cancel) {}
                    } message: {
                        Text("Every recorded observation is deleted. "
                             + "Export first if you want to keep them.")
                    }
                }
            }
            .padding(DesignTokens.Panel.outerPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One observation: a card whose header names the moment and whose
/// disclosure opens the readings table.
private struct NotebookEntryCard: View {
    let entry: NotebookEntry
    @Environment(AppModel.self) private var appModel

    var body: some View {
        PanelSection {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Grid(alignment: .leading,
                         horizontalSpacing: 14, verticalSpacing: 5) {
                        ForEach(entry.readings.indices, id: \.self) { index in
                            let reading = entry.readings[index]
                            GridRow {
                                Text(reading.name)
                                    .font(DesignTokens.TypeScale.footnote)
                                    .foregroundStyle(.secondary)
                                Text(reading.value)
                                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                                Text(reading.unit)
                                    .font(DesignTokens.TypeScale.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    Button(role: .destructive) {
                        appModel.notebook.remove(entry.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(DesignTokens.TypeScale.footnote)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(entry.title)
                            .font(DesignTokens.TypeScale.control.weight(.semibold))
                        Text(entry.moduleTitle)
                            .font(DesignTokens.TypeScale.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(entry.date, format: .relative(presentation: .named))
                            .font(DesignTokens.TypeScale.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    Text(entry.summary)
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .tint(.secondary)
        }
    }
}

#Preview(windowStyle: .automatic) {
    NotebookView()
        .environment(AppModel())
}
