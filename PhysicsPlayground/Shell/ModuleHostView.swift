//
//  ModuleHostView.swift
//  Physics Playground — Shell
//
//  Hosts the active module in the shared shell chrome, in a fixed order
//  every module inherits: first-run hint, the module's own controls, the
//  legend, and the real-world button — plus back and reset in the toolbar
//  and the reopen-space affordance when the user closed the space.
//

import SwiftUI

struct ModuleHostView: View {
    let module: ModuleDescriptor

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var showRealWorld = false

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Panel.sectionSpacing) {
                // Appears only if the user closed the space (e.g. with the
                // crown) and wants the module back in the room.
                if !appModel.isImmersiveSpaceOpen {
                    Button {
                        Task {
                            _ = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
                        }
                    } label: {
                        Label("Show in room", systemImage: "sparkles")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.podProminent)
                    .accessibilityHint("Places the simulation in your room")
                }

                identityHeader

                FirstRunHint(module: module)

                module.makeControls()

                LegendView(items: module.legend)

                RealWorldButton(accent: module.accent) {
                    showRealWorld = true
                }
            }
            .padding(DesignTokens.Panel.outerPadding)
            // The window's controls speak in the module accent: house
            // buttons via podAccent, sliders / toggles / pickers via tint.
            .environment(\.podAccent, module.accent)
            .tint(module.accent)
        }
        .navigationTitle(module.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    appModel.activeModuleID = nil
                } label: {
                    Label("All Simulations", systemImage: "chevron.left")
                }
                .accessibilityHint("Returns to the simulation catalog")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appModel.studioMode.toggle()
                } label: {
                    Label("Studio Mode",
                          systemImage: appModel.studioMode ? "moon.stars.fill" : "moon.stars")
                }
                .accessibilityHint("Replaces your room with a dark studio so the physics glows at full contrast")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    module.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .accessibilityHint("Returns this simulation to its starting state")
            }
        }
        .sheet(isPresented: $showRealWorld) {
            RealWorldPanel(
                moduleTitle: module.title,
                story: module.realWorld,
                accent: module.accent
            )
        }
    }

    /// The module's identity row: its icon in an accent chip beside the
    /// one-paragraph story of what's in the room, over the house fading
    /// accent rule — the same labelled-instrument header the pods wear,
    /// so the window and the space read as one designed system. (This is
    /// also the only place the module's blurb is actually shown.)
    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: DesignTokens.Panel.rowSpacing) {
                Image(systemName: module.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(module.accent)
                    .frame(width: 34, height: 34)
                    .background(module.accent.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                Text(module.blurb)
                    .font(DesignTokens.TypeScale.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LinearGradient(
                colors: [module.accent.opacity(0.55), module.accent.opacity(0.05)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
