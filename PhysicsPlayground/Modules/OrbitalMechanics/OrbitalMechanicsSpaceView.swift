//
//  OrbitalMechanicsSpaceView.swift
//  Physics Playground — Orbital Mechanics module
//
//  The orbital mechanics immersive scene. Every celestial body is
//  grabbable: holding one freezes it (it keeps attracting the others)
//  and shows the orbit it would get if released now; releasing applies
//  the hand's velocity. The floating data panel follows the selected
//  body; the instruments stand off the left shoulder.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct OrbitalMechanicsSpaceView: View {
    @Environment(OrbitalMechanicsModel.self) private var model
    @State private var renderer: OrbitalMechanicsRenderer?
    @State private var drag: RelativeDrag?
    @State private var bloom = Bloom()
    /// Which body's ring is open — shared by the tap gesture and the
    /// render loop (see RingState's header for why it's a reference).
    @State private var ring = RingState()
    @State private var wells: Well?
    /// The last `model.viewResetNonce` this view acted on, so Reset also
    /// snaps the two-hand scale and turn back to 1x.
    @State private var seenResetNonce = 0
    /// Two-handed scale and turn for the whole system. Up to 9×, where
    /// Mercury's orbit is 1.75 m across and the inner system becomes a
    /// room you walk through.
    @State private var scaleRig = SpatialScaleRig(
        pivot: OrbitalMechanicsRenderer.systemPosition, range: 0.4...9.0)
    /// Identifies the floating readout above the selected body.
    private static let dataCardID = "gravity-data"

    /// The world well, on the system's left flank where every control in
    /// the house stands, in the system's frame (it hangs under `systemRoot`,
    /// rig-compensated). Its clock, overlays, verbs and G live in More.
    static let wellOffset = SIMD3<Float>(-0.62, -0.10, 0.20)
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = OrbitalMechanicsRenderer()
            renderer.onObjectTap = { handleObjectTap(on: $0) }
            content.add(renderer.root)
            // Disabled here and raised by `Fade.tick`, so the apparatus arrives
            // rather than appears.
            renderer.root.isEnabled = false

            // Hands-free routes for the two controls that are only ever dragged,
            // each mirroring an existing debug argument: a bead step is
            // `-apsisDrag` at 10% per step; the ghost steps along its radius.
            renderer.onApsisAdjust = { apsis, steps in
                guard let selected = model.selectedBody,
                      let frame = model.orbitFrame(for: selected.id),
                      model.beginOrbitEdit(bodyID: selected.id, holding: apsis)
                else { return }
                let direction = apsis == .near
                    ? frame.periapsisDirection : -frame.periapsisDirection
                let factor = 1 + 0.1 * steps
                model.dragApsis(toDisplayPoint:
                    direction * frame.radius(at: apsis) * factor)
                model.endOrbitEdit()
            }
            renderer.onGhostAdjust = { steps in
                guard let point = model.prediction?.position else { return }
                let radius = simd_length(point)
                guard radius > 1e-9 else { return }
                model.movePrediction(to: point / radius * (radius * (1 + 0.1 * steps)))
            }

            // The selected body's orbit and energy, on the body. `selectedAnchor`
            // sits under `systemRoot`, which the rig scales, so the card is
            // compensated.
            if let card = attachments.entity(for: Self.dataCardID) {
                stripInput(from: card)
                renderer.selectedAnchor.addChild(card)
                renderer.compensateForRig(card)
            }

            // Pull a world out of the well and let go: it takes the circular orbit
            // at the radius you let go at, bent by whatever throw the hand added.
            let sources = Well([
                .init(name: "World", tint: UIColor(red: 0.55, green: 0.72, blue: 1, alpha: 1),
                      label: "Add world",
                      preview: { OrbitalMechanicsRenderer.worldPreview() },
                      position: Self.wellOffset,
                      spawn: { point in
                          model.addBody(at: SIMD3<Double>(point))
                      }),
            ])
            // Under systemRoot: every body position is in the system's display
            // space.
            renderer.systemRoot.addChild(sources.root)
            renderer.systemRoot.addChild(bloom.root)
            // The well is an instrument, not an object in the sky: it keeps its
            // size and place whatever the rig does.
            renderer.compensateForRig(sources.root)
            wells = sources

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's arrival and departure, on the shell's one flag.
                    if let renderer {
                        Fade.tick(renderer.root, visible: !appModel.isDeparting,
                                  duration: AppModel.departure)
                    }
                    model.step(dt: event.deltaTime)
                    renderer?.tick(model)
                    // The bodies' slow spin — presentation, ticked apart
                    // from the physics.
                    renderer?.tickIdleMotion(dt: event.deltaTime, model: model)
                    scaleRig.apply(to: renderer?.viewRoot ?? Entity())
                    // The beads need the head and the rig scale in the system's frame.
                    // Reset means reset: the rig is a view transform, so the view snaps it
                    // back here.
                    if model.viewResetNonce != seenResetNonce {
                        seenResetNonce = model.viewResetNonce
                        scaleRig.reset()
                        scaleRig.apply(to: renderer?.viewRoot ?? Entity())
                    }
                    renderer?.rigScale = scaleRig.liveScale
                    renderer?.showScaleReadout(
                        scaleRig.isTransformed ? scaleRig.label : nil,
                        anchor: OrbitalMechanicsRenderer.systemPosition
                            + SIMD3(0.55, 0.05, 0))
                    renderer?.viewerInSystem = appModel.room.headPosition.map {
                        SIMD3<Float>(renderer?.displayPoint(
                            fromWorld: SIMD3<Float>($0)) ?? .zero)
                    }
                    wells?.update(dt: event.deltaTime,
                                  nearestHand: appModel.room.nearestFingertip(
                                    to: OrbitalMechanicsRenderer.systemPosition))
                    if let renderer {
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                    }
                    // Constant display offset; every instrument is a child of
                    // `renderer.root`, so the whole lab moves together.
                    renderer?.root.position = appModel.labPlacement.offset
                }
            )

            #if DEBUG
            // `-gravLagrange 1` lights the Lagrange layer and parks a body
            // at L4 — a capability, not a control (the callout appears on a
            // release near a point, which the simulator cannot pinch).
            if UserDefaults.standard.bool(forKey: "gravLagrange") {
                model.showLagrangePoints = true
                if let host = model.bodies.dropFirst().first {
                    model.select(id: host.id)
                }
                if let target = model.lagrangePoints.first(where: { $0.name == "L4" })
                    ?? model.lagrangePoints.first,
                   let mover = model.bodies.first(where: {
                       $0.id != model.primaryBody?.id
                           && $0.id != model.selectedBody?.id
                   }) {
                    let display = target.position * model.simToDisplay
                    model.grab(id: mover.id, at: display, timestamp: 0)
                    model.hold(id: mover.id, at: display, timestamp: 0.05)
                    model.release(id: mover.id, timestamp: 0.1)
                }
            }
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
            // `-gravClock 100` sets the clock the picker would — the only CLI
            // reach to a speed, and the way to photograph the outer planets'
            // trails full in a minute rather than an afternoon.
            if let clock = UserDefaults.standard.string(forKey: "gravClock").flatMap(Double.init),
               OrbitalMechanicsModel.timeScales.contains(clock) {
                model.timeScale = clock
            }
            // `-predict 1` arms a prediction at the body's current spot; pair with
            // `-gravRing 1` to photograph the petal and its effect together.
            if UserDefaults.standard.double(forKey: "predict") > 0 {
                model.armPrediction()
            }
            // `-gravBinary 1` splits the star into a binary pair. Fired rather than
            // armed: it does not confirm, and the reshaped system is a photograph
            // of the physics.
            if UserDefaults.standard.bool(forKey: "gravBinary") {
                model.makeBinary()
            }
            // `-gravRing 1` opens the first orbiting body's control
            // ring at launch, for CLI screenshots.
            if UserDefaults.standard.bool(forKey: "gravRing"),
               let body = model.bodies.first(where: { $0.id != model.primaryBody?.id }) {
                ring.openID = body.id
            }
            // `-apsisDrag near,0.35` takes hold of an apsis and pulls it to a
            // fraction of its radius, so a screenshot shows a reshaped orbit. A
            // value argument: a bead at its default proves nothing about the
            // mapping.
            if let spec = UserDefaults.standard.string(forKey: "apsisDrag") {
                let parts = spec.split(separator: ",")
                let apsis: Apsis = parts.first == "far" ? .far : .near
                let factor = parts.count > 1 ? (Double(parts[1]) ?? 1.5) : 1.5
                if let selected = model.selectedBody
                    ?? model.bodies.first(where: { $0.id != model.primaryBody?.id }) {
                    model.select(id: selected.id)
                    if let frame = model.orbitFrame(for: selected.id),
                       model.beginOrbitEdit(bodyID: selected.id, holding: apsis) {
                        let direction = apsis == .near
                            ? frame.periapsisDirection : -frame.periapsisDirection
                        model.dragApsis(toDisplayPoint:
                            direction * frame.radius(at: apsis) * factor
                            * model.simToDisplay)
                        model.endOrbitEdit()
                    }
                }
            }
            #endif
            renderer.tick(model)
            self.renderer = renderer
        } attachments: {
            Attachment(id: Self.dataCardID) {
                OrbitalMechanicsDataCard()
                    // A readout must never intercept a pinch — this one
                    // floats over an orrery whose every body is grabbable.
                    .allowsHitTesting(false)
                    .environment(model)
            }
        }
        // An in-flight grab never gets its `onEnded` when the space closes;
        // clear it here.
        .onDisappear {
            renderer?.teardown()
            // `Bloom` is a class: a live grip would outlive the view.
            bloom.endGrip()
            drag = nil
        }
        .simultaneousGesture(
            // A tap must not become a throw: at minimumDistance 0 a tap would
            // hold, zero the velocity and release the planet at rest into the Sun.
            DragGesture(minimumDistance: 0.012)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                    if drag == nil {
                        if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                        // An orbit bead: only the selected body has a ring, so these two
                        // colliders can carry literal names.
                        if let apsis = renderer.apsis(for: value.entity),
                           let selected = model.selectedBody,
                           model.beginOrbitEdit(bodyID: selected.id, holding: apsis) {
                            drag = RelativeDrag(
                                name: apsis == .near ? OrbitRing.nearBeadName
                                                     : OrbitRing.farBeadName,
                                target: renderer.beadDisplayPoint(apsis), hand: hand)
                            return
                        }
                        if let id = wells?.pull(value.entity, at: hand) {
                            drag = RelativeDrag(name: id.uuidString,
                                                target: hand, hand: hand)
                            model.grab(id: id, at: hand)
                            return
                        }
                        var current: Entity? = value.entity
                        while let candidate = current {
                            // The prediction ghost is draggable like a
                            // body, but it moves the guess, not physics.
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
                    if drag.name == OrbitRing.nearBeadName
                        || drag.name == OrbitRing.farBeadName {
                        model.dragApsis(toDisplayPoint: drag.position(forHand: hand))
                        return
                    }
                    if drag.name == "prediction-ghost" {
                        model.movePrediction(
                            to: drag.position(forHand: hand) * model.displayToSim)
                        return
                    }
                    guard let id = UUID(uuidString: drag.name) else { return }
                    model.hold(id: id, at: drag.position(forHand: hand))
                }
                .onEnded { value in
                    defer {
                        bloom.endGrip()
                        model.endOrbitEdit()
                        drag = nil
                    }
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
                .onEnded { value in handleObjectTap(on: value.entity) }
        )
    }

    /// Points the one bloom at whichever body you tapped. Mass is the grip:
    /// pull and the planet inflates as the cube root, its pull rising live.
    private func syncBloom(renderer: OrbitalMechanicsRenderer, dt: Double) {
        let toDisplay = model.simToDisplay
        if let openID = ring.openID,
           !model.bodies.contains(where: { $0.id == openID }) {
            ring.openID = nil     // consumed by a merge or deleted
        }
        guard let uuid = ring.openID,
              let body = model.bodies.first(where: { $0.id == uuid }) else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }
        // The star's mass is a grip like every planet's, in solar masses. No
        // delete petal: deleting the Sun deletes the system.
        let isPrimary = body.id == model.primaryBody?.id
        // Where a body is now, in the system's display frame — the frame the
        // ring and the hands share.
        let center: (UUID) -> SIMD3<Float> = { id in
            model.bodies.first { $0.id == id }
                .map { SIMD3<Float>($0.body.position * model.simToDisplay) } ?? .zero
        }
        bloom.retarget(
            uuid,
            petals: isPrimary ? [] : [
                // Predict lives on the ring of the body it predicts; the Sun never
                // offers it.
                .init(name: "Predict", symbol: "scope",
                      tint: UIColor(DesignTokens.Palette.gravityAccent)) {
                    model.armPrediction()
                },
                .init(name: "Delete", symbol: "trash",
                      tint: DesignTokens.Palette.destructiveUI) {
                    model.removeBody(id: uuid)
                },
            ],
            grip: isPrimary
                ? .init(
                    name: "Mass",
                    range: OrbitalMechanicsModel.primaryMassRangeSuns,
                    read: { model.massInSuns(id: uuid) },
                    write: { model.setMass(id: uuid, suns: $0) },
                    format: { PhysicsFormat.count($0, singular: "Sun", plural: "Suns",
                                                  decimals: 2) },
                    radius: { Float(model.displayRadius(id: uuid)) },
                    stretch: .surface(
                        center: { center(uuid) },
                        radius: { Float(model.displayRadius(id: uuid)) },
                        read: { model.massInSuns(id: uuid) }))
                : .init(
                    name: "Mass",
                    range: OrbitalMechanicsModel.massRangeEarths,
                    read: { model.massInEarths(id: uuid) },
                    write: { model.setMass(id: uuid, earths: $0) },
                    // A comet (3.7 × 10⁻¹¹ Earths) or Ceres read "0.00 Earths"
                    // at two decimals — massless, which they are not.
                    format: { $0 < 0.01
                        ? PhysicsFormat.scientific($0) + " Earths"
                        : PhysicsFormat.count($0, singular: "Earth", plural: "Earths",
                                              decimals: $0 < 1 ? 2 : 0) },
                    radius: { Float(model.displayRadius(id: uuid)) },
                    stretch: .surface(
                        center: { center(uuid) },
                        radius: { Float(model.displayRadius(id: uuid)) },
                        read: { model.massInEarths(id: uuid) })))

        let viewer = appModel.room.headPosition.map {
            renderer.systemRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(body.body.position * toDisplay),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }


    /// The tap routing, out of the gesture closure so VoiceOver reaches it
    /// too.
    private func handleObjectTap(on entity: Entity) {
        if bloom.handleTap(entity) { return }
        // A tap toggles the body's ring and selects it. Matched on the body's
        // UUID, which is what the renderer names its spheres.
        var current: Entity? = entity
        while let candidate = current {
            if let id = UUID(uuidString: candidate.name),
               let body = model.bodies.first(where: { $0.id == id }) {
                // The star opens a ring too (mass is a bead) but is never selected:
                // selection means "whose orbit am I looking at".
                if body.id != model.primaryBody?.id {
                    model.select(id: body.id)
                }
                if ring.openID == body.id {
                    ring.openID = nil
                    SoundPalette.play(.releaseTick, on: entity,
                                      volume: 0.3)
                } else {
                    ring.openID = body.id
                    SoundPalette.play(.pop, on: entity, volume: 0.35)
                }
                return
            }
            current = candidate.parent
        }
        if ring.openID != nil {
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
        }
        ring.openID = nil
    
    }

}

