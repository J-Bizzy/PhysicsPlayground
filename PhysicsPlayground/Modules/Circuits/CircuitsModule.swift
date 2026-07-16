//
//  CircuitsModule.swift
//  Physics Playground — Circuits module
//
//  Catalog registration for the circuit lab: descriptor, legend, and
//  first-run hint. The real-world story lives in CircuitsRealWorld.swift.
//

import SwiftUI

@MainActor
enum CircuitsModule {
    static let id = "circuits"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Circuit Lab",
            blurb: "Build real circuits in mid-air — batteries, bulbs, resistors, capacitors, switches — and watch the electrons actually flow.",
            icon: "powerplug.fill",
            accent: DesignTokens.Palette.circuitsAccent,
            firstRunHint: "Grab a part off the tray — a copy follows your hand; carry it anywhere. Connect parts by pinching one copper terminal, then another. Pull a wire's orange end grip to change its length, and use the trash button above a selected part to remove it.",
            legend: legend,
            realWorld: CircuitsRealWorld.story,
            isPaused: { appModel.circuitsModel.isPaused },
            togglePause: { appModel.circuitsModel.isPaused.toggle() },
            makeControls: {
                AnyView(
                    CircuitsControlsView()
                        .environment(appModel.circuitsModel)
                )
            },
            makeScene: {
                AnyView(
                    CircuitsSpaceView()
                        .environment(appModel.circuitsModel)
                )
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
