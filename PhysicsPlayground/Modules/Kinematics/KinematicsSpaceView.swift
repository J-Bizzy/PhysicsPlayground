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
    /// Which ball you are throwing, chosen in the room instead of from a
    /// menu on a card. A golf ball and a table-tennis ball are 17× apart
    /// in mass and behave nothing alike in air, so this is the module's
    /// most consequential choice — and it was the one hidden behind a
    /// collapsed section.
    @State private var ballPicker = SpatialPicker(
        accessibilityNoun: "Ball",
        choices: KinematicsModel.ProjectileKind.allCases
            .filter { $0 != .custom }
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
    /// Whether the room's walls are real, and whether the air is.
    @State private var layers: SpatialLayerBank?
    @State private var activeTrack: SpatialTrackControl?
    /// The ball well: pull one out and it is already in your hand —
    /// the launcher stops being the only way a ball enters the room.
    @State private var wells: Well?

    // Placement: an instrument wall to the LEFT of the launcher's home,
    // at its depth. This module is 1:1 with the room and balls go
    // everywhere, so the one thing these must not do is stand in the
    // firing line — the launcher opens at x = −0.6 aiming down −z, so
    // everything here sits further out in −x, beside the shot rather
    // than in front of it.
    //
    // They do NOT ride the launcher, though it is grabbable and the
    // controls would then live on the apparatus. Two reasons, and the
    // second is a correctness one: `SpatialTrackControl.adjust(hand:)`
    // measures the hand against `root.position`, so a rail whose root is
    // being carried would shift its own mapping mid-drag; and a rig of
    // four instruments swinging around the room with the launcher is a
    // lot of furniture to drag through a wall.
    private static let instrumentZ: Float = -1.10
    private static let bankAnchor = SIMD3<Float>(-1.52, 1.34, instrumentZ)
    private static let worldsAnchor = SIMD3<Float>(-1.05, 1.50, instrumentZ)
    private static let gravityCenter = SIMD3<Float>(-1.05, 1.30, instrumentZ)
    private static let windCenter = SIMD3<Float>(-1.05, 1.10, instrumentZ)
    private static let instrumentNormal = SIMD3<Float>(0.42, 0, 0.91)

    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            let renderer = KinematicsRenderer()
            content.add(renderer.root)
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
                format: { String(format: "%.2f m/s²", $0) })
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
                format: { String(format: "%.1f m/s", $0) })
            renderer.root.addChild(wind.root)
            windTrack = wind

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
                      position: SIMD3(-1.52, 1.06, Self.instrumentZ),
                      spawn: { point in
                          let id = model.spawnBall(at: point)
                          // Already in the hand: grabbing it here is
                          // what arms the throw sampler, so letting go
                          // with a moving hand throws and letting go
                          // still just hangs it in the air.
                          model.grabBall(id: id)
                          return id
                      }),
            ])
            renderer.root.addChild(sources.root)
            wells = sources

            #if DEBUG
            // `-kinBalls 1` opens the ball fan at launch, so the picker is
            // screenshot-checkable from the CLI (no hand to pinch with).
            if UserDefaults.standard.bool(forKey: "kinBalls") {
                ballPicker.toggle()
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
                    // On device, detected walls flow into the physics.
                    // The walls come from the SHARED room session — this
                    // module used to run a second plane-detection session
                    // of its own, for the same planes the shell was
                    // already tracking.
                    // Everything the room hands the model is TRANSLATED
                    // INTO MODULE SPACE first. The model's coordinates
                    // render under `renderer.root`, which carries the
                    // lab-placement offset — so a wall fed in raw world
                    // coordinates is correct only while the lab has
                    // never been moved, and wrong by exactly the offset
                    // after the anchor relocates it. "Bounces at the
                    // wall sometimes, a step past it other times" was
                    // this line, not the physics.
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
                    // A ball that reaches an open hand is caught: the
                    // one moment in the module where the simulation
                    // reaches back to you. Device-only — the simulator
                    // reports no fingertips, so this is simply inert
                    // there. Fingertips arrive in world space and cross
                    // into module space like the walls do.
                    model.catchBalls(atFingertips:
                        appModel.room.fingertips.map { $0 - placement })
                    renderer?.tick(model)
                    wells?.update(dt: event.deltaTime)
                    syncBloom(dt: event.deltaTime)
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

            renderer.tick(model)
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
            // A rail mid-adjust swallows every `onChanged` until an
            // `onEnded` clears it, against an orphaned control.
            activeTrack = nil
            drag = nil
            // A pending press now STICKS — `press` refuses to overwrite
            // one — so an `onEnded` that never arrives would otherwise
            // let the next gesture promote it on frame one, against a
            // stale anchor, and grab the object you pressed last time.
            pressedBall.cancel()
        }
        .task {
            // Plane detection: device-only, quietly absent in the sim.
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // The fan first: its discs sit above the launcher and
                    // would otherwise be read as a tap on the launcher.
                    if ballPicker.handleTap(value.entity) { return }
                    if worldPicker.handleTap(value.entity) { return }
                    if layers?.handleTap(value.entity) == true { return }
                    _ = bloom.handleTap(value.entity)
                }
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
                        for track in [gravityTrack, windTrack].compactMap({ $0 })
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
                        // A TAP ON A FLYING BALL MUST NOT CATCH IT.
                        //
                        // This recogniser is `minimumDistance: 0`, so it
                        // fires on a bare press, and for a ball in
                        // flight the whole path runs: `grabBall` freezes
                        // it, `apply` holds it exactly where it was, and
                        // `onEnded` releases it with no hand motion to
                        // throw it. The ball stopped dead in mid-air and
                        // hung there — losing its strobe trail and its
                        // flight record — because you looked at it and
                        // pinched. Gravity Lab already carried the same
                        // diagnosis about tapping a planet.
                        //
                        // Only the ball needs this. The launcher, the aim
                        // bead and a hoop are positional: a press that
                        // does not move moves them by zero.
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
        let anchor = SIMD3<Float>(model.launcherPosition) + SIMD3(0, 0.12, 0)
        bloom.retarget(
            "launcher",
            petals: [
                .init(name: "Fire", symbol: "paperplane.fill",
                      tint: UIColor(DesignTokens.Palette.kinematicsAccent)) {
                    model.fire()
                },
                .init(name: "Balls", symbol: "circle.grid.2x2.fill",
                      tint: UIColor(white: 0.45, alpha: 1)) { [ballPicker] in
                    ballPicker.toggle()
                },
                // Clearing the volley, off the window panel. The
                // launcher made every ball in the room, so the thing
                // that unmakes them belongs on the launcher — and this
                // is the third petal, which is the ceiling `Petal`'s own
                // doc sets ("two or three per object, never more").
                //
                // UNCONDITIONAL, and that is not laziness. The panel
                // button was `.disabled(flights.isEmpty)` and the
                // obvious translation is to leave the petal out when
                // there is nothing to clear — but `retarget` rebuilds
                // ONLY when the target id changes, and this bloom's id
                // is the constant "launcher". A conditional list would
                // be evaluated once, on the first frame, and then never
                // again: the petal would be permanently present or
                // permanently absent depending on what the room happened
                // to look like at launch. Clearing nothing is a no-op;
                // a control that silently stops tracking its condition
                // is a lie.
                // BOTH of those are expressible now (2026-08-03). The
                // note above is why they were not: a plain `Bool` read
                // once at configure time would freeze, so the petal had
                // no condition at all — and, separately, no confirmation,
                // which made this the one destructive verb in the app
                // with no guard. Circuits' and Electric Fields' identical
                // "Clear" are both confirming plates that track their own
                // availability; this was one pinch.
                //
                // `isAvailable` is a closure, so it is read every frame
                // and cannot freeze. `confirms` gives it the same two-tap
                // arm the standing plates use.
                .init(name: "Clear", symbol: "trash.slash",
                      tint: UIColor(white: 0.45, alpha: 1),
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
                format: { String(format: "%.1f m/s", $0) },
                radius: { 0.10 }))
        let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
        bloom.update(anchor: anchor, viewer: viewer, revealTarget: 1, dt: dt)
        // Clear of the bloom's own petal arc, which reaches ~0.17 m up.
        ballPicker.update(anchor: anchor + SIMD3(0, 0.20, 0),
                          viewer: viewer, dt: dt)

        worldPicker.update(anchor: Self.worldsAnchor, viewer: viewer, dt: dt)
        layers?.update(anchor: Self.bankAnchor, viewer: viewer, dt: dt)
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
    }

    /// The glyph each ball wears on its disc — Kinematics vocabulary, not
    /// the picker's business.
    private static func symbol(for kind: KinematicsModel.ProjectileKind) -> String? {
        switch kind {
        case .tableTennisBall: "circle"
        case .basketball: "basketball.fill"
        case .golfBall: "circle.dotted"
        case .cannonball: "circle.fill"
        case .custom: nil
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
}
