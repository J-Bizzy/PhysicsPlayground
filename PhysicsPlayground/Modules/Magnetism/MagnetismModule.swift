//
//  MagnetismModule.swift
//  Physics Playground — Magnetism bench
//
//  What the magnetic bench contributes to the catalog: its legend and
//  its notebook readings. Bar magnets whose looping field fills the
//  room in 3D.
//
//  This IS a catalog entry — one of the three behind the Electricity &
//  Magnetism door. It briefly was not: the merged E&M world made this
//  the right-hand station of a shared room, and that world was undone
//  on 2026-07-30 when the geometry refused to close (see DECISIONS.md).
//  The coil that makes "a current is a magnet" watchable did not come
//  back here — it belongs to Circuit Workshop, because the CIRCUIT is
//  what powers it. Magnetism opened alone forces `electromagnetOn` off
//  on entry rather than reading a current from a room you are not in.
//

import SwiftUI
import PhysicsCore
import simd

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
            firstRunHint: "Pinch a magnet and carry it. Bring two close and watch — they pull together head-to-tail, push apart N-to-N, and swing to align. Tap a magnet and its controls unfold: flip its poles to switch attraction for repulsion.",
            // Opens part-dimmed: the looping lines ARE the module.
            preferredDimming: 0.35,
            legend: legendItems,
            isPaused: { appModel.magnetismModel.isPaused },
            togglePause: { appModel.magnetismModel.isPaused.toggle() },
            makeScene: {
                AnyView(MagnetismSpaceView().environment(appModel.magnetismModel))
            },
            makeControls: {
                AnyView(MagnetismControlsPanel().environment(appModel.magnetismModel))
            },
            captureReadings: { readings(appModel: appModel) },
            reset: { appModel.magnetismModel.reset() }
        )
    }
    /// The readings this bench writes into the lab notebook.
    /// Shared with the combined module that now hosts it.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
        let model = appModel.magnetismModel
        var rows: [NotebookEntry.Reading] = [
            .init("Magnets", "\(model.magnets.count)"),
            .init("|B| at centre",
                  String(format: "%.5f", model.centerFieldMilliTesla), "mT"),
            .init("Dynamics", model.dynamicsOn ? "free" : "frozen"),
        ]
        if let selected = model.selectedMagnet {
            rows.append(.init("Selected moment",
                              String(format: "%.3f", selected.strength), "A·m²"))
            let others = model.magnets.filter { $0.id != selected.id }
            if !others.isEmpty {
                let force = MagneticField.netForce(on: selected, from: others)
                rows.append(.init("Force on it",
                                  String(format: "%.3e", simd_length(force)), "N"))
                // U = −m·B summed over the other dipoles.
                let energy = others.reduce(0.0) {
                    $0 + MagneticField.potentialEnergy(of: selected, in: $1)
                }
                rows.append(.init("Potential energy",
                                  String(format: "%.3e", energy), "J"))
            }
        }
        if model.electromagnetOn {
            rows.append(.init("Coil moment",
                              String(format: "%.3f", model.electromagnetMoment), "A·m²"))
            rows.append(.init("Induced EMF",
                              String(format: "%.4f", model.inducedEMF * 1000), "mV"))
        }
        return rows
    }

    static let legendItems: [LegendItem] = [
        LegendItem(swatch: .fill(DesignTokens.Palette.positive),
                   text: "North pole (red)"),
        LegendItem(swatch: .fill(DesignTokens.Palette.negative),
                   text: "South pole (blue)"),
        LegendItem(swatch: .line(Color(uiColor: MagnetismRenderer.lineColor)),
                   text: "Field lines — closed loops running N to S outside the magnet, seeded evenly THROUGH the room so the field fills the space it is in. Every curve is a true streamline of B; but because the lines are spread by volume rather than by flux, how many you see somewhere is not how strong the field is there — this is the field's shape, and the compasses are its strength."),
        LegendItem(swatch: .symbol("location.north.fill", Color(uiColor: MagnetismRenderer.lineColor)),
                   text: "Compass needles point along the local field — and the one you can carry is a SPHERE, with its needle free to swing in any direction. A flat dial can only show the part of B lying in the dial; between two poles the field usually points out of it."),
        LegendItem(swatch: .stroke(DesignTokens.Palette.selectionHalo),
                   text: "Halo marks the selected magnet"),
    ]

}
