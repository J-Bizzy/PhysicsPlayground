//
//  OpticsSpaceView.swift
//  Physics Playground — Ray Optics module
//
//  The optical bench immersive scene: elements slide along the rail
//  (axis-projected, like the spring blocks), the ray fan re-traces
//  instantly, and the panel adds elements and tunes the selected lens.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit
import simd

struct OpticsSpaceView: View {
    @Environment(OpticsModel.self) private var model
    @State private var renderer: OpticsRenderer?
    @State private var router = ManipulationRouter()
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = OpticsRenderer()
            content.add(renderer.root)

            let podsRoot = PodMount.makeRoot(module: "optics")
            renderer.root.addChild(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-bench"), name: "Bench",
                           at: [-1.1, 1.65, -0.8], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-selected"), name: "Selected element",
                           at: [1.1, 1.55, -0.8], in: podsRoot)
            if let info = attachments.entity(for: "info") {
                info.position = [0, 0.02, 0]
                renderer.infoAnchor.addChild(info)
            }

            configureRouter(renderer: renderer)
            renderer.subscriptions = router.subscriptions(for: content)
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] _ in
                    renderer?.tick(model: model)
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    PodMount.persistIfMoved(podsRoot)
                }
            )
            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-bench") {
                OpticsBenchPod()
                    .environment(model)
            }
            Attachment(id: "pod-selected") {
                OpticsSelectedPod()
                    .environment(model)
            }
            Attachment(id: "info") {
                OpticsInfoCard()
                    .environment(model)
                    .padding(12)
                    .glassBackgroundEffect()
            }
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    var current: Entity? = value.entity
                    while let candidate = current {
                        if let id = UUID(uuidString: candidate.name) {
                            model.select(id: id)
                            return
                        }
                        current = candidate.parent
                    }
                }
        )
    }

    private func configureRouter(renderer: OpticsRenderer) {
        router.onBegin = { [weak renderer] name, position in
            guard let id = UUID(uuidString: name) else { return }
            renderer?.manipulatingID = id
            model.select(id: id)
            model.moveElement(id: id, toX: Double(position.x) - OpticsModel.center.x)
        }
        router.onMove = { name, position in
            guard let id = UUID(uuidString: name) else { return }
            model.moveElement(id: id, toX: Double(position.x) - OpticsModel.center.x)
        }
        router.onEnd = { [weak renderer] name, position in
            guard let id = UUID(uuidString: name) else { return }
            model.moveElement(id: id, toX: Double(position.x) - OpticsModel.center.x)
            renderer?.manipulatingID = nil
        }
    }
}

/// The optical bench: add elements, choose the source, read insight.
struct OpticsBenchPod: View {
    @Environment(OpticsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Bench", icon: "camera.aperture", tint: .green) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                ForEach(OpticsModel.ElementKind.allCases, id: \.rawValue) { kind in
                    Button(kind.displayName) {
                        model.addElement(kind)
                    }
                    .buttonStyle(.bordered)
                    .font(DesignTokens.TypeScale.footnote)
                    .disabled(model.elements.count >= OpticsModel.elementBudget)
                }
            }
            Picker("Source", selection: $model.sourceMode) {
                Text("Parallel beam").tag(OpticsModel.SourceMode.parallel)
                Text("Point source").tag(OpticsModel.SourceMode.point)
            }
            .pickerStyle(.segmented)
            if !model.insightText.isEmpty {
                Text(model.insightText)
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The selected element's own controls — or a nudge to pick one.
struct OpticsSelectedPod: View {
    @Environment(OpticsModel.self) private var model

    var body: some View {
        ControlPod(title: "Selected", icon: "viewfinder", tint: .green) {
            if let selected = model.selected {
                if selected.kind == .convergingLens || selected.kind == .divergingLens {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Focal length: \(selected.focal * 100, specifier: "%.0f") cm")
                            .font(DesignTokens.TypeScale.control.monospacedDigit())
                        Slider(value: Binding(
                            get: { selected.focal },
                            set: { model.setFocal(id: selected.id, $0) }
                        ), in: OpticsModel.focalRange)
                        .accessibilityLabel("Focal length")
                    }
                }
                Button(role: .destructive) {
                    model.removeSelected()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            } else {
                Text("Pinch an element on the bench to select it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The card above the selected element: thin-lens numbers, live.
struct OpticsInfoCard: View {
    @Environment(OpticsModel.self) private var model

    var body: some View {
        if let element = model.selected {
            VStack(alignment: .leading, spacing: 3) {
                Text(element.kind.displayName)
                    .font(DesignTokens.TypeScale.sectionHeader)
                if let prediction = model.imagePrediction,
                   element.kind == .convergingLens || element.kind == .divergingLens {
                    Text("dₒ \(prediction.objectDistance * 100, specifier: "%.0f") cm   dᵢ \(prediction.imageDistance * 100, specifier: "%+.0f") cm")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    Text("m \(prediction.magnification, specifier: "%+.2f")\(prediction.imageDistance < 0 ? "   (virtual image)" : "")")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if element.kind == .mirror {
                    Text("Folds the bench — equal angles in and out")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
