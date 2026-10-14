//
//  CircuitsModule.swift
//  Physics Playground — Circuit bench
//
//  The circuit bench's catalog entry: its legend and notebook readings.
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
            legend: legend,
            isPaused: { appModel.circuitsModel.isPaused },
            togglePause: { appModel.circuitsModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(
                    CircuitsSpaceView()
                        .environment(appModel.circuitsModel)
                )
            },
            captureReadings: { readings(appModel: appModel) },
            physicsRows: { boxRows(appModel: appModel) },
            timeScrub: .init(model: appModel.circuitsModel),
            reset: {
                appModel.circuitsModel.reset()
                appModel.circuitsModel.commitBench()
            }
        )
    }
    /// The readings this bench writes into the lab notebook.
    /// The Physics box's list: the bench in two numbers, then the selected
    /// part's — the notebook records every part, a card cannot.
    static func boxRows(appModel: AppModel) -> [NotebookEntry.Reading] {
        let model = appModel.circuitsModel
        var rows: [NotebookEntry.Reading] = [
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

    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
        let model = appModel.circuitsModel
        var rows: [NotebookEntry.Reading] = [
            .init("Components", "\(model.components.count)"),
            .init("Wires", "\(model.wires.count)"),
        ]
        for component in model.components {
            guard let readout = model.readouts[component.id] else { continue }
            let name = component.kind.displayName
            rows.append(.init("\(name) current",
                              PhysicsFormat.metric(readout.amps, "A", decimals: 2)))
            rows.append(.init("\(name) voltage",
                              PhysicsFormat.fixed(readout.volts, decimals: 2), "V"))
            rows.append(.init("\(name) power",
                              PhysicsFormat.metric(readout.watts, "W", decimals: 2)))
        }
        return rows
    }

    /// The bench's full legend.
    static let legend: [LegendItem] = [
        LegendItem(
            swatch: .fill(Color(uiColor: DesignTokens.Palette.copperUI)),
            text: "Copper terminals — pull a lead from one to another to wire them; pull a wire's end into open air to remove it"
        ),
        LegendItem(
            swatch: .fill(Color(uiColor: DesignTokens.Palette.electronUI)),
            text: "Electrons — they drift − to +, opposite the conventional current arrow, faster where the current is larger"
        ),
        LegendItem(
            swatch: .fill(.yellow),
            text: "Bulb glow = true power dissipated (P = I²R) — dim it by adding resistance"
        ),
        LegendItem(
            swatch: .line(Color(uiColor: DesignTokens.Palette.copperUI)),
            text: "Resistor bands show the real 4-band color code and repaint as you adjust the value"
        ),
        LegendItem(
            swatch: .symbol("bolt.badge.clock", DesignTokens.Palette.circuitsAccent),
            text: "Capacitors charge in real time — watch a bulb fade as its capacitor fills (τ = RC)"
        ),
    ]
}
