//
//  WavesControlsView.swift
//  Physics Playground — Waves module
//
//  The waves control panel content: sources (add, remove, per-source
//  amplitude and the phase-invert switch), wave parameters, time, and
//  the live interference numbers. The shell adds the hint, legend, and
//  real-world button around it.
//

import PhysicsCore
import SwiftUI

struct WavesControlsView: View {
    @Environment(WavesModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Sources") {
                HStack(spacing: DesignTokens.Panel.rowSpacing) {
                    Button {
                        model.addSource()
                    } label: {
                        Label("Add source", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent)
                    .tint(DesignTokens.Palette.wavesAccent)
                    .disabled(model.sources.count >= WavesModel.sourceBudget)

                    Button(role: .destructive) {
                        model.removeSelectedSource()
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podQuiet)
                    .disabled(model.sources.count <= 1)
                    .accessibilityLabel("Remove selected source")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Strength: \(model.selectedAmplitude * 1000, specifier: "%.1f") mm")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.selectedAmplitude, in: WavesModel.amplitudeRange)
                        .disabled(model.selectedSource == nil)
                        .accessibilityLabel("Selected source strength")
                }

                Toggle("Invert phase (noise-cancelling)", isOn: $model.selectedInverted)
                    .font(DesignTokens.TypeScale.control)
                    .disabled(model.selectedSource == nil)
                    .accessibilityHint("Starts this source half a cycle late — where the waves met loudly they now cancel")

                Toggle("Doppler flyby", isOn: $model.selectedIsFlying)
                    .font(DesignTokens.TypeScale.control)
                    .disabled(model.selectedSource == nil)
                    .accessibilityHint("Sends this source cruising across the field so its wavefronts bunch up ahead — the ambulance-passing Doppler effect. Or just grab a source and sweep it yourself.")

                Text("\(model.sources.count) of \(WavesModel.sourceBudget) sources — the last one grabbed is the one these edit.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }

            PanelSection("Waves") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wave speed: \(model.waveSpeed, specifier: "%.2f") m/s")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.waveSpeed, in: WavesModel.speedRange)
                        .accessibilityLabel("Wave speed")
                }

                Toggle("Wavefronts", isOn: $model.showWavefronts)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("Expanding crest spheres from each source; sweep a source and they bunch ahead — the Doppler effect made visible")

            }

            PanelSection {
                WavesStatsView()
            }
        }
    }
}

// MARK: - Live interference numbers

struct WavesStatsView: View {
    @Environment(WavesModel.self) private var model

    var body: some View {
        let readout = model.probeReadout

        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            HStack {
                Text("Interference")
                    .font(DesignTokens.TypeScale.sectionHeader)
                Spacer()
                Text("real scale")
                    .font(.caption.smallCaps())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Wavelength λ", String(format: "%.1f", model.wavelength * 100), "cm")
                if let separation = model.sourceSeparation {
                    row("Separation d", String(format: "%.1f", separation * 100), "cm")
                    row("d / λ", String(format: "%.2f", separation / model.wavelength), "")
                }
                if let silent = model.silentSurfaceCount {
                    row("Silence surfaces", "\(silent)", "")
                }
                row("Probe amplitude", String(format: "%.1f", readout.amplitude * 1000), "mm")
                if let cycles = readout.pathDifferenceInWavelengths {
                    row("Probe Δr", String(format: "%.2f", cycles), "λ")
                }
            }

            if let kind = readout.interference {
                HStack(spacing: 8) {
                    Circle()
                        .fill(kind == .destructive ? Color.red :
                              kind == .constructive ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(explanation(for: kind))
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            Text("Dot size shows the live field; brightness shows how loud each spot ever gets. Every number here is the true value.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    private func explanation(for kind: WaveField.Interference) -> String {
        switch kind {
        case .constructive:
            "The probe sits where crests arrive together — amplitudes add."
        case .destructive:
            "The probe sits on a silence surface — crest meets trough and they cancel."
        case .intermediate:
            "Partial overlap here — between a loud zone and a silent sheet."
        }
    }

    private func row(_ label: String, _ value: String, _ unit: String) -> some View {
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
