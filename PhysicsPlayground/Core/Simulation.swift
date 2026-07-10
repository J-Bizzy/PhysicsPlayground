//
//  Simulation.swift
//  Physics Playground — Core kernel
//
//  The module contract that makes this a *platform*: every simulation is a
//  SimulationDescriptor — a catalog card plus two view factories, one for
//  the control window and one for the immersive scene. The hub lists the
//  catalog; picking a card swaps the active simulation. Each simulation's
//  model is created lazily by AppModel and retained, so switching sims
//  preserves their state.
//
//  Future "challenges" bolt on here as an optional field on the descriptor
//  without touching any simulation internals.
//

import SwiftUI
import Observation

@MainActor
struct SimulationDescriptor: Identifiable {
    let id: String
    let title: String
    /// One-line hook shown on the catalog card.
    let blurb: String
    /// SF Symbol for the card.
    let icon: String
    let accent: Color
    let makeControls: () -> AnyView
    let makeScene: () -> AnyView
}

@MainActor
enum SimulationCatalog {
    /// Every simulation in the playground, in display order. New modules
    /// register by adding one line here.
    static func all(appModel: AppModel) -> [SimulationDescriptor] {
        [
            ElectrostaticsSimulation.descriptor(appModel: appModel),
        ]
    }
}

/// App-wide state: which simulation is active and whether the shared
/// immersive space is on screen.
@MainActor
@Observable
final class AppModel {
    var activeSimulationID: String?
    var isImmersiveSpaceOpen = false

    var activeSimulation: SimulationDescriptor? {
        guard let activeSimulationID else { return nil }
        return SimulationCatalog.all(appModel: self).first { $0.id == activeSimulationID }
    }

    // MARK: Per-simulation models — created on first entry, retained so a
    // sim's state survives leaving and re-entering it.

    private var electrostatics: FieldModel?

    var electrostaticsModel: FieldModel {
        if let electrostatics { return electrostatics }
        let model = FieldModel()
        electrostatics = model
        return model
    }
}
