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
    @State private var drag: RelativeDrag?
    @Environment(AppModel.self) private var appModel
    /// Two gauges you TWIST rather than two sliders on a card: the
    /// driver frequency and the medium's wave speed, standing at the
    /// edge of the field where the physics is.

    var body: some View {
        RealityView { content in
            let renderer = WavesRenderer()
            content.add(renderer.root)

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.step(dt: event.deltaTime)
                    // Look-to-measure: with the probe following the head
                    // ray, turning to face a part of the field reads it
                    // out there. Head direction, not eye gaze — visionOS
                    // never hands an app the eyes, and nothing here
                    // pretends otherwise.
                    if model.lookProbe, let ray = appModel.room.lookRay,
                       let point = WavesModel.region.point(
                        onRay: ray.origin, direction: ray.direction,
                        reach: model.lookReach) {
                        model.moveProbe(to: point)
                    }
                    renderer?.tick(model, listener: appModel.room.headPosition)
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                    // …but the control pods do NOT go with it: the user
                    // parked them where they wanted them, and moving the
                    // apparatus is not a request to move the controls.
                }
            )

            renderer.tick(model, listener: appModel.room.headPosition)
            self.renderer = renderer
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if drag == nil {
                        var current: Entity? = value.entity
                        while let candidate = current {
                            if candidate.name == WavesRenderer.probeName {
                                drag = RelativeDrag(name: candidate.name,
                                                    target: model.probePosition, hand: hand)
                                break
                            }
                            if let id = UUID(uuidString: candidate.name),
                               let source = model.sources.first(where: { $0.id == id }) {
                                model.select(id: id)
                                drag = RelativeDrag(name: candidate.name,
                                                    target: source.wave.position, hand: hand)
                                break
                            }
                            current = candidate.parent
                        }
                    }
                    guard let drag else { return }
                    let position = drag.position(forHand: hand)
                    if drag.name == WavesRenderer.probeName {
                        model.moveProbe(to: position)
                    } else if let id = UUID(uuidString: drag.name) {
                        model.moveSource(id: id, to: position)
                    }
                }
                .onEnded { _ in
                    drag = nil
                }
        )
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
