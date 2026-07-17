//
//  SpringsModule.swift
//  Physics Playground — Springs module
//
//  Catalog registration, window controls, and the real-world story.
//

import PhysicsCore
import SwiftUI

@MainActor
enum SpringsModule {
    static let id = "springs"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Springs",
            blurb: "Pull a block on a coiled spring — Hooke's law live, energy bars trading, a scrolling motion graph, and two coupled masses swapping energy.",
            icon: "alternatingcurrent",
            accent: .teal,
            firstRunHint: "Pull the block along its rail and let go — the coils spread with the true extension and the ghost blocks mark the turning points you'll reach. Try Coupled ×2 and pull one block: watch its energy drain into the other and slosh back.",
            legend: legend,
            realWorld: story,
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
            reset: {
                appModel.springsModel.reset()
            }
        )
    }

    private static let legend: [LegendItem] = [
        LegendItem(swatch: .fill(Color(red: 0.2, green: 0.8, blue: 0.35)),
                   text: "Green arrow & bar — spring force F = −kx and potential energy ½kx²"),
        LegendItem(swatch: .fill(Color(red: 0.25, green: 0.5, blue: 1)),
                   text: "Blue arrow & bar — velocity and kinetic energy; the white bar is their constant total"),
        LegendItem(swatch: .fill(Color(red: 0.4, green: 0.85, blue: 1)),
                   text: "The floating graph scrolls the motion — walk around it, pause time, inspect any moment"),
        LegendItem(swatch: .fill(.white),
                   text: "Ghost blocks while pulling — the exact turning points a release right now would reach"),
    ]

    private static let story = RealWorldStory(
        tagline: "Almost everything that vibrates is secretly a mass on a spring.",
        applications: [
            .init(title: "Car suspension", icon: "car.fill",
                  body: "A spring supports each wheel and a damper drains the bounce — exactly your damping slider. Blown dampers make a car float and wallow; stiff ones make it skate."),
            .init(title: "Quartz watches", icon: "clock.fill",
                  body: "The quartz tuning fork inside a watch is a microscopic spring oscillating 32,768 times a second; its T = 2π√(m/k) steadiness is why watches keep time."),
            .init(title: "Earthquake engineering", icon: "building.columns.fill",
                  body: "Buildings are giant masses on springy frames. Engineers tune stiffness so the building's natural frequency avoids the ground's shaking frequencies — resonance is the enemy."),
            .init(title: "Molecular bonds", icon: "atom",
                  body: "Chemical bonds behave like tiny springs between atoms; infrared spectroscopy reads their vibration frequencies to identify molecules — coupled oscillators at nanometer scale."),
        ])
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
