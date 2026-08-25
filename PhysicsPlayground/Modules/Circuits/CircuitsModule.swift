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
            blurb: "A live electronics workbench: build anything from a flashlight to an RLC network, and watch voltage, current, and charge become visible.",
            icon: "powerplug.fill",
            accent: DesignTokens.Palette.circuitsAccent,
            // WHAT THIS SENTENCE SAYS HAS TO BE WHAT THE HANDS DO. It
            // described two gestures that were retired on 2026-08-11: an
            // "orange end grip" (the grips were deleted — a lead is the only
            // thing at an end now) and "pinch two copper terminals to wire"
            // (tap-tap wiring is gone; a tap selects and never wires).
            firstRunHint: "The loop in front of you is live — pinch the switch lever to break it. Pull parts out of the racks on either side of you and drop them so copper ends nearly touch: they connect themselves. To wire across a distance, pull a lead out of one copper end and let go on another. Tap a lead to light everything it is connected to; pull a wire's end off to move it somewhere else. The trash button removes a selected part. visionOS will ask to use your room so the bench can stand in it.",
            // The house dimming — see `PendulumsModule`. Gravity Lab is the exception.
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
            timeScrub: .init(model: appModel.circuitsModel),
            reset: { appModel.circuitsModel.reset() }
        )
    }
    /// The readings this bench writes into the lab notebook.
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
