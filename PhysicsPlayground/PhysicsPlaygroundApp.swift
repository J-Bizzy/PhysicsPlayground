//
//  PhysicsPlaygroundApp.swift
//  Physics Playground
//
//  The scenes: one shared ImmersiveSpace whose content follows the
//  active module, a main window (the flat catalog or the module's title
//  bar) and three utility windows. The space is declared first because
//  Info.plist makes it the launch scene and visionOS picks the first
//  one declared.
//

import SwiftUI

@main
struct PhysicsPlaygroundApp: App {
    @State private var appModel = AppModel()

    init() {
        #if DEBUG
        LaunchTrace.begin()
        #endif
    }

    var body: some Scene {
        // The launch scene; declared first on purpose.
        ImmersiveSpace(id: PlaygroundSpaceView.spaceID) {
            PlaygroundSpaceView()
                .environment(appModel)
        }
        .immersionStyle(
            selection: Bindable(appModel).immersionStyle,
            in: .mixed, .progressive, .full
        )

        // Identified so the shell can put it away and bring it back; nothing
        // opens it implicitly.
        WindowGroup(id: MainWindowView.windowID) {
            MainWindowView()
                .environment(appModel)
        }
        // Plain style: no glass slab behind the hub nameplate. The module title
        // bar brings its own glass.
        .windowStyle(.plain)
        .windowResizability(.contentMinSize)
        // The height is headroom: the module title bar top-aligns in this
        // frame, above the apparatus.
        .defaultSize(width: 560, height: 960)

        // The utility windows keep the system glass and are value-less
        // WindowGroups, so reopening one brings it forward. All three ask for
        // `.utilityPanel`: without a placement visionOS anchors them off the key
        // window, which while the gallery is up is the parked, empty main window.
        WindowGroup(id: SettingsView.windowID) {
            SettingsView()
                .environment(appModel)
        }
        // Tall enough to show the whole form at default type; the ScrollView is
        // for Dynamic Type.
        .defaultSize(width: 460, height: 780)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, _ in WindowPlacement(.utilityPanel) }

        WindowGroup(id: NotebookView.windowID) {
            NotebookView()
                .environment(appModel)
        }
        .defaultSize(width: 480, height: 760)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, _ in WindowPlacement(.utilityPanel) }

        // About: behind the home's info button.
        WindowGroup(id: AboutView.windowID) {
            AboutView()
        }
        .defaultSize(width: 420, height: 380)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, _ in WindowPlacement(.utilityPanel) }
    }
}
