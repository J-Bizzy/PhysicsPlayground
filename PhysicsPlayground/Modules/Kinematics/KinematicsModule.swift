//
//  KinematicsModule.swift
//  Physics Playground — Kinematics module
//
//  Catalog registration for projectile motion: descriptor, legend, and
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
            firstRunHint: "Grab any ball and throw it — physics takes over the instant you let go. For precise launches, drag the launcher anywhere and pinch its orange bead to aim.",
            legend: legend,
            isPaused: { appModel.kinematicsModel.isPaused },
            togglePause: { appModel.kinematicsModel.isPaused.toggle() },
            makeScene: {
                AnyView(KinematicsSpaceView().environment(appModel.kinematicsModel))
            },
            captureReadings: { readings(appModel: appModel) },
            reset: { appModel.kinematicsModel.reset() }
        )
    }

    /// The readings this bench writes into the lab notebook.
    /// Shared with the world that now hosts it.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
            let model = appModel.kinematicsModel
            var rows: [NotebookEntry.Reading] = [
                .init("Projectile", model.kind.rawValue),
                .init("Mass", String(format: "%.3f", model.projectile.mass), "kg"),
                .init("Gravity", String(format: "%.2f", model.gravity), "m/s²"),
                .init("Launch speed", String(format: "%.2f", model.launchSpeed), "m/s"),
                .init("Elevation", String(format: "%.1f", model.elevationDegrees), "°"),
                .init("Air resistance", model.airResistance ? "on" : "off"),
            ]
            if let last = model.lastFlight {
                rows.append(.init("Measured range", String(format: "%.3f", last.range), "m"))
                rows.append(.init("Apex height", String(format: "%.3f", last.apexHeight), "m"))
                rows.append(.init("Flight time", String(format: "%.3f", last.flightTime), "s"))
                rows.append(.init("Launched by", last.wasThrown ? "hand" : "launcher"))
            }
            // No Score row. Hoops left the surface in 6b2508c and
            // `addRing` has no caller outside tests, so the score was
            // structurally always 0 — a column of zeroes in every
            // exported notebook, implying a game that isn't there.
            //
            // CLASSIFIED, since the project's rule is that every
            // caller-less thing must say which it is: this is a
            // MOTHBALL, and it is the third category. Not a missing
            // door (the surface existed and worked), not a grave (the
            // code was not decided against — the SURFACE was, because
            // hoops read as clutter around a bench about trajectories).
            // Model, renderer, scoring and tests are all intact and
            // exercised; only the way to make one is gone. Restoring it
            // is one call from a Bloom petal on the launcher, and that
            // is a decision for the owner, not a cleanup.
            return rows
    }

    /// The bench's full legend. The world curates a shorter key
    /// from this and the pendulum rig's.
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
