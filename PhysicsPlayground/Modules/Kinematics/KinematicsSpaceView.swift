//
//  KinematicsSpaceView.swift
//  Physics Playground — Kinematics module
//
//  The room-scale immersive scene. Drags route by entity name through a
//  `RelativeDrag`: the launcher body (move it), the aim bead (point it),
//  any ball (grab and THROW — release velocity comes from the hand's
//  motion), and any hoop (place it). The flight clock is
//  SceneEvents.Update. ("Manipulation events" here named RenderKit's
//  `ManipulationRouter`, which never had a caller and was deleted on
//  2026-08-03.)
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct KinematicsSpaceView: View {
    @Environment(KinematicsModel.self) private var model
    @State private var renderer: KinematicsRenderer?
    @State private var drag: RelativeDrag?
    /// The ball this press landed on, held until it has moved far
    /// enough to be a catch. See `PressLatch`, and the drag's
    /// `onChanged`.
    @State private var pressedBall = PressLatch<BallPress>()

    /// A press on a ball in flight — identity only. Where the ball IS
    /// is read at promotion, not here; see `PressLatch`'s header.
    struct BallPress: Sendable {
        let id: UUID
        let name: String
    }
    @State private var bloom = Bloom()
    /// Whether the launcher's ring is open. A SELECTION, not a model flag:
    /// it stays out of `reset()`, out of the capsule snapshot and out of
    /// the `ResetCoverageTests` sweep, the same reasoning as Circuits'
    /// `highlightedNet`. The ring folded by tap from 2026-09-01; until
    /// then `syncBloom` passed `revealTarget: 1` every frame and the
    /// launcher was the one object in the app whose ring never closed —
    /// against the design system's "unfolded by tap, never gaze". Only
    /// the launch-speed grip lives behind the tap; the aim bead is the
    /// renderer's own sibling entity and stays reachable folded.
    @State private var ring = RingState()
    /// The one id this module's ring can hold for the launcher — there is
    /// one launcher; hoops use their own ids.
    static let launcherRingID = UUID()

    /// Where the custom ball's mass rail hangs: under the launcher,
    /// riding it when it is carried.
    static func massRailCenter(launcher: SIMD3<Double>) -> SIMD3<Float> {
        SIMD3<Float>(launcher) + SIMD3(0, -0.16, 0)
    }
    /// Which ball you are throwing, chosen in the room instead of from a
    /// menu on a card. A golf ball and a table-tennis ball are 17× apart
    /// in mass and behave nothing alike in air, so this is the module's
    /// most consequential choice — and it was the one hidden behind a
    /// collapsed section.
    @State private var ballPicker = SpatialPicker(
        accessibilityNoun: "Ball",
        // `.custom` was filtered out until 2026-09-01; its mass rail hangs
        // under the launcher while it is the pick.
        choices: KinematicsModel.ProjectileKind.allCases
            .map {
                PickerChoice(id: $0.rawValue, label: $0.displayName,
                             symbol: KinematicsSpaceView.symbol(for: $0))
            })
    /// The world you are throwing on, as four discs.
    ///
    /// Zero-g is in this bank and NOT in Pendulums' — a pendulum in
    /// zero-g does not swing, so there is no period to show, whereas a
    /// projectile in zero-g flies dead straight and the straight line IS
    /// the lesson. Same object, same grammar, one more choice.
    @State private var worldPicker = SpatialPicker(
        accessibilityNoun: "World",
        choices: KinematicsModel.gravityPresets.map {
            PickerChoice(id: $0.name, label: $0.name, symbol: "globe")
        },
        staysOpen: true,
        layout: FanLayout(span: 54 * .pi / 180, reach: 0.32,
                          verticalScale: 0.25, lift: 0, stagger: 0))
    /// g between and beyond the worlds — including 0, which is why the
    /// range starts there rather than at the rail's usual floor.
    @State private var gravityTrack: SpatialTrackControl?
    /// Wind. Only exists while the air does: `SpatialTrackControl` gained
    /// an `isEnabled` check during the Electric Fields pass precisely so
    /// a hidden rail stops writing, and this is its first user — a drag
    /// already in flight when air resistance goes off must not keep
    /// setting a wind speed nothing is applying.
    @State private var windTrack: SpatialTrackControl?
    /// The custom ball's mass, on a rail UNDER THE LAUNCHER — the thing
    /// that fires it — present only while the fan says Custom, the way
    /// the wind rail exists only while the air does (2026-09-01). A rail
    /// rather than a ring grip: one grip per ring is the vocabulary's
    /// ceiling and mass has no extent of its own.
    @State private var massTrack: SpatialTrackControl?
    /// Whether the room's walls are real, and whether the air is.
    @State private var layers: SpatialLayerBank?
    @State private var activeTrack: SpatialTrackControl?
    /// The ball well: pull one out and it is already in your hand —
    /// the launcher stops being the only way a ball enters the room.
    @State private var wells: Well?

    // An instrument wall LEFT of the launcher's home, at its depth —
    // never in the firing line (the launcher opens at x = −0.6 down −z).
    // It does NOT ride the launcher: `SpatialTrackControl.adjust(hand:)`
    // measures against `root.position`, so a carried rail would shift its
    // own mapping mid-drag.
    //
    // ONE COLUMN, because three constraints meet and only two can hold
    // for anything outboard of the rails: reach (≤ 1.25 m), off-axis
    // (≤ 48°) and the firing line. Depth is set by the ANGLE, not reach:
    // z −0.94 holds 43.8° and still brings every instrument inside 1.25 m.
    // Order top down: ball, world, its g, its wind, then the room's
    // material — the well leads because a small box's near face is far.
    private static let wallX: Float = -0.90
    private static let wallZ: Float = -0.94

    /// Internal since 2026-08-09 so the reach criterion can measure it.
    ///
    /// TWO MOUTHS ON THE WELL ROW since 2026-09-01 — the ball inboard,
    /// the hoop outboard — at the pitch Electric Fields' four mouths
    /// share (0.095), centred on the column's x. The row is the only
    /// place a second mouth fits: sideways toward the launcher is the
    /// firing line, further outboard fails reach (√(1.06² + 0.94²) is
    /// 1.41 m before any height), and a sixth row would push the bank
    /// below knee height. Measured, not reasoned: the hoop mouth's near
    /// face is 1.20 m from a standing viewer against the 1.25 limit, and
    /// the ball mouth's inboard edge stays 0.15 m clear of the launcher's
    /// line — `InstrumentReachCriterionTests` holds both.
    static let wellAnchor = SIMD3<Float>(wallX + 0.0475, 1.70, wallZ)
    /// The hoop's mouth: a target you make, beside the ball you throw at
    /// it. Hoops are MATERIALS, not instruments — pulled from a well like
    /// a ball or a magnet, nothing standing at rest, which is the answer
    /// to the 2026-07-29 clutter objection that put them in a mothball.
    static let hoopWellAnchor = SIMD3<Float>(wallX - 0.0475, 1.70, wallZ)
    static let worldsAnchor = SIMD3<Float>(wallX, 1.50, wallZ)
    static let gravityCenter = SIMD3<Float>(wallX, 1.30, wallZ)
    static let windCenter = SIMD3<Float>(wallX, 1.10, wallZ)
    static let bankAnchor = SIMD3<Float>(wallX, 0.90, wallZ)
    /// Unchanged: the wall's bearing from a standing viewer is 43.8°,
    /// which is where it was, so the angle it is turned to should be too.
    private static let instrumentNormal = SIMD3<Float>(0.42, 0, 0.91)

    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            let renderer = KinematicsRenderer()
            renderer.onObjectTap = { handleObjectTap(on: $0) }
            content.add(renderer.root)
            // ARRIVES, NEVER APPEARS. Disabled here and raised by
            // `Fade.tick` below, so the apparatus resolves into the room
            // instead of being there between one frame and the next.
            renderer.root.isEnabled = false

            // THE WELCOME SHOT REACHES THE SECOND VISIT. `reset()` ends with
            // `fire()` and calls it "one shot already in the air", which is
            // right — but the model is retained on `AppModel`, so it fired
            // once per PROCESS and every later entry opened onto a dead
            // range. This is the same shot at the moment it was always meant
            // for, not a new behaviour.
            //
            // Guarded on an empty range rather than calling `reset()`, which
            // would throw away whatever the wearer had set up.
            if model.flights.isEmpty { model.fire() }

            renderer.root.addChild(bloom.root)
            renderer.root.addChild(ballPicker.root)
            ballPicker.onSelect = { id in
                guard let kind = KinematicsModel.ProjectileKind(rawValue: id) else { return }
                model.kind = kind
            }
            renderer.root.addChild(worldPicker.root)
            worldPicker.onSelect = { name in
                guard let world = KinematicsModel.gravityPresets
                    .first(where: { $0.name == name }) else { return }
                model.gravity = world.gravity
            }
            // The lit disc is read from the model, so dragging the rail
            // off a world darkens it and Reset lights Earth again.
            worldPicker.selectedID = {
                KinematicsModel.gravityPresets
                    .first { abs($0.gravity - model.gravity) < 0.01 }?.name
            }

            let bank = SpatialLayerBank(
                accent: UIColor(DesignTokens.Palette.kinematicsAccent),
                layers: [
                    // Neither of these draws anything. Both change what
                    // the room IS: whether its walls stop a ball, and
                    // whether its air does. The bank carries them because
                    // they are still labelled discrete choices, and the
                    // labels say what they do rather than what is shown.
                    .init(id: "walls", label: "Walls bounce",
                          symbol: "square.dashed",
                          isOn: { model.respectRoomWalls },
                          toggle: { model.respectRoomWalls.toggle() }),
                    .init(id: "air", label: "Air resistance", symbol: "wind",
                          isOn: { model.airResistance },
                          toggle: { model.airResistance.toggle() }),
                ])
            renderer.root.addChild(bank.root)
            layers = bank

            let gravity = SpatialTrackControl(
                name: "Gravity",
                center: Self.gravityCenter,
                normal: Self.instrumentNormal,
                accent: UIColor(DesignTokens.Palette.kinematicsAccent),
                range: KinematicsModel.gravityRange,
                read: { model.gravity },
                write: { model.gravity = $0 },
                format: { PhysicsFormat.measurement($0, "m/s²", decimals: 2) })
            renderer.root.addChild(gravity.root)
            gravityTrack = gravity

            let wind = SpatialTrackControl(
                name: "Wind",
                center: Self.windCenter,
                normal: Self.instrumentNormal,
                accent: UIColor(DesignTokens.Palette.kinematicsAccent),
                range: KinematicsModel.windSpeedRange,
                read: { model.windSpeed },
                write: { model.windSpeed = $0 },
                format: { PhysicsFormat.measurement($0, "m/s", decimals: 1) })
            renderer.root.addChild(wind.root)
            windTrack = wind

            let mass = SpatialTrackControl(
                name: "Mass",
                center: Self.massRailCenter(launcher: model.launcherPosition),
                normal: SIMD3(0, 0, 1),
                accent: UIColor(DesignTokens.Palette.kinematicsAccent),
                range: KinematicsModel.customMassRange,
                read: { model.customMass },
                write: { model.customMass = $0 },
                format: { PhysicsFormat.measurement($0, "kg", decimals: 2) },
                subtitle: { _ in "Ø 10 cm — same size, different mass" })
            mass.isEnabled = model.kind == .custom
            renderer.root.addChild(mass.root)
            massTrack = mass

            // The ball well, on the instrument wall under the switch
            // bank — out of the firing line with the rest of the
            // furniture, and deliberately NOT riding the launcher. A
            // ball pulled from it is born at the fingertips, staged and
            // inert, and rides the same grab/hold/release path a caught
            // ball does — so throwing it is the throw the module
            // already knows (owner, 2026-08-04: the launcher used to be
            // the only way to get a ball at all).
            let sources = Well([
                .init(name: "Ball",
                      tint: UIColor(DesignTokens.Palette.kinematicsAccent),
                      label: "Add ball",
                      preview: { KinematicsRenderer.ballPreview() },
                      position: Self.wellAnchor,
                      spawn: { point in
                          let id = model.spawnBall(at: point)
                          // Already in the hand: grabbing it here is
                          // what arms the throw sampler, so letting go
                          // with a moving hand throws and letting go
                          // still just hangs it in the air.
                          model.grabBall(id: id)
                          return id
                      }),
                // The hoop (2026-09-01). Born at the hand and carried by
                // the same gesture — `apply(drag:)` already routes a
                // ring's id to `moveRing`. Nil at the budget of three
                // fades the mouth in refusal.
                .init(name: "Hoop",
                      tint: DesignTokens.Palette.targetUI,
                      label: "Add hoop",
                      preview: { KinematicsRenderer.hoopPreview() },
                      position: Self.hoopWellAnchor,
                      spawn: { point in model.addRing(at: point) }),
            ])
            renderer.root.addChild(sources.root)
            wells = sources

            #if DEBUG
            // `-kinBalls 1` opens the ball fan at launch, so the picker is
            // screenshot-checkable from the CLI (no hand to pinch with).
            if UserDefaults.standard.bool(forKey: "kinBalls") {
                ballPicker.toggle()
            }
            // `-kinRing 1` opens the launcher's ring — folded by default
            // since 2026-09-01, and the simulator cannot tap the launcher.
            if UserDefaults.standard.bool(forKey: "kinRing") {
                ring.openID = Self.launcherRingID
            }
            // `-kinHoops 2` stands two hoops in the spawn layout — the
            // well's pull needs a hand the simulator does not have.
            let hoops = UserDefaults.standard.integer(forKey: "kinHoops")
            for _ in 0..<max(0, hoops) { model.addRing() }
            // `-kinSolve 1` opens the first hoop's ring and aims at it,
            // which is what draws the two ghost arcs and the callout.
            if UserDefaults.standard.bool(forKey: "kinSolve"),
               let first = model.rings.first?.id {
                ring.openID = first
                model.aimTargetID = first
            }
            // `-kinBall custom -kinMass 2.0` picks a ball and, for the
            // custom one, its mass; `-kinAir 1` switches the air on with
            // no wind, which is what the vacuum ghost needs (`-kinWind`
            // implies a wind).
            if let raw = UserDefaults.standard.string(forKey: "kinBall"),
               let kind = KinematicsModel.ProjectileKind(rawValue: raw) {
                model.kind = kind
            }
            if UserDefaults.standard.object(forKey: "kinMass") != nil {
                let mass = UserDefaults.standard.double(forKey: "kinMass")
                model.customMass = min(max(mass, KinematicsModel.customMassRange.lowerBound),
                                       KinematicsModel.customMassRange.upperBound)
            }
            if UserDefaults.standard.bool(forKey: "kinAir") {
                model.airResistance = true
            }
            // `-kinGravity 1.62` moves the g rail's bead AND lights the
            // Moon disc — a value, not a flag, because a bead parked at
            // its default proves nothing about the mapping behind it.
            let forcedGravity = UserDefaults.standard.object(forKey: "kinGravity")
            if forcedGravity != nil {
                let g = UserDefaults.standard.double(forKey: "kinGravity")
                model.gravity = min(max(g, KinematicsModel.gravityRange.lowerBound),
                                    KinematicsModel.gravityRange.upperBound)
            }
            // `-kinWind 8` switches the air on and sets a wind — the only
            // way to see the wind rail at all, since it is hidden until
            // there is air for it to blow.
            if UserDefaults.standard.object(forKey: "kinWind") != nil {
                model.airResistance = true
                let speed = UserDefaults.standard.double(forKey: "kinWind")
                model.windSpeed = min(max(speed,
                                          KinematicsModel.windSpeedRange.lowerBound),
                                      KinematicsModel.windSpeedRange.upperBound)
            }
            #endif

            renderer.subscriptions = []

            // Flight clock: step every rendered frame (simulated time —
            // the model applies the slow-motion scale and pause).
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
                    // Detected walls (from the SHARED room session) flow
                    // into the physics. Everything the room hands the model
                    // is TRANSLATED INTO MODULE SPACE first: model
                    // coordinates render under `renderer.root`, which
                    // carries the lab-placement offset, so raw world walls
                    // are wrong by exactly that offset once the lab moves.
                    let placement = SIMD3<Double>(appModel.labPlacement.offset)
                    if appModel.room.hasScannedRoom {
                        // Detected walls backed by the room's boundary
                        // box, so a ball ALWAYS bounces at the room's
                        // edge — including walls never looked at, and
                        // the ceiling. The bounds also feed the
                        // containment clamp: no escape, ever.
                        model.roomWalls = appModel.room.collisionWalls
                            .map { $0.translated(by: -placement) }
                        model.roomBounds = appModel.room.bounds
                            .translated(by: -placement)
                    }
                    model.step(dt: event.deltaTime)
                    // A ball reaching an open hand is caught. Device-only
                    // (the simulator reports no fingertips); fingertips
                    // cross into module space like the walls do.
                    model.catchBalls(atFingertips:
                        appModel.room.fingertips.map { $0 - placement })
                    renderer?.tick(model)
                    wells?.update(dt: event.deltaTime,
                                  nearestHand: appModel.room.nearestFingertip(
                                    to: Self.bankAnchor))
                    syncBloom(dt: event.deltaTime)
                    // Constant display offset — safe because grabs move a
                    // body by hand displacement. Every bank, rail, well and
                    // ring is a child of `renderer.root`, so the whole lab
                    // travels together: a rail belongs to the thing it sets.
                    renderer?.root.position = appModel.labPlacement.offset
                }
            )

            renderer.tick(model)
            self.renderer = renderer
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
            // A rail mid-adjust swallows every `onChanged` until an
            // `onEnded` clears it, against an orphaned control.
            activeTrack = nil
            drag = nil
            // A pending press now STICKS — `press` refuses to overwrite
            // one — so an `onEnded` that never arrives would otherwise
            // let the next gesture promote it on frame one, against a
            // stale anchor, and grab the object you pressed last time.
            pressedBall.cancel()
            // A selection, so it does not survive the lab: the next entry
            // opens on a folded ring like every other module.
            ring.openID = nil
            model.aimTargetID = nil
        }
        .task {
            // Plane detection: device-only, quietly absent in the sim.
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in handleObjectTap(on: value.entity) }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                    // A gesture already in a rail may not be re-claimed: a
                    // drag that starts on the wind rail and wanders over a
                    // ball must not pick the ball up.
                    if let track = activeTrack {
                        guard track.isEnabled else {
                            activeTrack = nil
                            return
                        }
                        track.adjust(hand: hand)
                        return
                    }
                    if drag == nil {
                        for track in [gravityTrack, windTrack, massTrack].compactMap({ $0 })
                        where track.owns(value.entity) {
                            activeTrack = track
                            track.adjust(hand: hand)
                            return
                        }
                        if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                        // Born at the fingertips, and dragged by the
                        // same gesture that made it.
                        if let id = wells?.pull(value.entity, at: hand) {
                            drag = RelativeDrag(name: id.uuidString,
                                                target: hand, hand: hand)
                            return
                        }
                        // A TAP ON A FLYING BALL MUST NOT CATCH IT: at
                        // `minimumDistance: 0` a bare press would freeze the
                        // ball, hold it, and release it with no hand motion,
                        // leaving it dead in mid-air. Only the ball needs
                        // this — the launcher, bead and hoops are positional,
                        // so a press that doesn't move moves them by zero.
                        if let press = flightPress(on: value.entity) {
                            pressedBall.press(press, at: hand)
                        } else {
                            drag = beginDrag(entity: value.entity, hand: hand)
                        }
                    }

                    // The promotion, once the hand has actually carried
                    // the ball. The drag pairs where the ball is NOW
                    // with where the hand is now, so the catch does not
                    // move the ball at all — the same behaviour Gravity
                    // Lab gets from its `minimumDistance`.
                    if drag == nil, pressedBall.isPending {
                        guard let caught = pressedBall.promote(hand: hand),
                              let flight = model.flights.first(where: {
                                  $0.id == caught.id
                              })
                        else { return }
                        model.grabBall(id: caught.id)
                        drag = RelativeDrag(name: caught.name,
                                            target: flight.state.position,
                                            hand: hand)
                    }
                    guard let drag else { return }
                    apply(drag: drag, hand: hand)
                }
                .onEnded { value in
                    // A ball press that never became a carry is a tap,
                    // and a tap on a ball does nothing to the ball.
                    pressedBall.cancel()
                    if let track = activeTrack {
                        track.endAdjust()
                        activeTrack = nil
                        return
                    }
                    bloom.endGrip()
                    defer { drag = nil }
                    guard let drag else { return }
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    apply(drag: drag, hand: hand)
                    if let id = UUID(uuidString: drag.name),
                       model.flights.contains(where: { $0.id == id }) {
                        model.releaseBall(id: id)
                    }
                }
        )
    }

    /// Resolves a pinch: launcher body, aim bead, a flying/resting
    /// ball, or a hoop.

    /// The launcher's own control. Launch SPEED has no size of its own
    /// — but its consequence does: the predicted arc, already drawn,
    /// stretches across the room as you pull. You are aiming a throw by
    /// changing the shape of where it lands.
    private func syncBloom(dt: Double) {
        let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
        // A HOOP'S RING (2026-09-01): the one Bloom retargets to whichever
        // hoop is selected — Delete, and the aim solutions once they
        // exist. Its anchor rides the hoop, so a hoop being carried
        // carries its own ring.
        if let id = ring.openID, id != Self.launcherRingID,
           let hoop = model.rings.first(where: { $0.id == id }) {
            // Three petals — `Petal`'s own ceiling. The two aims are dim
            // while the hoop is out of range at the current speed; the
            // solve is memoised, so asking every frame is cheap.
            bloom.retarget(
                id,
                petals: [
                    .init(name: "Aim low", symbol: "arrow.down.right",
                          tint: UIColor(DesignTokens.Palette.kinematicsAccent),
                          isAvailable: { model.solutions(for: id) != nil }) {
                        model.aim(atSolution: .low, for: id)
                    },
                    .init(name: "Aim high", symbol: "arrow.up.right",
                          tint: UIColor(DesignTokens.Palette.kinematicsAccent),
                          isAvailable: { model.solutions(for: id) != nil }) {
                        model.aim(atSolution: .high, for: id)
                    },
                    .init(name: "Delete", symbol: "trash",
                          tint: DesignTokens.Palette.neutralActionUI) { [ring] in
                        model.removeRing(id: id)
                        ring.openID = nil
                    },
                ],
                grip: nil)
            bloom.update(anchor: SIMD3<Float>(hoop.position) + SIMD3(0, 0.12, 0),
                         viewer: viewer, revealTarget: 1, dt: dt)
            return
        }
        let anchor = SIMD3<Float>(model.launcherPosition) + SIMD3(0, 0.12, 0)
        bloom.retarget(
            "launcher",
            petals: [
                .init(name: "Fire", symbol: "paperplane.fill",
                      tint: UIColor(DesignTokens.Palette.kinematicsAccent)) {
                    model.fire()
                },
                .init(name: "Balls", symbol: "circle.grid.2x2.fill",
                      tint: DesignTokens.Palette.neutralActionUI) { [ballPicker] in
                    ballPicker.toggle()
                },
                // Clear the volley — the third petal, `Petal`'s own ceiling.
                // `isAvailable` MUST be a closure, not a Bool: `retarget`
                // rebuilds only when the target id changes, and this bloom's
                // id is the constant "launcher", so a value read at configure
                // time would freeze on the first frame's state. `confirms`
                // gives it the same two-tap arm the standing plates use.
                .init(name: "Clear", symbol: "trash.slash",
                      tint: DesignTokens.Palette.neutralActionUI,
                      isAvailable: { !model.flights.isEmpty },
                      confirms: true) {
                    model.clearFlights()
                },
            ],
            grip: .init(
                name: "Launch speed",
                range: KinematicsModel.speedRange,
                read: { model.launchSpeed },
                write: { model.launchSpeed = $0 },
                format: { PhysicsFormat.measurement($0, "m/s", decimals: 1) },
                radius: { 0.10 }))
        // Open only while selected — `Bloom` eases the fold itself, and a
        // grip mid-drag pins it open whatever this says.
        bloom.update(anchor: anchor, viewer: viewer,
                     revealTarget: ring.openID == Self.launcherRingID ? 1 : 0,
                     dt: dt)
        // Clear of the bloom's own petal arc, which reaches ~0.17 m up.
        let hand = appModel.room.nearestFingertip(to: anchor)
        ballPicker.update(anchor: anchor + SIMD3(0, 0.20, 0),
                          viewer: viewer, dt: dt, nearestHand: hand)

        worldPicker.update(anchor: Self.worldsAnchor, viewer: viewer, dt: dt,
                           nearestHand: hand)
        layers?.update(anchor: Self.bankAnchor, viewer: viewer, dt: dt,
                       nearestHand: hand)
        // Nothing ticks a track by itself — the caller's duty, stated on
        // `SpatialTrackControl.refresh`.
        gravityTrack?.refresh()
        // The wind rail exists only while the air does. `isEnabled` also
        // kills a drag already in flight, which is the case that bites:
        // the gesture keeps delivering `onChanged` after the plate goes
        // dark, and without this the rail would go on writing a wind
        // speed nothing is applying.
        windTrack?.isEnabled = model.airResistance
        if model.airResistance { windTrack?.refresh() }
        // The mass rail exists exactly while the custom ball is the pick,
        // and rides the launcher it hangs under.
        let custom = model.kind == .custom
        massTrack?.isEnabled = custom
        if custom, let mass = massTrack {
            mass.root.position = Self.massRailCenter(launcher: model.launcherPosition)
            mass.refresh()
        }
    }

    /// The glyph each ball wears on its disc — Kinematics vocabulary, not
    /// the picker's business.
    private static func symbol(for kind: KinematicsModel.ProjectileKind) -> String? {
        switch kind {
        case .tableTennisBall: "circle"
        case .basketball: "basketball.fill"
        case .golfBall: "circle.dotted"
        case .cannonball: "circle.fill"
        case .custom: "scalemass"
        }
    }

    private func beginDrag(entity: Entity, hand: SIMD3<Double>) -> RelativeDrag? {
        var current: Entity? = entity
        while let candidate = current {
            switch candidate.name {
            case KinematicsRenderer.launcherName:
                return RelativeDrag(name: candidate.name,
                                    target: model.launcherPosition, hand: hand)
            case KinematicsRenderer.aimBeadName:
                let target = model.launcherPosition
                    + Double(KinematicsRenderer.beadDistance) * model.aimDirection
                return RelativeDrag(name: candidate.name, target: target, hand: hand)
            default:
                if let id = UUID(uuidString: candidate.name),
                   let ring = model.rings.first(where: { $0.id == id }) {
                    return RelativeDrag(name: candidate.name,
                                        target: ring.position, hand: hand)
                }
                // NO flight branch. A ball is claimed by `flightPress`
                // and promoted only once the hand has moved — see the
                // drag's `onChanged`.
                current = candidate.parent
            }
        }
        return nil
    }

    /// A press that landed on a ball in flight, or nil. Resolves the
    /// same way `beginDrag` does — up the parent chain to the named
    /// object — but takes no action, because taking action is exactly
    /// what a tap must not do here.
    private func flightPress(on entity: Entity) -> BallPress? {
        var current: Entity? = entity
        while let candidate = current {
            if let id = UUID(uuidString: candidate.name),
               model.flights.contains(where: { $0.id == id }) {
                return BallPress(id: id, name: candidate.name)
            }
            current = candidate.parent
        }
        return nil
    }

    private func apply(drag: RelativeDrag, hand: SIMD3<Double>) {
        let position = drag.position(forHand: hand)
        switch drag.name {
        case KinematicsRenderer.launcherName:
            model.moveLauncher(to: position)
        case KinematicsRenderer.aimBeadName:
            model.aim(toward: position)
        default:
            guard let id = UUID(uuidString: drag.name) else { return }
            if model.rings.contains(where: { $0.id == id }) {
                model.moveRing(id: id, to: position)
            } else {
                model.holdBall(id: id, at: position)
            }
        }
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
        // The fan first: its discs sit above the launcher and
        // would otherwise be read as a tap on the launcher.
        if ballPicker.handleTap(entity) { return }
        if worldPicker.handleTap(entity) { return }
        if layers?.handleTap(entity) == true { return }
        // A petal or the grip took the tap: the ring stays as it is. A
        // dim petal returns false and the tap falls through to the fold,
        // exactly as Magnetism's does.
        if bloom.handleTap(entity) { return }
        // A hoop toggles its own ring, ahead of the launcher's grammar.
        // The model mirrors the selection so the renderer can draw the
        // ghost arcs and the callout for the hoop being aimed at.
        if let hoop = Self.hoopID(under: entity, rings: model.rings) {
            let open = ring.openID != hoop
            SoundPalette.play(open ? .pop : .releaseTick, on: entity,
                              volume: open ? 0.35 : 0.3)
            ring.openID = open ? hoop : nil
            model.aimTargetID = open ? hoop : nil
            return
        }
        let wasOpen = ring.openID == Self.launcherRingID
        let open = Self.launcherRingOpen(afterTapOn: entity, wasOpen: wasOpen)
        if open != (ring.openID != nil) {
            // The unfold pops; a silent fold read as broken.
            SoundPalette.play(open ? .pop : .releaseTick, on: entity,
                              volume: open ? 0.35 : 0.3)
        }
        ring.openID = open ? Self.launcherRingID : nil
        if model.aimTargetID != nil { model.aimTargetID = nil }
    }

    /// The hoop a tap landed on, by walking the parent chain to the
    /// entity the renderer named with the ring's id — nil for anything
    /// that is not a hoop. Pure, so `LauncherRingTests` can drive it.
    static func hoopID(under entity: Entity, rings: [KinematicsModel.Ring]) -> UUID? {
        var current: Entity? = entity
        while let candidate = current {
            if let id = UUID(uuidString: candidate.name),
               rings.contains(where: { $0.id == id }) {
                return id
            }
            current = candidate.parent
        }
        return nil
    }

    /// What a tap does to the launcher's ring, as a pure function of what
    /// was tapped — a static over entity names, like Circuits'
    /// `resolveGrab`, so the routing is testable without a headset.
    ///
    /// The launcher toggles it. The aim bead leaves it alone: aiming is
    /// the launcher's own verb and a zero-travel aim must not fold the
    /// ring the wearer just opened. Anything else — a ball, a hoop, empty
    /// space — folds it, which is the same grammar every other module's
    /// ring answers to.
    static func launcherRingOpen(afterTapOn entity: Entity, wasOpen: Bool) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            switch candidate.name {
            case KinematicsRenderer.launcherName: return !wasOpen
            case KinematicsRenderer.aimBeadName: return wasOpen
            default: current = candidate.parent
            }
        }
        return false
    }

}
