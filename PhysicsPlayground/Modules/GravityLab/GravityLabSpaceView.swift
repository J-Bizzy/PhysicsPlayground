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

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct GravityLabSpaceView: View {
    @Environment(GravityLabModel.self) private var model
    @State private var renderer: GravityLabRenderer?
    @State private var drag: RelativeDrag?
    @State private var bloom = Bloom()
    @State private var look = LookReveal(coneDegrees: 13)
    @State private var wells: Well?
    /// Two-handed scale and turn for the whole system: pull your hands
    /// apart to grow the solar system around you, twist to look at the
    /// comet's inclined orbit from the side.
    /// Up to 9x: Earth's orbit displays at half a metre, so 4x let you
    /// stand inside Earth's orbit but never between Mercury and Venus.
    /// At 9x Mercury's orbit is 1.75 m across — the inner solar system
    /// becomes a room you walk through, planets streaming past your
    /// knees and the Kepler sectors sweeping underfoot like floor tiles.
    @State private var scaleRig = SpatialScaleRig(
        pivot: GravityLabRenderer.systemPosition, range: 0.4...9.0)
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            let renderer = GravityLabRenderer()
            content.add(renderer.root)

            // Pull a world out of the well and let go: it arrives at
            // rest beside the primary and immediately begins to fall,
            // so where you release it decides whether it is captured or
            // plunges. Making a planet and aiming it are one gesture.
            let sources = Well([
                .init(name: "World", tint: UIColor(red: 0.55, green: 0.72, blue: 1, alpha: 1),
                      glyph: "+",
                      position: SIMD3(-0.55, 0.10, 0.30),
                      spawn: { point in
                          model.addBody(at: SIMD3<Double>(point))
                      }),
            ])
            // Under systemRoot, NOT viewRoot: every body position here is
            // in the system's own display space, and a bloom anchored in
            // one frame while parented in another lands nowhere near the
            // thing it belongs to.
            renderer.systemRoot.addChild(sources.root)
            renderer.systemRoot.addChild(bloom.root)
            wells = sources

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.step(dt: event.deltaTime)
                    renderer?.tick(model, lookRay: appModel.room.lookRay)
                    // Separate from the tick so the field keeps flowing
                    // even while the simulation is paused.
                    renderer?.tickFieldParticles(dt: event.deltaTime, model: model)
                    scaleRig.apply(to: renderer?.viewRoot ?? Entity())
                    wells?.update(dt: event.deltaTime)
                    if let renderer {
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                    }
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
            // `-viewScale 7` bakes in a committed scale for CLI shots.
            let forcedScale = UserDefaults.standard.double(forKey: "viewScale")
            if forcedScale > 0 {
                scaleRig.updateMagnification(Float(forcedScale))
                scaleRig.endGesture()
            }
            // `-selectBody Earth` pins the selection for CLI shots.
            if let name = UserDefaults.standard.string(forKey: "selectBody"),
               let body = model.bodies.first(where: { $0.body.name == name }) {
                model.select(id: body.id)
            }
            // `-predict 1` arms a prediction at the body's current spot,
            // so the verdict flow can be screenshot-verified.
            if UserDefaults.standard.double(forKey: "predict") > 0 {
                model.armPrediction()
            }
            #endif
            renderer.tick(model, lookRay: appModel.room.lookRay)
            self.renderer = renderer
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                    if drag == nil {
                        if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                        if let id = wells?.pull(value.entity, at: hand) {
                            drag = RelativeDrag(name: id.uuidString,
                                                target: hand, hand: hand)
                            model.grab(id: id, at: hand)
                            return
                        }
                        var current: Entity? = value.entity
                        while let candidate = current {
                            // The prediction ghost is draggable like a
                            // body, but it moves the GUESS, not physics.
                            if candidate.name == "prediction-ghost",
                               let prediction = model.prediction {
                                drag = RelativeDrag(
                                    name: candidate.name,
                                    target: prediction.position * model.simToDisplay,
                                    hand: hand)
                                break
                            }
                            if let id = UUID(uuidString: candidate.name),
                               let body = model.bodies.first(where: { $0.id == id }) {
                                let target = body.body.position * model.simToDisplay
                                drag = RelativeDrag(
                                    name: candidate.name, target: target, hand: hand)
                                model.grab(id: id, at: target)
                                break
                            }
                            current = candidate.parent
                        }
                    }
                    guard let drag else { return }
                    if drag.name == "prediction-ghost" {
                        model.movePrediction(
                            to: drag.position(forHand: hand) * model.displayToSim)
                        return
                    }
                    guard let id = UUID(uuidString: drag.name) else { return }
                    model.hold(id: id, at: drag.position(forHand: hand))
                }
                .onEnded { value in
                    defer { bloom.endGrip(); drag = nil }
                    guard let renderer, let drag,
                          drag.name != "prediction-ghost",
                          let id = UUID(uuidString: drag.name) else { return }
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    model.hold(id: id, at: drag.position(forHand: hand))
                    model.release(id: id)
                }
        )
        .spatialScale(scaleRig)
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in _ = bloom.handleTap(value.entity) }
        )
    }

    /// Points the one bloom at whichever body you are looking at.
    /// Mass IS the grip: pull and the planet inflates, because a
    /// sphere's radius goes as the cube root of its mass — and its
    /// pull on everything around it rises live as you do it.
    private func syncBloom(renderer: GravityLabRenderer, dt: Double) {
        let toDisplay = model.simToDisplay
        // Keyed by NAME, matching the renderer's own look-reveal, so the
        // two agree about what you are looking at (and one -lookReveal
        // flag drives both).
        let candidates = model.bodies.map {
            (id: $0.body.name,
             position: SIMD3<Float>($0.body.position * toDisplay))
        }
        var ray: (origin: SIMD3<Float>, direction: SIMD3<Float>)?
        if let look = appModel.room.lookRay {
            ray = (renderer.systemRoot.convert(position: SIMD3<Float>(look.origin), from: nil),
                   renderer.systemRoot.convert(direction: SIMD3<Float>(look.direction), from: nil))
        }
        look.update(dt: dt, ray: ray, candidates: candidates)

        guard let winner = look.focusedID,
              let body = model.bodies.first(where: { $0.body.name == winner }),
              body.id != model.primaryBody?.id else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }

        let uuid = body.id
        bloom.retarget(
            uuid,
            petals: [
                .init(name: "Delete", symbol: "trash",
                      tint: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)) {
                    model.removeBody(id: uuid)
                },
            ],
            grip: .init(
                name: "Mass",
                range: GravityLabModel.massRangeEarths,
                read: { model.massInEarths(id: uuid) },
                write: { model.setMass(id: uuid, earths: $0) },
                format: { $0 < 1
                    ? String(format: "%.2f Earths", $0)
                    : String(format: "%.0f Earths", $0) },
                radius: { Float(model.displayRadius(id: uuid)) + 0.03 }))

        let viewer = appModel.room.headPosition.map {
            renderer.systemRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(body.body.position * toDisplay),
                     viewer: viewer, revealTarget: 1, dt: dt)
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
            .buttonStyle(.podQuiet)
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
