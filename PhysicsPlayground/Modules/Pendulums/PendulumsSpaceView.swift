//
//  PendulumsSpaceView.swift
//  Physics Playground — Pendulums module
//
//  The pendulum lab immersive scene. A bob is carried by a
//  `RelativeDrag`: grabbing freezes that pendulum, the bob rides the
//  hand (cable staying taut), and release rethrows it with the hand's
//  velocity estimated from the last tenth of a second of motion.
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
    /// Which pendulum's pivot is open. A separate ring from the bob's;
    /// tapping a pivot and tapping a bob are exclusive, so one `Bloom`
    /// serves both.
    @State private var pivotRing = RingState()
    /// The collar this press started on, and whether it has moved. A
    /// press that never moves is a tap; see the drag's `onEnded`.
    @State private var pressedPivot: (id: UUID, moved: Bool)?
    /// The bob this press landed on, before it has moved far enough to be a
    /// grab: a tap on a bob must not stop the pendulum and wipe the trails.
    @State private var pressedBob = PressLatch<BobPress>()

    /// A press on a bob — identity only. Where the bob is gets read at
    /// promotion: it is still swinging at around a metre a second.
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
    // `gravity` and `timeScale` are retired capabilities: this bench is
    // Earth at 1×, and `-penGravity`/`-penTime` exist only for screenshots.

    // Placement: every instrument sits at the apparatus's own depth (the
    // pivot plane), in the ~14° band below eye — controls on a console
    // below the thing they belong to are never seen.
    private static let instrumentZ: Float = -1.08
    /// Left of the swing, above the well. Internal so
    /// `InstrumentReachCriterionTests` can measure it.
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
            renderer.onPivotAction = { entity in
                if let id = Self.pivotID(of: entity) { togglePivotRing(id, on: entity) }
            }
            content.add(renderer.root)
            // Disabled here and raised by `Fade.tick`, so the apparatus arrives
            // rather than appears.
            renderer.root.isEnabled = false
            renderer.root.addChild(bloom.root)

            // The selected bob's numbers, on the bob.
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
                          // Born hanging plumb, at rest: a pendulum pulled out by hand must hold
                          // still until the hand swings it.
                          model.addPendulum(angle: 0, at: point)
                      }),
                // The chaotic one, as its own mouth: different physics, so a labelled
                // object rather than a hidden modifier.
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
                    // Not a display layer, and the label says so: off, the pendulum is
                    // ideal and swings for ever.
                    .init(id: "friction", label: "Air resistance", symbol: "wind",
                          isOn: { model.frictionOn },
                          toggle: { model.frictionOn.toggle() }),
                ])
            renderer.root.addChild(bank.root)
            layers = bank

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's arrival and departure, on the shell's one flag.
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
                    // The lab's placement: a pure display offset, safe because every grab
                    // moves a body by hand displacement.
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
            // `-penPivotRing 1` opens the collar's ring (cable bead and trash),
            // which a press-without-moving opens.
            if UserDefaults.standard.bool(forKey: "penPivotRing"),
               let first = model.pendulums.first {
                pivotRing.openID = first.id
                ring.openID = nil
            }
            // Each instrument argument sets a value: `-penGravity 1.62` is the Moon.
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
            // `-penLayers 1` lights every plate on the bank.
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
                    // An attachment carries a collider for its content, and this one floats
                    // directly above a bob you are meant to grab.
                    .allowsHitTesting(false)
                    // The environment does not flow into an attachment the way it flows
                    // down a view tree.
                    .environment(model)
            }
        }
        // Leaving the lab must not leave anything running or held: `teardown`
        // cancels subscriptions and geometry jobs, and an in-flight grab that
        // never gets its `onEnded` would re-target every later drag.
        .onDisappear {
            renderer?.teardown()
            // `Bloom` is a class: a grip left set would claim every subsequent
            // drag.
            bloom.endGrip()
            // A collar press left armed intercepts the next gesture's `onEnded`.
            pressedPivot = nil
            drag = nil
            // A pending press sticks, so an `onEnded` that never arrives would let
            // the next gesture promote it against a stale anchor.
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
                            // Hold the swing still for the length edit: the bead rides the bob,
                            // which was sweeping past at a metre a second.
                            if let id = ring.openID { model.beginGrab(id: id) }
                            return
                        }
                        if let id = wells?.pull(value.entity, at: hand) {
                            drag = RelativeDrag(name: "pivot-\(id.uuidString)",
                                                target: hand, hand: hand)
                            return
                        }

                        // The pivot collar: the renderer names it `pivot-<uuid>`, which the
                        // bare-uuid loop below does not match.
                        if let id = Self.pivotID(of: value.entity),
                           let pendulum = model.pendulums.first(where: { $0.id == id }) {
                            drag = RelativeDrag(name: "pivot-\(id.uuidString)",
                                                target: pendulum.pivot, hand: hand)
                            pressedPivot = (id: id, moved: false)
                            return
                        }

                        // A press that never moves is not a drag: a bare tap on a bob would
                        // wipe every trail and release it at rest. Recorded here, promoted to a
                        // grab once the hand moves.
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

                    // The promotion, at the same threshold the collar uses. The bob's
                    // position is read here, at the instant of the grab, because it has
                    // gone on swinging.
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

                    // A press on the collar that never moved it opens the length bead.
                    // Folded into this drag rather than a `TapGesture`: two recognisers
                    // over one entity were ambiguous and the rig refused to be re-hung.
                    if let pressed = pressedPivot {
                        pressedPivot = nil
                        if !pressed.moved {
                            togglePivotRing(pressed.id, on: value.entity)
                        }
                        drag = nil
                        bloom.endGrip()
                        return
                    }
                    // End the grip, or `updateGrip` claims every subsequent drag in the
                    // scene.
                    let wasGripping = bloom.isGripping
                    bloom.endGrip()
                    defer {
                        renderer?.grabbedID = nil
                        drag = nil
                        handSampler.reset()
                    }
                    if wasGripping {
                        // Hand the swing back exactly as it was, not with `.zero`: `release`
                        // writes the velocity it is given, and `setLength` keeps the swing
                        // running through the edit — the period changes, the motion does not
                        // restart.
                        if let id = ring.openID,
                           let pendulum = model.pendulums.first(where: { $0.id == id }) {
                            model.release(id: id,
                                          handVelocity: pendulum.state.velocity,
                                          isThrow: false)
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
        // `.simultaneousGesture`, not `.gesture`: the drag above claims a touch
        // the instant it lands, so a plain `.gesture` tap never resolves.
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in handleObjectTap(on: value.entity) }
        )
    }


    /// A bob's own controls. Length is the grip and its extent is the
    /// cable: pull the bead and the cable pays out, and the period tag
    /// climbs as the square root of length while the hand is still moving.
    private func syncBloom(dt: Double) {
        // The pivot's ring: a bead for the cable (the quantity a pivot
        // owns) and Delete. The bob's ring keeps its own Delete — you can
        // throw a rig away from either end, as you can pick one up.
        if let openPivot = pivotRing.openID,
           !model.pendulums.contains(where: { $0.id == openPivot }) {
            // Deleted out from under the ring — by its own trash petal, the bob's,
            // or a reset.
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

    /// Opens or folds a collar's ring — from a press that never moved the
    /// collar, or from VoiceOver — and answers with the pop and tick every
    /// other ring in the house makes. It opened and closed silently until
    /// 2026-10-14.
    private func togglePivotRing(_ id: UUID, on entity: Entity) {
        ring.openID = nil
        if pivotRing.openID == id {
            pivotRing.openID = nil
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
        } else {
            pivotRing.openID = id
            SoundPalette.play(.pop, on: entity, volume: 0.35)
        }
    }

    /// The tap routing, out of the gesture closure so VoiceOver reaches it
    /// too.
    private func handleObjectTap(on entity: Entity) {
        // The instruments get first refusal, or tapping a plate would also fold
        // the open ring.
        if layers?.handleTap(entity) == true { return }
        // No pivot branch here: the collar's bead opens from a press that does
        // not move it, inside the drag gesture; a tap target on the collar
        // competed with its own drag.
        if bloom.handleTap(entity) { return }
        // A tap on a collar belongs to the drag's settled press, which has
        // already toggled its ring; folding here would undo it.
        if Self.pivotID(of: entity) != nil { return }
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
        // A tap elsewhere folds whichever ring is open, the collar's too.
        if ring.openID != nil || pivotRing.openID != nil {
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
        }
        ring.openID = nil
        pivotRing.openID = nil
    }

}

/// The card floating above the selected bob. Every value is quantised
/// to its displayed precision: an attachment is rasterised, so what
/// costs is how often the output changes.
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
                // No T for a double: 2π√(L/g) is the upper rod's small-
                // angle period, and a chaotic rig has none (the same rule
                // as the in-room tag).
                Text(pendulum.kind == .double
                     ? "L \(PhysicsFormat.measurement(length, "m", decimals: 2))   chaotic"
                     : "L \(PhysicsFormat.measurement(length, "m", decimals: 2))   "
                       + "T \(PhysicsFormat.measurement(period, "s", decimals: 2))")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                Text("θ \(PhysicsFormat.angle(degrees, decimals: 0))   "
                     + "v \(PhysicsFormat.measurement(speed, "m/s", decimals: 2))")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
            }
            // A card in a room: it has to hold its shape against a sunlit wall, a
            // dark studio, and the furniture behind it.
            .readoutCard()
            .accessibilityElement(children: .combine)
        }
    }

}
