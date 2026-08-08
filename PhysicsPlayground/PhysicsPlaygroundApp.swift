//
//  PhysicsPlaygroundApp.swift
//  Physics Playground
//
//  The scenes: a main window that shows either the flat catalog (the
//  hub) or the active module's title bar, three utility windows
//  (Settings, the Lab Notebook, About), and ONE shared ImmersiveSpace
//  whose content switches with the active module. Immersion style
//  follows the module: .mixed keeps passthrough for room-scale modules;
//  Gravity Lab asks for .progressive, so turning the crown opens its
//  starfield.
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
        // The height predates the panels' removal (their content asked
        // for 620 pt); it is kept because the flat catalog uses it and
        // the hub nameplate centers itself in whatever height it gets.
        .defaultSize(width: 560, height: 720)

        // The three utility windows — Settings, the Lab Notebook, About.
        // Each keeps the system glass (unlike the plain main window,
        // whose bareness serves the floating nameplate, not control
        // surfaces), and each is a value-less WindowGroup(id:), which is
        // single-instance: reopening one just brings it forward.
        //
        // All three ask for `.utilityPanel`. Without a placement,
        // visionOS anchors a programmatically opened window off the
        // app's key window — and while the gallery is up that is the
        // MAIN window, which is deliberately empty and parked wherever
        // the user last left it. The symptom on device was exact and
        // unmissable: every one of these opened somewhere behind the
        // podium, off to one side, half of it occluded by a plinth. A
        // utility panel is placed in front of the user instead, which is
        // the only correct answer for a window summoned by a button the
        // user is looking at.
        WindowGroup(id: SettingsView.windowID) {
            SettingsView()
                .environment(appModel)
        }
        // Tall enough that the whole form shows without scrolling at
        // default type size; the ScrollView is there for Dynamic Type.
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

        // Experiments: behind the gallery bar's flask, beside Settings
        // and the Lab Notebook (owner's call 2026-08-08). Tall, because
        // it is the first surface that lists every authored step rather
        // than counting them.
        WindowGroup(id: ExperimentsView.windowID) {
            ExperimentsView()
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
