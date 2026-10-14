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
            isPaused: { appModel.pendulumsModel.isPaused },
            togglePause: { appModel.pendulumsModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(PendulumsSpaceView().environment(appModel.pendulumsModel))
            },
            readings: { readings(appModel: appModel) },
            timeScrub: .init(model: appModel.pendulumsModel),
            reset: { appModel.pendulumsModel.reset() }
        )
    }

    /// The live numbers the Physics box shows.
    static func readings(appModel: AppModel) -> [Reading] {
        let model = appModel.pendulumsModel
        var rows: [Reading] = [
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

}
