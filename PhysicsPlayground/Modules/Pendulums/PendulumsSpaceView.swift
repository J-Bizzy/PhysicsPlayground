//
//  PendulumsSpaceView.swift
//  Physics Playground — Pendulums module
//
//  The pendulum lab immersive scene. A bob is carried by a
//  `RelativeDrag`: grabbing freezes that pendulum, the bob rides the
//  hand (cable staying taut), and release rethrows it with the hand's
//  velocity estimated from the last tenth of a second of motion — a
//  hard sideways throw whips it, a gentle release barely stirs it.
//
//  (This said "route through the ManipulationRouter" until 2026-08-03.
//  They never did; the router had no callers anywhere and is deleted.)
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
    /// Which pendulum's PIVOT is open.
    ///
    /// A separate ring from the bob's, and a reference type for the same
    /// reason that one is: a `@State` struct read from inside a
    /// RealityKit closure comes back stale. Tapping a pivot and tapping a
    /// bob are exclusive — opening either closes the other — so one
    /// `Bloom` serves both, and what it carries depends on which is open.
    @State private var pivotRing = RingState()
    /// The collar this press started on, and whether it has moved. A
    /// press that never moves is a tap; see the drag's `onEnded`.
    @State private var pressedPivot: (id: UUID, moved: Bool)?
    /// The bob this press landed on, before it has moved far enough to
    /// be a grab. Held rather than grabbed, so a TAP on a bob does not
    /// stop the pendulum and wipe the room's trails — see the drag's
    /// `onChanged`. The collar above has always worked this way; the bob
    /// did not until 2026-08-07.
    @State private var pressedBob = PressLatch<BobPress>()

    /// A press on a bob — identity only. Where the bob IS is read at
    /// promotion: it is still swinging, at around a metre a second, so
    /// its position at press time is stale by more than the threshold
    /// by the time the threshold is crossed. See `PressLatch`.
    struct BobPress: Sendable {
        let id: UUID
        let name: String
    }
    /// How far a press may wander and still count as a tap, metres.
    private static let tapTravel: Double = 0.012
    @State private var wells: Well?
    /// `PhysicsCore.ThrowSampler`. The 0.14 s window is wider than the
    /// 0.12 the other two modules use: a bob is released out of a swing
    /// rather than flicked.
    @State private var handSampler = ThrowSampler(window: 0.14)

    // MARK: The instruments

    /// What is drawn, and whether the air is real. Five plates — the
    /// fifth (air resistance) is not a display layer but a labelled
    /// discrete choice, and one lone plate beside a bank of four is worse.
    @State private var layers: SpatialLayerBank?
    // `gravity` and `timeScale` are RETIRED CAPABILITIES, not hidden ones:
    // the wearer is not offered them at all (this bench is Earth at 1×),
    // and `-penGravity`/`-penTime` exist only so a screenshot can put it
    // elsewhere. Anybody restoring either must restore its rail in the
    // same commit.

    // Placement. Every one of these sits at the apparatus's own DEPTH
    // (z ≈ −1.08, the pivot plane) rather than at a height picked on its
    // own — the podium mistake this project has now made three times is
    // to put controls on a console BELOW the thing they belong to, where
    // they read 38° under the eye line and are simply never seen. Being
    // close magnifies the drop. The band that works is ~14°, which at
    // this depth is y ≈ 1.35.
    private static let instrumentZ: Float = -1.08
    /// Left of the swing, above the well at y = 1.30.
    ///
    /// Internal rather than private since 2026-08-09 so
    /// `InstrumentReachCriterionTests` can measure it. Every module's
    /// bank used to be a literal buried in a render closure, which is
    /// why nothing had ever checked whether they were reachable — and
    /// two of them were not.
    static let bankAnchor = SIMD3<Float>(-0.92, 1.58, instrumentZ)

    /// Walks up from a tapped entity to a pivot collar, if it is one.
    /// The renderer names them `pivot-<uuid>`.
    private static func pivotID(of entity: Entity) -> UUID? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name.hasPrefix("pivot-") {
                return UUID(uuidString: String(candidate.name.dropFirst(6)))
            }
            current = candidate.parent
        }
        return nil
    }

    /// Identifies the floating readout above the selected bob.
    private static let infoCardID = "pendulum-info"

    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content, attachments in
            let renderer = PendulumsRenderer()
            renderer.onObjectTap = { handleObjectTap(on: $0) }
            content.add(renderer.root)
            // ARRIVES, NEVER APPEARS. Disabled here and raised by
            // `Fade.tick` below, so the apparatus resolves into the room
            // instead of being there between one frame and the next.
            renderer.root.isEnabled = false
            renderer.root.addChild(bloom.root)

            // The selected bob's numbers, finally attached.
            //
            // `infoAnchor` has been built, billboarded, added to the
            // scene and repositioned above the selected bob every frame
            // since the renderer was written — with NOTHING on it. The
            // card it was waiting for existed too, in the window panel's
            // "Numbers" dropdown. This is the wire that was never run.
            if let card = attachments.entity(for: Self.infoCardID) {
                stripInput(from: card)
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
                          // Born hanging plumb, at rest. The default
                          // draw-back is for the cradle cold-open; a
                          // pendulum pulled out by hand must hold still
                          // until the hand swings it (owner, 2026-08-03).
                          model.addPendulum(angle: 0, at: point)
                      }),
                // The chaotic one, as its own mouth rather than a mode
                // on the first. They are different physics — a taut
                // cable on a sphere versus a two-angle Lagrangian system
                // — and the interaction law says a discrete choice gets
                // a labelled object rather than a hidden modifier.
                .init(name: "Double", tint: UIColor(DesignTokens.Palette.pendulumsAccent),
                      label: "Double pendulum",
                      preview: { PendulumsRenderer.doublePendulumPreview() },
                      position: SIMD3(-1.10, 1.30, -0.95),
                      spawn: { point in
                          model.addDoublePendulum(at: point)
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
                ])
            renderer.root.addChild(bank.root)
            layers = bank

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
                    renderer?.tick(dt: event.deltaTime, model: model)
                    let hand = appModel.room.nearestFingertip(to: Self.bankAnchor)
                    wells?.update(dt: event.deltaTime, nearestHand: hand)
                    syncBloom(dt: event.deltaTime)
                    let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
                    layers?.update(anchor: Self.bankAnchor,
                                   viewer: viewer, dt: event.deltaTime,
                                   nearestHand: hand)
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                    // Every bank, rail, well and ring is a child of
                    // `renderer.root`, so the whole lab travels together.
                }
            )
            #if DEBUG
            // `-penRing 1` opens the first bob's control ring at
            // launch, for CLI screenshots.
            if UserDefaults.standard.bool(forKey: "penRing"),
               let first = model.pendulums.first {
                ring.openID = first.id
            }
            // `-penPivotRing 1` opens the COLLAR's ring (cable bead and
            // trash), which a press-without-moving opens — not something
            // the simulator can do.
            if UserDefaults.standard.bool(forKey: "penPivotRing"),
               let first = model.pendulums.first {
                pivotRing.openID = first.id
                ring.openID = nil
            }
            // Each instrument arg sets a VALUE, not a flag: a bead parked
            // at its default proves the rail rendered and nothing about
            // the mapping behind it. `-penGravity 1.62` is the Moon.
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
            // shows all four lamps and all four labels rather than the
            // two that happen to be on by default.
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
            // A collar press left armed intercepts the NEXT gesture's
            // `onEnded` and returns early, so the next bob you grab is
            // never released and stays held forever.
            pressedPivot = nil
            drag = nil
            // A pending press now STICKS — `press` refuses to overwrite
            // one — so an `onEnded` that never arrives would otherwise
            // let the next gesture promote it on frame one, against a
            // stale anchor, and grab the object you pressed last time.
            pressedBob.cancel()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                    if drag == nil {
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

                        // THE PIVOT COLLAR. This branch was missing
                        // entirely: the renderer names the collar
                        // `pivot-<uuid>` and calls
                        // `Grabbable.configureTouchTarget` on it, saying
                        // "a rig you cannot re-hang is furniture, not
                        // rigging" — but nothing here ever began a drag
                        // from one. The only `pivot-` drag in the file
                        // came from pulling a NEW pendulum out of the
                        // well, so re-hanging an existing rig had never
                        // once worked. The loop below matches a BARE
                        // uuid, which a collar's name is not.
                        if let id = Self.pivotID(of: value.entity),
                           let pendulum = model.pendulums.first(where: { $0.id == id }) {
                            drag = RelativeDrag(name: "pivot-\(id.uuidString)",
                                                target: pendulum.pivot, hand: hand)
                            pressedPivot = (id: id, moved: false)
                            return
                        }

                        // A press that never moves is NOT a drag: on this
                        // `minimumDistance: 0` recogniser a bare tap on a
                        // bob would wipe every trail, zero the swing and
                        // release it at rest. The press is only RECORDED
                        // here and promoted to a grab below once the hand
                        // moves, anchored back at the press so nothing jumps.
                        var current: Entity? = value.entity
                        while let candidate = current {
                            if let id = UUID(uuidString: candidate.name),
                               model.pendulums.contains(where: { $0.id == id }) {
                                pressedBob.press(
                                    BobPress(id: id, name: candidate.name),
                                    at: hand)
                                break
                            }
                            current = candidate.parent
                        }
                    }

                    // The promotion. `tapTravel` is the same threshold
                    // the collar uses — under a finger's width. The bob's
                    // position is read HERE, at the instant of the grab,
                    // because it has gone on swinging throughout the
                    // press.
                    if drag == nil, pressedBob.isPending {
                        guard let grabbed = pressedBob.promote(hand: hand),
                              let pendulum = model.pendulums.first(where: {
                                  $0.id == grabbed.id
                              })
                        else { return }
                        let bobWorld = pendulum.bobWorld
                        renderer?.grabbedID = grabbed.id
                        renderer?.clearTrail()
                        model.beginGrab(id: grabbed.id)
                        drag = RelativeDrag(name: grabbed.name,
                                            target: bobWorld, hand: hand)
                        handSampler.reset()
                        handSampler.record(bobWorld,
                                           at: Date.timeIntervalSinceReferenceDate)
                    }
                    // A pivot drag re-hangs the rig; a bob drag swings it.
                    if drag?.name.hasPrefix("pivot-") == true, let drag,
                       let id = UUID(uuidString: String(drag.name.dropFirst(6))) {
                        let target = drag.position(forHand: hand)
                        if var pressed = pressedPivot, pressed.id == id,
                           let pendulum = model.pendulums.first(where: { $0.id == id }),
                           simd_distance(target, pendulum.pivot) > Self.tapTravel {
                            pressed.moved = true
                            pressedPivot = pressed
                        }
                        model.movePivot(id: id, to: target)
                        return
                    }
                    guard let drag, let id = UUID(uuidString: drag.name) else { return }
                    let world = drag.position(forHand: hand)
                    model.moveGrabbed(id: id, toWorld: world)
                    handSampler.record(world, at: Date.timeIntervalSinceReferenceDate)
                }
                .onEnded { value in
                    // A bob press that never became a grab is a tap,
                    // and the tap recogniser below owns it.
                    pressedBob.cancel()

                    // A PRESS ON THE COLLAR THAT NEVER MOVED IT opens the
                    // length bead. Folded into this drag rather than
                    // given its own `TapGesture`, which is how it was
                    // written first and which cost the collar its drag:
                    // `DragGesture(minimumDistance: 0)` and a
                    // `TapGesture` over the same entity are ambiguous, so
                    // a pinch on the pivot could resolve as the tap and
                    // the rig would refuse to be re-hung. One recogniser,
                    // two outcomes, decided by whether the thing moved.
                    if let pressed = pressedPivot {
                        pressedPivot = nil
                        if !pressed.moved {
                            pivotRing.openID =
                                pivotRing.openID == pressed.id ? nil : pressed.id
                            ring.openID = nil
                        }
                        drag = nil
                        bloom.endGrip()
                        return
                    }
                    // `bloom.endGrip()` — every other module in the app
                    // called it and this one never did. `gripDrag` then
                    // stayed non-nil forever after the first touch of a
                    // length bead, which made `updateGrip` claim EVERY
                    // subsequent drag in the scene: grabbing a bob,
                    // re-hanging a pivot, pulling one out of the well
                    // all silently became length edits on whatever the
                    // ring had last been open on. One missing line.
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
        // `.simultaneousGesture`, NOT `.gesture`: the drag above is
        // `minimumDistance: 0` and claims a touch the instant it lands, so
        // a plain `.gesture` tap never resolves and every plate, disc and
        // rail in the room stops responding.
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in handleObjectTap(on: value.entity) }
        )
    }


    /// A bob's own controls. LENGTH is the grip, and its extent is the
    /// cable: pull the bead and the cable pays out, the bob falls with
    /// it, and the period tag over the pivot climbs as the square root
    /// of length while your hand is still moving.
    private func syncBloom(dt: Double) {
        // The pivot's ring: a bead for the cable (the quantity a pivot
        // owns) and Delete. The bob's ring keeps its own Delete — you can
        // throw a rig away from either end, as you can pick one up.
        if let openPivot = pivotRing.openID,
           !model.pendulums.contains(where: { $0.id == openPivot }) {
            // Deleted out from under the ring — by its own trash petal,
            // by the bob's, or by a reset. The bob's ring already had
            // this guard; the pivot's needs it for the same reason, and
            // now needs it MORE, because its own petal is what usually
            // triggers it.
            pivotRing.openID = nil
            bloom.clearTarget()
        }
        if let pivotID = pivotRing.openID,
           let pendulum = model.pendulums.first(where: { $0.id == pivotID }) {
            bloom.retarget(
                "pivot-\(pivotID)",
                petals: [
                    .init(name: "Delete", symbol: "trash",
                          tint: DesignTokens.Palette.destructiveUI) {
                        model.removePendulum(id: pivotID)
                    },
                ],
                grip: .init(
                    name: "Length",
                    range: PendulumsModel.lengthRange,
                    read: { model.pendulums.first(where: { $0.id == pivotID })?.length ?? 0.8 },
                    write: { model.setLength(id: pivotID, $0) },
                    format: { PhysicsFormat.measurement($0, "m", decimals: 2) },
                    radius: { 0.07 }))
            let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
            bloom.update(anchor: SIMD3<Float>(pendulum.pivot),
                         viewer: viewer, revealTarget: 1, dt: dt)
            return
        }
        if pivotRing.openID != nil { pivotRing.openID = nil }

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
                      tint: DesignTokens.Palette.neutralActionUI) {
                    // Cycle light → medium → heavy → light. The period
                    // doesn't change — which is the lesson.
                    let masses = [0.5, 1.5, 3.0]
                    let current = model.pendulums.first(where: { $0.id == uuid })?.mass ?? 1
                    let next = masses.first(where: { $0 > current + 0.01 }) ?? masses[0]
                    model.setMass(id: uuid, next)
                },
                .init(name: "Delete", symbol: "trash",
                      tint: DesignTokens.Palette.destructiveUI) {
                    model.removePendulum(id: uuid)
                },
            ],
            grip: .init(
                name: "Length",
                range: PendulumsModel.lengthRange,
                read: { model.pendulums.first(where: { $0.id == uuid })?.length ?? 0.8 },
                write: { model.setLength(id: uuid, $0) },
                format: { PhysicsFormat.measurement($0, "m", decimals: 2) },
                radius: { Float(pendulum.bobRadius) + 0.03 }))

        let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
        bloom.update(anchor: SIMD3<Float>(pendulum.bobWorld),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }

    /// EXTRACTED FROM THE TAP CLOSURE, 2026-08-08, so VoiceOver reaches
    /// the same routing a pinch does.
    ///
    /// `Grabbable` has taken an `activate` closure since the mechanism
    /// moved into RenderKit, and every call site passed nothing — so the
    /// objects a hand can carry could be reached no other way. It is not
    /// a sweep: the helper configures entities it did not build and
    /// cannot know what pressing one should mean. Here it means opening
    /// that object's control ring, and only the module knows that, so
    /// the routing had to come out of the gesture first.
    private func handleObjectTap(on entity: Entity) {
        // The instruments get first refusal, before the
        // fall-through that folds the ring away — otherwise
        // tapping a switch plate would also close whatever
        // bob ring was open.
        if layers?.handleTap(entity) == true { return }
        // NO pivot branch here. The collar's bead is opened
        // by a press that does not move it, inside the drag
        // gesture — see `onEnded`. A tap target on the collar
        // competed with its own drag and stopped the rig
        // being re-hung.
        if bloom.handleTap(entity) { return }
        // A tap on a bob selects it and toggles its control
        // ring; a tap on anything else folds the ring away.
        var current: Entity? = entity
        while let candidate = current {
            if let id = UUID(uuidString: candidate.name),
               model.pendulums.contains(where: { $0.id == id }) {
                model.select(id: id)
                pivotRing.openID = nil
                if ring.openID == id {
                    ring.openID = nil
                    SoundPalette.play(.releaseTick, on: entity,
                                      volume: 0.3)
                } else {
                    ring.openID = id
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

/// The card floating above the selected bob, on the billboarded
/// `PendulumsRenderer.infoAnchor`.
///
/// Every value is QUANTISED to its displayed precision and the strings
/// built from the quantised numbers: an attachment is rasterised into a
/// texture, so what costs is how often the rendered output changes. A bob
/// at 1.2345 m/s then redraws ~10 times a second instead of 90.
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
                Text("L \(PhysicsFormat.measurement(length, "m", decimals: 2))   "
                     + "T \(PhysicsFormat.measurement(period, "s", decimals: 2))")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                Text("θ \(PhysicsFormat.angle(degrees, decimals: 0))   "
                     + "v \(PhysicsFormat.measurement(speed, "m/s", decimals: 2))")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
            }
            // A card in a ROOM, not on a panel: it has to hold its shape
            // against a sunlit wall, a dark studio, and whatever the
            // user's furniture is doing behind it.
            .readoutCard()
            .accessibilityElement(children: .combine)
        }
    }

}
