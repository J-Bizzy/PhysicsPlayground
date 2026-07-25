//
//  ModuleHostView.swift
//  Physics Playground — Shell
//
//  The module's window is no longer a control panel — it is a floating
//  TITLE BAR: the module's name in the middle, navigation on the left
//  (back to the catalog, jump to any module), modes on the right
//  (Studio, Reset). Everything else — controls, experiments, legend —
//  lives on the pods surrounding the user (ShellPodsView plus each
//  module's own pods).
//
//  When the immersive space is closed the pods don't exist, so the bar
//  grows a "Show in room" button; the space is where the module lives.
//

import SwiftUI

struct ModuleHostView: View {
    let module: ModuleDescriptor

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

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

                // Right: run state and modes.
                Button {
                    module.togglePause()
                } label: {
                    Image(systemName: module.isPaused() ? "play.fill" : "pause.fill")
                }
                .accessibilityLabel(module.isPaused() ? "Resume" : "Pause")
                .accessibilityHint("Freezes the physics so you can walk around it")

                Button {
                    appModel.controlPodsVisible.toggle()
                } label: {
                    Image(systemName: appModel.controlPodsVisible
                          ? "circle.grid.2x2.fill" : "circle.grid.2x2")
                }
                .accessibilityLabel(appModel.controlPodsVisible ? "Hide pods" : "Show pods")
                .accessibilityHint("Clears the floating control pods for an unobstructed view")

                Button {
                    appModel.studioMode.toggle()
                } label: {
                    Image(systemName: appModel.studioMode ? "moon.stars.fill" : "moon.stars")
                }
                .accessibilityLabel("Studio Mode")
                .accessibilityHint("Replaces your room with a dark studio")

                Button {
                    module.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset")
                .accessibilityHint("Returns this simulation to its starting state")
            }
            .buttonBorderShape(.circle)

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
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minWidth: 560)
        .glassBackgroundEffect(
            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
