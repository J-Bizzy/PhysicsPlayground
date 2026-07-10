//
//  PhysicsPlaygroundApp.swift
//  Physics Playground
//
//  Two scenes: a window that shows either the simulation catalog (the hub)
//  or the active simulation's controls, and ONE shared ImmersiveSpace whose
//  content switches with the active simulation. `.mixed` immersion keeps
//  passthrough on, so every simulation happens in the user's real room.
//

import SwiftUI

@main
struct PhysicsPlaygroundApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(appModel)
        }
        .defaultSize(width: 520, height: 700)

        ImmersiveSpace(id: PlaygroundSpaceView.spaceID) {
            PlaygroundSpaceView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
