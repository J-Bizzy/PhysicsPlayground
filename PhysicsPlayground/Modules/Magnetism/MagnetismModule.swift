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
//  The bench stands alone now: bar magnets and the field they make,
//  and nothing that belongs to another module.
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
            firstRunHint: "Pinch a magnet and carry it. Bring two close and watch — they pull together head-to-tail, push apart N-to-N, and swing to align. Tap a magnet and its controls unfold: flip its poles to switch attraction for repulsion. visionOS will ask to use your room so the lab can stand in it.",
            // Opens part-dimmed: the looping lines ARE the module.
            preferredDimming: 0.35,
            legend: legendItems,
            isPaused: { appModel.magnetismModel.isPaused },
            togglePause: { appModel.magnetismModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(MagnetismSpaceView().environment(appModel.magnetismModel))
            },
            captureReadings: { readings(appModel: appModel) },
            timeScrub: .init(model: appModel.magnetismModel),
            reset: { appModel.magnetismModel.reset() }
        )
    }
    /// The readings this bench writes into the lab notebook.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
        let model = appModel.magnetismModel
        var rows: [NotebookEntry.Reading] = [
            .init("Magnets", "\(model.magnets.count)"),
            // One spelling of a magnetic field, chosen by magnitude, instead
            // of this module hand-writing mT while Electric Fields hand-wrote
            // µT and kT in three other places.
            .init("|B| at centre",
                  PhysicsFormat.metric(model.centerFieldMilliTesla / 1000, "T",
                                       decimals: 2)),
            // "free"/"frozen" was this module's own spelling of a switched
            // state; three rooms had three. `PhysicsFormat.state` is the
            // one the notebook now reads everywhere.
            .init("Magnets move", PhysicsFormat.state(model.dynamicsOn)),
        ]
        if let selected = model.selectedMagnet {
            rows.append(.init("Selected moment",
                              PhysicsFormat.fixed(selected.strength, decimals: 3), "A·m²"))
            let others = model.magnets.filter { $0.id != selected.id }
            if !others.isEmpty {
                let force = MagneticField.netForce(on: selected, from: others)
                rows.append(.init("Force on it",
                                  PhysicsFormat.scientific(simd_length(force)), "N"))
                // U = −m·B summed over the other dipoles.
                let energy = others.reduce(0.0) {
                    $0 + MagneticField.potentialEnergy(of: selected, in: $1)
                }
                rows.append(.init("Potential energy",
                                  PhysicsFormat.scientific(energy), "J"))
            }
        }
        return rows
    }

    static let legendItems: [LegendItem] = [
        LegendItem(swatch: .fill(DesignTokens.Palette.positive),
                   text: "North pole (red)"),
        LegendItem(swatch: .fill(DesignTokens.Palette.negative),
                   text: "South pole (blue)"),
        LegendItem(swatch: .line(Color(uiColor: MagnetismRenderer.lineColor)),
                   text: "Field lines — closed loops running N to S outside the magnet, seeded THROUGH the room so the field fills the space you stand in. Every curve is a true streamline of B, and a stronger magnet sends out more of them; within one picture the lines are spread by volume, so exact local density is the field's shape rather than a flux count."),
        LegendItem(swatch: .symbol("location.north.fill", Color(uiColor: MagnetismRenderer.lineColor)),
                   text: "The hand compass points along the local field — and it is a SPHERE, with its needle free to swing in any direction. A flat dial can only show the part of B lying in the dial; between two poles the field usually points out of it."),
        LegendItem(swatch: .stroke(DesignTokens.Palette.selectionHalo),
                   text: "Halo marks the selected magnet"),
        // A DISCLOSED FUDGE, added 2026-08-03, and the module's largest.
        // The FIELDS here are exact — `MagneticField` gives the true
        // dipole B, force and torque, and `barVector` even swaps in a
        // finite two-pole bar where a point dipole would be wrong. The
        // MOTION is not: a magnet's speed is proportional to the force on
        // it and its turn rate to the torque, both capped, which is a
        // quasi-static mobility law rather than Newton's. The bars have
        // no mass and no moment of inertia here.
        LegendItem(
            swatch: .symbol("arrow.triangle.2.circlepath",
                            Color(uiColor: MagnetismRenderer.lineColor)),
            text: "The magnets GLIDE rather than accelerate. Every field, force and torque on this bench is exact — but a magnet's speed is set by the force on it and its turn rate by the torque, so it slides into alignment and stops. A real bar magnet has mass and rotational inertia: released at an angle it would swing PAST north and ring back and forth before settling. Nothing here overshoots, and that is a simplification, not the physics."
        ),
        LegendItem(
            swatch: .symbol("globe", Color(uiColor: MagnetismRenderer.lineColor)),
            text: "Earth's field is here too, at its real 50 µT — and a 6 A·m² bar magnet matches that at about 30 cm, so a compass carried an arm's length clear of the bench hands over to the planet. It is NOT horizontal: it runs 65° into the ground, which is why the needle tips down when it settles, and why a dip circle is a separate instrument in a real lab. Which way north lies is a convention — visionOS gives no heading — but the strength and the dip are real. Earth pulls on the compasses only, not on the bar magnets."),
    ]

}
