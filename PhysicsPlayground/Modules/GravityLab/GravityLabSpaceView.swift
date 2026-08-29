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
    /// The display layers, as switch plates beside the system. Doesn't
    /// fold: a bank is a readout as well as a control.
    @State private var layers: SpatialLayerBank?
    /// The module's two standing verbs — "Twin suns" and the plate that
    /// opens the preset worlds.
    @State private var verbs: SpatialActionBank?
    /// The ten preset worlds, as a MOMENTARY fan (unlike the clock and
    /// layer banks, a list of things you could add reports nothing, so it
    /// folds away when done).
    @State private var worldPicker = SpatialPicker(
        accessibilityNoun: "Preset world",
        choices: GravityLabModel.Preset.allCases.map {
            PickerChoice(id: $0.id, label: $0.displayName, symbol: "globe")
        },
        staysOpen: false,
        accent: UIColor(DesignTokens.Palette.gravityAccent),
        // TEN discs, measured: colliders (`SpatialPicker.colliderSpan`
        // 0.068 m) need ~0.08 m pitch, so ten need ~0.8 m of arc.
        // arc = reach × span: 0.58 m at 120° gives 1.21 m and ~0.12 m
        // pitch, clearing the labels. Opens centred UNDER the system —
        // a fan this wide cannot hang off a flank.
        layout: FanLayout(span: 120 * .pi / 180, reach: 0.58,
                          verticalScale: 0.22, lift: 0, stagger: 0))
    /// Newton's G, as a rail under the switch bank. Lives under `root`,
    /// UNSCALED: a track's collider is a box sized to the rail, and
    /// scaling it would make that box a region.
    @State private var gravityTrack: SpatialTrackControl?
    /// The rail's live drag, if any.
    @State private var activeTrack: SpatialTrackControl?
    /// The last `model.viewResetNonce` this view acted on, so Reset also
    /// snaps the two-hand scale and turn back to 1x.
    @State private var seenResetNonce = 0
    /// Two-handed scale and turn for the whole system. Up to 9×, where
    /// Mercury's orbit is 1.75 m across and the inner system becomes a
    /// room you walk through.
    @State private var scaleRig = SpatialScaleRig(
        pivot: GravityLabRenderer.systemPosition, range: 0.4...9.0)
    /// The clock: −20× / −1× / 1× / 5× / 20× / 100×, a permanent bank.
    /// At 1× an Earth year takes ~2 minutes, so speed decides whether an
    /// orbit is watched or waited for. Stays open — it is also a readout.
    @State private var clockPicker = SpatialPicker(
        accessibilityNoun: "Clock speed",
        choices: GravityLabModel.timeScales.map {
            PickerChoice(id: String(Int($0)), label: "\(Int($0))×",
                         symbol: "clock")
        },
        staysOpen: true,
        // A bank is a ROW, not a fan: a flat vertical squash keeps the
        // discs a tidy row instead of spraying them across the orrery.
        // The span is DERIVED from the count, never typed — a hand-tuned
        // span stops fitting the moment `timeScales` grows, and overlapping
        // touch targets let a tap on 1× select −1×.
        layout: FanLayout.spread(
            count: GravityLabModel.timeScales.count,
            itemSpan: Double(SpatialPicker.colliderSpan),
            reach: 0.34, verticalScale: 0.25, lift: 0, stagger: 0))
    /// The clock, folded. Legitimate because `SummonHandle.summary` keeps
    /// the readout — the tab reads "Clock · 5×", the same fact the six
    /// discs carried, in one object.
    @State private var clockHandle = SummonHandle(
        title: "Clock", symbol: "clock",
        accent: UIColor(DesignTokens.Palette.gravityAccent))

    /// Kepler sweep and Lagrange points: ANALYSIS overlays (switched on to
    /// study, then off), as against the grid and flow, which are how the
    /// system is drawn. Behind a door that says which are on.
    @State private var analysisHandle = SummonHandle(
        title: "Analysis", symbol: "chart.xyaxis.line",
        accent: UIColor(DesignTokens.Palette.gravityAccent))
    /// The plates the Analysis handle unfolds.
    @State private var analysis: SpatialLayerBank?

    /// Velocity, acceleration and force — arrows drawn on the selected
    /// body. NOT on the body's ring: these are GLOBAL flags, so a per-body
    /// control would lie about its own scope.
    @State private var vectorsHandle = SummonHandle(
        title: "Vectors", symbol: "arrow.up.right",
        accent: UIColor(DesignTokens.Palette.gravityAccent))
    @State private var vectors: SpatialLayerBank?

    /// Identifies the floating readout above the selected body.
    private static let dataCardID = "gravity-data"

    /// LEFT — what exists. The layers bank, with the analysis and
    /// vectors handles hanging under it.
    static let bankAnchor = GravityLabRenderer.systemPosition
        + SIMD3<Float>(-0.62, 0.06, 0)

    /// LEFT AND FORE — what you make and unmake. Binary and Worlds, moved
    /// from the right flank on 2026-08-29 (all controls left, owner's
    /// call). Both offsets are FORCED: at the system's own depth the
    /// reach limit wants x ≤ 0.60 and these two instruments (0.26 and
    /// 0.09 wide) cannot both fit there, so the column comes forward —
    /// and 0.40 of z rather than the old 0.20 because the left flank,
    /// unlike the old right one, is not empty: at 0.20 this column's
    /// sightline shadow from the standing viewpoint lands on the tab
    /// column and the G rail at x −0.62. At (−0.85, z +0.40) the shadow
    /// projects to x ≤ −1.08 on the deep plane, clear of everything.
    static let verbAnchor = GravityLabRenderer.systemPosition
        + SIMD3<Float>(-0.85, 0.07, 0.40)

    /// The clock's folding tab, stacked ABOVE the verbs on their x —
    /// one column, clock at the head, clear of each other by 8.5 cm.
    /// Measured by `InstrumentReachCriterionTests`.
    static let clockAnchor = GravityLabRenderer.systemPosition
        + SIMD3<Float>(-0.85, 0.29, 0.40)

    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = GravityLabRenderer()
            renderer.onObjectTap = { handleObjectTap(on: $0) }
            content.add(renderer.root)
            // ARRIVES, NEVER APPEARS. Disabled here and raised by
            // `Fade.tick` below, so the apparatus resolves into the room
            // instead of being there between one frame and the next.
            renderer.root.isEnabled = false

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

            // Under `root`, NOT `viewRoot`: the rig reaches 9×, and a
            // control that grew with the system would put its own plates
            // out of reach. Two plates only — what the SYSTEM is drawn
            // with; per-body vectors and the analysis overlays live behind
            // their own handles.
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
                format: { PhysicsFormat.measurement($0, "× G", decimals: 2) })
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
                    // The lab's own arrival and departure, on the shell's
                    // one flag. `Fade.tick` settles to a no-op — it drops its
                    // clock and its OpacityComponent once landed — so this
                    // costs one comparison for all the frames that are not a
                    // transition.
                    if let renderer {
                        Fade.tick(renderer.root, visible: !appModel.isDeparting,
                                  duration: AppModel.departure)
                    }
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
                    let clockAnchor = Self.clockAnchor
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
                    // Every control stands on the LEFT (owner, 2026-08-29,
                    // app-wide) — what EXISTS deep at the system's flank,
                    // what you MAKE fore of it, the same depth split
                    // Electric Fields lays out its instruments by, so the
                    // two modules teach one layout rather than two.
                    let bankAnchor = Self.bankAnchor
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
                        anchor: Self.verbAnchor,
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
                    // Constant display offset — safe because grabs move a
                    // body by hand displacement. Every bank, handle, rail
                    // and picker is a child of `renderer.root`, so moving
                    // the lab moves the whole lab.
                    renderer?.root.position = appModel.labPlacement.offset
                }
            )

            #if DEBUG
            // `-gravLagrange 1` lights the Lagrange layer AND parks a body
            // at L4 — a CAPABILITY, not a control (the callout appears on a
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
        // Leaving the lab must not leave anything running or held: an
        // in-flight grab never gets its `onEnded` when the space closes,
        // so it must be cleared here or it strands and re-targets every
        // later drag.
        .onDisappear {
            renderer?.teardown()
            // MUST clear: `Bloom` is a class, so a live grip outlives the
            // view and would claim every subsequent drag in the module.
            bloom.endGrip()
            drag = nil
        }
        .simultaneousGesture(
            // A TAP MUST NOT BECOME A THROW: at minimumDistance 0 a tap
            // runs grab → hold → release, `hold` zeroes the body's
            // velocity, and with no hand motion to sample the planet is
            // released at rest and falls into the Sun.
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
                .onEnded { value in handleObjectTap(on: value.entity) }
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
        // The star's mass is a bead like every planet's (mass has physical
        // extent — the star inflates as the cube root). No delete petal:
        // deleting the Sun deletes the system. Its bead reads in SOLAR
        // masses, since a star measured in Earths reads "333000".
        let isPrimary = body.id == model.primaryBody?.id
        bloom.retarget(
            uuid,
            petals: isPrimary ? [] : [
                // Predict lives on the ring of the body it predicts; the
                // `isPrimary` branch means the Sun never offers it, so
                // there is no disabled control to wonder about.
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
                    range: GravityLabModel.primaryMassRangeSuns,
                    read: { model.massInSuns(id: uuid) },
                    write: { model.setMass(id: uuid, suns: $0) },
                    format: { PhysicsFormat.measurement($0, "Suns", decimals: 2) },
                    radius: { Float(model.displayRadius(id: uuid)) + 0.05 })
                : .init(
                    name: "Mass",
                    range: GravityLabModel.massRangeEarths,
                    read: { model.massInEarths(id: uuid) },
                    write: { model.setMass(id: uuid, earths: $0) },
                    format: { $0 < 1
                        ? PhysicsFormat.measurement($0, "Earths", decimals: 2)
                        : PhysicsFormat.measurement($0, "Earths", decimals: 0) },
                    radius: { Float(model.displayRadius(id: uuid)) + 0.03 }))

        let viewer = appModel.room.headPosition.map {
            renderer.systemRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(body.body.position * toDisplay),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }

    /// EXTRACTED FROM THE TAP CLOSURE, 2026-08-08, so VoiceOver reaches
    /// the same routing a pinch does.
    ///
    /// `Grabbable` has taken an `activate` closure since the mechanism
    /// moved into RenderKit, and every call site passed nothing — so the
    /// objects a hand can carry could be reached no other way. It is not
    /// a sweep: the helper configures entities it did not build and
    /// cannot know what pressing one should mean. Only the module knows
    /// that, so the routing had to come out of the gesture first.
    private func handleObjectTap(on entity: Entity) {
        // The handles get first refusal — they are the
        // doors, and a door has to answer before the room
        // behind it.
        if clockHandle.handleTap(entity) { return }
        if analysisHandle.handleTap(entity) { return }
        if vectorsHandle.handleTap(entity) { return }
        if vectorsHandle.isOpen,
           vectors?.handleTap(entity) == true { return }
        if clockHandle.isOpen,
           clockPicker.handleTap(entity) { return }
        if analysisHandle.isOpen,
           analysis?.handleTap(entity) == true { return }
        if layers?.handleTap(entity) == true { return }
        if worldPicker.handleTap(entity) { return }
        if verbs?.handleTap(entity) == true { return }
        if bloom.handleTap(entity) { return }
        // A tap toggles the body's control ring and SELECTS it (selection
        // drives the vectors, Kepler sweep, Predict and the notebook rows).
        // Matched on the body's UUID — that is what the renderer names its
        // spheres; no entity here carries a display name.
        var current: Entity? = entity
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

