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
            // `addRing` now has no caller outside tests, so the
            // score was structurally always 0 — a column of zeroes
            // in every exported notebook, implying a game that
            // isn't there. The ring machinery stays in the model,
            // dormant and tested, for whenever hoops come back.
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
