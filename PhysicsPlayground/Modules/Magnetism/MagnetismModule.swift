//
//  MagnetismModule.swift
//  Physics Playground — Magnetism module
//
//  Catalog registration for the magnetism sandbox: descriptor, legend,
//  first-run hint, and the real-world story. The magnetic twin of Electric
//  Fields — bar magnets whose looping field fills the room in 3D.
//

import SwiftUI

@MainActor
enum MagnetismModule {
    static let id = "magnetism"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Magnetism",
            blurb: "Carry bar magnets around the room; their looping field reorganises live and they attract, repel, and snap into alignment.",
            icon: "cylinder.fill",
            accent: DesignTokens.Palette.magnetismAccent,
            podsCoverControls: true,
            firstRunHint: "Look at a magnet and pinch to carry it. Bring two close and watch — they pull together head-to-tail, push apart N-to-N, and swing to align. Flip a magnet's poles to switch attraction for repulsion.",
            legend: legend,
            isPaused: { appModel.magnetismModel.isPaused },
            togglePause: { appModel.magnetismModel.isPaused.toggle() },
            makeControls: {
                AnyView(MagnetismControlsView().environment(appModel.magnetismModel))
            },
            makeScene: {
                AnyView(MagnetismSpaceView().environment(appModel.magnetismModel))
            },
            reset: { appModel.magnetismModel.reset() }
        )
    }

    private static let legend: [LegendItem] = [
        LegendItem(swatch: .fill(DesignTokens.Palette.positive),
                   text: "North pole (red)"),
        LegendItem(swatch: .fill(DesignTokens.Palette.negative),
                   text: "South pole (blue)"),
        LegendItem(swatch: .line(Color(uiColor: MagnetismRenderer.lineColor)),
                   text: "Field lines — closed loops running N to S outside the magnet"),
        LegendItem(swatch: .symbol("location.north.fill", Color(uiColor: MagnetismRenderer.lineColor)),
                   text: "Compass needles point along the local field"),
        LegendItem(swatch: .stroke(DesignTokens.Palette.selectionHalo),
                   text: "Halo marks the selected magnet"),
    ]

}
