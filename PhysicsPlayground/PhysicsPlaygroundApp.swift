//
//  PhysicsPlaygroundApp.swift
//  Physics Playground
//
//  Three scenes: a window that shows either the simulation catalog (the
//  hub) or the active module's controls, a small settings window, and
//  ONE shared ImmersiveSpace whose content switches with the active
//  module. Immersion style follows the module: .mixed keeps passthrough
//  for room-scale modules; Gravity Lab asks for .progressive, so turning
//  the crown opens its starfield.
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
        // Plain style: no glass slab behind the hub title — the nameplate
        // floats bare in the room. Module controls restore their own glass
        // (MainWindowView adds it back for that branch).
        .windowStyle(.plain)
        .windowResizability(.contentMinSize)
        // Tall enough for a module's control panel (its content asks for
        // 620 pt); any shorter and the panel clips top and bottom. The
        // hub nameplate centers itself in whatever height it gets.
        .defaultSize(width: 560, height: 720)

        // The settings window keeps the system glass (unlike the plain
        // main window — its bareness serves the floating nameplate, not
        // control surfaces). A value-less WindowGroup(id:) is single-
        // instance, so reopening it just brings it forward.
        WindowGroup(id: SettingsView.windowID) {
            SettingsView()
                .environment(appModel)
        }
        // Tall enough that the whole form shows without scrolling at
        // default type size; the ScrollView is there for Dynamic Type.
        .defaultSize(width: 460, height: 900)
        .windowResizability(.contentSize)

        // The Lab Notebook: same single-instance pattern as Settings.
        WindowGroup(id: NotebookView.windowID) {
            NotebookView()
                .environment(appModel)
        }
        .defaultSize(width: 480, height: 760)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: PlaygroundSpaceView.spaceID) {
            PlaygroundSpaceView()
                .environment(appModel)
        }
        .immersionStyle(
            selection: Bindable(appModel).immersionStyle,
            in: .mixed, .progressive, .full
        )
    }
}
