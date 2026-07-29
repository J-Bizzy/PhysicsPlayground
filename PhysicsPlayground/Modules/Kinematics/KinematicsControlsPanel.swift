//
//  KinematicsControlsPanel.swift
//  Physics Playground — Kinematics module
//
//  The module's one-glance panel, kept deliberately SHORT: fire and
//  play up top, then just two sections — the world and the hoops.
//  A first pass shipped five sections (projectile picker with a custom
//  ball, throw boost, wind direction, a separate Time card); the owner
//  called it what it was — submenus populating the background. What
//  remains is what a person actually reaches for: throw things, change
//  the world, hang targets, slow time.
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
                        Text("Wind: \(self.model.windSpeed, specifier: "%.1f") m/s")
                            .font(DesignTokens.TypeScale.control.monospacedDigit())
                        Slider(value: $model.windSpeed, in: KinematicsModel.windSpeedRange)
                            .accessibilityLabel("Wind speed")
                    }
                    Picker("Ball", selection: $model.kind) {
                        ForEach(KinematicsModel.ProjectileKind.allCases.filter { $0 != .custom }) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Projectile kind")
                    .accessibilityHint("Drag treats a golf ball and a table-tennis ball very differently")
                }
                Toggle("Bounce off my walls", isOn: $model.respectRoomWalls)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("Balls strike the room's real walls and ceiling — device only")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time: \(self.model.timeScale, specifier: "%.1f")×")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.timeScale, in: KinematicsModel.timeScaleRange)
                        .accessibilityLabel("Time scale")
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
        }
    }
}
