//
//  CircuitsModule.swift
//  Physics Playground — Circuits module
//
//  Catalog registration for the circuit lab: descriptor, legend, and
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
            isPaused: { appModel.circuitsModel.isPaused },
            togglePause: { appModel.circuitsModel.isPaused.toggle() },
            makeScene: {
                AnyView(
                    CircuitsSpaceView()
                        .environment(appModel.circuitsModel)
                )
            },
            captureReadings: {
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
            },
            reset: {
                appModel.circuitsModel.reset()
            }
        )
    }

    private static let legend: [LegendItem] = [
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
