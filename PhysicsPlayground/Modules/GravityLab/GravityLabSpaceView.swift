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
    /// Which body's ring is open — shared by the tap gesture and the
    /// render loop (see RingState's header for why it's a reference).
    @State private var ring = RingState()
    @State private var wells: Well?
    /// The display layers, as switch plates standing beside the system.
    ///
    /// Six of them, and the sixth is the point: the acceleration vector
    /// has been read by the renderer, defaulted to false and given no
    /// control ANYWHERE since it was written. The arrow, its log scaling
    /// and its legend entry all existed for something no user could turn
    /// on. A bank is a readout as well as a control, which is why this
    /// one does not fold.
    @State private var layers: SpatialLayerBank?
    /// Newton's G, as a rail under the switch bank.
    ///
    /// The one quantity in this module with NO physical extent — it is a
    /// constant of nature, not a size — which is precisely why it gets
    /// the app's decided form for a continuous quantity rather than an
    /// invented one. Under `root`, unscaled: `SpatialTrackControl`'s own
    /// header says a track must never be scaled, because its collider is
    /// a box sized to the rail and scaling it makes that box a region.
    @State private var gravityTrack: SpatialTrackControl?
    /// The rail's live drag, if any.
    @State private var activeTrack: SpatialTrackControl?
    /// The last `model.viewResetNonce` this view acted on, so Reset also
    /// snaps the two-hand scale and turn back to 1x.
    @State private var seenResetNonce = 0
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
    /// The clock: 1× / 5× / 20× / 100×, standing beside the system as a
    /// permanent bank rather than hiding behind a pinch.
    ///
    /// This one looks like display chrome and is not. At 1× an Earth year
    /// takes about two minutes, so the speed is what decides whether an
    /// orbit is a thing you watch or a thing you wait for — Neptune at 1×
    /// is a planet that appears not to move. It stays open because it is
    /// also a READOUT: the bank shows which speed you are running.
    @State private var clockPicker = SpatialPicker(
        accessibilityNoun: "Clock speed",
        choices: GravityLabModel.timeScales.map {
            PickerChoice(id: String(Int($0)), label: "\(Int($0))×",
                         symbol: "clock")
        },
        staysOpen: true,
        // A bank is a ROW, not a fan. The default 150° arc is built for a
        // menu that unfolds and folds away, and a screenshot showed why it
        // is wrong here: four discs at ±75° and ±25° spray across the
        // orrery at four different heights, reading as scattered debris
        // rather than as one instrument. Narrowing the span to 50° and
        // flattening the vertical squash to 0.25 lays them out as a
        // shallow, tidy row — the same arithmetic, different shape.
        layout: FanLayout(span: 50 * .pi / 180, reach: 0.30,
                          verticalScale: 0.25, lift: 0, stagger: 0))
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            let renderer = GravityLabRenderer()
            content.add(renderer.root)

            // Under `root`, NOT `viewRoot`: the scale rig reaches 9×, and
            // a control that grew to nine times its size along with the
            // solar system would be a 0.45 m clock face.
            // Under `root`, NOT `viewRoot`, for the reason the clock
            // bank gives below: a switch that grew nine times along with
            // the solar system would put its own plates out of reach the
            // moment you used them.
            let bank = SpatialLayerBank(
                accent: UIColor(DesignTokens.Palette.gravityAccent),
                layers: [
                    .init(id: "grid", label: "Spacetime grid", symbol: "grid",
                          isOn: { model.showSpacetimeGrid },
                          toggle: { model.showSpacetimeGrid.toggle() }),
                    .init(id: "sweep", label: "Kepler sweep", symbol: "triangle",
                          isOn: { model.keplerSweepOn },
                          toggle: { model.keplerSweepOn.toggle() }),
                    .init(id: "particles", label: "Field flow", symbol: "sparkles",
                          isOn: { model.showFieldParticles },
                          toggle: { model.showFieldParticles.toggle() }),
                    .init(id: "velocity", label: "Velocity", symbol: "arrow.right",
                          isOn: { model.showVelocityVector },
                          toggle: { model.showVelocityVector.toggle() }),
                    .init(id: "acceleration", label: "Acceleration",
                          symbol: "arrow.up.right",
                          isOn: { model.showAccelerationVector },
                          toggle: { model.showAccelerationVector.toggle() }),
                    .init(id: "force", label: "Force", symbol: "arrow.down.right",
                          isOn: { model.showForceVector },
                          toggle: { model.showForceVector.toggle() }),
                    // The door onto `PhysicsCore.Lagrange`, which has
                    // solved this correctly and been unreachable since it
                    // was written. Shows L1–L5 for the SELECTED planet
                    // against the Sun — so it is Jupiter's Trojan points
                    // when Jupiter is selected, and Sun–Earth L2 (where
                    // JWST is) when Earth is.
                    .init(id: "lagrange", label: "Lagrange points",
                          symbol: "circlebadge.2",
                          isOn: { model.showLagrangePoints },
                          toggle: { model.showLagrangePoints.toggle() }),
                ])
            renderer.root.addChild(bank.root)
            layers = bank

            let gravity = SpatialTrackControl(
                name: "Gravity",
                center: GravityLabRenderer.systemPosition
                    + SIMD3(-0.62, -0.19, 0),
                normal: SIMD3(0.62, 0, 0.50),
                accent: UIColor(DesignTokens.Palette.gravityAccent),
                range: 0.2...4.0,
                read: { model.gMultiplier },
                write: { model.gMultiplier = $0 },
                format: { String(format: "%.2f × G", $0) })
            renderer.root.addChild(gravity.root)
            gravityTrack = gravity

            renderer.root.addChild(clockPicker.root)
            clockPicker.onSelect = { id in
                guard let scale = Double(id) else { return }
                model.timeScale = scale
            }
            // The bank has claimed to be a READOUT since it was built, and
            // was not one: four identical discs, nothing lit, no way to see
            // which speed was running without inferring it from how fast
            // Neptune moved. One closure makes the claim true, and it reads
            // from the model rather than remembering a choice, so a reset
            // moves the lit disc too.
            clockPicker.selectedID = { String(Int(model.timeScale)) }

            // Pull a world out of the well and let go: it arrives at
            // rest beside the primary and immediately begins to fall,
            // so where you release it decides whether it is captured or
            // plunges. Making a planet and aiming it are one gesture.
            let sources = Well([
                .init(name: "World", tint: UIColor(red: 0.55, green: 0.72, blue: 1, alpha: 1),
                      label: "Add world",
                      preview: { GravityLabRenderer.worldPreview() },
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
            // The well is an INSTRUMENT, not an object in the sky: it
            // keeps its size and its place in the room whatever the rig
            // does. Without this it becomes a 29 cm ball five metres to
            // the left at 9x — the module's one creation affordance,
            // out of reach exactly when you are inside the system and
            // most want to add something to it.
            renderer.compensateForRig(sources.root)
            wells = sources

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.step(dt: event.deltaTime)
                    renderer?.tick(model, calloutBodyID: ring.openID)
                    // Separate from the tick so the field keeps flowing
                    // even while the simulation is paused.
                    renderer?.tickFieldParticles(dt: event.deltaTime, model: model)
                    scaleRig.apply(to: renderer?.viewRoot ?? Entity())
                    // The orbit beads need both of these, and both have
                    // to be in the SYSTEM's frame: the reach rule
                    // compares a bead against a head, and the rig
                    // compensation keeps a 14 mm bead 14 mm wide at 9x
                    // instead of letting it inflate into a region.
                    // Reset means reset. The scale rig is a view
                    // transform and so cannot live on the model, but a
                    // Reset that left you at 6x and turned 40 degrees
                    // had not reset what the user was actually looking
                    // at — and `SpatialScaleRig.reset()` had existed,
                    // unwired, the whole time.
                    if model.viewResetNonce != seenResetNonce {
                        seenResetNonce = model.viewResetNonce
                        scaleRig.reset()
                        scaleRig.apply(to: renderer?.viewRoot ?? Entity())
                    }
                    renderer?.rigScale = scaleRig.liveScale
                    renderer?.showScaleReadout(
                        scaleRig.isTransformed ? scaleRig.label : nil,
                        anchor: GravityLabRenderer.systemPosition
                            + SIMD3(0.55, 0.05, 0))
                    renderer?.viewerInSystem = appModel.room.headPosition.map {
                        SIMD3<Float>(renderer?.displayPoint(
                            fromWorld: SIMD3<Float>($0)) ?? .zero)
                    }
                    wells?.update(dt: event.deltaTime)
                    // The clock bank stands beside the system, offset to
                    // the right so it never sits on the Sun, and at ~16°
                    // below eye — the same glance as the orrery itself.
                    clockPicker.update(
                        anchor: GravityLabRenderer.systemPosition
                            + SIMD3(0.55, -0.09, 0),
                        viewer: appModel.room.headPosition.map { SIMD3<Float>($0) },
                        dt: event.deltaTime)
                    // What EXISTS is on the left, what you MAKE is on the
                    // right — the same hand rule Electric Fields lays out
                    // its instruments by, so the two modules teach one
                    // layout rather than two.
                    layers?.update(
                        anchor: GravityLabRenderer.systemPosition
                            + SIMD3(-0.62, 0.06, 0),
                        viewer: appModel.room.headPosition.map { SIMD3<Float>($0) },
                        dt: event.deltaTime)
                    // Nothing ticks a track by itself — the caller's duty,
                    // stated on `SpatialTrackControl.refresh`.
                    gravityTrack?.refresh()
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
            // `-gravRing 1` opens the first orbiting body's control
            // ring at launch, for CLI screenshots.
            if UserDefaults.standard.bool(forKey: "gravRing"),
               let body = model.bodies.first(where: { $0.id != model.primaryBody?.id }) {
                ring.openID = body.id
            }
            // `-apsisDrag near,0.35` runs one bead drag: it takes hold of
            // an apsis and pulls it to a fraction of its current radius,
            // so a screenshot shows a RESHAPED orbit rather than the one
            // the scene was born with.
            //
            // A VALUE argument, not a flag, and that is the point. A bead
            // parked at its default in every screenshot proves the bead
            // rendered and nothing whatever about the mapping behind it —
            // which is exactly the mistake CLAUDE.md records about the
            // field module's rails.
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
        }
        .simultaneousGesture(
            // A TAP MUST NOT BECOME A THROW.
            //
            // At minimumDistance 0 this gesture fires on a bare tap, and
            // the consequence in this module is catastrophic rather than
            // cosmetic: the tap runs grab → hold → release, `hold` zeroes
            // the body's velocity, and a tap carries no hand motion for
            // `ThrowSampler` to read — so the planet is released AT REST
            // and falls straight down its own radius into the Sun. Tap
            // Earth, watch Earth die.
            //
            // It was always a landmine; it became the main path the day
            // tapping started selecting a planet and raising its orbit
            // ring. 12 mm is under a finger's width of travel — nobody
            // drags a planet that little on purpose — and it is the same
            // shape of threshold the hub already uses to stop a pinch on
            // an exhibit from being read as a carry.
            DragGesture(minimumDistance: 0.012)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                    // A gesture already in flight may not be re-claimed:
                    // a drag that starts on the rail and wanders over a
                    // planet must not begin dragging the planet.
                    if let track = activeTrack {
                        guard track.isEnabled else {
                            activeTrack = nil
                            return
                        }
                        // The rail lives under `root`, which the rig does
                        // not scale — so it reads a ROOM point, not the
                        // system-space one the bodies use.
                        track.adjust(hand: SIMD3<Double>(SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene))))
                        return
                    }
                    if drag == nil {
                        if let track = gravityTrack, track.owns(value.entity) {
                            activeTrack = track
                            track.adjust(hand: SIMD3<Double>(SIMD3<Float>(value.convert(
                                value.location3D, from: .local, to: .scene))))
                            return
                        }
                        if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                        // An orbit bead. Only the SELECTED body has a
                        // ring, so there are at most two of these
                        // colliders in the whole scene — which is why
                        // they can carry literal names the way the
                        // prediction ghost does, rather than needing a
                        // UUID to tell them apart.
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
                        activeTrack?.endAdjust()
                        activeTrack = nil
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
                .onEnded { value in
                    if clockPicker.handleTap(value.entity) { return }
                    if layers?.handleTap(value.entity) == true { return }
                    if bloom.handleTap(value.entity) { return }
                    // A tap on a body toggles its control ring; the
                    // primary keeps no ring (deleting the sun deletes
                    // the system). A tap on anything else folds it.
                    //
                    // Matched on the body's UUID, because that is what
                    // the renderer names its spheres. It used to match
                    // `$0.body.name == candidate.name` — the DISPLAY
                    // name, "Earth", "Mars" — and no entity in this
                    // scene has ever carried one. So the condition was
                    // never true, and the mass bead and delete petal
                    // could not be opened by tapping a planet at all.
                    // The drag handler two functions up got this right;
                    // the tap handler did not, and `-gravRing 1` sets
                    // `ring.openID` directly, so every screenshot of the
                    // ring was taken down a path no user can walk.
                    // A TAP ALSO SELECTS, and until now it did not.
                    //
                    // `select(id:)` was reachable only from a DEBUG
                    // launch argument, so the one user path to a
                    // selection was to grab a body and drag it — which
                    // freezes it and zeroes its velocity, destroying the
                    // orbit you were about to study. Selection drives the
                    // vectors, the Kepler sweep, the Predict button's
                    // enabled state, the notebook rows and now the orbit
                    // ring, and the Prophet experiment's own step text
                    // says "Tap a planet to select it" — describing an
                    // interaction that did not exist.
                    var current: Entity? = value.entity
                    while let candidate = current {
                        if let id = UUID(uuidString: candidate.name),
                           let body = model.bodies.first(where: { $0.id == id }) {
                            // The star opens a ring too now — it has a
                            // mass, and mass is a bead. It is never
                            // SELECTED, though: selection means "whose
                            // orbit am I looking at", and the focus of
                            // every orbit has none of its own.
                            if body.id != model.primaryBody?.id {
                                model.select(id: body.id)
                            }
                            if ring.openID == body.id {
                                ring.openID = nil
                            } else {
                                ring.openID = body.id
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

    /// Points the one bloom at whichever body you tapped.
    /// Mass IS the grip: pull and the planet inflates, because a
    /// sphere's radius goes as the cube root of its mass — and its
    /// pull on everything around it rises live as you do it.
    private func syncBloom(renderer: GravityLabRenderer, dt: Double) {
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
        // THE STAR GETS A BEAD, AND THE SLIDER GOES. Its mass was a
        // slider in a window while every planet's was a bead on the
        // planet — the same quantity, in the same scene, with two
        // different grammars. Mass has physical extent (the star
        // visibly inflates as the cube root), so by the interaction law
        // it is changed by changing that extent.
        //
        // No delete petal, for the obvious reason: deleting the Sun
        // deletes the system. And its bead is calibrated in SOLAR
        // masses, because a star measured in Earths reads "333000".
        let isPrimary = body.id == model.primaryBody?.id
        bloom.retarget(
            uuid,
            petals: isPrimary ? [] : [
                .init(name: "Delete", symbol: "trash",
                      tint: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)) {
                    model.removeBody(id: uuid)
                },
            ],
            grip: isPrimary
                ? .init(
                    name: "Mass",
                    range: GravityLabModel.primaryMassRangeSuns,
                    read: { model.massInSuns(id: uuid) },
                    write: { model.setMass(id: uuid, suns: $0) },
                    format: { String(format: "%.2f Suns", $0) },
                    radius: { Float(model.displayRadius(id: uuid)) + 0.05 })
                : .init(
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

