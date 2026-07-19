//
//  WavesSpaceView.swift
//  Physics Playground — Waves module
//
//  The 3D interference field immersive scene. Sources and the probe are
//  free-floating grabbables routed through RenderKit's
//  ManipulationRouter (positions are room coordinates, 1:1); the wave
//  clock is SceneEvents.Update, scaled and pausable in the model.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct WavesSpaceView: View {
    @Environment(WavesModel.self) private var model
    @State private var renderer: WavesRenderer?
    @State private var router = ManipulationRouter()
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = WavesRenderer()
            content.add(renderer.root)

            let podsRoot = PodMount.makeRoot(module: "waves")
            renderer.root.addChild(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-waves"), name: "Waves",
                           at: [-1.15, 1.6, -0.85], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-time"), name: "Time",
                           at: [-1.2, 1.0, -0.8], in: podsRoot)
            if let readout = attachments.entity(for: "probe") {
                readout.position = [0, 0.02, 0]
                renderer.probeAnchor.addChild(readout)
            }

            configureRouter(renderer: renderer)
            renderer.subscriptions = router.subscriptions(for: content)
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { event in
                    model.step(dt: event.deltaTime)
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    PodMount.persistIfMoved(podsRoot)
                }
            )

            renderer.startObserving(model)
            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-waves") {
                WavesPod()
                    .environment(model)
            }
            Attachment(id: "pod-time") {
                WavesTimePod()
                    .environment(model)
            }
            Attachment(id: "probe") {
                WavesProbeReadout()
                    .environment(model)
                    .padding(12)
                    .glassBackgroundEffect()
            }
        }
    }

    private func configureRouter(renderer: WavesRenderer) {
        router.onBegin = { [weak renderer] name, position in
            guard let renderer else { return }
            if name == WavesRenderer.probeName {
                renderer.isManipulatingProbe = true
                model.moveProbe(to: SIMD3<Double>(position))
            } else if let id = UUID(uuidString: name) {
                renderer.manipulatingSourceID = id
                model.select(id: id)
                model.moveSource(id: id, to: SIMD3<Double>(position))
            }
        }
        router.onMove = { name, position in
            if name == WavesRenderer.probeName {
                model.moveProbe(to: SIMD3<Double>(position))
            } else if let id = UUID(uuidString: name) {
                model.moveSource(id: id, to: SIMD3<Double>(position))
            }
        }
        router.onEnd = { [weak renderer] name, position in
            guard let renderer else { return }
            if name == WavesRenderer.probeName {
                model.moveProbe(to: SIMD3<Double>(position))
                renderer.isManipulatingProbe = false
            } else if let id = UUID(uuidString: name) {
                model.moveSource(id: id, to: SIMD3<Double>(position))
                renderer.manipulatingSourceID = nil
            }
        }
    }
}

/// The wave sources' pod: frequency, wavelength, and the cancel sheets.
struct WavesPod: View {
    @Environment(WavesModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Waves", icon: "waveform", tint: .cyan) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Frequency: \(model.frequency, specifier: "%.2f") Hz   λ = \(model.wavelength * 100, specifier: "%.1f") cm")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Slider(value: $model.frequency, in: WavesModel.frequencyRange)
                    .accessibilityLabel("Frequency")
            }
            Toggle("Silence surfaces", isOn: $model.showSilenceSurfaces)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("The 3D sheets where the waves cancel to nothing")
        }
    }
}

/// Freeze or slow the wave clock.
struct WavesTimePod: View {
    @Environment(WavesModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Time", icon: "clock", tint: .cyan) {
            HStack(spacing: DesignTokens.Panel.rowSpacing) {
                Button {
                    model.isPaused.toggle()
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(model.isPaused ? "Resume waves" : "Freeze waves")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Slow motion ×\(model.timeScale, specifier: "%.1f")")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    Slider(value: $model.timeScale, in: WavesModel.timeScaleRange)
                        .accessibilityLabel("Time scale")
                }
            }
        }
    }
}

/// The little card floating above the probe.
struct WavesProbeReadout: View {
    @Environment(WavesModel.self) private var model

    var body: some View {
        let readout = model.probeReadout
        VStack(alignment: .leading, spacing: 4) {
            Text("\(readout.amplitude * 1000, specifier: "%.1f") mm")
                .font(DesignTokens.TypeScale.sectionHeader.monospacedDigit())
            if let cycles = readout.pathDifferenceInWavelengths {
                Text("Δr = \(cycles, specifier: "%.2f") λ")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let kind = readout.interference {
                Text(label(for: kind))
                    .font(DesignTokens.TypeScale.footnote.bold())
                    .foregroundStyle(color(for: kind))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func label(for kind: WaveField.Interference) -> String {
        switch kind {
        case .constructive: "constructive"
        case .destructive: "silent"
        case .intermediate: "in between"
        }
    }

    private func color(for kind: WaveField.Interference) -> Color {
        switch kind {
        case .constructive: .green
        case .destructive: .red
        case .intermediate: .secondary
        }
    }
}
