//
//  GravityLabModule.swift
//  Physics Playground — Gravity Lab module
//
//  Catalog registration for the orbital mechanics lab: descriptor,
//

import SwiftUI
import PhysicsCore

@MainActor
enum GravityLabModule {
    static let id = "gravitylab"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Gravity Lab",
            blurb: "A real solar system in your room — grab planets, throw them into new orbits, and watch Newton's laws answer instantly.",
            icon: "sun.max.fill",
            accent: DesignTokens.Palette.gravityAccent,
            immersionStyle: .mixed,
            firstRunHint: "Pinch Earth and drag — the white line shows the orbit you're about to create. Release gently for an ellipse, throw hard to escape the Sun. Turn the crown to dim your room into deep space.",
            // Opens part-dimmed: a pale Sun and specks of planet have no contrast at all against a bright wall — this module is unreadable in daylight.
            preferredDimming: 0.85,
            legend: legend,
            isPaused: { appModel.gravityLabModel.isPaused },
            togglePause: { appModel.gravityLabModel.isPaused.toggle() },
            makeControls: {
                AnyView(
                    GravityLabControlsView()
                        .environment(appModel.gravityLabModel)
                )
            },
            makeScene: {
                AnyView(
                    GravityLabSpaceView()
                        .environment(appModel.gravityLabModel)
                )
            },
            captureReadings: {
                let model = appModel.gravityLabModel
                var rows: [NotebookEntry.Reading] = [
                    .init("Bodies", "\(model.bodies.count)"),
                    .init("Elapsed", String(format: "%.1f", model.simulatedDays), "days"),
                    .init("G multiplier", String(format: "%.2f", model.gMultiplier)),
                    .init("Sun mass", String(format: "%.2f", model.sunMassMultiplier), "× real"),
                ]
                if let body = model.selectedBody, let readout = model.readout(for: body) {
                    rows.append(.init("Selected", body.body.name))
                    rows.append(.init("Distance", String(format: "%.4f", readout.distanceAU), "AU"))
                    rows.append(.init("Speed", String(format: "%.3f", readout.speedKmPerS), "km/s"))
                    rows.append(.init("Escape speed",
                                      String(format: "%.3f", readout.escapeSpeedKmPerS), "km/s"))
                    rows.append(.init("Bound", readout.isBound ? "yes" : "no — unbound"))
                    if let period = readout.periodDays {
                        rows.append(.init("Period", String(format: "%.2f", period), "days"))
                    }
                }
                return rows
            },
            reset: {
                appModel.gravityLabModel.reset()
            }
        )
    }

    private static let legend: [LegendItem] = [
        LegendItem(
            swatch: .fill(DesignTokens.Palette.sunColor),
            text: "The Sun — real solar mass; grab and drag it and every orbit follows"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.gravityAccent),
            text: "Planets with real masses and real orbits (sizes exaggerated — to scale they'd be invisible)"
        ),
        LegendItem(
            swatch: .line(DesignTokens.Palette.predictedArc),
            text: "While holding a body: the orbit it gets if you release right now"
        ),
        LegendItem(
            swatch: .symbol("arrow.up.right", DesignTokens.Palette.velocityVector),
            text: "Vectors on the selected body: blue velocity, orange acceleration, red force toward the Sun (lengths log-scaled)"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.target),
            text: "Lagrange markers (L1–L5) — drop the satellite on one and see which points actually hold it"
        ),
        LegendItem(
            swatch: .symbol("clock", .secondary),
            text: "1 second = 3 simulated days at 1× — an Earth year in about two minutes"
        ),
    ]
}
