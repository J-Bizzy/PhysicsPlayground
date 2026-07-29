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
    @State private var bloom = Bloom()
    /// Which bob's ring is open — shared by the tap gesture and the
    /// render loop (see RingState's header for why it's a reference).
    @State private var ring = RingState()
    @State private var wells: Well?
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
            renderer.root.addChild(bloom.root)

            // Pull a pendulum out and hang it wherever you let go. The
            // pivot lands at your fingertips, so rigging one and moving
            // one are the same gesture.
            let sources = Well([
                .init(name: "Pendulum",
                      tint: UIColor(DesignTokens.Palette.pendulumsAccent),
                      glyph: "+",
                      position: SIMD3(-0.85, 1.30, -0.95),
                      spawn: { point in
                          model.addPendulum(at: point)
                      }),
            ])
            renderer.root.addChild(sources.root)
            wells = sources

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    renderer?.tick(dt: event.deltaTime, model: model)
                    wells?.update(dt: event.deltaTime)
                    syncBloom(dt: event.deltaTime)
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
            #if DEBUG
            // `-penRing 1` opens the first bob's control ring at
            // launch, for CLI screenshots.
            if UserDefaults.standard.bool(forKey: "penRing"),
               let first = model.pendulums.first {
                ring.openID = first.id
            }
            #endif
            self.renderer = renderer
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                    if drag == nil {
                        if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                        if let id = wells?.pull(value.entity, at: hand) {
                            drag = RelativeDrag(name: "pivot-\(id.uuidString)",
                                                target: hand, hand: hand)
                            return
                        }

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
                    // A pivot drag re-hangs the rig; a bob drag swings it.
                    if drag?.name.hasPrefix("pivot-") == true, let drag,
                       let id = UUID(uuidString: String(drag.name.dropFirst(6))) {
                        model.movePivot(id: id, to: drag.position(forHand: hand))
                        return
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
                    if bloom.handleTap(value.entity) { return }
                    // A tap on a bob selects it and toggles its control
                    // ring; a tap on anything else folds the ring away.
                    var current: Entity? = value.entity
                    while let candidate = current {
                        if let id = UUID(uuidString: candidate.name),
                           model.pendulums.contains(where: { $0.id == id }) {
                            model.select(id: id)
                            if ring.openID == id {
                                ring.openID = nil
                            } else {
                                ring.openID = id
                                SoundPalette.play(.pop, on: value.entity, volume: 0.35)
                            }
                            return
                        }
                        current = candidate.parent
                    }
                    ring.openID = nil
                }
        )
    }


    /// A bob's own controls. LENGTH is the grip, and its extent is the
    /// cable: pull the bead and the cable pays out, the bob falls with
    /// it, and the period tag over the pivot climbs as the square root
    /// of length while your hand is still moving.
    private func syncBloom(dt: Double) {
        if let openID = ring.openID,
           !model.pendulums.contains(where: { $0.id == openID }) {
            ring.openID = nil     // deleted out from under the ring
        }
        guard let uuid = ring.openID,
              let pendulum = model.pendulums.first(where: { $0.id == uuid }) else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }

        bloom.retarget(
            uuid,
            petals: [
                .init(name: "Delete", symbol: "trash",
                      tint: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)) {
                    model.removePendulum(id: uuid)
                },
            ],
            grip: .init(
                name: "Length",
                range: PendulumsModel.lengthRange,
                read: { model.pendulums.first(where: { $0.id == uuid })?.length ?? 0.8 },
                write: { model.setLength(id: uuid, $0) },
                format: { String(format: "%.2f m", $0) },
                radius: { Float(pendulum.bobRadius) + 0.03 }))

        let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
        bloom.update(anchor: SIMD3<Float>(pendulum.bobWorld),
                     viewer: viewer, revealTarget: 1, dt: dt)
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
