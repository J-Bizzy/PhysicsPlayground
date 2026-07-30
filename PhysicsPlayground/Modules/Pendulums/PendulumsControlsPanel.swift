//
//  PendulumsControlsPanel.swift
//  Physics Playground — Pendulums module
//
//  The module's one-glance panel — and the door to its whole reason
//  for existing: "what if this were the Moon?" The always-open card
//  makes pendulums and carries the three worlds; the full gravity
//  slider, display layers, time, and numbers wait behind collapsed
//  sections. Per-BOB editing (length bead, mass petal, delete) lives
//  on the bob itself: tap it and its ring unfolds.
//

import PhysicsCore
import SwiftUI

struct PendulumsControlsPanel: View {
    @Environment(PendulumsModel.self) private var model

    /// `PhysicsCore.SurfaceGravity` — shared with Projectiles, which had
    /// its own copy of these numbers. Real bodies only: a pendulum in
    /// zero-g does not swing, so there is no period to show.
    private static let worlds = SurfaceGravity.bodies

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Pendulums") {
                HStack(spacing: 12) {
                    Button {
                        self.model.addPendulum()
                    } label: {
                        Label("Add pendulum", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent)
                    .disabled(self.model.pendulums.count >= PendulumsModel.pendulumBudget)

                    Button("Resonance ×5") {
                        self.model.loadResonancePreset()
                    }
                    .buttonStyle(.podQuiet)
                    .accessibilityHint("Five lengths, five periods — watch them drift apart and realign")
                }

                // The worlds: one pinch and every swing stretches or
                // snaps tight — T = 2π√(L/g), felt before it is read.
                HStack(spacing: 10) {
                    ForEach(Self.worlds) { world in
                        Button {
                            self.model.gravity = world.gravity
                        } label: {
                            Text(world.name)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(abs(self.model.gravity - world.gravity) < 0.01
                                     ? AnyButtonStyle(.podProminent)
                                     : AnyButtonStyle(.podQuiet))
                        .accessibilityLabel("Gravity of \(world.name)")
                    }
                }

                Text("Tap a bob for its own controls — pull the bead to pay out cable, petals cycle its mass or delete it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("Gravity & friction") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("g = \(self.model.gravity, specifier: "%.2f") m/s²")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.gravity, in: PendulumsModel.gravityRange)
                        .accessibilityLabel("Gravity")
                }
                Toggle("Air resistance", isOn: $model.frictionOn)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("Off, the pendulum is ideal and swings forever")
                if !self.model.insightText.isEmpty {
                    Text(self.model.insightText)
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CollapsedSection("Display") {
                Picker("Trail", selection: $model.trailMode) {
                    ForEach(PendulumsModel.TrailMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Trail length")
                Toggle("Velocity arrows", isOn: $model.showVelocity)
                    .font(DesignTokens.TypeScale.control)
                Toggle("Acceleration arrows", isOn: $model.showAcceleration)
                    .font(DesignTokens.TypeScale.control)
                Toggle("Force arrows", isOn: $model.showForces)
                    .font(DesignTokens.TypeScale.control)
                Toggle("Energy bars", isOn: $model.showEnergyBars)
                    .font(DesignTokens.TypeScale.control)
            }

            CollapsedSection("Time") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time: \(self.model.timeScale, specifier: "%.2f")×")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.timeScale, in: 0.1...5.0)
                        .accessibilityLabel("Time scale")
                }
            }

            CollapsedSection("Numbers") {
                PendulumInfoCard()
                Text("The selected bob — tap one to read it here.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Type-erases a pod button style so a button can pick prominent vs
/// quiet from state (the selected world wears the filled capsule).
private struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init(_ style: some ButtonStyle) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
