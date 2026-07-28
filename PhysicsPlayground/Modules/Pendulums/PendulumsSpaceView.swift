//
//  PendulumsSpaceView.swift
//  Physics Playground — Pendulums module
//
//  The pendulum lab immersive scene. Bobs route through the
//  ManipulationRouter: grabbing freezes that pendulum, the bob rides
//  the hand (cable staying taut), and release rethrows it with the
//  hand's velocity estimated from the last tenth of a second of
//  motion — a hard sideways throw whips it, a gentle release barely
//  stirs it.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit
import simd

struct PendulumsSpaceView: View {
    @Environment(PendulumsModel.self) private var model
    @State private var renderer: PendulumsRenderer?
    @State private var drag: RelativeDrag?
    @State private var handSamples: [(time: Double, position: SIMD3<Double>)] = []
    /// A gravity gauge under the beam. "What if this were the Moon" is
    /// the question this bench exists to answer, and it was a slider in
    /// a card — now it is a dial you turn while watching the swing
    /// stretch out in front of you.
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            let renderer = PendulumsRenderer()
            content.add(renderer.root)

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    renderer?.tick(dt: event.deltaTime, model: model)
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
                            if let id = UUID(uuidString: candidate.name),
                               let pendulum = model.pendulums.first(where: { $0.id == id }) {
                                renderer?.grabbedID = id
                                renderer?.clearTrail()
                                model.beginGrab(id: id)
                                drag = RelativeDrag(
                                    name: candidate.name,
                                    target: pendulum.bobWorld, hand: hand)
                                handSamples = [(Date.timeIntervalSinceReferenceDate,
                                                pendulum.bobWorld)]
                                break
                            }
                            current = candidate.parent
                        }
                    }
                    guard let drag, let id = UUID(uuidString: drag.name) else { return }
                    let world = drag.position(forHand: hand)
                    model.moveGrabbed(id: id, toWorld: world)
                    let now = Date.timeIntervalSinceReferenceDate
                    handSamples.append((now, world))
                    handSamples.removeAll { now - $0.time > 0.14 }
                }
                .onEnded { value in
                    defer {
                        renderer?.grabbedID = nil
                        drag = nil
                        handSamples = []
                    }
                    guard let drag, let id = UUID(uuidString: drag.name) else { return }
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    let world = drag.position(forHand: hand)
                    model.moveGrabbed(id: id, toWorld: world)
                    var velocity = SIMD3<Double>.zero
                    let now = Date.timeIntervalSinceReferenceDate
                    if let oldest = handSamples.first, now - oldest.time > 0.02 {
                        velocity = (world - oldest.position) / (now - oldest.time)
                    }
                    model.release(id: id, handVelocity: velocity)
                }
        )
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

}

/// The card floating above the selected bob: the numbers behind the swing.
struct PendulumInfoCard: View {
    @Environment(PendulumsModel.self) private var model

    var body: some View {
        if let pendulum = model.selected {
            let speed = simd_length(pendulum.state.velocity)
            let angle = pendulum.state.angle(length: pendulum.length)
            let energies = pendulum.state.energies(
                length: pendulum.length, gravity: model.gravity, mass: pendulum.mass)
            VStack(alignment: .leading, spacing: 3) {
                Text("L \(pendulum.length, specifier: "%.2f") m   T \(pendulum.period(gravity: model.gravity), specifier: "%.2f") s")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                Text("θ \(angle * 180 / .pi, specifier: "%.0f")°   v \(speed, specifier: "%.2f") m/s")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                Text("KE \(energies.kinetic, specifier: "%.2f") J   PE \(energies.potential, specifier: "%.2f") J")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
