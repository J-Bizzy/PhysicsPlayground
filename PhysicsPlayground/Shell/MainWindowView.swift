//
//  MainWindowView.swift
//  Physics Playground — Shell
//
//  The main window: the flat catalog when nothing is active, or the
//  active module's title bar. The shell owns navigation, reset and the
//  space lifecycle.
//

import SwiftUI

struct MainWindowView: View {
    /// Named so the shell can dismiss it while the gallery owns the home
    /// screen and open it again after (`PlaygroundSpaceView.syncMainWindow`).
    static let windowID = "main"

    @Environment(AppModel.self) private var appModel

    var body: some View {
        // Counted in and out so the shell never opens a second one
        // (`AppModel.mainWindowCount`). A ZStack, not a Group: a Group hands its
        // modifiers to every child and would count one window twice.
        ZStack { content }
            .onAppear { appModel.mainWindowCount += 1 }
            .onDisappear {
                appModel.mainWindowCount = max(appModel.mainWindowCount - 1, 0)
                // Closed by hand in a lab, the bar takes Home, More and Pause with
                // it and nothing brings it back; so the lab goes home, the one
                // scene that stands without a window (2026-11-07).
                if Self.closingGoesHome(activeModuleID: appModel.activeModuleID,
                                        spaceOpen: appModel.isImmersiveSpaceOpen) {
                    appModel.go(to: nil)
                }
            }
    }

    /// Whether a window going away was the wearer closing a lab's bar. The
    /// app's own dismissal clears the module first (`syncMainWindow`), and
    /// the space closing brings the window back rather than taking it, so a
    /// lab still active with the space open means a hand closed it.
    static func closingGoesHome(activeModuleID: String?, spaceOpen: Bool) -> Bool {
        activeModuleID != nil && spaceOpen
    }

    @ViewBuilder
    private var content: some View {
        if let module = appModel.activeModule {
            // The plain window carries just the floating title bar, which brings
            // its own glass.
            ModuleHostView(module: module)
                .id(module.id)
        } else {
            // The nameplate floats bare; the plain window adds no slab.
            HubView()
        }
    }
}

#Preview(windowStyle: .automatic) {
    MainWindowView()
        .environment(AppModel())
}
