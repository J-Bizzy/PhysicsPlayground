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
            firstRunHint: "Look at a magnet and pinch to carry it. Bring two close and watch — they pull together head-to-tail, push apart N-to-N, and swing to align. Flip a magnet's poles to switch attraction for repulsion.",
            legend: legend,
            realWorld: realWorld,
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

    private static let realWorld = RealWorldStory(
        tagline: "The same dipole field that snaps two fridge magnets together runs the machines that image your body and store your data.",
        applications: [
            .init(title: "MRI scanners", icon: "waveform.path.ecg",
                  body: "A superconducting magnet aligns the spins of hydrogen nuclei in your body, then reads how they relax — a picture built entirely from magnetic dipoles, the same physics as these bars."),
            .init(title: "Hard drives & tape", icon: "externaldrive.fill",
                  body: "Data is stored as billions of tiny magnetic domains, each a dipole flipped N or S. A read head senses the field of each one flying past — your files are a field map."),
            .init(title: "Electric motors", icon: "gearshape.2.fill",
                  body: "A motor is a magnet trying to align with a field that keeps rotating out from under it — the torque τ = m × B you feel when two magnets swing to line up, harnessed to spin a shaft."),
            .init(title: "Compasses & Earth's field", icon: "location.north.line.fill",
                  body: "A compass needle is a bar magnet free to turn; it points along Earth's own dipole field. Move a magnet near it and, like the needles here, it swings to the stronger local field."),
        ]
    )
}
