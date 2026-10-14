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
    /// The magnet well, off the left shoulder below the region. Internal
    /// so the reach criterion can measure it. What is drawn and whether the
    /// magnets are free are in More.
    static let wellAnchor = SIMD3<Float>(MagnetismModel.regionCenter)
        + SIMD3(-0.72, -0.20, 0.34)

    var body: some View {
        RealityView { content in
            let renderer = MagnetismRenderer()
            renderer.onObjectTap = { handleTap(on: $0) }
            content.add(renderer.root)
            // Disabled here and raised by `Fade.tick`, so the apparatus arrives
            // rather than appears.
            renderer.root.isEnabled = false
            sceneContent = content

            let sources = Well([
                .init(name: "Magnet",
                      tint: UIColor(DesignTokens.Palette.magnetismAccent),
                      label: "Add magnet",
                      preview: { MagnetismRenderer.magnetPreview() },
                      position: Self.wellAnchor,
                      spawn: { point in model.addMagnet(at: point) }),
            ])
            renderer.viewRoot.addChild(sources.root)
            renderer.viewRoot.addChild(bloom.root)
            wells = sources

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's arrival and departure, on the shell's one flag.
                    if let renderer {
                        Fade.tick(renderer.root, visible: !appModel.isDeparting,
                                  duration: AppModel.departure)
                    }
                    // Per frame, not per event: a hand that leaves the tracking volume
                    // mid-carry stops sending events, so an event-driven expiry never runs
                    // for the pinch it exists to forget.
                    expireStaleGrabs(now: CACurrentMediaTime())
                    if let renderer { scaleRig.apply(to: renderer.viewRoot) }
                    let hand = appModel.room.nearestFingertip(to: Self.wellAnchor)
                    wells?.update(dt: event.deltaTime, nearestHand: hand)
                    if let renderer {
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                    }
                    model.step(dt: event.deltaTime)
                    renderer?.tick(model, viewer: appModel.room.headPosition.map {
                        renderer?.displayPoint(fromWorld: SIMD3<Float>($0)) ?? $0
                    })
                    // The lab's placement: a pure display offset, safe because every grab
                    // moves a body by hand displacement.
                    renderer?.root.position = appModel.labPlacement.offset
                }
            )
            #if DEBUG
            // `-viewScale 2.5` bakes a committed scale in at launch;
            // `double(forKey:)` coerces the stored string.
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
            // `-magLayers 0` switches the field lines, the compass and the
            // dynamics off, as More would (`earthFieldOn` has no argument).
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
        // Leaving the lab must not leave anything running or held: `teardown`
        // cancels subscriptions and geometry jobs, and an in-flight grab that
        // never gets its `onEnded` would re-target every later drag.
        .onDisappear {
            renderer?.teardown()
            // `Bloom` is a class: a grip left set would claim every subsequent
            // drag.
            bloom.endGrip()
            drag = nil
            // Released, not merely forgotten: a magnet left `held` stays frozen out
            // of the dynamics, and the model outlives this view.
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
                        // Magnets and the compass are not claimed here —
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
                    // here used to drop everything, including whatever
                    // the other hand was holding.
                    if let drag, let id = UUID(uuidString: drag.name) {
                        model.release(id: id)
                    }
                    drag = nil
                }
        )
    }

    // MARK: The multi-hand grab
    // `DragGesture` is a single recogniser, so the second hand's pinch is
    // never delivered to it; raw `SpatialEventGesture` events carry their
    // own ids, so each hand gets its own grab session. A second pinch on an
    // already-held object starts no session and falls through to the
    // two-hand scale.

    /// One hand's live hold: what it grabbed, and the relative drag
    /// anchored where it grabbed it.
    private struct GrabSession {
        enum Target { case magnet(UUID), compass }
        var target: Target
        var drag: RelativeDrag
        /// When this pinch was last heard from. See `expireStaleGrabs`.
        var lastSeen: Double
        /// What the hand took hold of: it flashed and ticked on the grab,
        /// and ticks again where it is let go.
        var entity: Entity
    }

    /// The house acknowledgement of a grab and of letting go — the live
    /// glow and the tick every other lab's objects answer a hand with.
    private static func acknowledgeGrab(_ entity: Entity) {
        LiveGlow.set(true, on: entity)
        SoundPalette.play(.grabTick, on: entity, volume: 0.2)
    }

    private static func acknowledgeRelease(_ session: GrabSession) {
        LiveGlow.set(false, on: session.entity)
        SoundPalette.play(.releaseTick, on: session.entity, volume: 0.18)
    }

    /// How long a grab survives without being mentioned by an event.
    /// The same number, for the same reason, as `PinchLedger.staleAfter`.
    private static let grabStaleAfter: Double = 0.5

    /// Releases grabs whose pinch stopped reporting: a hand that leaves the
    /// tracking volume mid-carry sends no ending event, and its magnet
    /// would stay held forever.
    private func expireStaleGrabs(now: Double) {
        for (id, session) in grabs where now - session.lastSeen >= Self.grabStaleAfter {
            grabs.removeValue(forKey: id)
            Self.acknowledgeRelease(session)
            if case .magnet(let magnetID) = session.target { model.release(id: magnetID) }
        }
    }

    /// Live grab sessions, one per pinch id.
    @State private var grabs: [SpatialEventCollection.Event.ID: GrabSession] = [:]

    private func handleGrabEvents(_ events: SpatialEventCollection) {
        guard let renderer, let content = sceneContent else { return }
        let now = CACurrentMediaTime()
        // Also here, so a pinch that ends while others continue is forgotten
        // this frame.
        defer { expireStaleGrabs(now: now) }
        for event in events {
            guard event.phase == .active else {
                if let ended = grabs.removeValue(forKey: event.id) {
                    Self.acknowledgeRelease(ended)
                    if case .magnet(let id) = ended.target {
                        model.release(id: id)
                    }
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
                Self.acknowledgeGrab(candidate)
                return GrabSession(
                    target: .compass,
                    drag: RelativeDrag(name: candidate.name,
                                       target: model.compassPosition, hand: hand),
                    lastSeen: now,
                    entity: candidate)
            }
            if let id = UUID(uuidString: candidate.name),
               let magnet = model.magnets.first(where: { $0.id == id }) {
                // A second hand on a held magnet is the resize gesture,
                // not a second grab.
                guard !model.heldIDs.contains(id) else { return nil }
                model.grab(id: id)
                Self.acknowledgeGrab(candidate)
                return GrabSession(
                    target: .magnet(id),
                    drag: RelativeDrag(name: candidate.name,
                                       target: magnet.position, hand: hand),
                    lastSeen: now,
                    entity: candidate)
            }
            current = candidate.parent
        }
        return nil
    }

    /// Tap a magnet and it offers exactly what a magnet offers:
    /// reverse its poles, remove it, or draw its strength out from under
    /// it — and the field loops thicken and reach further as you pull,
    /// which is the only readout that matters.
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
                radius: { Float(MagnetismModel.magnetLength) * 0.6 },
                // Out of the underside, not a pole: attracted magnets sit nose to
                // tail, so a handle off the north pole was buried in its partner.
                stretch: .track(range: MagnetismModel.strengthRange, under: {
                    model.magnets.first(where: { $0.id == uuid })
                        .map { SIMD3<Float>($0.position) } ?? .zero
                }, read: { model.strength(id: uuid) })))

        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(magnet.position),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }


    /// The tap routing, out of the gesture closure so VoiceOver reaches it
    /// too.
    private func handleTap(on entity: Entity) {
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
                    // The ring and the halo name one magnet: opening selects.
                    model.select(id: id)
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
