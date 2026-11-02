//
//  OrbitalMechanicsModule.swift
//  Catalog registration for the orbital mechanics lab.
//

import SwiftUI
import PhysicsCore

@MainActor
enum OrbitalMechanicsModule {
    static let id = "gravitylab"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Orbital Mechanics",
            shortTitle: "Orbits",
            icon: "sun.max.fill",
            accent: DesignTokens.Palette.gravityAccent,
            // The sky is space: the lab opens there whatever the wearer last
            // chose, and puts deep space's distant Sun away for its own.
            // The three below are the room, for a wearer who chooses it here.
            // .progressive so the Digital Crown genuinely dims the room; the 0.85 shell does the contrast work.
            immersionStyle: .progressive,
            // 0.85: the one allowed departure from the house dimming — pale Sun has no contrast on a lit wall.
            preferredDimming: 0.85,
            // Shell must stand outside the apparatus: 16 m clears Neptune at 1×; the default 3.4 m dome cuts through the rings (AtmosphereCriterionTests).
            preferredDimmingRadius: 16,
            preferredSurroundings: .deepSpace,
            drawsItsOwnSun: true,
            isPaused: { appModel.orbitalMechanicsModel.isPaused },
            togglePause: { appModel.orbitalMechanicsModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(
                    OrbitalMechanicsSpaceView()
                        .environment(appModel.orbitalMechanicsModel)
                )
            },
            // What the data card on the selected body does not already say:
            // the system, its star and its clock, and how fast the selected
            // body would have to go to leave.
            readings: {
                let model = appModel.orbitalMechanicsModel
                var rows: [Reading] = [
                    .init("Bodies", "\(model.bodies.count)"),
                    .init("Elapsed", PhysicsFormat.fixed(model.simulatedDays, decimals: 1), "days"),
                ]
                if let star = model.primaryBody {
                    // As its bead says it: "1.00 Sun", not "1.00 Suns".
                    rows.append(.init("Star mass",
                                      PhysicsFormat.count(model.massInSuns(id: star.id),
                                                          singular: "Sun", plural: "Suns",
                                                          decimals: 2)))
                }
                if let body = model.selectedBody, let readout = model.readout(for: body) {
                    let r = PhysicsFormat.fixed(readout.distanceAU, decimals: 2)
                    // Newton's law of gravitation, from the star, and the
                    // speed at which the orbit's energy reaches zero.
                    rows.append(.init("Gravity from the star",
                                      PhysicsFormat.scientific(readout.forceNewtons), "N",
                                      formula: "F = GMm/r², r = \(r) AU"))
                    rows.append(.init("Escape speed",
                                      PhysicsFormat.fixed(readout.escapeSpeedKmPerS,
                                                          decimals: 3), "km/s",
                                      formula: "v = √(2G(M + m)/r)"))
                }
                return rows
            },
            // G alone: the star's mass is its own grip, on the star.
            adjustables: [
                .init(id: "gravitationalConstant", label: "G", unit: "× G",
                      range: 0.2...4.0, decimals: 2,
                      read: { appModel.orbitalMechanicsModel.gMultiplier },
                      write: { appModel.orbitalMechanicsModel.gMultiplier = $0 }),
            ],
            more: more(appModel.orbitalMechanicsModel),
            timeScrub: .init(model: appModel.orbitalMechanicsModel),
            reset: {
                appModel.orbitalMechanicsModel.reset()
            }
        )
    }

    /// What More holds for the sky: the clock, what is drawn on it, and
    /// what you can add to it.
    static func more(_ model: OrbitalMechanicsModel) -> [MoreItem] {
        [
            // At 1× an Earth year takes about two minutes: the clock decides
            // whether an orbit is watched or waited for. Negative runs it back.
            .choice(id: "clock", title: "Clock",
                    options: OrbitalMechanicsModel.timeScales.map {
                        (id: String(Int($0)), label: PhysicsFormat.multiplier($0))
                    },
                    selected: { String(Int(model.timeScale)) },
                    select: { id in
                        if let scale = Double(id) { model.timeScale = scale }
                    }),
            .toggle(id: "velocity", title: "Velocity", symbol: "arrow.right",
                    isOn: { model.showVelocityVector },
                    set: { model.showVelocityVector = $0 }),
            .toggle(id: "force", title: "Net force", symbol: "arrow.down.right",
                    isOn: { model.showForceVector },
                    set: { model.showForceVector = $0 }),
            .toggle(id: "sweep", title: "Kepler sweep", symbol: "triangle",
                    isOn: { model.keplerSweepOn },
                    set: { model.keplerSweepOn = $0 }),
            .toggle(id: "lagrange", title: "Lagrange points", symbol: "circlebadge.2",
                    isOn: { model.showLagrangePoints },
                    set: { model.showLagrangePoints = $0 }),
            .verbs(id: "worlds", title: "Add a world",
                   items: OrbitalMechanicsModel.Preset.allCases.map {
                       (id: $0.id, label: $0.displayName, symbol: "globe")
                   },
                   // Grey at the budget, where `spawn` would refuse.
                   isEnabled: { model.hasRoomForABody },
                   run: { id in
                       if let preset = OrbitalMechanicsModel.Preset(rawValue: id) {
                           model.spawn(preset)
                       }
                   }),
            // Splits a star named Sun into two, so it needs that star and
            // room for one more body; `makeBinary` refuses otherwise.
            .action(id: "binary", title: "Twin suns", symbol: "sun.max",
                    isEnabled: { model.hasSingleSun && model.hasRoomForABody },
                    run: { model.makeBinary() }),
        ]
    }

}
