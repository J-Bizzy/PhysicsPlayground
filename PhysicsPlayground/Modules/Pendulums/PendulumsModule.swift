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
            icon: "metronome.fill",
            accent: DesignTokens.Palette.pendulumsAccent,
            // The house dimming; Orbital Mechanics' 0.85 is the one deliberate exception.
            preferredDimming: 0.35,
            legend: legendItems,
            isPaused: { appModel.pendulumsModel.isPaused },
            togglePause: { appModel.pendulumsModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(PendulumsSpaceView().environment(appModel.pendulumsModel))
            },
            captureReadings: { readings(appModel: appModel) },
            timeScrub: .init(model: appModel.pendulumsModel),
            reset: { appModel.pendulumsModel.reset() }
        )
    }

    /// The readings this bench writes into the lab notebook.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
        let model = appModel.pendulumsModel
        var rows: [NotebookEntry.Reading] = [
            .init("Pendulums", "\(model.pendulums.count)"),
            .init("Gravity", PhysicsFormat.fixed(model.gravity, decimals: 2), "m/s²"),
            // Named for the plate that switches it.
            .init("Air resistance", PhysicsFormat.state(model.frictionOn)),
        ]
        if let selected = model.selected {
            rows.append(.init("Length", PhysicsFormat.fixed(selected.length, decimals: 3), "m"))
            rows.append(.init("Mass", PhysicsFormat.fixed(selected.mass, decimals: 3), "kg"))
            // A double pendulum writes no period: the formula is the
            // upper rod's alone and the system has none.
            if selected.kind != .double {
                rows.append(.init("Period 2π√(L/g)",
                                  PhysicsFormat.fixed(selected.period(gravity: model.gravity),
                                                      decimals: 3), "s"))
            }
            rows.append(.init("Speed",
                              PhysicsFormat.fixed(simd_length(selected.state.velocity),
                                                  decimals: 3), "m/s"))
        }
        return rows
    }

    static let legendItems: [LegendItem] = [
        LegendItem(swatch: .fill(DesignTokens.Palette.velocityVector),
                   text: "Blue arrow — velocity; the trail runs blue (slow) to orange (fast), so the swing colors its own speed"),
        LegendItem(swatch: .fill(Color(red: 0.95, green: 0.85, blue: 0.2)),
                   text: "Force arrows — cyan gravity, yellow cable tension, red net force"),
        LegendItem(swatch: .line(.white),
                   text: "White ghost line while holding a bob — the exact swing a release right now would launch"),
    ]

}
