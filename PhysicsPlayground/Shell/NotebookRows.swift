//
//  NotebookRows.swift
//  Physics Playground — Shell
//
//  The lab notebook's face: capture a moment, see what you have kept,
//  and take it with you.
//
//  Every measurement in the app used to be live-only — a number that
//  existed while your hand was in the right place and was gone the
//  moment it moved. A student who found the exact angle where the beam
//  went into total internal reflection, or nailed a three-body
//  resonance, had no way to keep it, compare it, or show anyone. That
//  is the difference between a toy and an instrument.
//
//  The capture bead on the nav rail writes a row; this pod shows it,
//  and hands the whole book over as CSV (for a spreadsheet or a
//  plotting script) or Markdown (for a report).
//

import SwiftUI

struct NotebookRows: View {
    let module: ModuleDescriptor

    @Environment(AppModel.self) private var appModel
    @State private var showingExport = false
    @State private var exportText = ""
    @State private var exportTitle = ""

    var body: some View {
        let entries = appModel.notebook.entries(forModule: module.id)

        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            Button {
                let entry = appModel.notebook.record(
                    moduleID: module.id, moduleTitle: module.title,
                    title: module.title, readings: module.captureReadings())
                _ = entry
            } label: {
                Label("Record this moment", systemImage: "camera.aperture")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.podProminent(module.accent))
            .accessibilityHint("Writes every live reading in this module into the notebook")

            if entries.isEmpty {
                Text("Nothing recorded here yet. Set up something worth keeping, then record it — the numbers written down are exactly what the physics said at that instant.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(entries.count) recorded in this module · \(appModel.notebook.entries.count) in all")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)

                ForEach(entries.prefix(4)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.date, style: .time)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 6)
                            Button(role: .destructive) {
                                appModel.notebook.remove(entry.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete this entry")
                        }
                        Text(entry.summary)
                            .font(DesignTokens.TypeScale.footnote.monospaced())
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }

                HStack(spacing: 8) {
                    Button {
                        exportTitle = "Notebook — CSV"
                        exportText = appModel.notebook.csv
                        showingExport = true
                    } label: {
                        Text("CSV").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podQuiet)

                    Button {
                        exportTitle = "Notebook — Markdown"
                        exportText = appModel.notebook.markdown
                        showingExport = true
                    } label: {
                        Text("Markdown").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podQuiet)
                }
            }
        }
        .sheet(isPresented: $showingExport) {
            NotebookExportView(title: exportTitle, text: exportText)
        }
    }
}

/// The export sheet: the whole book as text, ready to copy out.
struct NotebookExportView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.podQuiet)
                Button("Done") { dismiss() }
                    .buttonStyle(.podProminent)
            }
            ScrollView {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }
}
