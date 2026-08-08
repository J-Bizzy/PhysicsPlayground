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
    /// The module's two standing verbs — "Twin suns", and the plate that
    /// opens the preset worlds. Both were window buttons; "Twin suns" is
    /// also the target of an authored experiment (`gravity.binary`), so
    /// deleting it with the panel would have broken content.
    @State private var verbs: SpatialActionBank?
    /// The ten preset worlds, as a fan the "Worlds" plate opens.
    ///
    /// A momentary fan, NOT a standing bank: the clock bank and the
    /// layers bank stay open because they are readouts — which speed am
    /// I running, what is drawn — and a list of things you could add
    /// reports nothing. It folds away when it is done, the same grammar
    /// as Projectiles' Balls petal.
    @State private var worldPicker = SpatialPicker(
        accessibilityNoun: "Preset world",
        choices: GravityLabModel.Preset.allCases.map {
            PickerChoice(id: $0.id, label: $0.displayName, symbol: "globe")
        },
        staysOpen: false,
        accent: UIColor(DesignTokens.Palette.gravityAccent),
        // TEN discs, the most any fan in this app carries, and the
        // geometry is measured rather than inherited.
        //
        // A `SpatialPicker` disc is 0.026 m in radius and its touch
        // target `SpatialPicker.colliderSpan` is 0.068 m across, so the
        // pitch that keeps ten of them from overlapping — colliders, not
        // just paint, since hit-testing uses the former — is about
        // 0.08 m. Ten discs therefore need ~0.8 m of arc, and
        // `arc = reach × span`: 0.58 m at 120° gives 1.21 m of arc and
        // ~0.12 m of pitch, which clears the labels too.
        //
        // The first attempt was 150° over 0.62 m ANCHORED ON THE CLOCK
        // BANK'S FLANK, and a screenshot showed both halves of why that
        // was wrong: the arc threw its far discs off the bottom-right of
        // the frame, and its near discs climbed into the clock bank's
        // own row. A fan this wide cannot hang off a flank — it has to
        // open into the empty space under the system, centred, where its
        // width is symmetric about the thing it adds to.
        layout: FanLayout(span: 120 * .pi / 180, reach: 0.58,
                          verticalScale: 0.22, lift: 0, stagger: 0))
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
    /// The clock: −20× / −1× / 1× / 5× / 20× / 100×, standing beside the
    /// system as a permanent bank rather than hiding behind a pinch.
    /// (Six since 2026-08-07 — the two reverse scales were added and
    /// this comment still said four until the fan was re-derived.)
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
        // is wrong here: discs at ±75° and ±25° spray across the orrery
        // at four different heights, reading as scattered debris rather
        // than as one instrument. Flattening the vertical squash to 0.25
        // lays them out as a shallow, tidy row.
        //
        // THE SPAN IS DERIVED, NOT TYPED, and that is the fix for
        // 2026-08-07. It was 50°, hand-tuned against FOUR discs and
        // reasoned about as four in the comment that used to sit here.
        // `timeScales` then grew to six and nothing widened: end-pair
        // centres sat 0.0494 m apart against a 0.068 m touch target, so
        // aiming at 1× could select −1× and run the solar system
        // backwards. Asking `FanLayout` for a span that fits the count
        // means the next scale added to the array widens the bank
        // instead of jamming it.
        layout: FanLayout.spread(
            count: GravityLabModel.timeScales.count,
            itemSpan: Double(SpatialPicker.colliderSpan),
            reach: 0.34, verticalScale: 0.25, lift: 0, stagger: 0))
    /// THE CLOCK, FOLDED — and the reason folding it is legitimate.
    ///
    /// The picker below stays open because it is a READOUT: which speed
    /// you are running is the difference between an orbit you can watch
    /// and one you cannot. That argument is right, and it is exactly
    /// what `SummonHandle.summary` answers — the tab reads "Clock · 5×",
    /// which is the same fact the six discs were carrying, in one object
    /// instead of six. Six became fourteen centimetres wider on
    /// 2026-08-07 when the fan was re-derived to fit its own touch
    /// targets, which is what made this urgent.
    @State private var clockHandle = SummonHandle(
        title: "Clock", symbol: "clock",
        accent: UIColor(DesignTokens.Palette.gravityAccent))

    /// The second row: Kepler sweep and the Lagrange points.
    ///
    /// Both are ANALYSIS — overlays you switch on to study something
    /// specific and then switch off again — as against the grid and the
    /// field flow, which are how the system is drawn. Two plates behind
    /// a door, and the door says which of them are on.
    @State private var analysisHandle = SummonHandle(
        title: "Analysis", symbol: "chart.xyaxis.line",
        accent: UIColor(DesignTokens.Palette.gravityAccent))
    /// The plates the Analysis handle unfolds.
    @State private var analysis: SpatialLayerBank?

    /// Velocity, acceleration and force — the arrows drawn ON the
    /// selected body.
    ///
    /// THE GOAL SAID PUT THESE ON THE BODY'S BLOOM RING, and the code
    /// says otherwise, so they are here instead. Two reasons, and the
    /// first is the one that matters: `showVelocityVector` and its two
    /// siblings are GLOBAL flags. The renderer draws the arrows on
    /// whichever body is selected, but the switch is not a property of
    /// that body — put it on a per-body ring and toggling it for Earth
    /// silently changes what Jupiter shows, which is a control that lies
    /// about its own scope. (Second, and minor: the ring already carries
    /// Predict and Delete, and `Bloom.Petal`'s own ceiling is "two or
    /// three per object, never more".)
    ///
    /// So the audit's diagnosis is right — three per-body annotations
    /// had no business on a bank beside system-wide overlays — and its
    /// prescription is not. They are their own group, behind their own
    /// door, which says which of them are on.
    @State private var vectorsHandle = SummonHandle(
        title: "Vectors", symbol: "arrow.up.right",
        accent: UIColor(DesignTokens.Palette.gravityAccent))
    @State private var vectors: SpatialLayerBank?

    /// Identifies the floating readout above the selected body.
    private static let dataCardID = "gravity-data"

    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = GravityLabRenderer()
            content.add(renderer.root)

            // HANDS-FREE ROUTES FOR THE TWO CONTROLS THAT ARE ONLY EVER
            // DRAGGED. Both mirror a debug argument that already exists,
            // so neither is an invented interaction: a bead step is
            // `-apsisDrag near|far,<factor>` at 10% per step, and the
            // ghost steps along its own radius from the star.
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

            // The selected body's orbit and energy, on the body.
            //
            // `selectedAnchor` sits under `systemRoot`, which the scale
            // rig drives between 0.4× and 9×, so the card has to be
            // compensated or it is a postage stamp when you step back
            // and a billboard when you walk in. Same call the creation
            // well makes, for the same reason.
            if let card = attachments.entity(for: Self.dataCardID) {
                stripInput(from: card)
                renderer.selectedAnchor.addChild(card)
                renderer.compensateForRig(card)
            }

            // Under `root`, NOT `viewRoot`: the scale rig reaches 9×, and
            // a control that grew to nine times its size along with the
            // solar system would be a 0.45 m clock face.
            // Under `root`, NOT `viewRoot`, for the reason the clock
            // bank gives below: a switch that grew nine times along with
            // the solar system would put its own plates out of reach the
            // moment you used them.
            // TWO PLATES, not seven. (Owner, 2026-08-07: this module
            // is "way too cluttered".)
            //
            // What is left here is what the SYSTEM is drawn with — the
            // grid it curves and the flow through it. The other five
            // left for two different reasons, and the reasons are
            // different kinds of wrong:
            //
            // · velocity / acceleration / force are PER-BODY
            //   annotations. They were sitting on a system-wide bank
            //   beside system-wide overlays, which is a category error:
            //   "show the force" is a question about the planet you have
            //   selected, and the selected body's control ring already
            //   exists to answer questions about it. They are petals on
            //   that ring now.
            // · Kepler sweep and Lagrange points are ANALYSIS — things
            //   you switch on to study something and off again. They are
            //   behind the Analysis handle, which says which of them are
            //   on, so folding them costs no readout.
            let bank = SpatialLayerBank(
                accent: UIColor(DesignTokens.Palette.gravityAccent),
                layers: [
                    .init(id: "grid", label: "Spacetime grid", symbol: "grid",
                          isOn: { model.showSpacetimeGrid },
                          toggle: { model.showSpacetimeGrid.toggle() }),
                    .init(id: "particles", label: "Field flow", symbol: "sparkles",
                          isOn: { model.showFieldParticles },
                          toggle: { model.showFieldParticles.toggle() }),
                ])
            renderer.root.addChild(bank.root)
            layers = bank

            // The second row, folded away behind the Analysis handle.
            // The door onto `PhysicsCore.Lagrange`, which has solved
            // this correctly and been unreachable since it was written,
            // shows L1–L5 for the SELECTED planet against the Sun — so
            // it is Jupiter's Trojan points when Jupiter is selected,
            // and Sun–Earth L2 (where JWST is) when Earth is.
            let analysisBank = SpatialLayerBank(
                accent: UIColor(DesignTokens.Palette.gravityAccent),
                layers: [
                    .init(id: "sweep", label: "Kepler sweep", symbol: "triangle",
                          isOn: { model.keplerSweepOn },
                          toggle: { model.keplerSweepOn.toggle() }),
                    .init(id: "lagrange", label: "Lagrange points",
                          symbol: "circlebadge.2",
                          isOn: { model.showLagrangePoints },
                          toggle: { model.showLagrangePoints.toggle() }),
                ])
            renderer.root.addChild(analysisBank.root)
            analysis = analysisBank

            // The handles' summaries are what make folding honest: each
            // reads out the state of what it hides, every frame.
            analysisHandle.summary = {
                let on = [model.keplerSweepOn ? "sweep" : nil,
                          model.showLagrangePoints ? "Lagrange" : nil]
                    .compactMap { $0 }
                return on.isEmpty ? "off" : on.joined(separator: ", ")
            }
            let vectorBank = SpatialLayerBank(
                accent: UIColor(DesignTokens.Palette.gravityAccent),
                layers: [
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
                ])
            renderer.root.addChild(vectorBank.root)
            vectors = vectorBank
            vectorsHandle.summary = {
                let on = [model.showVelocityVector ? "v" : nil,
                          model.showAccelerationVector ? "a" : nil,
                          model.showForceVector ? "F" : nil].compactMap { $0 }
                return on.isEmpty ? "off" : on.joined(separator: " ")
            }
            renderer.root.addChild(vectorsHandle.root)
            clockHandle.summary = { "\(Int(model.timeScale))×" }
            renderer.root.addChild(clockHandle.root)
            renderer.root.addChild(analysisHandle.root)

            // The two verbs, under `root` like every other instrument
            // here — the scale rig reaches 9×, and a control that grew
            // with the solar system would put itself out of reach
            // exactly when you had walked into the system to use it.
            // That mistake has already been made and paid for by the
            // well, which is why `compensateForRig` exists.
            let systemVerbs = SpatialActionBank(
                accent: UIColor(DesignTokens.Palette.gravityAccent),
                actions: [
                    .init(id: "worlds", label: "Worlds", symbol: "globe",
                          fire: { worldPicker.toggle() }),
                    .init(id: "binary", label: "Twin suns", symbol: "sun.max",
                          fire: { model.makeBinary() }),
                ])
            renderer.root.addChild(systemVerbs.root)
            verbs = systemVerbs

            renderer.root.addChild(worldPicker.root)
            worldPicker.onSelect = { id in
                guard let preset = GravityLabModel.Preset(rawValue: id) else { return }
                model.spawn(preset)
            }

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
                    wells?.update(dt: event.deltaTime,
                                  nearestHand: appModel.room.nearestFingertip(
                                    to: GravityLabRenderer.systemPosition))
                    // The clock bank stands beside the system, offset to
                    // the right so it never sits on the Sun, and at ~16°
                    // below eye — the same glance as the orrery itself.
                    let head = appModel.room.headPosition.map { SIMD3<Float>($0) }
                    let clockAnchor = GravityLabRenderer.systemPosition
                        + SIMD3<Float>(0.55, -0.09, 0)
                    let hand = appModel.room.nearestFingertip(to: clockAnchor)
                    // The TAB stands where the fan used to; the fan
                    // unfolds above it only when asked.
                    clockHandle.update(anchor: clockAnchor, viewer: head,
                                       dt: event.deltaTime, nearestHand: hand)
                    clockPicker.root.isEnabled = clockHandle.isOpen
                    if clockHandle.isOpen {
                        clockPicker.update(
                            anchor: clockAnchor + SIMD3(0, 0.13, 0),
                            viewer: head,
                            dt: event.deltaTime)
                    }
                    // What EXISTS is on the left, what you MAKE is on the
                    // right — the same hand rule Electric Fields lays out
                    // its instruments by, so the two modules teach one
                    // layout rather than two.
                    let bankAnchor = GravityLabRenderer.systemPosition
                        + SIMD3<Float>(-0.62, 0.06, 0)
                    layers?.update(anchor: bankAnchor, viewer: head,
                                   dt: event.deltaTime)
                    Recession.apply(to: layers?.root ?? Entity(),
                                    anchor: bankAnchor, nearestHand: hand)
                    // The Analysis handle sits under the two plates it
                    // is a sibling of, and its own row unfolds below it.
                    let analysisAnchor = bankAnchor + SIMD3<Float>(0, -0.115, 0)
                    analysisHandle.update(anchor: analysisAnchor, viewer: head,
                                          dt: event.deltaTime, nearestHand: hand)
                    analysis?.root.isEnabled = analysisHandle.isOpen
                    if analysisHandle.isOpen {
                        analysis?.update(anchor: analysisAnchor + SIMD3(0, -0.105, 0),
                                         viewer: head, dt: event.deltaTime)
                    }
                    let vectorAnchor = bankAnchor + SIMD3<Float>(0, -0.230, 0)
                    vectorsHandle.update(anchor: vectorAnchor, viewer: head,
                                         dt: event.deltaTime, nearestHand: hand)
                    vectors?.root.isEnabled = vectorsHandle.isOpen
                    if vectorsHandle.isOpen {
                        vectors?.update(anchor: vectorAnchor + SIMD3(0, -0.105, 0),
                                        viewer: head, dt: event.deltaTime)
                    }
                    // Under the clock bank, on the same flank: the clock
                    // decides how fast the system runs, these decide what
                    // is IN it. Both are things you do to the system as a
                    // whole, as against the layers bank's what-is-drawn.
                    verbs?.update(
                        anchor: GravityLabRenderer.systemPosition
                            + SIMD3(0.82, -0.20, 0),
                        viewer: appModel.room.headPosition.map { SIMD3<Float>($0) },
                        dt: event.deltaTime,
                        resetNonce: appModel.resetNonce)
                    // Centred ABOVE the system, not on the plate that
                    // opens it — see the layout note on `worldPicker`.
                    // Above rather than below because below is where the
                    // floor grid and the orrery are: a fan 1.2 m of arc
                    // wide needs a band with nothing in it, and in this
                    // module that band is the sky.
                    worldPicker.update(
                        anchor: GravityLabRenderer.systemPosition
                            + SIMD3(0, 0.55, 0.30),
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
            // so the verdict flow can be screenshot-verified. (The
            // control that arms it by hand is now a petal on the
            // selected body's ring — pair this with `-gravRing 1` to
            // photograph the petal and its effect together.)
            if UserDefaults.standard.double(forKey: "predict") > 0 {
                model.armPrediction()
            }
            // `-gravBinary 1` splits the star into a binary pair, which
            // reshapes every orbit in the system at once. Unlike the two
            // Clear plates, this one is FIRED rather than armed: it does
            // not confirm, and its effect is the most visible change any
            // control in this app makes — a second sun and a system of
            // reshaped ellipses is a photograph of the physics, not of a
            // lit lamp.
            if UserDefaults.standard.bool(forKey: "gravBinary") {
                model.makeBinary()
            }
            // `-gravWorlds 1` opens the ten-preset fan, the one control
            // here that is invisible until something opens it. A fan
            // this wide is also the thing most likely to be WRONG —
            // ten discs is the most any fan in this app carries — so it
            // needs to be photographable without a hand.
            if UserDefaults.standard.bool(forKey: "gravWorlds") {
                worldPicker.toggle()
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
        } attachments: {
            Attachment(id: Self.dataCardID) {
                GravityLabDataCard()
                    // A readout must never intercept a pinch — this one
                    // floats over an orrery whose every body is grabbable.
                    .allowsHitTesting(false)
                    .environment(model)
            }
        }
        // Leaving the lab must not leave anything running or held.
        //
        // `teardown` cancels the renderer's event subscriptions and any
        // geometry job in flight (see `GeometryPipeline.cancel`), and the
        // drag state is cleared because NOTHING ELSE CAN CLEAR IT: an
        // in-flight grab that never receives its `onEnded` — the space
        // closing under it is the ordinary way that happens — otherwise
        // strands the object wherever the hand left it and re-targets
        // every later drag at the same one, with no exit but leaving.
        .onDisappear {
            renderer?.teardown()
            // A GRIP SURVIVES THE SPACE CLOSING, and that is worse than
            // it sounds. `Bloom` is a class, so `gripDrag` outlives this
            // view; left set, `updateGrip` claims EVERY subsequent drag
            // in the module and nothing at all can be grabbed. That
            // exact failure is documented in PendulumsSpaceView's
            // `onEnded` — it cost this module every one of its verbs
            // once already.
            bloom.endGrip()
            drag = nil
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
                    // The handles get first refusal — they are the
                    // doors, and a door has to answer before the room
                    // behind it.
                    if clockHandle.handleTap(value.entity) { return }
                    if analysisHandle.handleTap(value.entity) { return }
                    if vectorsHandle.handleTap(value.entity) { return }
                    if vectorsHandle.isOpen,
                       vectors?.handleTap(value.entity) == true { return }
                    if clockHandle.isOpen,
                       clockPicker.handleTap(value.entity) { return }
                    if analysisHandle.isOpen,
                       analysis?.handleTap(value.entity) == true { return }
                    if layers?.handleTap(value.entity) == true { return }
                    if worldPicker.handleTap(value.entity) { return }
                    if verbs?.handleTap(value.entity) == true { return }
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
                                SoundPalette.play(.releaseTick, on: value.entity,
                                                  volume: 0.3)
                            } else {
                                ring.openID = body.id
                                SoundPalette.play(.pop, on: value.entity, volume: 0.35)
                            }
                            return
                        }
                        current = candidate.parent
                    }
                    if ring.openID != nil {
                        SoundPalette.play(.releaseTick, on: value.entity, volume: 0.3)
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
                // "Predict an orbit", off the window panel and onto the
                // ring of the body it predicts.
                //
                // The panel button carried `.disabled(selection is nil
                // or primary)`. Here that predicate is GEOMETRY: this
                // ring only exists while a body is selected, and the
                // `isPrimary` branch above means the Sun never gets one.
                // A control that cannot be reached in the state where it
                // would be meaningless is better than one that greys out
                // — there is no disabled thing to wonder about.
                .init(name: "Predict", symbol: "scope",
                      tint: UIColor(DesignTokens.Palette.gravityAccent)) {
                    model.armPrediction()
                },
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

