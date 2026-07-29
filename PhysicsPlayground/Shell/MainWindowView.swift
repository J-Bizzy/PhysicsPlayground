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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        content
            .task {
                // Synthesize the sound set no matter how the app was
                // entered (the debug -openModule path skips the hub).
                SoundPalette.warmUp()
                #if DEBUG
                // Companion to AppModel's `-openModule` debug hook: a module
                // launched from the command line needs its space opened too
                // (normally the hub does this before any module is entered).
                if UserDefaults.standard.string(forKey: "openModule") != nil,
                   !appModel.isImmersiveSpaceOpen {
                    let result = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
                    print("openModule debug hook: openImmersiveSpace -> \(result)")
                }
                // `-settingsOpen 1` opens the settings window at launch for
                // CLI screenshots (no immersive space or bead pinch needed).
                if UserDefaults.standard.bool(forKey: "settingsOpen") {
                    openWindow(id: SettingsView.windowID)
                }
                // `-seedCircuits 1` drops a few parts (one wire aimed off-axis)
                // so component visuals can be screenshot-checked from the CLI.
                if UserDefaults.standard.bool(forKey: "seedCircuits") {
                    let circuits = appModel.circuitsModel
                    if circuits.components.isEmpty {
                        circuits.add(.battery, at: SIMD3(-0.35, 1.3, -0.9))
                        circuits.add(.bulb, at: SIMD3(0.35, 1.3, -0.9))
                        circuits.add(.wire, at: SIMD3(0, 1.5, -0.9))
                        if let wire = circuits.components.last {
                            let pivot = wire.terminalPosition(0)
                            circuits.dragEnd(id: wire.id, grabbedEnd: 1, pivot: pivot,
                                             hand: pivot + SIMD3(0.35, 0.4, 0.05))
                        }
                    }
                    // `-circuitVoltageHeights 1` raises the voltage skyline.
                    if UserDefaults.standard.bool(forKey: "circuitVoltageHeights") {
                        circuits.showVoltageHeights = true
                    }
                    // `-seedMotor 1` builds a battery→motor loop so the
                    // rotor spins for a screenshot check.
                    if UserDefaults.standard.bool(forKey: "seedMotor") {
                        circuits.clearBench()
                        if let battery = circuits.add(.battery, at: SIMD3(-0.3, 1.3, -0.85)),
                           let motor = circuits.add(.motor, at: SIMD3(0.3, 1.3, -0.85)) {
                            circuits.connectTerminals(.init(componentID: battery, end: 0),
                                                      .init(componentID: motor, end: 0))
                            circuits.connectTerminals(.init(componentID: battery, end: 1),
                                                      .init(componentID: motor, end: 1))
                        }
                    }
                }
                #endif
            }
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
