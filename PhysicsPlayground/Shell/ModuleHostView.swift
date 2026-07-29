//
//  ModuleHostView.swift
//  Physics Playground — Shell
//
//  The module's window is a floating TITLE BAR — the module's name in
//  the middle, navigation on the left (back to the catalog, jump to any
//  module), modes on the right (Studio, Reset) — plus an optional flat
//  control panel beneath it for modules that opt in via makeControls.
//  Modules whose spatial affordances carry everything show the bare bar.
//
//  When the immersive space is closed the pods don't exist, so the bar
//  grows a "Show in room" button; the space is where the module lives.
//

import SwiftUI

struct ModuleHostView: View {
    let module: ModuleDescriptor

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @State private var confirmingReset = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                // Left: navigation.
                Button {
                    appModel.activeModuleID = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("All simulations")
                .accessibilityHint("Returns to the catalog")

                Menu {
                    ForEach(ModuleCatalog.all(appModel: appModel)) { entry in
                        Button {
                            appModel.activeModuleID = entry.id
                        } label: {
                            if entry.id == module.id {
                                Label(entry.title, systemImage: "checkmark")
                            } else {
                                Label(entry.title, systemImage: entry.icon)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.3x3")
                }
                .accessibilityLabel("Switch simulation")

                Spacer(minLength: 12)

                // Center: the module's identity.
                HStack(spacing: 10) {
                    Image(systemName: module.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(module.accent)
                        .frame(width: 30, height: 30)
                        .background(module.accent.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)
                    Text(module.title)
                        .font(.title2.bold())
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                // Right: modes.
                Button {
                    openWindow(id: NotebookView.windowID)
                } label: {
                    Image(systemName: "book.closed")
                }
                .accessibilityLabel("Lab Notebook")
                .accessibilityHint("Your recorded observations — capture, read, export")

                Button {
                    appModel.labPlacement.isPlacing.toggle()
                } label: {
                    Image(systemName: appModel.labPlacement.isPlacing
                          ? "scope" : "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                }
                .accessibilityLabel("Place the lab")
                .accessibilityHint("Shows an anchor you can drag to move the whole experiment to where you have room")

                Button {
                    appModel.studioMode.toggle()
                } label: {
                    Image(systemName: appModel.studioMode ? "moon.stars.fill" : "moon.stars")
                }
                .accessibilityLabel("Studio Mode")
                .accessibilityHint("Replaces your room with a dark studio")

                // Reset ASKS FIRST.
                //
                // It used to live on the in-space rail, where a stray
                // gaze-pinch could fire it, so it carried a two-pinch
                // arming dance to be safe. Moving it to the window
                // removed the stray-pinch risk but also removed the
                // guard — and in Circuit Workshop a reset wipes a bench
                // that persists across launches. A confirmation is the
                // platform's own answer and a clearer one than arming.
                Button {
                    confirmingReset = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset")
                .accessibilityHint("Returns this simulation to its starting state")
                .confirmationDialog("Reset \(module.title)?",
                                    isPresented: $confirmingReset,
                                    titleVisibility: .visible) {
                    Button("Reset", role: .destructive) { module.reset() }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Everything you have set up here goes back to how the module opened. Recorded notebook entries are kept.")
                }
            }
            .buttonBorderShape(.circle)

            if appModel.labPlacement.isPlacing {
                HStack(spacing: 10) {
                    Text("Drag the cross-hair to move the whole experiment.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Button("Recentre") { appModel.labPlacement.recentre() }
                        .buttonStyle(.podQuiet)
                    Button("Done") { appModel.labPlacement.isPlacing = false }
                        .buttonStyle(.podProminent(module.accent))
                }
            }

            if !appModel.isImmersiveSpaceOpen {
                Button {
                    Task {
                        _ = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
                    }
                } label: {
                    Label("Show in room", systemImage: "sparkles")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.podProminent(module.accent))
                .accessibilityHint("Places the simulation and its control pods in your room")
            }

            // The one-time hint: a sentence from the module, shown
            // until the user closes it. Dismissal is the read receipt.
            if !appModel.settings.hasSeenHint(module.id) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.point.up.left")
                        .font(.footnote)
                        .foregroundStyle(module.accent)
                    Text(module.firstRunHint)
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            appModel.settings.markHintSeen(module.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss hint")
                }
                .padding(.horizontal, 8)
            }

            // The module's current task: the first unfinished
            // experiment, with its step — the strings were authored
            // for exactly this and never rendered until now. It
            // advances on its own as experiments land.
            if let next = ExperimentCatalog.experiments(for: module.id,
                                                        appModel: appModel)
                .first(where: {
                    !appModel.experiments.completed.contains($0.experiment.id)
                }) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "flask")
                        .font(.footnote)
                        .foregroundStyle(module.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(next.experiment.title)
                            .font(DesignTokens.TypeScale.footnote.weight(.semibold))
                        if !next.experiment.step.isEmpty {
                            Text(next.experiment.step)
                                .font(DesignTokens.TypeScale.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Current experiment: \(next.experiment.title). \(next.experiment.step)")
            }

            if module.makeControls != nil || !module.legend.isEmpty {
                ScrollView {
                    VStack(spacing: DesignTokens.Panel.sectionSpacing) {
                        if let makeControls = module.makeControls {
                            makeControls()
                        }
                        // The legend, appended by the SHELL — every
                        // module gets the same key in the same place,
                        // and none can restyle or forget it.
                        if !module.legend.isEmpty {
                            CollapsedSection("Legend") {
                                LegendView(items: module.legend)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(maxHeight: 480)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        // Wide enough for the LONGEST module name.
        //
        // At 560 the bar ran out of room and truncated: "Circuit
        // Workshop" arrived as "Circuit Works…", which is the module's
        // own name, misspelled by the layout, in the largest type on
        // screen. Five circular buttons take about 280 points before the
        // title gets any, and "Wave Interference" needs about 200 more.
        .frame(minWidth: 680)
        .glassBackgroundEffect(
            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
