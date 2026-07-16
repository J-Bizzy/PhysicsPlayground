//
//  PhysicsPlaygroundApp.swift
//  Physics Playground
//
//  Two scenes: a window that shows either the simulation catalog (the hub)
//  or the active module's controls, and ONE shared ImmersiveSpace whose
//  content switches with the active module. Immersion style follows the
//  module: .mixed keeps passthrough for room-scale modules; Gravity Lab
//  asks for .progressive, so turning the crown opens its starfield.
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
        .windowResizability(.contentMinSize)
        .defaultSize(width: 520, height: 340)

        ImmersiveSpace(id: PlaygroundSpaceView.spaceID) {
            PlaygroundSpaceView()
                .environment(appModel)
        }
        .immersionStyle(
            selection: Bindable(appModel).immersionStyle,
            in: .mixed, .progressive
        )
    }
}
