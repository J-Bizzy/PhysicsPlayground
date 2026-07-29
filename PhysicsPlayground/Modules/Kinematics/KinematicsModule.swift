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
            blurb: "Throw real balls across your room — slow time, hang hoops in mid-air, and try every gravity from zero-g to Jupiter.",
            icon: "paperplane.fill",
            accent: DesignTokens.Palette.kinematicsAccent,
            firstRunHint: "Grab any ball and throw it — physics takes over the instant you let go. For precise launches, drag the launcher anywhere and pinch its orange bead to aim.",
            legend: legend,
            isPaused: { appModel.kinematicsModel.isPaused },
            togglePause: { appModel.kinematicsModel.isPaused.toggle() },
            makeScene: {
                AnyView(
                    KinematicsSpaceView()
                        .environment(appModel.kinematicsModel)
                )
            },
            captureReadings: {
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
                rows.append(.init("Score", "\(model.totalScore)"))
                return rows
            },
            reset: {
                appModel.kinematicsModel.reset()
            }
        )
    }

    private static let legend: [LegendItem] = [
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
            text: "Strobe dots — one per 1/15 s of simulated time, so wider spacing means faster (honest even in slow motion)"
        ),
        LegendItem(
            swatch: .stroke(DesignTokens.Palette.target),
            text: "Hoop — anything passing down through it scores; the dark disc under each ball marks the spot below it"
        ),
    ]
}
