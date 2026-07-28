//
//  ElectromagnetismModule.swift
//  Physics Playground — Electromagnetism module
//
//  Catalog registration for the electromagnetism sandbox (the original
//  Field Playground experience): descriptor, legend, and first-run hint.
//

import SwiftUI
import PhysicsCore
import simd

@MainActor
enum ElectromagnetismModule {
    // Kept from the original module so saved per-module state (like the
    // dismissed-hint flag) survives the rename.
    static let id = "electrostatics"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Electric Fields",
            blurb: "Place charges, trace field lines and equipotential shells, and ride a test charge through Coulomb's law.",
            icon: "bolt.fill",
            accent: DesignTokens.Palette.electromagnetismAccent,
            firstRunHint: "Look at a charge and pinch to grab it, then drag it anywhere — the field follows. The charge with the white halo is the one the sliders edit.",
            // Opens part-dimmed: field lines are thin glowing filaments — they need something to glow against.
            preferredDimming: 0.35,
            legend: legendItems,
            isPaused: { appModel.electromagnetismModel.isPaused },
            togglePause: { appModel.electromagnetismModel.isPaused.toggle() },
            makeScene: {
                AnyView(
                    FieldSpaceView()
                        .environment(appModel.electromagnetismModel)
                )
            },
            captureReadings: { readings(appModel: appModel) },
            reset: {
                appModel.electromagnetismModel.reset()
            }
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
                              String(format: "%.1f", model.plateVoltage / 1000), "kV"))
            rows.append(.init("Plate gap",
                              String(format: "%.3f", model.plateSeparation), "m"))
            rows.append(.init("E between plates",
                String(format: "%.0f", model.plateVoltage / model.plateSeparation), "V/m"))
        }
        if model.magneticFieldOn {
            rows.append(.init("B", String(format: "%.4g",
                model.electronMode ? model.electronFieldTesla : model.magneticFieldTesla), "T"))
            rows.append(.init("Cyclotron radius",
                              String(format: "%.4f", model.cyclotronRadius), "m"))
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
            swatch: .translucent(DesignTokens.Palette.positiveShell),
            text: "Translucent shells: equal potential (orange +, indigo −), always at right angles to field lines"
        ),
        LegendItem(
            swatch: .stroke(DesignTokens.Palette.selectionHalo),
            text: "Halo marks the selected charge"
        ),
        LegendItem(
            swatch: .symbol("arrow.up.right", DesignTokens.Palette.fieldLine),
            text: "Arrowheads ride the field lines, pointing along E"
        ),
    ]
}
