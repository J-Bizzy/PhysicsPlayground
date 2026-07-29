//
//  KinematicsControlsPanel.swift
//  Physics Playground — Kinematics module
//
//  The module's one-glance panel. The always-open card fires, spawns,
//  and hangs hoops; the world (gravity, air, wind, walls), the
//  projectile, and time wait behind collapsed sections. The launcher's
//  own ring carries aim-and-speed; balls are thrown by hand.
//

import SwiftUI

struct KinematicsControlsPanel: View {
    @Environment(KinematicsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Launch & play") {
                HStack(spacing: 12) {
                    Button {
                        self.model.fire()
                    } label: {
                        Label("Fire", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent)

                    Button {
                        self.model.spawnBall()
                    } label: {
                        Label("Ball", systemImage: "circle.fill")
                    }
                    .buttonStyle(.podQuiet)
                    .accessibilityLabel("Spawn a ball to throw")

                    Button {
                        self.model.clearFlights()
                    } label: {
                        Label("Clear", systemImage: "trash.slash")
                    }
                    .buttonStyle(.podQuiet)
                    .disabled(self.model.flights.isEmpty)
                    .accessibilityLabel("Clear every ball")
                }

                if !self.model.rings.isEmpty {
                    Text("Score \(self.model.totalScore) · streak \(self.model.streak) · best \(self.model.bestStreak)")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text("Grab any ball and THROW it — release speed comes from your hand. The launcher's ring aims and fires the repeatable shot.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("World") {
                HStack(spacing: 8) {
                    ForEach(KinematicsModel.gravityPresets, id: \.name) { preset in
                        Button(preset.name) {
                            self.model.gravity = preset.value
                        }
                        .buttonStyle(.podQuiet)
                        .accessibilityLabel("Gravity of \(preset.name)")
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("g = \(self.model.gravity, specifier: "%.2f") m/s²")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.gravity, in: KinematicsModel.gravityRange)
                        .accessibilityLabel("Gravity")
                }
                Toggle("Air resistance", isOn: $model.airResistance)
                    .font(DesignTokens.TypeScale.control)
                if self.model.airResistance {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wind: \(self.model.windSpeed, specifier: "%.1f") m/s at \(self.model.windDirectionDegrees, specifier: "%.0f")°")
                            .font(DesignTokens.TypeScale.control.monospacedDigit())
                        Slider(value: $model.windSpeed, in: KinematicsModel.windSpeedRange)
                            .accessibilityLabel("Wind speed")
                        Slider(value: $model.windDirectionDegrees, in: 0...360)
                            .accessibilityLabel("Wind direction")
                    }
                }
                Toggle("Bounce off my walls", isOn: $model.respectRoomWalls)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("Balls strike the room's real walls — device only")
            }

            CollapsedSection("Projectile") {
                Picker("Ball", selection: $model.kind) {
                    ForEach(KinematicsModel.ProjectileKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Projectile kind")
                if self.model.kind == .custom {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mass: \(self.model.customMass * 1000, specifier: "%.0f") g")
                            .font(DesignTokens.TypeScale.control.monospacedDigit())
                        Slider(value: $model.customMass, in: KinematicsModel.customMassRange)
                            .accessibilityLabel("Custom mass")
                        Text("Diameter: \(self.model.customDiameter * 100, specifier: "%.0f") cm")
                            .font(DesignTokens.TypeScale.control.monospacedDigit())
                        Slider(value: $model.customDiameter, in: KinematicsModel.customDiameterRange)
                            .accessibilityLabel("Custom diameter")
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Throw boost: \(self.model.throwBoost, specifier: "%.1f")×")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.throwBoost, in: KinematicsModel.throwBoostRange)
                        .accessibilityLabel("Throw boost")
                }
            }

            CollapsedSection("Hoops") {
                HStack(spacing: 12) {
                    Button {
                        self.model.addRing()
                    } label: {
                        Label("Add hoop", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podQuiet)
                    .disabled(self.model.rings.count >= KinematicsModel.ringBudget)

                    Button {
                        self.model.removeLastRing()
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                    .buttonStyle(.podQuiet)
                    .disabled(self.model.rings.isEmpty)
                    .accessibilityLabel("Remove the last hoop")
                }
                Toggle("Hoops orbit", isOn: $model.hoopsOrbit)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("The hoops drift on slow loops — lead your shots")
            }

            CollapsedSection("Time") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time: \(self.model.timeScale, specifier: "%.1f")×")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.timeScale, in: KinematicsModel.timeScaleRange)
                        .accessibilityLabel("Time scale")
                }
                Text("Slow motion shows the strobe dots bunch at the top of the arc — equal time steps, unequal spacing.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
