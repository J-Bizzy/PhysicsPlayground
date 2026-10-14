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
            timeScrub: .init(model: appModel.circuitsModel),
            reset: {
                appModel.circuitsModel.reset()
                appModel.circuitsModel.commitBench()
            }
        )
    }
    /// The live numbers the Physics box shows: the bench in two numbers,
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
