//
//  ElectrostaticsSimulation.swift
//  Physics Playground — Electrostatics module
//
//  Catalog registration for the electrostatics sandbox (the original
//  Field Playground experience).
//

import SwiftUI

@MainActor
enum ElectrostaticsSimulation {
    static let id = "electrostatics"

    static func descriptor(appModel: AppModel) -> SimulationDescriptor {
        SimulationDescriptor(
            id: id,
            title: "Electric Fields",
            blurb: "Place charges, trace field lines and equipotential shells, and ride a test charge through Coulomb's law.",
            icon: "bolt.fill",
            accent: .yellow,
            makeControls: {
                AnyView(
                    ElectrostaticsControlsView()
                        .environment(appModel.electrostaticsModel)
                )
            },
            makeScene: {
                AnyView(
                    FieldSpaceView()
                        .environment(appModel.electrostaticsModel)
                )
            }
        )
    }
}
