//
//  GravityLabModule.swift
//  Catalog registration for the orbital mechanics lab.
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
            shortTitle: "Gravity",
            blurb: "A real solar system in your room — grab planets, throw them into new orbits, and watch Newton's laws answer instantly.",
            icon: "sun.max.fill",
            accent: DesignTokens.Palette.gravityAccent,
            // .progressive so the Digital Crown genuinely dims the room; the 0.85 shell does the contrast work.
            immersionStyle: .progressive,
            firstRunHint: "Tap a planet: its orbit appears as a ring with a bead at each end. Pull a bead and the orbit reshapes under your hand — out to stretch it, sideways to swing it round the Sun, up to tilt it out of the plane. Distant orbits are drawn but out of arm's reach; pinch with both hands to bring them in. visionOS will ask to use your room so the orrery can stand in it.",
            // 0.85: the one allowed departure from the house dimming — pale Sun has no contrast on a lit wall.
            preferredDimming: 0.85,
            // Shell must stand outside the apparatus: 16 m clears Neptune at 1×; the default 3.4 m dome cuts through the rings (AtmosphereCriterionTests).
            preferredDimmingRadius: 16,
            legend: legend,
            isPaused: { appModel.gravityLabModel.isPaused },
            togglePause: { appModel.gravityLabModel.togglePauseRespectingScrub() },
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
                    .init("Elapsed", PhysicsFormat.fixed(model.simulatedDays, decimals: 1), "days"),
                    .init("G multiplier", PhysicsFormat.fixed(model.gMultiplier, decimals: 2)),
                    .init("Sun mass", PhysicsFormat.fixed(model.sunMassMultiplier, decimals: 2), "× real"),
                ]
                if let body = model.selectedBody, let readout = model.readout(for: body) {
                    rows.append(.init("Selected", body.body.name))
                    if let elements = model.orbitElements(for: body.id) {
                        if let a = elements.semiMajorAxis {
                            rows.append(.init(
                                "Semi-major axis",
                                PhysicsFormat.fixed(a / CelestialBody.astronomicalUnit,
                                                    decimals: 3),
                                "AU"))
                        }
                        rows.append(.init("Eccentricity",
                                          PhysicsFormat.fixed(elements.eccentricity,
                                                              decimals: 3)))
                        rows.append(.init("Inclination",
                                          PhysicsFormat.angle(elements.inclination * 180 / .pi)))
                    }
                    rows.append(.init("Total energy",
                                      PhysicsFormat.scientific(readout.totalEnergy), "J"))
                    rows.append(.init("Distance", PhysicsFormat.fixed(readout.distanceAU, decimals: 3), "AU"))
                    rows.append(.init("Speed", PhysicsFormat.fixed(readout.speedKmPerS, decimals: 3), "km/s"))
                    rows.append(.init("Escape speed",
                                      PhysicsFormat.fixed(readout.escapeSpeedKmPerS,
                                                          decimals: 3), "km/s"))
                    rows.append(.init("Bound", PhysicsFormat.state(readout.isBound)))
                    if let period = readout.periodDays {
                        rows.append(.init("Period", PhysicsFormat.fixed(period, decimals: 2), "days"))
                    }
                }
                return rows
            },
            timeScrub: .init(model: appModel.gravityLabModel),
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
            swatch: .line(DesignTokens.Palette.gravityAccent),
            text: "The selected body's orbit ring: the two-body ellipse it is on RIGHT NOW — the path it would take if nothing else pulled on it. The trail beside it is what actually happens; the gap between them is Jupiter's pull, and it is real. Grab a bead at either end to reshape the orbit."
        ),
        LegendItem(
            swatch: .symbol("exclamationmark.circle", DesignTokens.Palette.gravityAccent),
            text: "The precession you can watch here is NEWTONIAN — the other planets tugging. Mercury's famous extra 43 arcseconds per century needs general relativity, which this lab does not model."
        ),
        LegendItem(
            swatch: .symbol("arrow.counterclockwise", DesignTokens.Palette.gravityAccent),
            text: "The clock runs backwards. Verlet integration is time-symmetric, so reverse is the real physics run the other way, not a replay — perturb an orbit and rewind it and it un-perturbs. Merges are the exception: combining two bodies destroys the information needed to separate them again."
        ),
        LegendItem(
            swatch: .symbol("circlebadge.2", DesignTokens.Palette.gravityAccent),
            text: "Lagrange points, for the planet you last tapped: L1–L3 solved as real roots of the rotating frame, L4/L5 exactly equilateral. Release a body onto one and it matches the rotating frame — L4 and L5 hold (that is where Jupiter's Trojans are), L1–L3 shed their occupants within days."
        ),
        LegendItem(
            swatch: .symbol("arrow.up.right", DesignTokens.Palette.velocityVector),
            text: "Vectors on the selected body: blue velocity, orange acceleration, red force toward the Sun (lengths log-scaled)"
        ),
        LegendItem(
            swatch: .line(DesignTokens.Palette.gravityAccent),
            text: "Spacetime grid — an analogy, not a measurement: the dips are drawn to look right, not solved. Every other number here is real"
        ),
        LegendItem(
            swatch: .symbol("clock", .secondary),
            text: "1 second = 3 simulated days at 1× — an Earth year in about two minutes"
        ),
    ]
}
