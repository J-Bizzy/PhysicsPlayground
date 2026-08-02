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
    /// `PhysicsCore.ThrowSampler` — shared with Projectiles and Gravity
    /// Lab, which each kept their own copy of this buffer.
    ///
    /// The 0.14 s window is inherited from the hand-rolled version this
    /// replaced; the other two used 0.12. Nothing in the old code said
    /// why, and it looks like drift rather than intent — but a bob is
    /// released out of a swing rather than flicked, so it is plausible
    /// enough to keep until someone compares the two on device. Stated
    /// here rather than diverging silently in a third file.
    @State private var handSampler = ThrowSampler(window: 0.14)

    // MARK: The instruments
    //
    // This module held SEVEN panel controls — two sliders and five
    // toggles, the largest surviving panel in the app — while the
    // interaction law (DECISIONS.md, 2026-07-29) said a display layer is
    // a labelled object in the room and a continuous quantity is a rail.
    //
    // The claim that used to stand here was worse than absent: it said
    // gravity "is a dial you turn while watching the swing stretch out in
    // front of you." There was no dial. `SpatialDial` was deleted on
    // 2026-07-29 for being relative, and gravity was a `Slider` in a
    // collapsed card three taps from the physics. It is a rail now, and
    // the sentence is finally true.

    /// What is drawn, and whether the air is real. Five plates, and the
    /// fifth is not a display layer — air resistance decides whether the
    /// swing ever stops. It earns the bank anyway: it is a labelled
    /// discrete choice, and one lone plate standing beside a bank of four
    /// is worse than one bank of five.
    @State private var layers: SpatialLayerBank?
    /// The one standing VERB in this room: rig five pendulums whose
    /// lengths step 4 % apart. It was a button in the window panel, and
    /// it is the module's signature demonstration — five bobs leaving
    /// together, drifting apart, and realigning — so it could not simply
    /// be deleted with the panel.
    ///
    /// It stands under the Well because it is the same kind of act: the
    /// well makes one pendulum, this makes five. A verb that creates
    /// belongs beside the thing you create with.
    @State private var actions: SpatialActionBank?
    /// "What if this were the Moon?" — the question the bench exists to
    /// ask, as three discs you tap rather than three buttons in a card.
    @State private var worldPicker = SpatialPicker(
        accessibilityNoun: "World",
        choices: SurfaceGravity.bodies.map {
            PickerChoice(id: $0.name, label: $0.name, symbol: "globe")
        },
        staysOpen: true,
        // A standing bank is a ROW, not a fan: the default 150° arc is
        // built for a menu that unfolds and folds away, and at that span
        // three discs spray across the swing at three different heights.
        // Same arithmetic as Gravity Lab's clock, same shape.
        layout: FanLayout(span: 50 * .pi / 180, reach: 0.30,
                          verticalScale: 0.25, lift: 0, stagger: 0))
    /// g itself, between and beyond the three worlds — 0.5 to 25 m/s²,
    /// so you can also ask what a pendulum does somewhere that is not a
    /// place. Gravity has no extent of its own here (the BOB's mass and
    /// the CABLE's length do, and both are already grips), which is
    /// exactly why it takes the app's decided form for a continuous
    /// quantity rather than an invented one.
    @State private var gravityTrack: SpatialTrackControl?
    /// Time. Not chrome: a 1.6 m pendulum has a 2.5 s period, and
    /// whether you can see the swing's shape at all is a question about
    /// this number.
    @State private var timeTrack: SpatialTrackControl?
    /// The rail a drag is currently in, if any.
    @State private var activeTrack: SpatialTrackControl?
    /// Where on Earth the bench stands — a globe you touch, not a rail.
    @State private var globe: LatitudeGlobe?
    /// The Panthéon ring: the precession as a record on the floor.
    @State private var markers: MarkerRing?
    /// How fast the frame is turned, exaggerated and disclosed.
    @State private var spinTrack: SpatialTrackControl?
    /// True while a drag is setting latitude on the globe.
    @State private var turningGlobe = false

    // Placement. Every one of these sits at the apparatus's own DEPTH
    // (z ≈ −1.08, the pivot plane) rather than at a height picked on its
    // own — the podium mistake this project has now made three times is
    // to put controls on a console BELOW the thing they belong to, where
    // they read 38° under the eye line and are simply never seen. Being
    // close magnifies the drop. The band that works is ~14°, which at
    // this depth is y ≈ 1.35.
    private static let instrumentZ: Float = -1.08
    /// Left of the swing, above the well at y = 1.30.
    private static let bankAnchor = SIMD3<Float>(-0.92, 1.58, instrumentZ)
    /// The verb plate, hanging directly beneath the Well.
    ///
    /// It takes the well's OWN x and z (-0.85, -0.95) and drops 0.22 in
    /// y, which is the whole trick: the first attempt put it on the
    /// instrument plane at z = -1.08, 13 cm behind the well, and
    /// perspective promptly slid it sideways until it sat tucked against
    /// the well orb — two objects a hand's width apart in the room
    /// reading as one smudge from where the user actually stands. Depth
    /// separation is not visual separation. Sharing the well's depth and
    /// separating in height is, from every viewpoint in the room.
    ///
    /// The drop is 0.36, not the 0.22 that looked like enough on paper.
    /// A `Well` hangs its own nameplate at `bounds.min.y - 0.034` —
    /// BELOW the preview object, not below the anchor — so the well's
    /// footprint reaches far lower than its position suggests, and at
    /// 0.22 this plate sat squarely on top of "Add pendulum".
    private static let verbAnchor = SIMD3<Float>(-0.85, 0.94, -0.95)
    private static let worldsAnchor = SIMD3<Float>(0.80, 1.56, instrumentZ)
    private static let gravityCenter = SIMD3<Float>(0.80, 1.34, instrumentZ)
    private static let timeCenter = SIMD3<Float>(0.80, 1.14, instrumentZ)
    /// Foucault's two instruments, on the far side from the layer bank.
    private static let globeAnchor = SIMD3<Float>(-1.32, 1.30, instrumentZ)
    private static let spinCenter = SIMD3<Float>(-1.32, 1.08, instrumentZ)
    /// The rails face the user, not straight down the room.
    private static let instrumentNormal = SIMD3<Float>(-0.34, 0, 0.94)

    /// Identifies the floating readout above the selected bob.
    private static let infoCardID = "pendulum-info"

    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = PendulumsRenderer()
            content.add(renderer.root)
            renderer.root.addChild(bloom.root)

            // The selected bob's numbers, finally attached.
            //
            // `infoAnchor` has been built, billboarded, added to the
            // scene and repositioned above the selected bob every frame
            // since the renderer was written — with NOTHING on it. The
            // card it was waiting for existed too, in the window panel's
            // "Numbers" dropdown. This is the wire that was never run.
            if let card = attachments.entity(for: Self.infoCardID) {
                renderer.infoAnchor.addChild(card)
            }

            // Pull a pendulum out and hang it wherever you let go. The
            // pivot lands at your fingertips, so rigging one and moving
            // one are the same gesture.
            let sources = Well([
                .init(name: "Pendulum",
                      tint: UIColor(DesignTokens.Palette.pendulumsAccent),
                      label: "Add pendulum",
                      preview: { PendulumsRenderer.pendulumPreview() },
                      position: SIMD3(-0.85, 1.30, -0.95),
                      spawn: { point in
                          model.addPendulum(at: point)
                      }),
            ])
            renderer.root.addChild(sources.root)
            wells = sources

            let bank = SpatialLayerBank(
                accent: UIColor(DesignTokens.Palette.pendulumsAccent),
                layers: [
                    .init(id: "velocity", label: "Velocity", symbol: "arrow.right",
                          isOn: { model.showVelocity },
                          toggle: { model.showVelocity.toggle() }),
                    .init(id: "acceleration", label: "Acceleration",
                          symbol: "arrow.up.right",
                          isOn: { model.showAcceleration },
                          toggle: { model.showAcceleration.toggle() }),
                    .init(id: "force", label: "Force", symbol: "arrow.down.right",
                          isOn: { model.showForces },
                          toggle: { model.showForces.toggle() }),
                    // Not a display layer, and the label says so plainly:
                    // switched off the pendulum is ideal and swings for
                    // ever, which is a statement about the physics and not
                    // about what is drawn.
                    .init(id: "friction", label: "Air resistance", symbol: "wind",
                          isOn: { model.frictionOn },
                          toggle: { model.frictionOn.toggle() }),
                    // The module's deepest switch, and the only one that
                    // changes what FRAME you are standing in rather than
                    // what is drawn or what force is applied.
                    .init(id: "foucault", label: "Earth turns",
                          symbol: "globe.europe.africa",
                          isOn: { model.foucaultOn },
                          toggle: { model.foucaultOn.toggle() }),
                ])
            renderer.root.addChild(bank.root)
            layers = bank

            let verbs = SpatialActionBank(
                accent: UIColor(DesignTokens.Palette.pendulumsAccent),
                actions: [
                    .init(id: "resonance", label: "Resonance ×5",
                          symbol: "waveform.path",
                          fire: { model.loadResonancePreset() }),
                ])
            renderer.root.addChild(verbs.root)
            actions = verbs

            renderer.root.addChild(worldPicker.root)
            worldPicker.onSelect = { name in
                guard let world = SurfaceGravity.bodies
                    .first(where: { $0.name == name }) else { return }
                model.gravity = world.gravity
            }
            // The bank is a READOUT as well as a control: the lit disc is
            // whichever world your current g matches, read from the model
            // every frame rather than remembered from the last tap — so
            // dragging the rail off Earth unlights Earth, and a reset
            // lights it again.
            worldPicker.selectedID = {
                SurfaceGravity.bodies
                    .first { abs($0.gravity - model.gravity) < 0.01 }?.name
            }

            let gravity = SpatialTrackControl(
                name: "Gravity",
                center: Self.gravityCenter,
                normal: Self.instrumentNormal,
                accent: UIColor(DesignTokens.Palette.pendulumsAccent),
                range: PendulumsModel.gravityRange,
                read: { model.gravity },
                write: { model.gravity = $0 },
                format: { String(format: "%.2f m/s²", $0) })
            renderer.root.addChild(gravity.root)
            gravityTrack = gravity

            let time = SpatialTrackControl(
                name: "Time",
                center: Self.timeCenter,
                normal: Self.instrumentNormal,
                accent: UIColor(DesignTokens.Palette.pendulumsAccent),
                range: PendulumsModel.timeScaleRange,
                read: { model.timeScale },
                write: { model.timeScale = $0 },
                format: { String(format: "%.2f×", $0) })
            renderer.root.addChild(time.root)
            timeTrack = time

            let earth = LatitudeGlobe(
                accent: UIColor(DesignTokens.Palette.pendulumsAccent))
            renderer.root.addChild(earth.root)
            globe = earth

            let spin = SpatialTrackControl(
                name: "Earth spin",
                center: Self.spinCenter,
                normal: Self.instrumentNormal,
                accent: UIColor(DesignTokens.Palette.pendulumsAccent),
                range: PendulumsModel.spinRange,
                read: { model.earthSpin },
                write: { model.earthSpin = $0 },
                // The rail states the EXAGGERATION, in the units it is
                // an exaggeration of. "×3000 Earth" is a claim a reader
                // can check against the globe's true-rate caption; a bare
                // "3000" would be a number pretending to be a measurement.
                format: { String(format: "×%.0f Earth", $0) })
            renderer.root.addChild(spin.root)
            spinTrack = spin

            // NOT `ring` — that name belongs to the bob's `RingState`,
            // and shadowing it here silently redirected `-penRing`.
            let pantheonRing = MarkerRing(
                accent: UIColor(DesignTokens.Palette.pendulumsAccent),
                count: PendulumsModel.markerCount)
            renderer.root.addChild(pantheonRing.root)
            markers = pantheonRing

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    renderer?.tick(dt: event.deltaTime, model: model)
                    wells?.update(dt: event.deltaTime)
                    syncBloom(dt: event.deltaTime)
                    let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
                    layers?.update(anchor: Self.bankAnchor,
                                   viewer: viewer, dt: event.deltaTime)
                    actions?.update(anchor: Self.verbAnchor,
                                    viewer: viewer, dt: event.deltaTime)
                    worldPicker.update(anchor: Self.worldsAnchor,
                                       viewer: viewer, dt: event.deltaTime)
                    // Nothing ticks a track by itself — the caller's duty,
                    // stated on `SpatialTrackControl.refresh`. Without
                    // these two lines the beads would keep showing the
                    // value they were last dragged to while Reset moved
                    // the model out from under them.
                    gravityTrack?.refresh()
                    timeTrack?.refresh()

                    // Foucault's instruments exist only while the Earth
                    // is turning — an unlit globe beside a bench that is
                    // not in a rotating frame would be a control over
                    // nothing. `isEnabled` also kills a drag in flight.
                    globe?.root.isEnabled = model.foucaultOn
                    markers?.root.isEnabled = model.foucaultOn
                    spinTrack?.isEnabled = model.foucaultOn
                    if model.foucaultOn {
                        globe?.update(
                            anchor: Self.globeAnchor,
                            latitudeDegrees: model.latitudeDegrees,
                            trueDegreesPerHour: model.truePrecessionDegreesPerHour,
                            truePeriodHours: model.truePrecessionHours)
                        spinTrack?.refresh()
                        // The ring lies on the floor under the first
                        // pendulum's pivot — the bob sweeps over it.
                        if let first = model.pendulums.first {
                            markers?.update(
                                center: SIMD3<Float>(
                                    Float(first.pivot.x), 0.002,
                                    Float(first.pivot.z)),
                                ringRadius: Float(PendulumsModel.markerRingRadius),
                                standing: model.standingMarkers,
                                originAngle: model.markerOriginAngle)
                        }
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
            // `-penRing 1` opens the first bob's control ring at
            // launch, for CLI screenshots.
            if UserDefaults.standard.bool(forKey: "penRing"),
               let first = model.pendulums.first {
                ring.openID = first.id
            }
            // NO `-penResonance`, deliberately. Every other instrument
            // here gets an argument because its state is invisible until
            // something sets it. The Resonance plate is the opposite: it
            // stands lit and labelled at launch with nothing to reveal,
            // and `reset()` already calls `loadResonancePreset()`, so the
            // five stepped bobs ARE the opening state. An argument that
            // fired it would change nothing on screen and photograph as
            // proof of a mapping it never exercised — the "bead parked at
            // its default" mistake CLAUDE.md records against the field
            // module. The plate's tap path is covered by
            // `SpatialActionBankTests` instead, and its placement by the
            // launch screenshot.
            //
            // The instruments are all pinch-operated, and the simulator
            // has no hands — so each one gets an argument that sets a
            // VALUE rather than a flag. A bead parked at its default in
            // every screenshot proves the rail rendered and nothing at
            // all about the mapping behind it, which is the mistake
            // CLAUDE.md already records against the field module.
            //
            // `-penGravity 1.62` puts the bench on the Moon, which should
            // light the Moon disc on the standing bank as well as moving
            // the rail's bead — the two are one readout.
            let forcedGravity = UserDefaults.standard.double(forKey: "penGravity")
            if forcedGravity > 0 {
                model.gravity = min(max(forcedGravity,
                                        PendulumsModel.gravityRange.lowerBound),
                                    PendulumsModel.gravityRange.upperBound)
            }
            // `-penTime 0.25` for the time rail.
            let forcedTime = UserDefaults.standard.double(forKey: "penTime")
            if forcedTime > 0 {
                model.timeScale = min(max(forcedTime,
                                          PendulumsModel.timeScaleRange.lowerBound),
                                      PendulumsModel.timeScaleRange.upperBound)
            }
            // `-penLayers 1` lights every plate on the bank, so one shot
            // shows all five lamps and all five labels rather than the
            // two that happen to be on by default.
            // `-penFoucault 48.85` stands the bench at a latitude with
            // the Earth turning — the only way to see the globe, the
            // spin rail or the marker ring at all, since all three are
            // hidden until the frame is rotating. A VALUE, so a
            // screenshot proves the sine law moved something.
            if UserDefaults.standard.object(forKey: "penFoucault") != nil {
                model.foucaultOn = true
                let latitude = UserDefaults.standard.double(forKey: "penFoucault")
                model.latitudeDegrees = min(
                    max(latitude, PendulumsModel.latitudeRange.lowerBound),
                    PendulumsModel.latitudeRange.upperBound)
            }
            // `-penSpin 20000` winds the frame up so a short screenshot
            // run fells a visible arc of markers.
            if UserDefaults.standard.object(forKey: "penSpin") != nil {
                let spin = UserDefaults.standard.double(forKey: "penSpin")
                model.earthSpin = min(max(spin, PendulumsModel.spinRange.lowerBound),
                                      PendulumsModel.spinRange.upperBound)
            }
            if UserDefaults.standard.bool(forKey: "penLayers") {
                model.showVelocity = true
                model.showAcceleration = true
                model.showForces = true
                model.frictionOn = true
            }
            #endif
            self.renderer = renderer
        } attachments: {
            Attachment(id: Self.infoCardID) {
                PendulumInfoCard()
                    // An attachment carries a collider for its content.
                    // A readout that intercepted a pinch would be
                    // `SpatialScaleHandle` all over again — and this one
                    // floats directly above a bob you are meant to grab.
                    .allowsHitTesting(false)
                    // The environment does NOT flow into an attachment
                    // the way it flows down a view tree; `makeControls`
                    // got the model because the shell injected it, and
                    // nothing injects it here.
                    .environment(model)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                    // A gesture already in a rail may not be re-claimed: a
                    // drag that starts on the time rail and wanders over a
                    // bob must not start swinging the bob.
                    if let track = activeTrack {
                        guard track.isEnabled else {
                            activeTrack = nil
                            return
                        }
                        track.adjust(hand: hand)
                        return
                    }
                    if turningGlobe {
                        guard let globe, globe.root.isEnabled else {
                            turningGlobe = false
                            return
                        }
                        model.latitudeDegrees = globe.latitude(forHand: hand)
                        return
                    }
                    if drag == nil {
                        for track in [gravityTrack, timeTrack, spinTrack]
                            .compactMap({ $0 })
                        where track.owns(value.entity) {
                            activeTrack = track
                            track.adjust(hand: hand)
                            return
                        }
                        if let globe, globe.root.isEnabled,
                           globe.owns(value.entity) {
                            turningGlobe = true
                            model.latitudeDegrees = globe.latitude(forHand: hand)
                            return
                        }
                        if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) {
                            // Hold the swing still for the length edit.
                            // The bead rides the bob, and the bob was
                            // sweeping past at about a metre a second
                            // while you tried to pinch it — the one
                            // grip in the app whose handle runs away
                            // from the hand reaching for it.
                            if let id = ring.openID { model.beginGrab(id: id) }
                            return
                        }
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
                                handSampler.reset()
                                handSampler.record(pendulum.bobWorld,
                                                   at: Date.timeIntervalSinceReferenceDate)
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
                    handSampler.record(world, at: Date.timeIntervalSinceReferenceDate)
                }
                .onEnded { value in
                    // `bloom.endGrip()` — every other module in the app
                    // called it and this one never did. `gripDrag` then
                    // stayed non-nil forever after the first touch of a
                    // length bead, which made `updateGrip` claim EVERY
                    // subsequent drag in the scene: grabbing a bob,
                    // re-hanging a pivot, pulling one out of the well
                    // all silently became length edits on whatever the
                    // ring had last been open on. One missing line.
                    if turningGlobe {
                        turningGlobe = false
                        return
                    }
                    if let track = activeTrack {
                        track.endAdjust()
                        activeTrack = nil
                        return
                    }
                    let wasGripping = bloom.isGripping
                    bloom.endGrip()
                    defer {
                        renderer?.grabbedID = nil
                        drag = nil
                        handSampler.reset()
                    }
                    if wasGripping {
                        // Hand the swing back exactly as it was. Not
                        // `.zero`: `release` writes the velocity it is
                        // given, so releasing a length bead with zero
                        // would stop a pendulum dead every time anyone
                        // adjusted its cable — and `setLength` goes to
                        // some trouble to keep the swing running through
                        // the edit, which is the lesson (the period
                        // changes, the motion does not restart).
                        if let id = ring.openID,
                           let pendulum = model.pendulums.first(where: { $0.id == id }) {
                            model.release(id: id,
                                          handVelocity: pendulum.state.velocity)
                        }
                        return
                    }
                    guard let drag, let id = UUID(uuidString: drag.name) else { return }
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    let world = drag.position(forHand: hand)
                    model.moveGrabbed(id: id, toWorld: world)
                    // The release point is part of the throw, so it goes
                    // into the sampler before the velocity is read.
                    let now = Date.timeIntervalSinceReferenceDate
                    handSampler.record(world, at: now)
                    model.release(id: id,
                                  handVelocity: handSampler.velocity(at: now) ?? .zero)
                }
        )
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // The instruments get first refusal, before the
                    // fall-through that folds the ring away — otherwise
                    // tapping a switch plate would also close whatever
                    // bob ring was open.
                    if worldPicker.handleTap(value.entity) { return }
                    if layers?.handleTap(value.entity) == true { return }
                    if actions?.handleTap(value.entity) == true { return }
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
                .init(name: "Mass", symbol: "scalemass",
                      tint: UIColor(white: 0.45, alpha: 1)) {
                    // Cycle light → medium → heavy → light. The period
                    // doesn't change — which is the lesson.
                    let masses = [0.5, 1.5, 3.0]
                    let current = model.pendulums.first(where: { $0.id == uuid })?.mass ?? 1
                    let next = masses.first(where: { $0 > current + 0.01 }) ?? masses[0]
                    model.setMass(id: uuid, next)
                },
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
///
/// It hangs on `PendulumsRenderer.infoAnchor`, which is billboarded and
/// re-pointed at the selected bob every frame. It was written for the
/// window panel's "Numbers" dropdown and rendered nowhere else; the
/// anchor was built for it and carried nothing. They are connected now.
///
/// TWO of its four numbers change every frame — θ and v — which is the
/// cost `Callout.minimumInterval` exists to bound for text meshes. The
/// same argument applies to an attachment, whose content is rasterised
/// into a texture: what matters is how often the RENDERED OUTPUT
/// changes, not how often `body` runs. So every value is quantised to
/// the precision it is displayed at, and the strings are built from the
/// quantised numbers rather than by handing raw doubles to a format
/// specifier. A bob swinging at 1.2345 m/s then redraws when the reading
/// changes, roughly ten times a second, instead of ninety.
struct PendulumInfoCard: View {
    @Environment(PendulumsModel.self) private var model

    var body: some View {
        if let pendulum = model.selected {
            let speed = (simd_length(pendulum.state.velocity) * 100).rounded() / 100
            let degrees = (pendulum.state.angle(length: pendulum.length)
                           * 180 / .pi).rounded()
            let length = (pendulum.length * 100).rounded() / 100
            let period = (pendulum.period(gravity: model.gravity) * 100).rounded() / 100
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: "L %.2f m   T %.2f s", length, period))
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                Text(String(format: "θ %.0f°   v %.2f m/s", degrees, speed))
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // A card in a ROOM, not on a panel: it has to hold its shape
            // against a sunlit wall, a dark studio, and whatever the
            // user's furniture is doing behind it.
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}
