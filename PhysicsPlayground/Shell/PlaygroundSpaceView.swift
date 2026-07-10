//
//  PlaygroundSpaceView.swift
//  Physics Playground — Shell
//
//  The single shared immersive space. Its content is whatever the active
//  module's descriptor builds; `.id(module.id)` gives each module its own
//  view identity so per-module @State (like renderers) is rebuilt cleanly
//  on switch, while module *models* live on in AppModel.
//

import SwiftUI

struct PlaygroundSpaceView: View {
    static let spaceID = "PlaygroundSpace"

    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if let module = appModel.activeModule {
                module.makeScene()
                    .id(module.id)
            }
        }
        .onAppear { appModel.isImmersiveSpaceOpen = true }
        .onDisappear { appModel.isImmersiveSpaceOpen = false }
    }
}
