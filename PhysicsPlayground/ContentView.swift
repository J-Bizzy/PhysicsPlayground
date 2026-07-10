//
//  ContentView.swift
//  Physics Playground
//
//  The main window: the simulation catalog (hub) when nothing is active,
//  or the active simulation's control panel with shared shell chrome
//  (back button, reopen-space button). Simulations only supply their panel
//  content — the shell owns navigation and space lifecycle.
//

import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let simulation = appModel.activeSimulation {
            SimulationHostView(simulation: simulation)
        } else {
            HubView()
        }
    }
}

// MARK: - Hub (catalog)

struct HubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Physics Playground")
                        .font(.largeTitle.bold())
                    Text("Pick a simulation and it appears in your room.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(SimulationCatalog.all(appModel: appModel)) { simulation in
                        SimulationCard(simulation: simulation) {
                            enter(simulation)
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private func enter(_ simulation: SimulationDescriptor) {
        appModel.activeSimulationID = simulation.id
        Task {
            if !appModel.isImmersiveSpaceOpen {
                _ = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
            }
        }
    }
}

private struct SimulationCard: View {
    let simulation: SimulationDescriptor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: simulation.icon)
                    .font(.system(size: 34))
                    .foregroundStyle(simulation.accent)
                Text(simulation.title)
                    .font(.title3.bold())
                Text(simulation.blurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .hoverEffect()
        .accessibilityLabel("\(simulation.title). \(simulation.blurb)")
        .accessibilityHint("Opens this simulation in your room")
    }
}

// MARK: - Active simulation host

struct SimulationHostView: View {
    let simulation: SimulationDescriptor

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                // Appears only if the user closed the space (e.g. with the
                // crown) and wants the simulation back in the room.
                if !appModel.isImmersiveSpaceOpen {
                    Button {
                        Task {
                            _ = await openImmersiveSpace(id: PlaygroundSpaceView.spaceID)
                        }
                    } label: {
                        Label("Show in room", systemImage: "sparkles")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Places the simulation in your room")
                }

                simulation.makeControls()
            }
            .padding(28)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    appModel.activeSimulationID = nil
                } label: {
                    Label("All Simulations", systemImage: "chevron.left")
                }
                .accessibilityHint("Returns to the simulation catalog")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(simulation.title)
                .font(.largeTitle.bold())
        }
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview(windowStyle: .automatic) {
    MainWindowView()
        .environment(AppModel())
}
