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
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Places the simulation in your room")
                }

                FirstRunHint(module: module)

                module.makeControls()

                LegendView(items: module.legend)

                RealWorldButton(accent: module.accent) {
                    showRealWorld = true
                }
            }
            .padding(DesignTokens.Panel.outerPadding)
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
}
