//
//  PlaygroundSpaceView.swift
//  Physics Playground — Shell
//
//  The single shared immersive space. With no module active it shows the
//  spatial hub menu (floating title + module bubbles); entering a module
//  swaps in its scene. `.id(module.id)` gives each module its own view
//  identity so per-module @State (like renderers) is rebuilt cleanly on
//  switch, while module *models* live on in AppModel.
//

import SwiftUI

struct PlaygroundSpaceView: View {
    static let spaceID = "PlaygroundSpace"

    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if let module = appModel.activeModule {
                ZStack {
                    module.makeScene()
                        .id(module.id)
                    // The shared orb controls (pause / back) every module gets.
                    ModuleOrbControlsView(module: module)
                        .id("orbs-\(module.id)")
                }
            } else {
                HubSpaceView()
                    .id("hub")
            }
        }
        .onAppear { appModel.isImmersiveSpaceOpen = true }
        .onDisappear { appModel.isImmersiveSpaceOpen = false }
    }
}
