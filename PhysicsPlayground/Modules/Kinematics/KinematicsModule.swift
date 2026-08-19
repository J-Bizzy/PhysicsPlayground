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
            blurb: "Throw real balls across your room — they ricochet off your actual walls, you can catch them out of the air, and gravity runs from zero-g to Jupiter.",
            icon: "paperplane.fill",
            accent: DesignTokens.Palette.kinematicsAccent,
            // The room clause primes the ARKit prompt, which fires as the module
            // opens (RoomSensingView.task) — exactly when this hint is on screen.
            firstRunHint: "Grab any ball and throw it — physics takes over the instant you let go. For precise launches, drag the launcher anywhere and pinch its orange bead to aim. Balls bounce off your real walls and floor, so visionOS will ask to use your room.",
            // The house dimming (Gravity Lab's 0.85 is the one exception).
            preferredDimming: 0.35,
            legend: legend,
            isPaused: { appModel.kinematicsModel.isPaused },
            // Through the capsule: un-pausing from a scrubbed instant resumes FROM it.
            togglePause: { appModel.kinematicsModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(KinematicsSpaceView().environment(appModel.kinematicsModel))
            },
            captureReadings: { readings(appModel: appModel) },
            timeScrub: .init(model: appModel.kinematicsModel),
            reset: { appModel.kinematicsModel.reset() }
        )
    }

    /// The readings this bench writes into the lab notebook.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
            let model = appModel.kinematicsModel
            var rows: [NotebookEntry.Reading] = [
                .init("Projectile", model.kind.rawValue),
                .init("Mass", PhysicsFormat.fixed(model.projectile.mass, decimals: 3), "kg"),
                .init("Gravity", PhysicsFormat.fixed(model.gravity, decimals: 2), "m/s²"),
                .init("Launch speed", PhysicsFormat.fixed(model.launchSpeed, decimals: 2), "m/s"),
                .init("Elevation", PhysicsFormat.fixed(model.elevationDegrees, decimals: 1), "°"),
                .init("Air resistance", PhysicsFormat.state(model.airResistance)),
            ]
            if let last = model.lastFlight {
                rows.append(.init("Measured range", PhysicsFormat.fixed(last.range, decimals: 3), "m"))
                rows.append(.init("Apex height", PhysicsFormat.fixed(last.apexHeight, decimals: 3), "m"))
                rows.append(.init("Flight time", PhysicsFormat.fixed(last.flightTime, decimals: 3), "s"))
                rows.append(.init("Launched by", last.wasThrown ? "hand" : "launcher"))
            }
            // No Score row: hoops are a MOTHBALL — the surface is gone, `addRing`
            // has no caller outside tests, so the score is structurally 0.
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
