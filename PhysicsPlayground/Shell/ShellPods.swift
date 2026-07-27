//
//  ShellPods.swift
//  Physics Playground — Shell
//
//  The three pods every module inherits now that the window is just a
//  title bar: CONTROLS (the module's own control content, with the
//  first-run hint on top), EXPERIMENTS (live goals with checkmarks),
//  and LEGEND (the key to what's drawn in the scene). They surround
//  the user beside each module's own purpose-built pods, hang from the
//  same grabbable glass bars, persist wherever they're parked, and
//  clear away with the pods orb like everything else.
//

import RealityKit
import SwiftUI

struct ShellPodsView: View {
    let module: ModuleDescriptor

    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let podsRoot = PodMount.makeRoot(module: "shell-\(module.id)")
            content.add(podsRoot)
            if !module.podsCoverControls {
                PodMount.mount(attachments.entity(for: "shell-controls"), name: "Controls",
                               at: [1.5, 1.42, -0.25], in: podsRoot)
            }
            PodMount.mount(attachments.entity(for: "shell-experiments"), name: "Experiments",
                           at: [-1.5, 1.42, -0.25], in: podsRoot)
            PodMount.mount(attachments.entity(for: "shell-legend"), name: "Legend",
                           at: [-1.62, 0.82, -0.1], in: podsRoot)
            PodMount.mount(attachments.entity(for: "shell-notebook"), name: "Notebook",
                           at: [1.62, 0.82, -0.1], in: podsRoot)

            _ = content.subscribe(to: SceneEvents.Update.self) { _ in
                podsRoot.isEnabled = appModel.controlPodsVisible
                PodMount.persistIfMoved(podsRoot)
            }
        } attachments: {
            if !module.podsCoverControls {
                Attachment(id: "shell-controls") {
                    ControlPod(title: "Controls", icon: module.icon,
                               tint: module.accent, width: 340) {
                        FirstRunHint(module: module)
                        module.makeControls()
                    }
                }
            }
            Attachment(id: "shell-experiments") {
                ControlPod(title: "Experiments", icon: "flask",
                           tint: module.accent, width: 320) {
                    ExperimentRows(moduleID: module.id)
                }
            }
            Attachment(id: "shell-legend") {
                ControlPod(title: "Legend", icon: "list.bullet",
                           tint: module.accent, width: 320) {
                    LegendRows(items: module.legend)
                }
            }
            Attachment(id: "shell-notebook") {
                ControlPod(title: "Notebook", icon: "book.closed",
                           tint: module.accent, width: 340) {
                    NotebookRows(module: module)
                }
            }
        }
    }
}

/// The module's PATH: one task at a time, then the record of what you
/// have already done.
///
/// This was a flat checklist of outcomes with no order — a list of
/// achievements to stumble into rather than a route through the module.
/// Now the pod names the single next thing to do and tells you how to do
/// it, and the completed work collapses into a quiet trail behind it.
/// The physics still decides when a step is done; nothing is claimed
/// until the simulation itself notices.
struct ExperimentRows: View {
    let moduleID: String
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let entries = ExperimentCatalog.experiments(for: moduleID, appModel: appModel)
        let done = appModel.experiments.completed
        let doneCount = entries.filter { done.contains($0.experiment.id) }.count
        let next = entries.first { !done.contains($0.experiment.id) }

        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            // Progress through this module, as a spine.
            HStack(spacing: 8) {
                ProgressView(value: Double(doneCount),
                             total: Double(max(entries.count, 1)))
                    .tint(doneCount == entries.count ? .green : .accentColor)
                Text("\(doneCount)/\(entries.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let next {
                // THE CURRENT TASK. One thing, stated as an instruction.
                VStack(alignment: .leading, spacing: 5) {
                    Text("Next")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(next.experiment.title)
                        .font(DesignTokens.TypeScale.control.weight(.semibold))
                    Text(next.experiment.step.isEmpty
                         ? next.experiment.detail : next.experiment.step)
                        .font(DesignTokens.TypeScale.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(next.experiment.detail)
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .background(.thinMaterial,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Next: \(next.experiment.title). \(next.experiment.step)")
            } else {
                Label("Every experiment in this module is done.",
                      systemImage: "checkmark.seal.fill")
                    .font(DesignTokens.TypeScale.control)
                    .foregroundStyle(.green)
            }

            // The trail behind: what is already finished, quietly.
            if doneCount > 0 {
                DisclosureGroup("Done (\(doneCount))") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(entries.filter { done.contains($0.experiment.id) },
                                id: \.experiment.id) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 13))
                                Text(entry.experiment.title)
                                    .font(DesignTokens.TypeScale.footnote)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(DesignTokens.TypeScale.footnote)
                .tint(.secondary)
            }

            // Anything still ahead, named but not explained — so the
            // module's shape is visible without spoiling the route.
            let remaining = entries.filter {
                !done.contains($0.experiment.id) && $0.experiment.id != next?.experiment.id
            }
            if !remaining.isEmpty {
                Text("Then: " + remaining.map(\.experiment.title).joined(separator: " · "))
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The legend rows, pod-styled: one swatch per concept, shaped the way
/// the concept is actually drawn in the scene.
struct LegendRows: View {
    let items: [LegendItem]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            ForEach(items) { item in
                HStack(spacing: DesignTokens.Panel.rowSpacing) {
                    swatch(item.swatch)
                        .frame(width: 22, alignment: .center)
                    Text(item.text)
                        .font(DesignTokens.TypeScale.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func swatch(_ swatch: LegendItem.Swatch) -> some View {
        switch swatch {
        case .fill(let color):
            Circle().fill(color).frame(width: 16, height: 16)
        case .translucent(let color):
            Circle().fill(color.opacity(0.35)).frame(width: 16, height: 16)
        case .stroke(let color):
            Circle().stroke(color, lineWidth: 2).frame(width: 16, height: 16)
        case .line(let color):
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 16, height: 3)
        case .symbol(let name, let color):
            Image(systemName: name).foregroundStyle(color)
        }
    }
}
