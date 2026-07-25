//
//  ElasticFieldModule.swift
//  Physics Playground — Elastic Field module
//
//  Catalog registration, window controls, and the real-world story
//  for the membrane you reach into. Its scene and model (the exact
//  2-D wave equation) live in Modules/Springs alongside the classic
//  spring lab — two takes on coupled Hooke's law, one field and one
//  block.
//

import PhysicsCore
import SwiftUI

@MainActor
enum ElasticFieldModule {
    static let id = "elasticfield"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Elastic Field",
            blurb: "A resonance drumhead you can hear. A shaker drives a membrane of coupled springs — the real 2-D wave equation. Sweep the drive frequency: at each natural frequency the drumhead blooms into a standing mode, marker grains gather on the still nodal lines, and the tone peaks.",
            icon: "waveform",
            accent: DesignTokens.Palette.springsAccent,
            firstRunHint: "A shaker pushes the sheet's center. Drag the Drive frequency slowly: the sheet stays calm until you hit a resonance, when a standing mode blooms and the grains rush onto its nodal lines — and the tone swells. Lower the damping for sharper peaks, jump straight onto a mode, or reach in and pull the sheet yourself.",
            legend: legend,
            isPaused: { appModel.waveMediumModel.isPaused },
            togglePause: { appModel.waveMediumModel.isPaused.toggle() },
            makeControls: {
                AnyView(
                    WaveMediumControlsView()
                        .environment(appModel.waveMediumModel)
                )
            },
            makeScene: {
                AnyView(
                    WaveMediumSpaceView()
                        .environment(appModel.waveMediumModel)
                )
            },
            reset: {
                appModel.waveMediumModel.reset()
            }
        )
    }

    private static let legend: [LegendItem] = [
        LegendItem(swatch: .fill(Color(red: 1.0, green: 0.4, blue: 0.32)),
                   text: "Crests toward you glow warm, troughs away cool — the sheet's displacement IS the wave, lit so its 3-D shape reads straight on"),
        LegendItem(swatch: .fill(Color(red: 1.0, green: 0.96, blue: 0.86)),
                   text: "Marker grains flee the shaking antinodes and pile onto the still nodal lines — the drumhead's Chladni figure for that mode"),
        LegendItem(swatch: .fill(Color(red: 0.3, green: 0.85, blue: 0.85)),
                   text: "The driver puck rides the shaken center, pumping in and out; the rim traces the boundary — clamped or free"),
        LegendItem(swatch: .fill(.white),
                   text: "The halo marks the point in your hand; release it and the stored tension launches a wave"),
    ]

}

/// Window panel: the medium's parameters and the physics prose. The
/// room holds the sheet and two small pods; the paragraphs live here.
struct WaveMediumControlsView: View {
    @Environment(WaveMediumModel.self) private var model
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var model = model
        let near = model.nearestResonance()

        VStack(alignment: .leading, spacing: DesignTokens.Panel.sectionSpacing) {
            // While the space is open, the Shaker and Medium pods beside
            // the drum own these controls — repeating them here was a
            // second place to do the same thing. The window keeps the
            // physics prose the pods don't carry.
            if appModel.isImmersiveSpaceOpen {
                PanelSection("What you're seeing") {
                    Text("The sheet is a grid of masses joined by springs — in the small-displacement limit, the exact wave equation ∂²u/∂t² = c²∇²u. A shaker pushes the center with a force F = A·sin(2πf·t). Off resonance the sheet barely responds; when f matches a natural frequency f = (c/2)√((m/L)²+(p/L)²), that standing mode builds to full amplitude. Grains migrate off the shaking antinodes to the still nodal lines — the same Chladni figures a bowed metal plate makes.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !model.insightText.isEmpty {
                    Text(model.insightText)
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("The Shaker and Medium pods beside the drum hold the controls.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            } else {
            PanelSection("The shaker") {
                Toggle("Drive the drumhead", isOn: $model.driveOn)
                    .font(DesignTokens.TypeScale.control)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drive frequency: \(model.driveFrequency, specifier: "%.2f") Hz")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.driveFrequency, in: WaveMediumModel.driveFrequencyRange)
                        .disabled(!model.driveOn)
                }
                ResonanceMeter(resonance: model.resonance)
                Text("Nearest mode (\(near.mode.m),\(near.mode.p)) rings at \(near.frequency, specifier: "%.2f") Hz")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(WaveMediumModel.drivableModes) { mode in
                        ModeSeekButton(
                            mode: mode,
                            isCurrent: mode == near.mode && abs(near.detune) < 0.02
                        ) { model.seekMode(mode) }
                    }
                }
            }

            PanelSection("The medium") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wave speed c = \(model.waveSpeed, specifier: "%.1f") m/s")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.waveSpeed, in: WaveMediumModel.waveSpeedRange)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Damping: \(model.damping, specifier: "%.2f")")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.damping, in: WaveMediumModel.dampingRange)
                }
                Toggle("Clamped rim (drumhead)", isOn: $model.boundaryFixed)
                    .font(DesignTokens.TypeScale.control)
            }

            PanelSection("What you're seeing") {
                Text("The sheet is a grid of masses joined by springs — in the small-displacement limit, the exact wave equation ∂²u/∂t² = c²∇²u. A shaker pushes the center with a force F = A·sin(2πf·t). Off resonance the sheet barely responds; when f matches a natural frequency f = (c/2)√((m/L)²+(p/L)²), that standing mode builds to full amplitude. Grains migrate off the shaking antinodes to the still nodal lines — the same Chladni figures a bowed metal plate makes.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
}
