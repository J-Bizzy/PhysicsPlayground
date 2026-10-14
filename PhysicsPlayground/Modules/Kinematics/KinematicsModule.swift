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
            adjustables: [
                .init(id: "gravity", label: "Gravity g", unit: "m/s²",
                      range: KinematicsModel.gravityRange, decimals: 2,
                      read: { appModel.kinematicsModel.gravity },
                      write: { appModel.kinematicsModel.gravity = $0 }),
                // Wind needs air: setting a wind switches the air on, since
                // wind through a vacuum would set a number nothing reads.
                .init(id: "wind", label: "Wind", unit: "m/s",
                      range: KinematicsModel.windSpeedRange, decimals: 1,
                      read: { appModel.kinematicsModel.windSpeed },
                      write: {
                          appModel.kinematicsModel.windSpeed = $0
                          if $0 > 0 { appModel.kinematicsModel.airResistance = true }
                      }),
            ],
            timeScrub: .init(model: appModel.kinematicsModel),
            reset: { appModel.kinematicsModel.reset() }
        )
    }

    /// The live numbers the Physics box shows.
    static func readings(appModel: AppModel) -> [Reading] {
            let model = appModel.kinematicsModel
            var rows: [Reading] = [
                .init("Projectile", model.kind.displayName),
                .init("Mass", PhysicsFormat.fixed(model.projectile.mass, decimals: 3), "kg"),
                .init("Gravity", PhysicsFormat.fixed(model.gravity, decimals: 2), "m/s²"),
                .init("Launch speed", PhysicsFormat.fixed(model.launchSpeed, decimals: 2), "m/s"),
                .init("Elevation", PhysicsFormat.angle(model.elevationDegrees, decimals: 1)),
                .init("Air resistance", PhysicsFormat.state(model.airResistance)),
            ]
            if let last = model.lastFlight {
                rows.append(.init("Measured range", PhysicsFormat.fixed(last.range, decimals: 3), "m"))
                rows.append(.init("Apex height", PhysicsFormat.fixed(last.apexHeight, decimals: 3), "m"))
                rows.append(.init("Flight time", PhysicsFormat.fixed(last.flightTime, decimals: 3), "s"))
                rows.append(.init("Launched by", last.wasThrown ? "hand" : "launcher"))
            }
            return rows
    }

}
