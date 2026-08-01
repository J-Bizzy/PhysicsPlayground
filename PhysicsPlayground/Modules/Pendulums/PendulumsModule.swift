//
//  PendulumsModule.swift
//  Physics Playground — Pendulums module
//
//  Catalog registration, window controls, and the real-world story.
//

import PhysicsCore
import SwiftUI
import simd

@MainActor
enum PendulumsModule {
    static let id = "pendulums"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Pendulums",
            blurb: "Hang a pendulum anywhere in the room, then grab the steel bob and throw it — full nonlinear swings, energy trading between bars, and five-pendulum resonance.",
            icon: "metronome.fill",
            accent: DesignTokens.Palette.pendulumsAccent,
            firstRunHint: "The bob is already swinging — grab it and throw it sideways. While you hold it, the faint line shows the swing you're about to launch. Tap a bob to select it. To your right, tap a world — the Moon stretches every swing out to two and a half times its period.",
            legend: legendItems,
            isPaused: { appModel.pendulumsModel.isPaused },
            togglePause: { appModel.pendulumsModel.isPaused.toggle() },
            makeScene: {
                AnyView(PendulumsSpaceView().environment(appModel.pendulumsModel))
            },
            makeControls: {
                AnyView(PendulumsControlsPanel().environment(appModel.pendulumsModel))
            },
            captureReadings: { readings(appModel: appModel) },
            reset: { appModel.pendulumsModel.reset() }
        )
    }

    /// The readings this bench writes into the lab notebook.
    /// Shared with the combined module that now hosts it.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
        let model = appModel.pendulumsModel
        var rows: [NotebookEntry.Reading] = [
            .init("Pendulums", "\(model.pendulums.count)"),
            .init("Gravity", String(format: "%.3f", model.gravity), "m/s²"),
            .init("Friction", model.frictionOn ? "on" : "off"),
        ]
        if let selected = model.selected {
            let energies = selected.state.energies(
                length: selected.length,
                gravity: model.gravity, mass: selected.mass)
            rows.append(.init("Length", String(format: "%.4f", selected.length), "m"))
            rows.append(.init("Mass", String(format: "%.3f", selected.mass), "kg"))
            rows.append(.init("Period 2π√(L/g)",
                              String(format: "%.4f", selected.period(gravity: model.gravity)), "s"))
            rows.append(.init("Speed",
                              String(format: "%.4f", simd_length(selected.state.velocity)), "m/s"))
            rows.append(.init("Kinetic energy", String(format: "%.5f", energies.kinetic), "J"))
            rows.append(.init("Potential energy", String(format: "%.5f", energies.potential), "J"))
        }
        return rows
    }

    static let legendItems: [LegendItem] = [
        LegendItem(swatch: .fill(DesignTokens.Palette.velocityVector),
                   text: "Blue bar & arrow — kinetic energy and velocity; trail runs blue (slow) to orange (fast)"),
        LegendItem(swatch: .fill(Color(red: 0.2, green: 0.8, blue: 0.35)),
                   text: "Green bar — potential energy; watch the two bars trade while their sum holds"),
        LegendItem(swatch: .fill(Color(red: 0.95, green: 0.85, blue: 0.2)),
                   text: "Force arrows — purple gravity, yellow cable tension, red net force"),
        LegendItem(swatch: .line(.white),
                   text: "White ghost line while holding a bob — the exact swing a release right now would launch"),
    ]

}

// `PendulumsControlsView` was deleted here (2026-07-29): a window panel
// of six per-pendulum sliders — length, mass, damping, bob size, cable
// thickness, start angle — plus a Remove button, never instantiated by
// anything since it was written.
//
// It is the clearest specimen in the app of what the interaction law now
// forbids (DECISIONS.md, 2026-07-29): every quantity in it has physical
// extent and three of them are already manipulated BY that extent on the
// object itself — the bob's Bloom carries a Length grip you pull to pay
// out cable, a Mass petal, and a Delete petal. The panel was a second,
// worse way to do what the pendulum already does.
//
// A grave, not a missing door: `setBobRadius`, `setCableThickness`,
// `setInitialAngle` and `removeSelected` went with it. Bob size and cable
// thickness are cosmetics, not physics; a start angle is what grabbing
// the bob and letting go already sets, more honestly; and deletion is a
// petal. `setLength`, `setMass` and `setDamping` stay — the Bloom and the
// module panel use those.
