//
//  ElectromagnetismModule.swift
//  Physics Playground — Electromagnetism module
//
//  Catalog registration for Electric Fields: descriptor, readings and
//  legend. Briefly the centre station of a merged E&M world; the world
//  was undone for geometry (DECISIONS.md, 2026-07-30) and this is a
//  standalone experience again — but it keeps the lateral clamps that
//  merger forced into existence, because a charge that could be
//  dragged across the room was a bug with or without a neighbour.
//

import SwiftUI
import PhysicsCore
import simd

@MainActor
enum ElectromagnetismModule {
    // Kept even though nothing registers under it any more: it still
    // keys this bench's dismissed-hint flag and its notebook history.
    static let id = "electrostatics"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Electric Fields",
            shortTitle: "Fields",
            blurb: "Place charges, trace the field lines they make, and ride a test charge through Coulomb's law.",
            icon: "bolt.fill",
            accent: DesignTokens.Palette.electrostaticsAccent,
            firstRunHint: "Pull a charge out of the wells on your right — it is in your hand the moment it exists. Drag it anywhere and the field follows; tap it and its controls unfold around it. The switches on your left decide what else is in the room. visionOS will ask to use your room so the lab can stand in it.",
            // Opens part-dimmed: field lines are thin glowing filaments —
            // they need something to glow against.
            preferredDimming: 0.35,
            legend: legendItems,
            isPaused: { appModel.electromagnetismModel.isPaused },
            togglePause: { appModel.electromagnetismModel.isPaused.toggle() },
            makeScene: {
                AnyView(FieldSpaceView().environment(appModel.electromagnetismModel))
            },
            captureReadings: { readings(appModel: appModel) },
            timeScrub: .inert,
            reset: { appModel.electromagnetismModel.reset() }
        )
    }

    /// The readings this bench writes into the lab notebook.
    /// Shared with the combined module that now hosts it.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
        let model = appModel.electromagnetismModel
        var rows: [NotebookEntry.Reading] = [
            .init("Charges", "\(model.charges.count)"),
            .init("Net charge",
                  PhysicsFormat.scientific(
                    model.charges.reduce(0) { $0 + $1.charge }), "C"),
        ]
        if let selected = model.selectedCharge {
            rows.append(.init("Selected charge",
                              PhysicsFormat.scientific(selected.charge), "C"))
            rows.append(.init("|E| 10 cm away",
                PhysicsFormat.scientific(
                    simd_length(model.fieldVector(
                        at: selected.position + SIMD3(0.1, 0, 0)))), "N/C"))
        }
        if model.capacitorOn {
            rows.append(.init("Plate voltage",
                              PhysicsFormat.metric(model.plateVoltage, "V", decimals: 1)))
            rows.append(.init("Plate gap",
                              PhysicsFormat.fixed(model.plateSeparation, decimals: 3), "m"))
            rows.append(.init("E between plates",
                PhysicsFormat.metric(model.plateVoltage / model.plateSeparation,
                                     "V/m", decimals: 1)))
        }
        if model.magneticFieldOn {
            rows.append(.init("B", PhysicsFormat.metric(
                model.magneticFieldTesla, "T", decimals: 2)))
            rows.append(.init("Cyclotron radius",
                              PhysicsFormat.fixed(model.cyclotronRadius, decimals: 3), "m"))
        }
        return rows
    }

    static let legendItems: [LegendItem] = [
        LegendItem(
            swatch: .fill(DesignTokens.Palette.positive),
            text: "Positive charge"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.negative),
            text: "Negative charge"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.probePositive),
            text: "Positive test charge (accelerates via F = qE)"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.probeNegative),
            text: "Negative test charge"
        ),
        LegendItem(
            swatch: .line(DesignTokens.Palette.fieldLine),
            text: "Field lines run from positive to negative"
        ),
        LegendItem(
            swatch: .stroke(DesignTokens.Palette.selectionHalo),
            text: "Halo marks the selected charge"
        ),
        LegendItem(
            swatch: .symbol("arrow.up.right", DesignTokens.Palette.fieldLine),
            text: "Arrowheads ride the field lines, pointing along E"
        ),
        // A DISCLOSED FUDGE, added 2026-08-03. `chargesRespond` moves the
        // source charges by an overdamped mobility law — velocity ∝
        // force, capped — rather than by F = ma. Everything the module
        // COMPUTES is exact Coulomb; what is approximated is how the
        // charges travel, and nothing said so. Every other fiction in
        // this app is disclosed where it is read (the 50 kT field says so
        // in its own readout); this one was not.
        LegendItem(
            swatch: .symbol("arrow.left.and.right", DesignTokens.Palette.fieldLine),
            text: "Free charges DRIFT rather than accelerate: with the switch on, a charge's speed is set by the force on it instead of its acceleration, so the flock slides into place and settles rather than overshooting and oscillating. The field, the force and the potential are exact Coulomb; only the travel is a simplification, chosen so a pair you release finds equilibrium in front of you instead of ringing about it forever."
        ),
    ]
}
