//
//  MainWindowView.swift
//  Physics Playground — Shell
//
//  The main window: the module catalog (hub) when nothing is active, or
//  the active module hosted in the shared shell chrome. Modules only
//  supply their panel content — the shell owns navigation, the first-run
//  hint, the legend, the real-world panel, reset, and space lifecycle.
//

import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        // The NavigationStack is what gives the window a top bar: without a
        // navigation context, visionOS silently drops topBarLeading/trailing
        // toolbar items (the back and reset buttons).
        NavigationStack {
            if let module = appModel.activeModule {
                ModuleHostView(module: module)
                    .id(module.id)
            } else {
                HubView()
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    MainWindowView()
        .environment(AppModel())
}
