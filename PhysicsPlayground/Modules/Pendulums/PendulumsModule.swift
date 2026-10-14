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
            more: more(appModel.pendulumsModel),
            timeScrub: .init(model: appModel.pendulumsModel),
            reset: { appModel.pendulumsModel.reset() }
        )
    }

    /// What More holds for the bench: the two arrow layers, and whether
    /// the air is real. (Acceleration was a third layer until 2026-10-14:
    /// its arrow was the Force layer's net arrow over m.)
    static func more(_ model: PendulumsModel) -> [MoreItem] {
        [
            .toggle(id: "velocity", title: "Velocity", symbol: "arrow.right",
                    isOn: { model.showVelocity }, set: { model.showVelocity = $0 }),
            .toggle(id: "force", title: "Force", symbol: "arrow.down.right",
                    isOn: { model.showForces }, set: { model.showForces = $0 }),
            // Not a display layer, and the title says so: off, the pendulum
            // is ideal and swings for ever.
            .toggle(id: "friction", title: "Air resistance", symbol: "wind",
                    isOn: { model.frictionOn }, set: { model.frictionOn = $0 }),
        ]
    }

    /// The live numbers More shows.
    static func readings(appModel: AppModel) -> [Reading] {
        let model = appModel.pendulumsModel
        var rows: [Reading] = [
            .init("Pendulums", "\(model.pendulums.count)"),
            .init("Gravity", PhysicsFormat.fixed(model.gravity, decimals: 2), "m/s²"),
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
