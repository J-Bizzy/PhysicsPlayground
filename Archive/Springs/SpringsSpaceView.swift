//
//  SpringsSpaceView.swift
//  Physics Playground — Springs module
//
//  The spring lab immersive scene. Blocks route through the
//  ManipulationRouter constrained to the rail axis: pulling stretches
//  the helix live, release launches with the hand's along-rail
//  velocity. The panel switches single/coupled mode, graph channel,
//  and time scale.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit
import simd

struct SpringsSpaceView: View {
    @Environment(SpringsModel.self) private var model
    @State private var renderer: SpringsRenderer?
    @State private var drag: RelativeDrag?
    @State private var dials: DialConsole?
    @State private var handSamples: [(time: Double, position: SIMD3<Double>)] = []
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = SpringsRenderer()
            content.add(renderer.root)

            // The two numbers that ARE simple harmonic motion, as brass
            // you twist on the bench itself: T = 2π√(m/k), with k and m
            // mounted beside the anchor post their spring hangs from.
            // Twist either and hear the period answer.
            let console = DialConsole([
                .init(name: "dial-k", title: "Stiffness",
                      center: SIMD3(Float(SpringsModel.center.x - SpringsModel.railHalfLength) - 0.16,
                                    Float(SpringsModel.center.y) + 0.34,
                                    Float(SpringsModel.center.z)),
                      range: SpringsModel.stiffnessRange,
                      accent: UIColor(DesignTokens.Palette.springsAccent),
                      read: { model.stiffness },
                      write: { model.stiffness = $0 },
                      format: { String(format: "%.0f N/m", $0) }),
                .init(name: "dial-mass", title: "Mass",
                      center: SIMD3(Float(SpringsModel.center.x - SpringsModel.railHalfLength) - 0.16,
                                    Float(SpringsModel.center.y) + 0.18,
                                    Float(SpringsModel.center.z)),
                      range: SpringsModel.massRange,
                      accent: UIColor(DesignTokens.Palette.springsAccent),
                      read: { model.mass },
                      write: { model.mass = $0 },
                      format: { String(format: "%.1f kg", $0) }),
            ])
            renderer.root.addChild(console.root)
            dials = console

            let podsRoot = PodMount.makeRoot(module: "springs")
            renderer.root.addChild(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-apparatus"), name: "Apparatus",
                           at: [-1.1, 1.75, -0.8], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-time"), name: "Time",
                           at: [-1.2, 1.15, -0.8], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-graph"), name: "Graph",
                           at: [1.1, 1.72, -0.8], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-parameters"), name: "Parameters",
                           at: [1.2, 1.05, -0.8], in: podsRoot)
            if let info = attachments.entity(for: "info") {
                info.position = [0, 0.02, 0]
                renderer.infoAnchor.addChild(info)
            }

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    dials?.sync()
                    renderer?.tick(dt: event.deltaTime, model: model)
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    PodMount.persistIfMoved(podsRoot)
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                    // …but the control pods do NOT go with it: the user
                    // parked them where they wanted them, and moving the
                    // apparatus is not a request to move the controls.
                    podsRoot.position = -appModel.labPlacement.offset
                }
            )
            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-apparatus") {
                SpringsApparatusPod()
                    .environment(model)
            }
            Attachment(id: "pod-time") {
                SpringsTimePod()
                    .environment(model)
            }
            Attachment(id: "pod-graph") {
                SpringsGraphPod()
                    .environment(model)
            }
            Attachment(id: "pod-parameters") {
                SpringsParametersPod()
                    .environment(model)
            }
            Attachment(id: "info") {
                SpringInfoCard()
                    .environment(model)
                    .padding(12)
                    .glassBackgroundEffect()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if dials?.advanceTwist(hand: hand) == true { return }
                    if drag == nil {
                        if dials?.beginTwist(on: value.entity, hand: hand) == true { return }
                        var current: Entity? = value.entity
                        while let candidate = current {
                            if let index = blockIndex(from: candidate.name) {
                                let target = model.mode == .single
                                    ? model.blockWorld : model.coupledBlockWorld(index)
                                renderer?.grabbedBlock = index
                                model.beginGrab(block: index)
                                drag = RelativeDrag(name: candidate.name,
                                                    target: target, hand: hand)
                                handSamples = [(Date.timeIntervalSinceReferenceDate, target)]
                                break
                            }
                            current = candidate.parent
                        }
                    }
                    guard let drag else { return }
                    let world = drag.position(forHand: hand)
                    model.moveGrabbed(toWorld: world)
                    let now = Date.timeIntervalSinceReferenceDate
                    handSamples.append((now, world))
                    handSamples.removeAll { now - $0.time > 0.14 }
                }
                .onEnded { value in
                    defer {
                        dials?.endTwist()
                        renderer?.grabbedBlock = nil
                        drag = nil
                        handSamples = []
                    }
                    guard let drag else { return }
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    let world = drag.position(forHand: hand)
                    model.moveGrabbed(toWorld: world)
                    var velocity = 0.0
                    let now = Date.timeIntervalSinceReferenceDate
                    if let oldest = handSamples.first, now - oldest.time > 0.02 {
                        let handVelocity = (world - oldest.position) / (now - oldest.time)
                        velocity = simd_dot(handVelocity, model.axisDirection)
                    }
                    model.release(handVelocityX: velocity)
                    renderer?.playRelease(speed: abs(velocity), at: world)
                }
        )
    }

    private func blockIndex(from name: String) -> Int? {
        guard name.hasPrefix("s-block-") else { return nil }
        return Int(name.dropFirst(8))
    }

}

/// Single or coupled, on the rail or hanging.
struct SpringsApparatusPod: View {
    @Environment(SpringsModel.self) private var model

    var body: some View {
        ControlPod(title: "Apparatus", icon: "wrench.and.screwdriver", tint: DesignTokens.Palette.springsAccent) {
            HStack(spacing: 8) {
                Button("Single") { model.setMode(.single) }
                    .buttonStyle(.podQuiet)
                    .tint(model.mode == .single ? DesignTokens.Palette.springsAccent : nil)
                Button("Coupled ×2") { model.setMode(.coupled) }
                    .buttonStyle(.podQuiet)
                    .tint(model.mode == .coupled ? DesignTokens.Palette.springsAccent : nil)
            }
            .font(DesignTokens.TypeScale.footnote)
            HStack(spacing: 8) {
                Button {
                    model.setOrientation(.horizontal)
                } label: {
                    Label("Rail", systemImage: "arrow.left.and.right")
                }
                .buttonStyle(.podQuiet)
                .tint(model.orientation == .horizontal ? DesignTokens.Palette.springsAccent : nil)
                Button {
                    model.setOrientation(.vertical)
                } label: {
                    Label("Hanging", systemImage: "arrow.down")
                }
                .buttonStyle(.podQuiet)
                .tint(model.orientation == .vertical ? DesignTokens.Palette.springsAccent : nil)
                .disabled(model.mode == .coupled)
            }
            .font(DesignTokens.TypeScale.footnote)
        }
    }
}

/// Pause and slow motion for the oscillation clock.
struct SpringsTimePod: View {
    @Environment(SpringsModel.self) private var model

    private let timeScales: [(String, Double)] = [
        ("¼×", 0.25), ("½×", 0.5), ("1×", 1), ("2×", 2), ("5×", 5),
    ]

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Time", icon: "clock", tint: DesignTokens.Palette.springsAccent, width: 300) {
            HStack(spacing: 5) {
                Button {
                    model.isPaused.toggle()
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.podQuiet)
                ForEach(timeScales, id: \.1) { label, scale in
                    Button(label) {
                        model.timeScale = scale
                        model.isPaused = false
                    }
                    .buttonStyle(.podQuiet)
                    .tint(model.timeScale == scale && !model.isPaused ? DesignTokens.Palette.springsAccent : nil)
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                }
            }
        }
    }
}

/// The scrolling graph's channel, plus overlay vectors.
struct SpringsGraphPod: View {
    @Environment(SpringsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Graph", icon: "chart.xyaxis.line", tint: DesignTokens.Palette.springsAccent) {
            Picker("Graph", selection: $model.graphMode) {
                Text("x·t").tag(SpringsModel.GraphMode.position)
                Text("v·t").tag(SpringsModel.GraphMode.velocity)
                Text("a·t").tag(SpringsModel.GraphMode.acceleration)
                Text("E·t").tag(SpringsModel.GraphMode.energy)
            }
            .pickerStyle(.segmented)
            HStack(spacing: 10) {
                Toggle("v", isOn: $model.showVelocity)
                Toggle("a", isOn: $model.showAcceleration)
                Toggle("F", isOn: $model.showForce)
                Toggle("E", isOn: $model.showEnergyBars)
            }
            .toggleStyle(.button)
            .font(DesignTokens.TypeScale.footnote)
        }
    }
}

/// k, m, damping — the oscillator's DNA — plus the insight line.
struct SpringsParametersPod: View {
    @Environment(SpringsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Parameters", icon: "slider.horizontal.3", tint: DesignTokens.Palette.springsAccent) {
            slider("Stiffness k", $model.stiffness,
                   SpringsModel.stiffnessRange, "%.0f N/m")
            slider("Mass", $model.mass, SpringsModel.massRange, "%.1f kg")
            Toggle("Friction", isOn: $model.frictionOn)
                .font(DesignTokens.TypeScale.control)
                .accessibilityHint("Off: an ideal oscillator that never dies down")
            slider("Damping", $model.damping, SpringsModel.dampingRange, "%.2f N·s/m")
                .opacity(model.frictionOn ? 1 : 0.4)
                .disabled(!model.frictionOn)
            if model.orientation == .horizontal {
                Toggle("Gravity along the rail", isOn: $model.gravityOn)
                    .font(DesignTokens.TypeScale.footnote)
            } else {
                Text("Hanging: equilibrium sags mg/k = \(String(format: "%.1f", model.equilibriumSag * 100)) cm")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
            if !model.insightText.isEmpty {
                Text(model.insightText)
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>, _ format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label): \(String(format: format, value.wrappedValue))")
                .font(DesignTokens.TypeScale.control.monospacedDigit())
            Slider(value: value, in: range)
                .accessibilityLabel(label)
        }
    }
}

/// The card floating above the block.
struct SpringInfoCard: View {
    @Environment(SpringsModel.self) private var model

    var body: some View {
        let displacement = model.mode == .single
            ? model.state.displacement : model.coupled.displacements.x
        let velocity = model.mode == .single
            ? model.state.velocity : model.coupled.velocities.x
        let energies = model.energies()
        VStack(alignment: .leading, spacing: 3) {
            Text("x \(displacement * 100, specifier: "%+.1f") cm   v \(velocity, specifier: "%+.2f") m/s")
                .font(DesignTokens.TypeScale.footnote.monospacedDigit())
            Text("F \(model.springForce, specifier: "%+.1f") N   T \(model.period, specifier: "%.2f") s   f \(model.frequency, specifier: "%.2f") Hz")
                .font(DesignTokens.TypeScale.footnote.monospacedDigit())
            if model.mode == .single {
                Text("KE \(energies.kinetic, specifier: "%.2f") J   PE \(energies.potential, specifier: "%.2f") J")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
