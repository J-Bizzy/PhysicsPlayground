//
//  WavesControlsPanel.swift
//  Physics Playground — Waves module
//
//  The module's one-glance panel. The always-open card makes sources
//  and carries the app's best trick — listening to the field at your
//  own head. The medium (frequency, speed, time) and the display
//  layers wait behind collapsed sections; per-SOURCE editing lives on
//  the source itself: tap it and its ring unfolds.
//

import SwiftUI

struct WavesControlsPanel: View {
    @Environment(WavesModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Sources") {
                HStack(spacing: 12) {
                    Button {
                        self.model.addSource()
                    } label: {
                        Label("Add source", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent)
                    .disabled(self.model.sources.count >= WavesModel.sourceBudget)
                    .accessibilityHint("A new speaker joins the field, already ringing")

                    Text("\(self.model.sources.count) of \(WavesModel.sourceBudget)")
                        .font(DesignTokens.TypeScale.label.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Toggle("Listen to the field", isOn: $model.listenToField)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("The interference at your head, as a tone — walk into a silence surface and the sound dies")

                Text("Tap a source for its own controls — pull the bead for amplitude; petals invert its phase, send it on a Doppler flyby, or delete it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("Medium") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Frequency: \(self.model.frequency, specifier: "%.1f") Hz   λ = \(self.model.wavelength * 100, specifier: "%.0f") cm")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.frequency, in: WavesModel.frequencyRange)
                        .accessibilityLabel("Frequency")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wave speed: \(self.model.waveSpeed, specifier: "%.2f") m/s")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.waveSpeed, in: WavesModel.speedRange)
                        .accessibilityLabel("Wave speed")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time: \(self.model.timeScale, specifier: "%.1f")×")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.timeScale, in: WavesModel.timeScaleRange)
                        .accessibilityLabel("Time scale")
                }
                Text("Every crest slows together — the pattern holds while you walk through it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            CollapsedSection("Display") {
                Toggle("Silence surfaces", isOn: $model.showSilenceSurfaces)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("The 3D sheets where the waves cancel — walk between them")
                Toggle("Wavefront rings", isOn: $model.showWavefronts)
                    .font(DesignTokens.TypeScale.control)
                Toggle("Probe follows my gaze", isOn: $model.lookProbe)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("The probe reads the field wherever your head is facing — device only")
                if model.lookProbe {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reach: \(self.model.lookReach, specifier: "%.2f") m")
                            .font(DesignTokens.TypeScale.control.monospacedDigit())
                        Slider(value: $model.lookReach, in: WavesModel.lookReachRange)
                            .accessibilityLabel("Probe reach")
                    }
                }
            }

            CollapsedSection("Numbers") {
                WavesProbeReadout()
                Text("The probe's reading — drag the white bead anywhere in the field.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
