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
            // .progressive so the Digital Crown genuinely dims the room; the 0.85 shell does the contrast work.
            immersionStyle: .progressive,
            // 0.85: the one allowed departure from the house dimming — pale Sun has no contrast on a lit wall.
            preferredDimming: 0.85,
            // Shell must stand outside the apparatus: 16 m clears Neptune at 1×; the default 3.4 m dome cuts through the rings (AtmosphereCriterionTests).
            preferredDimmingRadius: 16,
            isPaused: { appModel.orbitalMechanicsModel.isPaused },
            togglePause: { appModel.orbitalMechanicsModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(
                    OrbitalMechanicsSpaceView()
                        .environment(appModel.orbitalMechanicsModel)
                )
            },
            readings: {
                let model = appModel.orbitalMechanicsModel
                var rows: [Reading] = [
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
                    // The data card's own word for it: a fate, not a switch.
                    rows.append(.init("Orbit", readout.isBound ? "bound" : "leaving"))
                    if let period = readout.periodDays {
                        rows.append(.init("Period", PhysicsFormat.fixed(period, decimals: 2), "days"))
                    }
                }
                return rows
            },
            adjustables: [
                .init(id: "gravitationalConstant", label: "G", unit: "× G",
                      range: 0.2...4.0, decimals: 2,
                      read: { appModel.orbitalMechanicsModel.gMultiplier },
                      write: { appModel.orbitalMechanicsModel.gMultiplier = $0 }),
                .init(id: "sunMass", label: "Star mass", unit: "× Sun",
                      range: OrbitalMechanicsModel.primaryMassRangeSuns, decimals: 2,
                      read: { appModel.orbitalMechanicsModel.sunMassMultiplier },
                      write: { appModel.orbitalMechanicsModel.sunMassMultiplier = $0 }),
            ],
            timeScrub: .init(model: appModel.orbitalMechanicsModel),
            reset: {
                appModel.orbitalMechanicsModel.reset()
            }
        )
    }

}
