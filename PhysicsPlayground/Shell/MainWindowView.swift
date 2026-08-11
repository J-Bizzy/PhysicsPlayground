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
                // `-notebookOpen 1` likewise for the Lab Notebook;
                // `-notebookSeed 1` fills it with sample observations
                // first, so the entry cards can be screenshot-checked.
                if UserDefaults.standard.bool(forKey: "notebookSeed"),
                   appModel.notebook.entries.isEmpty {
                    appModel.notebook.record(
                        moduleID: "electrostatics", moduleTitle: "Electric Fields",
                        title: "Seeded observation 1",
                        readings: [.init("Charges", "2"),
                                   .init("Net charge", "0.0", "C"),
                                   .init("|E| 10 cm away", "8.99e5", "N/C")])
                    appModel.notebook.record(
                        moduleID: "pendulums", moduleTitle: "Pendulums",
                        title: "Seeded observation 1",
                        readings: [.init("Length", "0.80", "m"),
                                   .init("Period", "1.79", "s")])
                }
                if UserDefaults.standard.bool(forKey: "notebookOpen") {
                    openWindow(id: NotebookView.windowID)
                }
                // `-seedCircuits 1` drops a few parts (one aimed
                // off-axis) so component visuals can be
                // screenshot-checked from the CLI. The off-axis part
                // was a jumper until the jumper was retired; a
                // resistor aims just as crookedly and is still a part
                // the bench can hold.
                if UserDefaults.standard.bool(forKey: "seedCircuits") {
                    let circuits = appModel.circuitsModel
                    if circuits.components.isEmpty {
                        circuits.add(.battery, at: SIMD3(-0.35, 1.3, -0.9))
                        circuits.add(.bulb, at: SIMD3(0.35, 1.3, -0.9))
                        circuits.add(.resistor, at: SIMD3(0, 1.5, -0.9))
                        if let part = circuits.components.last {
                            let pivot = part.terminalPosition(0)
                            circuits.dragEnd(id: part.id, grabbedEnd: 1, pivot: pivot,
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
