//
//  PlaygroundSpaceView.swift
//  Physics Playground
//
//  The single shared immersive space. Its content is whatever the active
//  simulation's descriptor builds; `.id(sim.id)` gives each simulation its
//  own view identity so per-sim @State (like renderers) is rebuilt cleanly
//  on switch, while sim *models* live on in AppModel.
//

import SwiftUI

struct PlaygroundSpaceView: View {
    static let spaceID = "PlaygroundSpace"

    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if let simulation = appModel.activeSimulation {
                simulation.makeScene()
                    .id(simulation.id)
            }
        }
        .onAppear { appModel.isImmersiveSpaceOpen = true }
        .onDisappear { appModel.isImmersiveSpaceOpen = false }
    }
}
