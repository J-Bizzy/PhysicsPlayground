//
//  GravityLabSpaceView.swift
//  Physics Playground — Gravity Lab module
//
//  The orbital mechanics immersive scene. Every celestial body is
//  grabbable: holding one freezes it (it keeps attracting the others)
//  and shows the orbit it would get if released now; releasing applies
//  the hand's velocity. The floating data panel follows the selected
//  body; the time panel floats by the platform.
//

import SwiftUI
import RealityKit
import RenderKit

struct GravityLabSpaceView: View {
    @Environment(GravityLabModel.self) private var model
    @State private var renderer: GravityLabRenderer?
    @State private var router = ManipulationRouter()
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = GravityLabRenderer()
            content.add(renderer.root)

            let podsRoot = PodMount.makeRoot(module: "gravitylab")
            renderer.root.addChild(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-time"), name: "Time",
                           at: [0, 1.14, -1.05], in: podsRoot)
            if let data = attachments.entity(for: "data") {
                data.position = [0, 0.05, 0]
                renderer.selectedAnchor.addChild(data)
            }

            configureRouter(renderer: renderer)
            renderer.subscriptions = router.subscriptions(for: content)
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.step(dt: event.deltaTime)
                    // Ticked here (not in the render loop) so the field
                    // keeps flowing even while the simulation is paused.
                    renderer?.tickFieldParticles(dt: event.deltaTime, model: model)
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    PodMount.persistIfMoved(podsRoot)
                }
            )

            renderer.startObserving(model)
            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-time") {
                ControlPod(title: "Time", icon: "clock",
                           tint: DesignTokens.Palette.gravityAccent, width: 460) {
                    GravityLabTimePanel()
                        .environment(model)
                }
            }
            Attachment(id: "data") {
                GravityLabDataPanel(compact: true)
                    .environment(model)
                    .padding(16)
                    .frame(width: 300)
                    .glassBackgroundEffect()
            }
        }
    }

    private func configureRouter(renderer: GravityLabRenderer) {
        router.onBegin = { [weak renderer] name, position in
            guard let renderer, let id = UUID(uuidString: name) else { return }
            renderer.manipulatingBodyID = id
            model.grab(id: id, at: renderer.displayPoint(fromWorld: position))
        }
        router.onMove = { [weak renderer] name, position in
            guard let renderer, let id = UUID(uuidString: name) else { return }
            model.hold(id: id, at: renderer.displayPoint(fromWorld: position))
        }
        router.onEnd = { [weak renderer] name, position in
            guard let renderer, let id = UUID(uuidString: name) else { return }
            model.hold(id: id, at: renderer.displayPoint(fromWorld: position))
            model.release(id: id)
            renderer.manipulatingBodyID = nil
        }
    }
}

/// Pause / play and the 1–100× time scale, plus the simulation clock.
struct GravityLabTimePanel: View {
    @Environment(GravityLabModel.self) private var model

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 14) {
            Button {
                model.isPaused.toggle()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(model.isPaused ? "Resume time" : "Pause time")

            Picker("Speed", selection: $model.timeScale) {
                ForEach(GravityLabModel.timeScales, id: \.self) { scale in
                    Text("\(Int(scale))×").tag(scale)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .accessibilityLabel("Time scale")

            Text(clockText)
                .font(DesignTokens.TypeScale.label.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
                .accessibilityLabel("Simulated time: \(clockText)")
        }
    }

    private var clockText: String {
        let days = model.simulatedDays
        return days < 400
            ? String(format: "%.0f days", days)
            : String(format: "%.2f years", days / 365.25)
    }
}
