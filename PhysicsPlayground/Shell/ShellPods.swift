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
        }
    }
}

/// The experiment rows, pod-styled: checkmark seals fill in live as the
/// simulation notices each goal, completed rows dim.
struct ExperimentRows: View {
    let moduleID: String
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let entries = ExperimentCatalog.experiments(for: moduleID, appModel: appModel)
        let doneCount = entries.filter {
            appModel.experiments.completed.contains($0.experiment.id)
        }.count

        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            Text("\(doneCount) of \(entries.count) complete")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(doneCount == entries.count ? .green : .secondary)
            ForEach(entries, id: \.experiment.id) { entry in
                let done = appModel.experiments.completed.contains(entry.experiment.id)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: done ? "checkmark.seal.fill" : "circle")
                        .foregroundStyle(done ? AnyShapeStyle(.green)
                                              : AnyShapeStyle(.secondary))
                        .font(.system(size: 15))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.experiment.title)
                            .font(DesignTokens.TypeScale.control)
                        Text(entry.experiment.detail)
                            .font(DesignTokens.TypeScale.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .opacity(done ? 0.75 : 1)
                .accessibilityElement(children: .combine)
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
