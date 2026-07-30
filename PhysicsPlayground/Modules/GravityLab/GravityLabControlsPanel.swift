//
//  GravityLabControlsPanel.swift
//  Physics Playground — Gravity Lab module
//
//  The module's one-glance panel. The always-open card makes worlds —
//  presets, a custom body, and the twin-suns split — and shows the
//  clock; time, prediction, the star itself, and the display layers
//  wait behind collapsed sections. Per-BODY editing (mass bead,
//  delete) lives on the body: tap a planet and its ring unfolds.
//

import SwiftUI

struct GravityLabControlsPanel: View {
    @Environment(GravityLabModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Worlds") {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(GravityLabModel.Preset.allCases) { preset in
                            Button(preset.displayName) {
                                self.model.spawn(preset)
                            }
                        }
                    } label: {
                        Label("Add world", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent)
                    .accessibilityLabel("Add a preset world")

                    Button("Twin suns") {
                        self.model.makeBinary()
                    }
                    .buttonStyle(.podQuiet)
                    .accessibilityHint("Splits the star into a binary pair — every orbit reshapes")
                }

                Text(clockText)
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("Pull a new world from the well and let it fall — or tap a planet for its own controls: pull the bead for mass, the petal deletes it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("Time") {
                HStack(spacing: 14) {
                    Button {
                        self.model.isPaused.toggle()
                    } label: {
                        Image(systemName: self.model.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.podQuiet)
                    .accessibilityLabel(self.model.isPaused ? "Resume time" : "Pause time")

                    // The speed picker is a standing bank of labelled discs
                    // beside the system now — tap one (DECISIONS.md,
                    // 2026-07-29). It stays visible rather than folding,
                    // because which speed you are running is itself a thing
                    // worth reading: at 1× an Earth year takes two minutes.
                    Text("Clock: \(Int(self.model.timeScale))× — tap a disc on the bank beside the system.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("1× is three simulated days per second.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            CollapsedSection("Prediction") {
                Button {
                    self.model.armPrediction()
                } label: {
                    Label("Predict an orbit", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.podQuiet)
                .disabled(self.model.selectedBody == nil
                          || self.model.selectedBody?.id == self.model.primaryBody?.id)
                Text("Arms a ghost at the selected planet: drag the ghost, and the white line shows the orbit that release would create — then time answers.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("The star") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sun mass: \(self.model.sunMassMultiplier, specifier: "%.1f")×")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.sunMassMultiplier, in: 0.2...4.0)
                        .accessibilityLabel("Sun mass multiplier")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("G: \(self.model.gMultiplier, specifier: "%.1f")×")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.gMultiplier, in: 0.2...4.0)
                        .accessibilityLabel("Gravitational constant multiplier")
                }
                Text("Heavier star, faster orbits: v = √(GM/r) live.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            CollapsedSection("Display") {
                Toggle("Field particles", isOn: $model.showFieldParticles)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("A flow of motes falling along the true field")
                Toggle("Spacetime grid", isOn: $model.showSpacetimeGrid)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("The rubber-sheet picture underfoot — depths are conceptual, not to scale")
                Toggle("Kepler sweep", isOn: $model.keplerSweepOn)
                    .font(DesignTokens.TypeScale.control)
                // The trail-length picker is deleted, not relocated. Three
                // lengths of ribbon is a display preference, not physics,
                // and the law's third clause refuses controls that are
                // neither an extent nor a real choice (DECISIONS.md,
                // 2026-07-29). Medium is the length that reads an ellipse
                // without smearing a fast inner orbit into a band;
                // `trailLength` stays on the model at that default, so a
                // future spatial control has something to set.
                Toggle("Velocity vectors", isOn: $model.showVelocityVector)
                    .font(DesignTokens.TypeScale.control)
                Toggle("Force vectors", isOn: $model.showForceVector)
                    .font(DesignTokens.TypeScale.control)
            }
        }
    }

    private var clockText: String {
        let days = model.simulatedDays
        let clock = days < 400
            ? String(format: "%.0f simulated days", days)
            : String(format: "%.2f simulated years", days / 365.25)
        return "\(model.bodies.count) bodies · \(clock)"
    }
}
