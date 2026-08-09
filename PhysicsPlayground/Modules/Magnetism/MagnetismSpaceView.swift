//
//  MagnetismSpaceView.swift
//  Physics Playground — Magnetism module
//
//  The magnetism immersive scene. RealityView installs the renderer and
//  the control pods; from then on the model steps and the renderer ticks
//  every frame from SceneEvents.Update. A magnet is grabbed by its UUID
//  name and moved by the hand's displacement (relative drag) — while it's
//  held the model freezes it and lets every other magnet respond.
//

import PhysicsCore
import QuartzCore
import SwiftUI
import RealityKit
import RenderKit

struct MagnetismSpaceView: View {
    @Environment(MagnetismModel.self) private var model
    @Environment(AppModel.self) private var appModel
    @State private var renderer: MagnetismRenderer?
    @State private var drag: RelativeDrag?
    @State private var bloom = Bloom()
    /// Held for coordinate conversion in `handleGrabEvents`: a raw
    /// `SpatialEventGesture` has no `value.convert`, so the view keeps
    /// the RealityView's own converter.
    @State private var sceneContent: RealityViewContent?
    /// Which magnet's ring is open — shared by the tap gesture and the
    /// render loop (see RingState's header for why it's a reference).
    @State private var ring = RingState()
    @State private var wells: Well?
    /// Two-hand scale and turn: grow the dipole field from a desk demo
    /// to loops you stand inside, or turn the whole field to see it
    /// side-on. A pure view transform — the tesla stay honest.
    @State private var scaleRig = SpatialScaleRig(
        pivot: SIMD3<Float>(MagnetismModel.regionCenter), range: 0.5...4.0)
    /// What is drawn, and whether the magnets are free.
    ///
    /// FOUR plates — field lines, hand compass, Earth's field, and the
    /// dynamics switch. (The compass-grid plate came off with the grid
    /// on 2026-08-03; `-magLayers 0` reaches three of these four —
    /// `earthFieldOn` has no argument.)
    /// The top one is not a display layer: `dynamicsOn` decides whether
    /// the magnets glide together and swing into alignment at all, which
    /// is the difference between a field diagram and a physics lab. It
    /// takes the top plate and a label that says what it does, because a
    /// bank whose plates all mean "draw this" plus one that means "run
    /// the simulation" has to admit the difference somewhere.
    @State private var layers: SpatialLayerBank?

    /// Beside the magnets, at the region's own depth — on the LEFT,
    /// like every other module's switch bank (owner, 2026-08-04: the
    /// side buttons live on the left everywhere; this was the one bank
    /// off the right shoulder).
    ///
    /// NOT under `viewRoot`: the scale rig reaches 4×, and a switch bank
    /// that grew fourfold with the field would push its own plates out of
    /// reach exactly when you had zoomed in to look at something. The
    /// well and the blooms belong to the field and DO scale with it; an
    /// instrument belongs to the room.
    /// Internal since 2026-08-09 so the reach criterion can measure it.
    static let bankAnchor = SIMD3<Float>(MagnetismModel.regionCenter)
        + SIMD3(-0.80, 0.10, 0.08)

    var body: some View {
        RealityView { content in
            let renderer = MagnetismRenderer()
            renderer.onObjectTap = { handleTap(on: $0) }
            content.add(renderer.root)
            sceneContent = content

            let sources = Well([
                .init(name: "Magnet",
                      tint: UIColor(DesignTokens.Palette.magnetismAccent),
                      label: "Add magnet",
                      preview: { MagnetismRenderer.magnetPreview() },
                      position: SIMD3<Float>(MagnetismModel.regionCenter)
                          + SIMD3(-0.72, -0.20, 0.34),
                      spawn: { point in model.addMagnet(at: point) }),
            ])
            renderer.viewRoot.addChild(sources.root)
            renderer.viewRoot.addChild(bloom.root)
            wells = sources

            let bank = SpatialLayerBank(
                accent: UIColor(DesignTokens.Palette.magnetismAccent),
                layers: [
                    .init(id: "dynamics", label: "Magnets move",
                          symbol: "arrow.triangle.merge",
                          isOn: { model.dynamicsOn },
                          toggle: { model.dynamicsOn.toggle() }),
                    .init(id: "lines", label: "Field lines", symbol: "scribble",
                          isOn: { model.showFieldLines },
                          toggle: { model.showFieldLines.toggle() }),
                    .init(id: "handCompass", label: "Hand compass",
                          symbol: "location.north.circle",
                          isOn: { model.compassOn },
                          toggle: { model.compassOn.toggle() }),
                    // The fifth: whether the room is standing on a
                    // planet. Switching it off is the comparison — the
                    // compasses stop knowing which way is north and go
                    // back to reading only the bench.
                    .init(id: "earth", label: "Earth's field",
                          symbol: "globe",
                          isOn: { model.earthFieldOn },
                          toggle: { model.earthFieldOn.toggle() }),
                ])
            renderer.root.addChild(bank.root)
            layers = bank

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // PER FRAME, not per event, and that distinction is
                    // the whole point: a hand that leaves the tracking
                    // volume mid-carry stops SENDING events, so an
                    // expiry driven by `handleGrabEvents` would never
                    // run for exactly the pinch it exists to forget.
                    expireStaleGrabs(now: CACurrentMediaTime())
                    if let renderer { scaleRig.apply(to: renderer.viewRoot) }
                    let hand = appModel.room.nearestFingertip(to: Self.bankAnchor)
                    wells?.update(dt: event.deltaTime, nearestHand: hand)
                    layers?.update(
                        anchor: Self.bankAnchor,
                        viewer: appModel.room.headPosition.map { SIMD3<Float>($0) },
                        dt: event.deltaTime, nearestHand: hand)
                    if let renderer {
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                    }
                    model.step(dt: event.deltaTime)
                    renderer?.tick(model, viewer: appModel.room.headPosition.map {
                        renderer?.displayPoint(fromWorld: SIMD3<Float>($0)) ?? $0
                    })
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                    // …AND THE INSTRUMENTS GO WITH IT. Every bank, rail,
                    // well and ring in this module is a child of
                    // `renderer.root`, so they ride the same offset the
                    // apparatus does.
                    //
                    // This comment said the opposite until 2026-08-03 —
                    // "the control pods do NOT go with it: the user
                    // parked them where they wanted them" — in all four
                    // modules that carry it, and it was false in all
                    // four. There are no pods; the instruments were
                    // reparented onto the apparatus when the panels died,
                    // and travelling with it is the RIGHT behaviour: a
                    // rail belongs to the thing it sets. Left standing,
                    // the sentence would eventually persuade somebody to
                    // "fix" a counter-translation back in.
                }
            )
            #if DEBUG
            // `-viewScale 2.5` bakes a committed scale in at launch, so
            // the scaled view can be screenshot-verified from the CLI —
            // the simulator has no second hand to pinch with.
            // double(forKey:) coerces the string the launch-argument
            // domain actually stores; `object as? Double` does not.
            let forced = UserDefaults.standard.double(forKey: "viewScale")
            if forced > 0 {
                scaleRig.updateMagnification(Float(forced))
                scaleRig.endGesture()
            }
            #endif
            #if DEBUG
            // `-magRing 1` opens the first magnet's control ring at
            // launch, so the ring can be screenshot from the CLI.
            if UserDefaults.standard.bool(forKey: "magRing"),
               let first = model.magnets.first {
                ring.openID = first.id
            }
            // `-magLayers 0` darkens every plate on the bank, so one shot
            // shows the lamps OFF against the labels — the only way to
            // check the dark state, since the scene opens with several
            // already lit and the simulator has no finger to flick them
            // with. (`earthFieldOn` still has no argument.)
            if UserDefaults.standard.object(forKey: "magLayers") != nil,
               !UserDefaults.standard.bool(forKey: "magLayers") {
                model.showFieldLines = false
                model.compassOn = false
                model.dynamicsOn = false
            }
            #endif
            renderer.tick(model, viewer: appModel.room.headPosition)
            self.renderer = renderer
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
            // Released, not merely forgotten: a magnet left `held` is
            // frozen out of the dynamics, and the model outlives this
            // view — it would still be frozen on the way back in.
            for session in grabs.values {
                if case .magnet(let id) = session.target { model.release(id: id) }
            }
            grabs.removeAll()
        }
        .spatialScale(scaleRig)
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in handleTap(on: value.entity) }
        )
        // The multi-hand grab first, then the single-recogniser drag for
        // the affordances that are one-hand by nature (the strength
        // bead's grip, and pulling a new magnet from the well).
        .simultaneousGesture(
            SpatialEventGesture()
                .onChanged { events in handleGrabEvents(events) }
                .onEnded { events in handleGrabEvents(events) }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    // Through the scaled root: at 3× a hand moving a
                    // metre moves a magnet a third of one, so what you
                    // hold stays under your fingers at every scale.
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                    if drag == nil {
                        if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                        if let id = wells?.pull(value.entity, at: hand) {
                            // Held from birth, so the glide cannot tug a
                            // newborn magnet out of the hand that made it.
                            model.grab(id: id)
                            drag = RelativeDrag(name: id.uuidString,
                                                target: hand, hand: hand)
                            return
                        }
                        // Magnets and the compass are NOT claimed here —
                        // `handleGrabEvents` owns them, one session per
                        // hand, which is what makes a magnet in each
                        // hand possible at all.
                    }
                    guard let drag else { return }
                    if let id = UUID(uuidString: drag.name) {
                        model.move(id: id, to: drag.position(forHand: hand))
                    }
                }
                .onEnded { _ in
                    bloom.endGrip()
                    // Only the well-pull's own magnet: `model.release()`
                    // here used to drop EVERYTHING, including whatever
                    // the other hand was holding.
                    if let drag, let id = UUID(uuidString: drag.name) {
                        model.release(id: id)
                    }
                    drag = nil
                }
        )
    }

    // MARK: The multi-hand grab
    //
    // `DragGesture` is a single recogniser: SwiftUI runs ONE instance
    // per attached gesture, so the second hand's pinch is never
    // delivered to it — which is why "grab a magnet in each hand" was
    // impossible no matter what the model allowed (owner report,
    // 2026-08-04, correctly suspecting it was fixable). Raw
    // `SpatialEventGesture` events have no such limit: every pinch
    // arrives with its own stable id and the entity it targeted, so
    // each hand gets its own grab session. The same-object rule keeps
    // its shape for free: a second pinch on an ALREADY-HELD object
    // starts no session and falls through to the two-hand scale.

    /// One hand's live hold: what it grabbed, and the relative drag
    /// anchored where it grabbed it.
    private struct GrabSession {
        enum Target { case magnet(UUID), compass }
        var target: Target
        var drag: RelativeDrag
        /// When this pinch was last heard from. See `expireStaleGrabs`.
        var lastSeen: Double
    }

    /// How long a grab survives without being mentioned by an event.
    /// The same number, for the same reason, as `PinchLedger.staleAfter`.
    private static let grabStaleAfter: Double = 0.5

    /// Releases grabs whose pinch stopped reporting.
    ///
    /// `grabs` is keyed by spatial-event id and was only ever emptied by
    /// an event NAMING that id. A hand that leaves the tracking volume
    /// mid-carry — walked out of frame, dropped to the side, occluded by
    /// the bench — sends no such event, so its magnet stayed held
    /// forever: frozen out of the dynamics, following nothing, and
    /// re-grabbed by every later pinch that resolved to the same id.
    private func expireStaleGrabs(now: Double) {
        for (id, session) in grabs where now - session.lastSeen >= Self.grabStaleAfter {
            grabs.removeValue(forKey: id)
            if case .magnet(let magnetID) = session.target { model.release(id: magnetID) }
        }
    }

    /// Live grab sessions, one per pinch id.
    @State private var grabs: [SpatialEventCollection.Event.ID: GrabSession] = [:]

    private func handleGrabEvents(_ events: SpatialEventCollection) {
        guard let renderer, let content = sceneContent else { return }
        let now = CACurrentMediaTime()
        // Also here, so a pinch that ends while others continue is
        // forgotten this frame rather than next. The per-frame call in
        // the update subscription is the one that covers a hand which
        // stops reporting altogether.
        defer { expireStaleGrabs(now: now) }
        for event in events {
            guard event.phase == .active else {
                if let ended = grabs.removeValue(forKey: event.id),
                   case .magnet(let id) = ended.target {
                    model.release(id: id)
                }
                continue
            }
            // Same conversion chain as the drag above: view point →
            // world → through the scaled root into model space.
            let world = content.convert(event.location3D,
                                        from: .local, to: .scene)
            let hand = renderer.displayPoint(fromWorld: world)

            if let session = grabs[event.id] {
                grabs[event.id]?.lastSeen = now
                switch session.target {
                case .magnet(let id):
                    model.move(id: id, to: session.drag.position(forHand: hand))
                case .compass:
                    model.moveCompass(to: session.drag.position(forHand: hand))
                }
            } else if let session = beginGrabSession(on: event.targetedEntity,
                                                     hand: hand, now: now) {
                grabs[event.id] = session
            }
        }
    }

    /// Resolves a fresh pinch to a grab, or nil for anything that is
    /// not a free object — banks, beads, wells and second pinches on a
    /// held object all decline, and the other recognisers take them.
    private func beginGrabSession(on entity: Entity?, hand: SIMD3<Double>,
                                  now: Double) -> GrabSession? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name == MagnetismRenderer.handCompassName {
                let compassHeld = grabs.values.contains {
                    if case .compass = $0.target { return true }
                    return false
                }
                guard !compassHeld else { return nil }
                return GrabSession(
                    target: .compass,
                    drag: RelativeDrag(name: candidate.name,
                                       target: model.compassPosition, hand: hand),
                    lastSeen: now)
            }
            if let id = UUID(uuidString: candidate.name),
               let magnet = model.magnets.first(where: { $0.id == id }) {
                // A second hand on a held magnet is the resize gesture,
                // not a second grab.
                guard !model.heldIDs.contains(id) else { return nil }
                model.grab(id: id)
                return GrabSession(
                    target: .magnet(id),
                    drag: RelativeDrag(name: candidate.name,
                                       target: magnet.position, hand: hand),
                    lastSeen: now)
            }
            current = candidate.parent
        }
        return nil
    }

    /// Tap a magnet and it offers exactly what a magnet offers:
    /// reverse its poles, remove it, or pull its strength up — and the
    /// field loops thicken and reach further as you pull, which is the
    /// only readout that matters.
    private func syncBloom(renderer: MagnetismRenderer, dt: Double) {
        if let openID = ring.openID,
           !model.magnets.contains(where: { $0.id == openID }) {
            ring.openID = nil     // deleted out from under the ring
        }
        guard let uuid = ring.openID,
              let magnet = model.magnets.first(where: { $0.id == uuid }) else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }

        bloom.retarget(
            uuid,
            petals: [
                .init(name: "Flip poles", symbol: "arrow.triangle.2.circlepath",
                      tint: DesignTokens.Palette.neutralActionUI) {
                    model.flipMagnet(id: uuid)
                },
                .init(name: "Delete", symbol: "trash",
                      tint: DesignTokens.Palette.destructiveUI) {
                    model.removeMagnet(id: uuid)
                },
            ],
            grip: .init(
                name: "Strength",
                range: MagnetismModel.strengthRange,
                read: { model.strength(id: uuid) },
                write: { model.setStrength(id: uuid, $0) },
                format: { PhysicsFormat.measurement($0, "A\u{00B7}m\u{00B2}", decimals: 1) },
                radius: { Float(MagnetismModel.magnetLength) * 0.6 }))

        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(magnet.position),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }


    /// EXTRACTED FROM THE TAP CLOSURE, 2026-08-08, so that VoiceOver can
    /// reach it too.
    ///
    /// `Grabbable` takes an `activate` closure but every call site
    /// passed nothing, so magnets and the compass could be moved by hand
    /// and reached no other way. The fix is not a sweep: the helper
    /// configures an entity it did not build and cannot know what
    /// pressing it should mean, and in this module it means opening the
    /// magnet's control ring. Only the module knows that — so the
    /// routing had to come out of the gesture closure first.
    private func handleTap(on entity: Entity) {
        // The bank gets first refusal, ahead of the fall-through that
        // folds the ring away — otherwise flicking a switch would also
        // close whichever magnet's ring was open.
        if layers?.handleTap(entity) == true { return }
        if bloom.handleTap(entity) { return }
        // A tap on a magnet toggles its control ring; a tap on anything
        // else folds it away.
        var current: Entity? = entity
        while let candidate = current {
            if let id = UUID(uuidString: candidate.name),
               model.magnets.contains(where: { $0.id == id }) {
                if ring.openID == id {
                    ring.openID = nil
                    SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
                } else {
                    ring.openID = id
                    SoundPalette.play(.pop, on: entity, volume: 0.35)
                }
                return
            }
            current = candidate.parent
        }
        // Folding by tapping elsewhere answers too — the unfold pops, so
        // a silent fold read as broken.
        if ring.openID != nil {
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
        }
        ring.openID = nil
    }

}
