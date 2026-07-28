//
//  SpringsModule.swift
//  Physics Playground — Springs module
//
//  Catalog registration, window controls, and the real-world story.
//

import PhysicsCore
import SwiftUI
import simd

@MainActor
enum SpringsModule {
    static let id = "springs"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Springs",
            blurb: "Pull a block on a coiled spring — Hooke's law live, energy bars trading, a scrolling motion graph, and two coupled masses swapping energy.",
            icon: "alternatingcurrent",
            accent: DesignTokens.Palette.springsAccent,
            firstRunHint: "Pull the block along its rail and let go — the coils spread with the true extension and the ghost blocks mark the turning points you'll reach. Try Coupled ×2 and pull one block: watch its energy drain into the other and slosh back.",
            legend: legendItems,
            isPaused: { appModel.springsModel.isPaused },
            togglePause: { appModel.springsModel.isPaused.toggle() },
            makeControls: {
                AnyView(
                    SpringsControlsView()
                        .environment(appModel.springsModel)
                )
            },
            makeScene: {
                AnyView(
                    SpringsSpaceView()
                        .environment(appModel.springsModel)
                )
            },
            captureReadings: { readings(appModel: appModel) },
            reset: {
                appModel.springsModel.reset()
            }
        )
    }

    /// The readings this bench writes into the lab notebook.
    /// Shared with the combined module that now hosts it.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
        let model = appModel.springsModel
        let energies = model.energies()
        var rows: [NotebookEntry.Reading] = [
            .init("Mode", model.mode == .single ? "single" : "coupled ×2"),
            .init("Stiffness k", String(format: "%.2f", model.stiffness), "N/m"),
            .init("Mass", String(format: "%.3f", model.mass), "kg"),
            .init("Damping", String(format: "%.3f", model.effectiveDamping), "N·s/m"),
            .init("Period 2π√(m/k)", String(format: "%.4f", model.period), "s"),
            .init("Frequency", String(format: "%.4f", model.frequency), "Hz"),
        ]
        if model.mode == .single {
            rows.append(.init("Displacement",
                              String(format: "%.4f", model.state.displacement), "m"))
            rows.append(.init("Velocity",
                              String(format: "%.4f", model.state.velocity), "m/s"))
            rows.append(.init("Spring force",
                              String(format: "%.4f", model.springForce), "N"))
            rows.append(.init("Kinetic energy", String(format: "%.5f", energies.kinetic), "J"))
            rows.append(.init("Potential energy", String(format: "%.5f", energies.potential), "J"))
        } else {
            let pair = model.coupled.massEnergies(
                stiffness: model.stiffness, coupling: model.coupling,
                masses: SIMD2(model.mass, model.mass))
            rows.append(.init("Coupling", String(format: "%.2f", model.coupling), "N/m"))
            rows.append(.init("Energy, block 1", String(format: "%.5f", pair.x), "J"))
            rows.append(.init("Energy, block 2", String(format: "%.5f", pair.y), "J"))
        }
        return rows
    }

    static let legendItems: [LegendItem] = [
        LegendItem(swatch: .fill(DesignTokens.Palette.forceVector),
                   text: "Red arrow — spring force F = −kx, always pulling toward rest"),
        LegendItem(swatch: .fill(Color(red: 0.2, green: 0.8, blue: 0.35)),
                   text: "Green bar — potential energy ½kx²"),
        LegendItem(swatch: .fill(DesignTokens.Palette.velocityVector),
                   text: "Blue arrow & bar — velocity and kinetic energy; the white bar is their constant total"),
        LegendItem(swatch: .fill(Color(red: 0.4, green: 0.85, blue: 1)),
                   text: "The floating graph scrolls the motion — walk around it, pause time, inspect any moment"),
        LegendItem(swatch: .fill(.white),
                   text: "Ghost blocks while pulling — the exact turning points a release right now would reach"),
    ]

}

/// Window panel: geometry parameters.
struct SpringsControlsView: View {
    @Environment(SpringsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Apparatus") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rest length: \(model.restLength, specifier: "%.2f") m")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.restLength, in: SpringsModel.restLengthRange)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max pull: \(model.maxExtension, specifier: "%.2f") m")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.maxExtension, in: SpringsModel.extensionRange)
                }
                if model.mode == .coupled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coupling spring: \(model.coupling, specifier: "%.0f") N/m")
                            .font(DesignTokens.TypeScale.control.monospacedDigit())
                        Slider(value: $model.coupling, in: 1...40)
                    }
                    Text("Softer coupling makes the energy hand-off slower — the beat period is 2π divided by the two normal-mode frequencies' difference.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !model.insightText.isEmpty {
                Text(model.insightText)
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
