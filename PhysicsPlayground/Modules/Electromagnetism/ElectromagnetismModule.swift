//
//  ElectromagnetismModule.swift
//  Physics Playground — Electromagnetism module
//
//  Catalog registration for the electromagnetism sandbox (the original
//  Field Playground experience): descriptor, legend, and first-run hint.
//

import SwiftUI

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
            legend: legend,
            isPaused: { appModel.electromagnetismModel.isPaused },
            togglePause: { appModel.electromagnetismModel.isPaused.toggle() },
            makeControls: {
                AnyView(
                    ElectrostaticsControlsView()
                        .environment(appModel.electromagnetismModel)
                )
            },
            makeScene: {
                AnyView(
                    FieldSpaceView()
                        .environment(appModel.electromagnetismModel)
                )
            },
            reset: {
                appModel.electromagnetismModel.reset()
            }
        )
    }

    private static let legend: [LegendItem] = [
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
