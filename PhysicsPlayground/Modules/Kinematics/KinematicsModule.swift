//
//  KinematicsModule.swift
//  Physics Playground — Kinematics: catalog registration — descriptor and readings.
//

import SwiftUI
import PhysicsCore

@MainActor
enum KinematicsModule {
    static let id = "kinematics"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Projectile Motion",
            shortTitle: "Projectiles",
            icon: "paperplane.fill",
            accent: DesignTokens.Palette.kinematicsAccent,
            // The house dimming (Orbital Mechanics' 0.85 is the one exception).
            preferredDimming: 0.35,
            isPaused: { appModel.kinematicsModel.isPaused },
            // Through the capsule: un-pausing from a scrubbed instant resumes from it.
            togglePause: { appModel.kinematicsModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(KinematicsSpaceView().environment(appModel.kinematicsModel))
            },
            readings: { readings(appModel: appModel) },
            more: more(appModel.kinematicsModel),
            timeScrub: .init(model: appModel.kinematicsModel),
            reset: { appModel.kinematicsModel.reset() }
        )
    }

    /// What More holds for the throw: the world it happens on, its air,
    /// and the room's walls. Angle and speed are the aim bead; the ball is
    /// the fan over the launcher.
    static func more(_ model: KinematicsModel) -> [MoreItem] {
        [
            // g was a world fan, a rail in the room and a rail in the box;
            // it is this one slider, which names the world it stands on.
            .slider(.init(id: "gravity", label: "Gravity", unit: "m/s²",
                          range: KinematicsModel.gravityRange, decimals: 2,
                          format: gravityReadout,
                          read: { model.gravity },
                          write: { model.gravity = gravityDetent($0) })),
            .toggle(id: "walls", title: "Walls bounce", symbol: "square.dashed",
                    isOn: { model.respectRoomWalls },
                    set: { model.respectRoomWalls = $0 }),
            .toggle(id: "air", title: "Air resistance", symbol: "wind",
                    isOn: { model.airResistance },
                    set: { model.airResistance = $0 }),
            // Wind blows through air or not at all.
            .slider(.init(id: "wind", label: "Wind", unit: "m/s",
                          range: KinematicsModel.windSpeedRange, decimals: 1,
                          read: { model.windSpeed },
                          write: { model.windSpeed = $0 }),
                    isEnabled: { model.airResistance }),
            // The custom ball's only free number; its diameter stays 10 cm.
            .slider(.init(id: "customMass", label: "Custom ball mass", unit: "kg",
                          range: KinematicsModel.customMassRange, decimals: 2,
                          read: { model.customMass },
                          write: { model.customMass = $0 }),
                    isEnabled: { model.kind == .custom }),
        ]
    }

    /// Within this of a world's g, the slider settles on it exactly: the
    /// hand can find Earth on a 0–30 track without a fine-tune.
    nonisolated static let gravityDetentWidth = 0.2

    nonisolated static func gravityDetent(_ g: Double) -> Double {
        KinematicsModel.gravityPresets
            .first { abs($0.gravity - g) <= gravityDetentWidth }?.gravity ?? g
    }

    /// "9.81 m/s² · Earth" on a world, the number alone between them.
    nonisolated static func gravityReadout(_ g: Double) -> String {
        let value = PhysicsFormat.measurement(g, "m/s²", decimals: 2)
        guard let world = KinematicsModel.gravityPresets
            .first(where: { abs($0.gravity - g) < 1e-9 }) else { return value }
        return value + " · " + world.name
    }

    /// The numbers the room does not already draw: what is being thrown,
    /// and what the last throw measured. Angle and speed ride the
    /// protractor; g, wind and air are More's own controls.
    static func readings(appModel: AppModel) -> [Reading] {
        let model = appModel.kinematicsModel
        var rows: [Reading] = [
            .init("Projectile", model.kind.displayName),
            .init("Mass", PhysicsFormat.fixed(model.projectile.mass, decimals: 3), "kg"),
        ]
        if let last = model.lastFlight {
            rows.append(.init("Measured range", PhysicsFormat.fixed(last.range, decimals: 3), "m"))
            rows.append(.init("Apex height", PhysicsFormat.fixed(last.apexHeight, decimals: 3), "m"))
            rows.append(.init("Flight time", PhysicsFormat.fixed(last.flightTime, decimals: 3), "s"))
        }
        return rows
    }
}
