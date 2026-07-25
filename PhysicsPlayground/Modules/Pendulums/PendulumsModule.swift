//
//  PendulumsModule.swift
//  Physics Playground — Pendulums module
//
//  Catalog registration, window controls, and the real-world story.
//

import PhysicsCore
import SwiftUI
import simd

@MainActor
enum PendulumsModule {
    static let id = "pendulums"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Pendulums",
            blurb: "Grab a steel bob off its beam and throw it — full nonlinear swings, energy trading between bars, and five-pendulum resonance.",
            icon: "metronome.fill",
            accent: DesignTokens.Palette.pendulumsAccent,
            firstRunHint: "The bob is already swinging — grab it and throw it sideways. While you hold it, the faint line shows the swing you're about to launch. Pinch a bob to select it and read its numbers.",
            legend: legend,
            isPaused: { appModel.pendulumsModel.isPaused },
            togglePause: { appModel.pendulumsModel.isPaused.toggle() },
            makeControls: {
                AnyView(
                    PendulumsControlsView()
                        .environment(appModel.pendulumsModel)
                )
            },
            makeScene: {
                AnyView(
                    PendulumsSpaceView()
                        .environment(appModel.pendulumsModel)
                )
            },
            reset: {
                appModel.pendulumsModel.reset()
            }
        )
    }

    private static let legend: [LegendItem] = [
        LegendItem(swatch: .fill(Color(red: 0.25, green: 0.5, blue: 1)),
                   text: "Blue bar & arrow — kinetic energy and velocity; trail runs blue (slow) to orange (fast)"),
        LegendItem(swatch: .fill(Color(red: 0.2, green: 0.8, blue: 0.35)),
                   text: "Green bar — potential energy; watch the two bars trade while their sum holds"),
        LegendItem(swatch: .fill(Color(red: 0.95, green: 0.85, blue: 0.2)),
                   text: "Force arrows — purple gravity, yellow cable tension, red net force"),
        LegendItem(swatch: .line(.white),
                   text: "White ghost line while holding a bob — the exact swing a release right now would launch"),
    ]

}

/// Window panel: per-pendulum parameter sliders.
struct PendulumsControlsView: View {
    @Environment(PendulumsModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Panel.sectionSpacing) {
            if let pendulum = model.selected {
                PanelSection("Selected pendulum") {
                    slider("Length", value: pendulum.length,
                           range: PendulumsModel.lengthRange, format: "%.2f m") {
                        model.setLength(id: pendulum.id, $0)
                    }
                    slider("Mass", value: pendulum.mass,
                           range: PendulumsModel.massRange, format: "%.1f kg") {
                        model.setMass(id: pendulum.id, $0)
                    }
                    slider("Damping", value: pendulum.damping,
                           range: PendulumsModel.dampingRange, format: "%.2f N·s/m") {
                        model.setDamping(id: pendulum.id, $0)
                    }
                    slider("Bob size", value: pendulum.bobRadius,
                           range: PendulumsModel.bobRadiusRange, format: "%.3f m") {
                        model.setBobRadius(id: pendulum.id, $0)
                    }
                    slider("Cable", value: pendulum.cableThickness,
                           range: PendulumsModel.cableRange, format: "%.3f m") {
                        model.setCableThickness(id: pendulum.id, $0)
                    }
                    slider("Start angle", value: pendulum.state.angle(length: pendulum.length),
                           range: 0.05...1.4, format: "%.2f rad") {
                        model.setInitialAngle(id: pendulum.id, $0)
                    }
                    Button(role: .destructive) {
                        model.removeSelected()
                    } label: {
                        Label("Remove pendulum", systemImage: "trash")
                    }
                    .disabled(model.pendulums.count <= 1)
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

    private func slider(_ label: String, value: Double, range: ClosedRange<Double>,
                        format: String, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label): \(String(format: format, value))")
                .font(DesignTokens.TypeScale.control.monospacedDigit())
            Slider(value: Binding(get: { value }, set: onChange), in: range)
                .accessibilityLabel(label)
        }
    }
}
