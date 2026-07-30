//
//  CircuitsModule.swift
//  Physics Playground — Circuit bench
//
//  What the circuit bench contributes to the catalog: its legend and
//  its notebook readings.
//
//  This is NOT a catalog entry any more. The workshop is the left-hand
//  station of the merged E&M world (EMWorldModule) rather than a module
//  of its own — its inductor current has always driven the magnet
//  bench's electromagnet, and that link was unwatchable while the two
//  benches were in different rooms. The bench's model, renderer, panel,
//  and physics are all unchanged; only its front door moved.
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
            blurb: "A live electronics workbench: build anything from a flashlight to an RLC network, and watch voltage, current, and charge become visible.",
            icon: "powerplug.fill",
            accent: DesignTokens.Palette.circuitsAccent,
            firstRunHint: "The loop in front of you is live — pinch the switch lever to break it. Grab parts off the tray and drop them so copper ends nearly touch: they connect themselves. Pull an orange end grip to aim or stretch a part; pinch two copper terminals to wire across a distance; the trash button removes a selected part.",
            legend: legend,
            // Pause freezes the PAIR: when the coil is on, the magnetic
            // field beside the bench is running this bench's current,
            // and a frozen circuit driving a live magnet would be a
            // frame of physics that never happened.
            isPaused: {
                appModel.circuitsModel.isPaused && appModel.magnetismModel.isPaused
            },
            togglePause: {
                let paused = appModel.circuitsModel.isPaused
                    && appModel.magnetismModel.isPaused
                appModel.circuitsModel.isPaused = !paused
                appModel.magnetismModel.isPaused = !paused
            },
            makeScene: {
                AnyView(
                    CircuitsSpaceView()
                        .environment(appModel.circuitsModel)
                        // The wired pair: the magnetic field this bench
                        // summons when its electromagnet switch is on.
                        .environment(appModel.magnetismModel)
                )
            },
            makeControls: {
                AnyView(
                    CircuitsControlsPanel()
                        .environment(appModel.circuitsModel)
                        .environment(appModel.magnetismModel)
                )
            },
            captureReadings: { readings(appModel: appModel) },
            reset: { appModel.circuitsModel.reset() }
        )
    }
    /// The readings this bench writes into the lab notebook.
    /// Shared with the combined module that now hosts it.
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
                              String(format: "%.4f", readout.amps), "A"))
            rows.append(.init("\(name) voltage",
                              String(format: "%.3f", readout.volts), "V"))
            rows.append(.init("\(name) power",
                              String(format: "%.4f", readout.watts), "W"))
        }
        return rows
    }

    /// The bench's full legend. The merged world curates its own
    /// shorter key from this and the magnet bench's; this stays as the
    /// complete one, and is what the bench would show if it ever
    /// stands alone again.
    static let legend: [LegendItem] = [
        LegendItem(
            swatch: .fill(Color(uiColor: DesignTokens.Palette.copperUI)),
            text: "Copper terminals — pinch one, then another, to wire them; pinch a wire to remove it"
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
