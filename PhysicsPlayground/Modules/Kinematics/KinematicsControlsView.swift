//
//  KinematicsControlsView.swift
//  Physics Playground — Kinematics module
//
//  The kinematics control panel content: launch controls, environment
//  (gravity, air, projectile), and the live flight numbers. The shell adds
//  the hint, legend, and real-world button around it.
//

import PhysicsCore
import SwiftUI

struct KinematicsControlsView: View {
    @Environment(KinematicsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Launch") {
                labeledSlider(
                    "Speed",
                    value: $model.launchSpeed,
                    range: KinematicsModel.speedRange,
                    format: "%.1f m/s"
                )
                labeledSlider(
                    "Angle",
                    value: $model.elevationDegrees,
                    range: KinematicsModel.elevationRangeDegrees,
                    format: "%.0f° above horizontal"
                )

                HStack(spacing: DesignTokens.Panel.rowSpacing) {
                    Button {
                        model.fire()
                    } label: {
                        Label("Fire", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.Palette.kinematicsAccent)
                    .accessibilityHint("Launches a projectile with the current aim and speed")

                    Button(role: .destructive) {
                        model.clearFlights()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.flights.isEmpty)
                    .accessibilityLabel("Clear all projectiles")
                }
            }

            PanelSection("Environment") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: DesignTokens.Panel.rowSpacing) {
                        ForEach(KinematicsModel.gravityPresets, id: \.name) { preset in
                            Button("\(preset.name)") {
                                model.gravity = preset.value
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Set gravity to \(preset.name)'s, \(preset.value, specifier: "%.2f") meters per second squared")
                        }
                    }
                    labeledSlider(
                        "Gravity",
                        value: $model.gravity,
                        range: KinematicsModel.gravityRange,
                        format: "%.2f m/s²"
                    )
                }

                Toggle("Air resistance", isOn: $model.airResistance)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("Quadratic drag — compare how much each projectile cares")

                Picker("Projectile", selection: $model.kind) {
                    ForEach(KinematicsModel.ProjectileKind.allCases) { kind in
                        Text(kind.projectile.name).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .font(DesignTokens.TypeScale.control)
                .accessibilityLabel("Projectile type")
            }

            PanelSection {
                KinematicsStatsView()
            }
        }
    }

    private func labeledSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label): \(String(format: format, value.wrappedValue))")
                .font(DesignTokens.TypeScale.control.monospacedDigit())
            Slider(value: value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue(String(format: format, value.wrappedValue))
        }
    }
}

// MARK: - Live flight numbers

struct KinematicsStatsView: View {
    @Environment(KinematicsModel.self) private var model

    var body: some View {
        let prediction = model.prediction

        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            HStack {
                Text("Flight numbers")
                    .font(DesignTokens.TypeScale.sectionHeader)
                Spacer()
                Text("real scale")
                    .font(.caption.smallCaps())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Values shown at real-world scale")
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                statRow("Range", PhysicsFormat.fixed(prediction.range) + (prediction.landed ? "" : "+"), "m")
                statRow("Peak height", PhysicsFormat.fixed(prediction.apexHeight), "m")
                statRow("Flight time", PhysicsFormat.fixed(prediction.flightTime) + (prediction.landed ? "" : "+"), "s")
                if let terminal = model.terminalSpeed {
                    statRow("Terminal speed", PhysicsFormat.fixed(terminal), "m/s")
                }
            }

            if !prediction.landed {
                Text("This throw sails off the table — try less speed or more gravity.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            if let last = model.lastFlight {
                Divider()
                Text("Last flight — \(last.projectileName)\(last.wentOffTable ? " (left the table)" : "")")
                    .font(DesignTokens.TypeScale.label)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    statRow("Range", PhysicsFormat.fixed(last.range), "m")
                    statRow("Peak height", PhysicsFormat.fixed(last.apexHeight), "m")
                    statRow("Flight time", PhysicsFormat.fixed(last.flightTime), "s")
                }
            }

            Text(specLine)
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    private var specLine: String {
        let p = model.kind.projectile
        let grams = p.mass * 1000
        let centimeters = p.diameter * 100
        return String(
            format: "%@: %.0f g, ⌀ %.1f cm, Cd %.2f.",
            p.name, grams, centimeters, p.dragCoefficient
        )
    }

    private func statRow(_ label: String, _ value: String, _ unit: String) -> some View {
        GridRow {
            Text(label)
                .font(DesignTokens.TypeScale.label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(DesignTokens.TypeScale.control.monospacedDigit())
                .gridColumnAlignment(.trailing)
            Text(unit)
                .font(DesignTokens.TypeScale.label)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit)")
    }
}
