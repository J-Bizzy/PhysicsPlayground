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
    /// What More holds for the bench: the four views of the current, the
    /// five authored circuits in one menu, and Clear. `loadPreset` starts
    /// by clearing a bench that persists across launches, so the menu says
    /// so before you choose.
    static func more(_ model: CircuitsModel) -> [MoreItem] {
        [
            // True speed slows the flow it draws, so it has nothing to show
            // without the flow on: it stands under it, and only then.
            .group(lead: .toggle(id: "flow", title: "Electron flow", symbol: "circle.dotted",
                                 isOn: { model.showElectronFlow },
                                 set: { model.showElectronFlow = $0 }),
                   reveals: { model.showElectronFlow },
                   items: [
                       .toggle(id: "truespeed", title: "True drift speed", symbol: "tortoise",
                               isOn: { model.trueSpeedMode },
                               set: { model.trueSpeedMode = $0 }),
                   ]),
            .toggle(id: "bfield", title: "Magnetic field", symbol: "circle.hexagongrid",
                    isOn: { model.showMagneticField },
                    set: { model.showMagneticField = $0 }),
            .toggle(id: "skyline", title: "Voltage skyline", symbol: "building.2",
                    isOn: { model.showVoltageHeights },
                    set: { model.showVoltageHeights = $0 }),
            // One menu, not five buttons. Choosing from it is the second
            // press a loaded preset's arming used to ask for, and its note
            // says what the choice does to the bench.
            .verbs(id: "presets", title: "Load a circuit",
                   items: CircuitsModel.Preset.allCases.map {
                       (id: $0.rawValue, label: $0.displayName, symbol: "bolt.horizontal")
                   },
                   note: "Replaces what is on the bench",
                   run: { id in
                       guard let preset = CircuitsModel.Preset(rawValue: id) else { return }
                       model.loadPreset(preset)
                       model.commitBench()
                   }),
            .action(id: "clear", title: "Clear the bench", symbol: "trash.slash",
                    confirms: true, destructive: true,
                    isEnabled: .when({ !model.components.isEmpty }, else: "The bench is empty"),
                    run: {
                        model.clearBench()
                        model.commitBench()
                    }),
        ]
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
            let amps = PhysicsFormat.metric(readout.amps, "A", decimals: 2)
            // Auto-ranged in the formulas, so a closed switch's 0.4 mV is
            // not a "0.00 V" that its 140 µW cannot be the product of.
            let volts = PhysicsFormat.metric(readout.volts, "V", decimals: 2)
            rows.append(.init("\(name) current", amps, formula: ohm(component, volts: volts)))
            rows.append(.init("\(name) voltage", volts))
            // P = IV for every part, exactly: the solver's own definition.
            rows.append(.init("\(name) power", PhysicsFormat.metric(readout.watts, "W", decimals: 2),
                              formula: "P = IV = \(amps) × \(volts)"))
        }
        return rows
    }

    /// Ohm's law, for the parts the solver models as a plain resistance —
    /// a resistor (unscorched) and a bulb. Nothing for a source, a
    /// capacitor, an inductor, a diode or a motor, which obey other laws.
    static func ohm(_ component: CircuitsModel.Component, volts: String) -> String? {
        switch component.kind {
        case .resistor where !component.failed, .bulb:
            "I = V/R = \(volts) ÷ \(CircuitsModel.formatValue(component.value, for: component.kind))"
        default:
            nil
        }
    }

}
