//
//  MainWindowView.swift
//  Physics Playground — Shell
//
//  The main window: the module catalog (hub) when nothing is active, or
//  the active module hosted in the shared shell chrome. A module supplies
//  its physics and its scene; the shell owns navigation, the first-run
//  hint, reset and the space lifecycle. (This listed "their panel
//  content", "the legend" and "the real-world panel" until 2026-08-03 —
//  the panels went on 2026-08-01 and the legend moved to the notebook.)
//

import SwiftUI

struct MainWindowView: View {
    /// The app's primary window. Named so the shell can dismiss it while
    /// the gallery owns the home screen and open it again after — see
    /// `PlaygroundSpaceView.syncMainWindow`.
    static let windowID = "main"

    @Environment(AppModel.self) private var appModel

    // THE LAUNCH PATH LEFT THIS FILE ON 2026-08-22, with the window's
    // job. It warmed the sound set and the prop cache and read seven
    // debug screenshot arguments — all of it on the reasoning that this
    // was the scene that launches. The ImmersiveSpace is, now, so that
    // work lives in `PlaygroundSpaceView` and this view is what its name
    // always claimed: a window, showing one of two things.
    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if let module = appModel.activeModule {
            // The plain window carries just the floating title bar; the
            // bar brings its own glass capsule.
            ModuleHostView(module: module)
                .id(module.id)
        } else {
            // The nameplate: bare floating type — the plain window adds
            // no slab, and the hub adds none of its own.
            HubView()
        }
    }
}

#Preview(windowStyle: .automatic) {
    MainWindowView()
        .environment(AppModel())
}
