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
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        content
            .task {
                #if DEBUG
                // Companion to AppModel's `-openModule` debug hook: a module
                // launched from the command line needs its space opened too
                // (normally the hub does this before any module is entered).
                if UserDefaults.standard.string(forKey: "openModule") != nil,
                   !appModel.isImmersiveSpaceOpen {
                    let result = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
                    print("openModule debug hook: openImmersiveSpace -> \(result)")
                }
                #endif
            }
    }

    @ViewBuilder
    private var content: some View {
        if let module = appModel.activeModule {
            // The NavigationStack is what gives the window a top bar: without
            // a navigation context, visionOS silently drops topBarLeading/
            // trailing toolbar items (the back and reset buttons). The window
            // itself is .plain, so the module panel brings its own glass.
            NavigationStack {
                ModuleHostView(module: module)
                    .id(module.id)
                    .frame(minWidth: 540, maxWidth: .infinity,
                           minHeight: 620, maxHeight: .infinity)
            }
            .glassBackgroundEffect()
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
