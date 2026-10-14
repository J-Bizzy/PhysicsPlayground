//
//  KinematicsModule.swift
//  Physics Playground — Kinematics: catalog registration — descriptor, legend, notebook readings.
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
            legend: legend,
            isPaused: { appModel.kinematicsModel.isPaused },
            // Through the capsule: un-pausing from a scrubbed instant resumes from it.
            togglePause: { appModel.kinematicsModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(KinematicsSpaceView().environment(appModel.kinematicsModel))
            },
            captureReadings: { readings(appModel: appModel) },
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

    /// The readings this bench writes into the lab notebook.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
            let model = appModel.kinematicsModel
            var rows: [NotebookEntry.Reading] = [
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
            // A bench with hoops on it writes its score.
            if !model.rings.isEmpty {
                rows.append(.init("Hoops", "\(model.rings.count)"))
                rows.append(.init("Score", "\(model.totalScore)"))
                rows.append(.init("Best streak", "\(model.bestStreak)"))
            }
            return rows
    }

    /// The bench's full legend.
    static let legend: [LegendItem] = [
        LegendItem(
            swatch: .fill(DesignTokens.Palette.projectile),
            text: "Balls at their real sizes — grab and throw any of them, anywhere"
        ),
        LegendItem(
            swatch: .stroke(DesignTokens.Palette.kinematicsAccent),
            text: "Aim bead — pinch and drag to point the launcher; grab the launcher body to move it"
        ),
        LegendItem(
            swatch: .line(DesignTokens.Palette.predictedArc),
            text: "Predicted arc from the launcher, bounces included"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.projectile),
            text: "Strobe dots — one per 1/15 s of simulated time, so wider spacing means faster"
        ),
    ]
}
