//
//  KinematicsControlsView.swift
//  Physics Playground — Kinematics module
//
//  The kinematics control panel content: launch & throw, environment
//  (gravity, air, wind), projectile choice (including a fully custom
//  ball), time control, hoops, and the live flight numbers. The shell
//  adds the hint, legend, and real-world button around it.
//

import PhysicsCore
import SwiftUI

struct KinematicsControlsView: View {
    @Environment(KinematicsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Launch & throw") {
                labeledSlider(
                    "Speed", value: $model.launchSpeed,
                    range: KinematicsModel.speedRange, format: "%.1f m/s"
                )
                labeledSlider(
                    "Angle", value: $model.elevationDegrees,
                    range: KinematicsModel.elevationRangeDegrees, format: "%.0f°"
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
                    .accessibilityHint("Launches a ball from the launcher")

                    Button {
                        model.spawnBall()
                    } label: {
                        Label("New ball", systemImage: "circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("A ball appears in the room — grab and throw it")

                    Button(role: .destructive) {
                        model.clearFlights()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.flights.isEmpty)
                    .accessibilityLabel("Clear all balls")
                }

                labeledSlider(
                    "Throw boost", value: $model.throwBoost,
                    range: KinematicsModel.throwBoostRange, format: "×%.1f"
                )
                if model.throwBoost > 1.01 {
                    Text("Boost multiplies your real hand speed — ×1 is an honest throw.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            PanelSection("Environment") {
                HStack(spacing: DesignTokens.Panel.rowSpacing) {
                    ForEach(KinematicsModel.gravityPresets, id: \.name) { preset in
                        Button(preset.name) {
                            model.gravity = preset.value
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Set gravity to \(preset.name): \(preset.value, specifier: "%.2f") meters per second squared")
                    }
                }
                labeledSlider(
                    "Gravity", value: $model.gravity,
                    range: KinematicsModel.gravityRange, format: "%.2f m/s²"
                )

                Toggle("Air resistance", isOn: $model.airResistance)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("Quadratic drag — compare how much each ball cares")

                labeledSlider(
                    "Wind", value: $model.windSpeed,
                    range: KinematicsModel.windSpeedRange, format: "%.1f m/s"
                )
                .disabled(!model.airResistance)
                labeledSlider(
                    "Wind heading", value: $model.windDirectionDegrees,
                    range: -180...180, format: "%.0f°"
                )
                .disabled(!model.airResistance || model.windSpeed == 0)
                if !model.airResistance, model.windSpeed > 0 {
                    Text("Wind only pushes through the air — turn air resistance on to feel it.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            PanelSection("Projectile") {
                Picker("Projectile", selection: $model.kind) {
                    ForEach(KinematicsModel.ProjectileKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .font(DesignTokens.TypeScale.control)
                .accessibilityLabel("Projectile type")

                if model.kind == .custom {
                    labeledSlider(
                        "Mass", value: $model.customMass,
                        range: KinematicsModel.customMassRange, format: "%.3f kg"
                    )
                    labeledSlider(
                        "Diameter", value: $model.customDiameter,
                        range: KinematicsModel.customDiameterRange, format: "%.2f m"
                    )
                }

                Text(specLine)
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            PanelSection("Time & hoops") {
                HStack(spacing: DesignTokens.Panel.rowSpacing) {
                    Button {
                        model.isPaused.toggle()
                    } label: {
                        Label(model.isPaused ? "Resume" : "Pause",
                              systemImage: model.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Freezes every ball mid-air so you can walk around them")
                }
                labeledSlider(
                    "Slow motion", value: $model.timeScale,
                    range: KinematicsModel.timeScaleRange, format: "×%.1f"
                )

                HStack(spacing: DesignTokens.Panel.rowSpacing) {
                    Button {
                        model.addRing()
                    } label: {
                        Label("Add hoop", systemImage: "circle.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.rings.count >= KinematicsModel.ringBudget)
                    .accessibilityHint("A hoop appears in the room — drag it anywhere; balls passing down through it score")

                    Button(role: .destructive) {
                        model.removeLastRing()
                    } label: {
                        Label("Remove", systemImage: "circle.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.rings.isEmpty)
                    .accessibilityLabel("Remove last hoop")
                }
                if !model.rings.isEmpty {
                    Text("Score: \(model.totalScore)")
                        .font(DesignTokens.TypeScale.sectionHeader.monospacedDigit())
                        .accessibilityLabel("Total score \(model.totalScore)")
                }
            }

            PanelSection {
                KinematicsStatsView()
            }
        }
    }

    private var specLine: String {
        let p = model.projectile
        return String(
            format: "%@: %.0f g, ⌀ %.1f cm, Cd %.2f, bounce e %.2f.",
            p.name, p.mass * 1000, p.diameter * 100, p.dragCoefficient, p.restitution
        )
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
                    .accessibilityLabel("Everything is at real-world scale")
            }

            Text("Launcher prediction")
                .font(DesignTokens.TypeScale.label)
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                statRow("Range", PhysicsFormat.fixed(prediction.range) + (prediction.landed ? "" : "+"), "m")
                statRow("Peak height", PhysicsFormat.fixed(prediction.apexHeight), "m")
                statRow("Flight time", PhysicsFormat.fixed(prediction.flightTime) + (prediction.landed ? "" : "+"), "s")
                if let terminal = model.terminalSpeed, terminal > 0 {
                    statRow("Terminal speed", PhysicsFormat.fixed(terminal), "m/s")
                }
            }
            if !prediction.landed {
                Text(model.gravity == 0
                     ? "Zero-g: nothing ever lands."
                     : "This launch flies beyond the room.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            if let last = model.lastFlight {
                Divider()
                Text("Last flight — \(last.projectileName)\(last.wasThrown ? ", thrown by hand" : "")")
                    .font(DesignTokens.TypeScale.label)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    statRow("Range", PhysicsFormat.fixed(last.range), "m")
                    statRow("Peak height", PhysicsFormat.fixed(last.apexHeight), "m")
                    statRow("Flight time", PhysicsFormat.fixed(last.flightTime), "s")
                }
            }
        }
        .accessibilityElement(children: .contain)
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
