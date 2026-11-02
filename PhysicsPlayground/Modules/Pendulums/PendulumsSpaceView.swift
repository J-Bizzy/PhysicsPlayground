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
    /// The collar this press started on, and whether it has moved. A
    /// press that never moves is a tap, and opens the pendulum's ring; see
    /// the drag's `onEnded`.
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

    // `gravity` and `timeScale` are retired capabilities: this bench is
    // Earth at 1×, and `-penGravity`/`-penTime` exist only for screenshots.
    // What is drawn and whether the air is real are in More.

    /// The wells, left of the swing at the pivot plane's depth, one above
    /// the other. Internal so `InstrumentReachCriterionTests` can measure
    /// them: the double's mouth stood outboard at x −1.10 until 2026-10-14,
    /// 1.38 m from a standing wearer, and nothing measured it — only the
    /// bank above it was checked. It stands where the bank stood now, 32 cm
    /// up, because a well's preview hangs about 20 cm under its mouth and
    /// its nameplate under that.
    static let wellAnchor = SIMD3<Float>(-0.85, 1.30, -0.95)
    static let doubleWellAnchor = SIMD3<Float>(-0.85, 1.62, -0.95)

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

    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            let renderer = PendulumsRenderer()
            renderer.onObjectTap = { handleObjectTap(on: $0) }
            renderer.onPivotAction = { entity in
                if let id = Self.pivotID(of: entity) { toggleRing(id, on: entity) }
            }
            content.add(renderer.root)
            // Disabled here and raised by `Fade.tick`, so the apparatus arrives
            // rather than appears.
            renderer.root.isEnabled = false
            renderer.root.addChild(bloom.root)

            // Pull a pendulum out and hang it wherever you let go. The
            // pivot lands at your fingertips, so rigging one and moving
            // one are the same gesture.
            let sources = Well([
                .init(name: "Pendulum",
                      tint: UIColor(DesignTokens.Palette.pendulumsAccent),
                      label: "Add pendulum",
                      preview: { PendulumsRenderer.pendulumPreview() },
                      position: Self.wellAnchor,
                      spawn: { point in
                          // Born hanging plumb, at rest: a pendulum pulled out by hand must hold
                          // still until the hand swings it.
                          model.addPendulum(angle: 0, at: point)
                      },
                      // With no hand to swing it, VoiceOver's comes out already swinging, 15°.
                      placeWithoutHands: {
                          model.addPendulum(angle: 15 * .pi / 180,
                                            at: SIMD3<Double>(Self.wellAnchor) + SIMD3(0, 0.06, 0.10))
                      }),
                // The chaotic one, as its own mouth: different physics, so a labelled
                // object rather than a hidden modifier.
                .init(name: "Double", tint: UIColor(DesignTokens.Palette.pendulumsAccent),
                      label: "Double pendulum",
                      preview: { PendulumsRenderer.doublePendulumPreview() },
                      position: Self.doubleWellAnchor,
                      spawn: { point in
                          model.addDoublePendulum(at: point)
                      }),
            ])
            renderer.root.addChild(sources.root)
            wells = sources

            // The lab shows once its scene has taken in the build (`Settle`):
            // it starts hidden and fades up then, rather than popping in and
            // stuttering through the long first frames after a mount.
            renderer.root.components.set(OpacityComponent(opacity: Settle.hiddenOpacity))
            var settle = Settle()
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's arrival and departure, on the shell's one flag.
                    if let renderer, settle.tick(dt: event.deltaTime) {
                        Fade.tick(renderer.root, visible: !appModel.isDeparting,
                                  duration: AppModel.departure)
                    }
                    renderer?.tick(dt: event.deltaTime, model: model)
                    let hand = appModel.room.nearestFingertip(to: Self.wellAnchor)
                    wells?.update(dt: event.deltaTime, nearestHand: hand)
                    syncBloom(dt: event.deltaTime)
                    // The lab's placement: a pure display offset, safe because every grab
                    // moves a body by hand displacement.
                    renderer?.root.position = appModel.labPlacement.offset
                    // Every well and ring is a child of `renderer.root`, so
                    // the whole lab travels together.
                }
            )
            #if DEBUG
            // `-penRing 1` opens the selected bob's control ring at launch (the
            // first bob's when none is), for CLI screenshots.
            if UserDefaults.standard.bool(forKey: "penRing"),
               let first = model.selected ?? model.pendulums.first {
                ring.openID = first.id
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
            // `-penLayers 1` switches on everything More draws.
            if UserDefaults.standard.bool(forKey: "penLayers") {
                model.showVelocity = true
                model.showForces = true
                model.frictionOn = true
            }
            #endif
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
            // A collar press left armed intercepts the next gesture's `onEnded`.
            pressedPivot = nil
            drag = nil
            // A pending press sticks, so an `onEnded` that never arrives would let
            // the next gesture promote it against a stale anchor.
            pressedBob.cancel()
            // Released, not merely forgotten: the model outlives this view.
            model.releaseAll()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    // The ring hangs under `renderer.root`, which carries the lab's
                    // placement; its grip reads the hand in that frame.
                    let ringHand = renderer?.root.convert(position: SIMD3<Float>(hand), from: nil)
                        ?? SIMD3<Float>(hand)
                    if bloom.updateGrip(hand: ringHand) { return }
                    if drag == nil {
                        if bloom.beginGrip(value.entity, hand: ringHand) {
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

                    // A press on the collar that never moved it opens the pendulum's
                    // ring. Folded into this drag rather than a `TapGesture`: two
                    // recognisers over one entity were ambiguous and the rig refused to
                    // be re-hung.
                    if let pressed = pressedPivot {
                        pressedPivot = nil
                        if !pressed.moved {
                            toggleRing(pressed.id, on: value.entity)
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


    /// A pendulum's controls, on its bob. Length is pulled along the
    /// cable: the handle hangs just past the bob, and drawing it down pays
    /// the cable out — the period tag climbs as the square root of length
    /// while the hand is still moving.
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

        // A simple pendulum offers a spring to its nearest neighbour, or to let
        // go of the one it has. The ring is keyed on whether it is coupled,
        // because a petal cannot rename itself.
        let coupled = model.partner(of: uuid) != nil
        var couplePetal: [Bloom.Petal] = []
        if pendulum.kind == .simple {
            couplePetal = [coupled
                ? .init(name: "Uncouple", symbol: "scissors",
                        tint: DesignTokens.Palette.neutralActionUI) { model.uncouple(id: uuid) }
                : .init(name: "Couple", symbol: "link",
                        tint: DesignTokens.Palette.neutralActionUI,
                        isAvailable: { model.couplingCandidate(for: uuid) != nil }) {
                    model.couple(id: uuid)
                }]
        }
        bloom.retarget(
            "\(uuid.uuidString)-\(coupled)",
            petals: couplePetal + [
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
                radius: { Float(pendulum.bobRadius) + 0.03 },
                stretch: Self.lengthStretch(
                    pendulum: { model.pendulums.first(where: { $0.id == uuid }) })))

        let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
        bloom.update(anchor: SIMD3<Float>(pendulum.bobWorld),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }

    /// Length runs along the cable, from the pivot through the bob: the
    /// handle stands just past the bob's surface, and a hand drawn further
    /// down asks for a longer cable by exactly that much. Read relative to
    /// where the bob is now, so it holds on a double pendulum too, whose
    /// lower bob is not one length from the pivot.
    static func lengthStretch(
        pendulum: @escaping () -> PendulumsModel.Pendulum?
    ) -> Bloom.Grip.Stretch {
        let gap: Float = 0.02
        func frame() -> (bob: SIMD3<Float>, down: SIMD3<Float>, clearance: Float, length: Double) {
            guard let current = pendulum() else { return (.zero, [0, -1, 0], gap, 0.8) }
            let bob = SIMD3<Float>(current.bobWorld)
            let cable = bob - SIMD3<Float>(current.pivot)
            let down = simd_length(cable) > 1e-4 ? simd_normalize(cable) : SIMD3<Float>(0, -1, 0)
            return (bob, down, Float(current.bobRadius) + gap, current.length)
        }
        return Bloom.Grip.Stretch(
            origin: { frame().bob },
            handle: { _ in
                let f = frame()
                return f.bob + f.down * f.clearance
            },
            value: { hand, _ in
                let f = frame()
                return f.length + Double(simd_dot(hand - f.bob, f.down) - f.clearance)
            })
    }

    /// Opens or folds a pendulum's ring — from a tap on its bob, a press
    /// that never moved its collar, or VoiceOver — with the pop and tick
    /// every ring in the house makes.
    private func toggleRing(_ id: UUID, on entity: Entity) {
        model.select(id: id)
        if ring.openID == id {
            ring.openID = nil
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
        } else {
            ring.openID = id
            SoundPalette.play(.pop, on: entity, volume: 0.35)
        }
    }

    /// The tap routing, out of the gesture closure so VoiceOver reaches it
    /// too.
    private func handleObjectTap(on entity: Entity) {
        // No pivot branch here: the collar's ring opens from a press that does
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
                toggleRing(id, on: entity)
                return
            }
            current = candidate.parent
        }
        // A tap elsewhere folds the ring.
        if ring.openID != nil {
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
        }
        ring.openID = nil
    }

}
