//
//  CircuitsModule.swift
//  Physics Playground — Circuit bench
//
//  The circuit bench's catalog entry and its live readings.
//

import SwiftUI
import PhysicsCore

@MainActor
enum CircuitsModule {
    static let id = "circuits"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Circuit Workshop",
            shortTitle: "Circuits",
            icon: "powerplug.fill",
            accent: DesignTokens.Palette.circuitsAccent,
            // The house dimming — see `PendulumsModule`. Orbital Mechanics is the exception.
            preferredDimming: 0.35,
            isPaused: { appModel.circuitsModel.isPaused },
            togglePause: { appModel.circuitsModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(
                    CircuitsSpaceView()
                        .environment(appModel.circuitsModel)
                )
            },
            readings: { readings(appModel: appModel) },
            more: more(appModel.circuitsModel),
            timeScrub: .init(model: appModel.circuitsModel),
            reset: {
                appModel.circuitsModel.reset()
                appModel.circuitsModel.commitBench()
            }
        )
    }
    /// What More holds for the bench: the four views of the current, Clear,
    /// and the five authored circuits. Every load confirms — `loadPreset`
    /// starts by clearing a bench that persists across launches.
    static func more(_ model: CircuitsModel) -> [MoreItem] {
        var items: [MoreItem] = [
            .toggle(id: "flow", title: "Electron flow", symbol: "circle.dotted",
                    isOn: { model.showElectronFlow },
                    set: { model.showElectronFlow = $0 }),
            // True speed slows the flow it draws, so it has nothing to show
            // without the flow on.
            .toggle(id: "truespeed", title: "True drift speed", symbol: "tortoise",
                    isOn: { model.trueSpeedMode },
                    set: { model.trueSpeedMode = $0 },
                    isEnabled: { model.showElectronFlow }),
            .toggle(id: "bfield", title: "Magnetic field", symbol: "circle.hexagongrid",
                    isOn: { model.showMagneticField },
                    set: { model.showMagneticField = $0 }),
            .toggle(id: "skyline", title: "Voltage skyline", symbol: "building.2",
                    isOn: { model.showVoltageHeights },
                    set: { model.showVoltageHeights = $0 }),
            .action(id: "clear", title: "Clear the bench", symbol: "trash.slash",
                    confirms: true, destructive: true,
                    isEnabled: { !model.components.isEmpty },
                    run: {
                        model.clearBench()
                        model.commitBench()
                    }),
        ]
        items += CircuitsModel.Preset.allCases.map { preset in
            .action(id: "preset-\(preset.rawValue)", title: "Load \(preset.displayName)",
                    symbol: "bolt.horizontal", confirms: true,
                    run: {
                        model.loadPreset(preset)
                        model.commitBench()
                    })
        }
        return items
    }

    /// The live numbers More shows: the bench in two numbers,
    /// then the selected part's, or the first two parts' when none is.
    static func readings(appModel: AppModel) -> [Reading] {
        let model = appModel.circuitsModel
        var rows: [Reading] = [
            .init("Components", "\(model.components.count)"),
            .init("Wires", "\(model.wires.count)"),
        ]
        let shown = model.selectedComponent.map { [$0] } ?? Array(model.components.prefix(2))
        for component in shown {
            guard let readout = model.readouts[component.id] else { continue }
            let name = component.kind.displayName
            rows.append(.init("\(name) current", PhysicsFormat.metric(readout.amps, "A", decimals: 2)))
            rows.append(.init("\(name) voltage", PhysicsFormat.fixed(readout.volts, decimals: 2), "V"))
            rows.append(.init("\(name) power", PhysicsFormat.metric(readout.watts, "W", decimals: 2)))
        }
        return rows
    }

}
