//
//  KinematicsSpaceView.swift
//  Physics Playground — Kinematics module
//
//  The room-scale immersive scene. Drags route by entity name through a
//  `RelativeDrag`: the launcher body (move it), the aim bead (point it),
//  any ball (grab and throw — release velocity comes from the hand's
//  motion), and any hoop (place it). The flight clock is
//  SceneEvents.Update.
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

    /// A press on a ball in flight — identity only. Where the ball is
    /// is read at promotion, not here; see `PressLatch`'s header.
    struct BallPress: Sendable {
        let id: UUID
        let name: String
    }
    @State private var bloom = Bloom()
    /// Whether the launcher's ring is open. A selection, not a model flag:
    /// out of `reset()`, the snapshot and the `ResetCoverageTests` sweep.
    /// The ring folds by tap; the aim bead — angle and speed — stays
    /// reachable folded.
    @State private var ring = RingState()
    /// The one id this module's ring can hold for the launcher — there is
    /// one launcher; hoops use their own ids.
    static let launcherRingID = UUID()

    /// Which ball you are throwing, chosen in the room. A golf ball and a
    /// table-tennis ball are 17× apart in mass and behave nothing alike in
    /// air.
    @State private var ballPicker = SpatialPicker(
        accessibilityNoun: "Ball",
        choices: KinematicsModel.ProjectileKind.allCases
            .map {
                PickerChoice(id: $0.rawValue, label: $0.displayName,
                             symbol: KinematicsSpaceView.symbol(for: $0))
            },
        layout: KinematicsSpaceView.ballFanLayout)

    /// The ball fan opens above and to the right of the launcher, tighter
    /// than the house default, so it stays off the arc it is about to
    /// throw along.
    static let ballFanLayout = FanLayout(span: 120 * .pi / 180, reach: 0.22)
    static let ballFanOffset = SIMD3<Float>(0.10, 0.24, 0)
    /// The two answers to "which arc reaches this hoop", as a fan opened
    /// from the hoop's Aim petal.
    @State private var aimPicker = SpatialPicker(
        accessibilityNoun: "Arc",
        choices: [
            PickerChoice(id: "low", label: "Low arc", symbol: "arrow.down.right"),
            PickerChoice(id: "high", label: "High arc", symbol: "arrow.up.right"),
        ])
    /// The ball well: pull one out and it is already in your hand —
    /// the launcher stops being the only way a ball enters the room.
    @State private var wells: Well?

    // The wells stand left of the launcher's home — never in the firing
    // line. Its world, its air and its walls are in More.
    private static let wallX: Float = -0.90
    private static let wallZ: Float = -0.94

    /// The ball's mouth: a ball always waiting at chest height on your left,
    /// taken and thrown and there again (2026-10-17, throwing the main act).
    /// It came down from the hoop's row at 1.70 m, head height, which is
    /// where you reach for a part, not where you pick up a ball to throw. As
    /// near as two house rules allow: clear of the launcher's line
    /// (x < −0.65) and within 48° of straight ahead — about 1.1 m from the
    /// eyes, a lean from the left shoulder.
    static let wellAnchor = SIMD3<Float>(-0.76, 1.18, -0.70)
    /// The hoop's mouth, up on the row above the ball you throw at it.
    /// Hoops are materials, not instruments: pulled from a well, nothing
    /// standing at rest.
    static let hoopWellAnchor = SIMD3<Float>(wallX - 0.065, 1.70, wallZ)
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            let renderer = KinematicsRenderer()
            renderer.onObjectTap = { handleObjectTap(on: $0) }
            content.add(renderer.root)
            // Disabled here and raised by `Fade.tick`, so the apparatus arrives
            // rather than appears.
            renderer.root.isEnabled = false

            // No welcome shot (2026-10-17): the room opens quiet, a ball waiting
            // in the ball well's mouth, and the first flight is the one you throw.

            renderer.root.addChild(bloom.root)
            renderer.root.addChild(ballPicker.root)
            renderer.root.addChild(aimPicker.root)
            aimPicker.onSelect = { [ring] id in
                guard let hoop = ring.openID, hoop != Self.launcherRingID else { return }
                model.aim(atSolution: id == "high" ? .high : .low, for: hoop)
            }
            ballPicker.onSelect = { id in
                guard let kind = KinematicsModel.ProjectileKind(rawValue: id) else { return }
                model.kind = kind
            }
            // The lit choice is the ball you will throw: read from the model, so
            // a reset moves it too.
            ballPicker.selectedID = { model.kind.rawValue }

            // The ball well, out of the firing line and not riding the launcher:
            // the ball return. A ball pulled from it is born at the fingertips,
            // already held, and rides the same grab/hold/release path a caught
            // ball does; the mouth is full again the moment it is taken.
            let sources = Well([
                .init(name: "Ball",
                      tint: UIColor(DesignTokens.Palette.kinematicsAccent),
                      label: "Add ball",
                      preview: { renderer.readyBall },
                      position: Self.wellAnchor,
                      spawn: { point in
                          let id = model.spawnBall(at: point)
                          // Already in the hand: grabbing it here arms the throw sampler, so
                          // letting go with a moving hand throws.
                          model.grabBall(id: id)
                          return id
                      },
                      // VoiceOver has no hand to throw it: let go and it waits, staged,
                      // for the launcher's Fire.
                      settle: { model.releaseBall(id: $0) }),
                // The hoop: born at the hand and carried by the same gesture; nil at
                // the budget fades the mouth in refusal.
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
            // and the simulator cannot tap the launcher.
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
            // `-kinHunter 1` arms the first hoop to drop, aims the launcher
            // straight at it and fires, so `-pauseAfter` can catch the
            // ball and the hoop meeting in mid-air.
            if UserDefaults.standard.bool(forKey: "kinHunter"),
               let first = model.rings.first {
                model.setDropOnFire(id: first.id, true)
                let toHoop = first.position - model.launcherPosition
                model.setAim(
                    elevationDegrees: atan2(toHoop.y, simd_length(SIMD2(toHoop.x, toHoop.z))) * 180 / .pi,
                    azimuthDegrees: atan2(toHoop.z, toHoop.x) * 180 / .pi)
                model.fire()
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
            // `-kinArc 1` and `-kinNumbers 1` show the two layers More keeps
            // off by default: the predicted arc with its marks (and the
            // vacuum ghost, with `-kinAir`), and every number in the room.
            if UserDefaults.standard.bool(forKey: "kinArc") {
                model.showsTrajectory = true
            }
            if UserDefaults.standard.bool(forKey: "kinNumbers") {
                model.showsNumbers = true
            }
            // `-kinGravity 1.62` sets g as More's slider would — a value,
            // not a flag, because a slider at its default proves nothing
            // about the mapping behind it.
            let forcedGravity = UserDefaults.standard.object(forKey: "kinGravity")
            if forcedGravity != nil {
                let g = UserDefaults.standard.double(forKey: "kinGravity")
                model.gravity = min(max(g, KinematicsModel.gravityRange.lowerBound),
                                    KinematicsModel.gravityRange.upperBound)
            }
            // `-kinWind 8` switches the air on and sets a wind: More's
            // wind slider is disabled until there is air for it to blow.
            if UserDefaults.standard.object(forKey: "kinWind") != nil {
                model.airResistance = true
                let speed = UserDefaults.standard.double(forKey: "kinWind")
                model.windSpeed = min(max(speed,
                                          KinematicsModel.windSpeedRange.lowerBound),
                                      KinematicsModel.windSpeedRange.upperBound)
            }
            // `-kinSpeed 12` sets the launch speed, which is where the aim
            // bead stands: the bead's distance is the speed, and a bead at
            // its default distance proves nothing about that mapping.
            if UserDefaults.standard.object(forKey: "kinSpeed") != nil {
                let speed = UserDefaults.standard.double(forKey: "kinSpeed")
                model.launchSpeed = min(max(speed, KinematicsModel.speedRange.lowerBound),
                                        KinematicsModel.speedRange.upperBound)
            }
            // `-kinThrow 6` throws a ball at 6 m/s, 35° up and straight ahead, from
            // a right hand at full stretch — far enough out for the simulator's
            // camera to hold the release callout — for a still of a throw.
            let thrown = UserDefaults.standard.double(forKey: "kinThrow")
            if thrown > 0 {
                let angle = 35.0 * .pi / 180
                model.stageThrow(from: SIMD3(0.20, 1.40, -0.70),
                                 velocity: thrown * SIMD3(0, sin(angle), -cos(angle)))
            }
            #endif

            renderer.subscriptions = []

            // Flight clock: step every rendered frame (simulated time —
            // the model applies the slow-motion scale and pause).
            // The lab shows once its scene has taken in the build (`Settle`):
            // it starts hidden and fades up then, rather than popping in and
            // stuttering through the long first frames after a mount.
            renderer.root.components.set(OpacityComponent(opacity: Settle.hiddenOpacity))
            var settle = Settle()
            var lastFeed: RoomFeed?
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's arrival and departure, on the shell's one flag.
                    if let renderer {
                        appModel.doorTick(renderer.root, lab: KinematicsModule.id,
                                          settled: settle.tick(dt: event.deltaTime))
                    }
                    // Everything the room hands the model is translated into module space
                    // first: model coordinates render under `renderer.root`, which carries
                    // the lab-placement offset.
                    let placement = SIMD3<Double>(appModel.labPlacement.offset)
                    // What the room hands the model (`roomFeed`), written only when the
                    // room or the placement changes. The first unscanned frame writes
                    // nothing: the model opens on its own stand-in box, or a `-kinWalls`
                    // seed, and keeps it until the room says otherwise.
                    let feed = RoomFeed(tangible: appModel.room.tangible, placement: placement)
                    if lastFeed == nil, feed.tangible == .unscanned {
                        lastFeed = feed
                    } else if feed != lastFeed {
                        lastFeed = feed
                        let fed = Self.roomFeed(feed.tangible, placement: placement)
                        model.roomWalls = fed.walls
                        model.roomBounds = fed.bounds
                    }
                    // Hands are things a ball bounces off: every tracked joint with its
                    // speed, in module space.
                    model.handStrikes = appModel.room.handStrikes.map { sphere in
                        var moved = sphere
                        moved.center -= placement
                        return moved
                    }
                    model.step(dt: event.deltaTime)
                    // A ball reaching an open hand is caught (device-only). A hand faster
                    // than `swatSpeed` swats instead.
                    let tips = appModel.room.fingertips
                    let tipVelocities = appModel.room.fingertipVelocities
                    let waiting = tips.indices.filter { index in
                        index >= tipVelocities.count
                            || simd_length(tipVelocities[index]) < KinematicsModel.swatSpeed
                    }.map { tips[$0] - placement }
                    model.catchBalls(atFingertips: waiting)
                    renderer?.tick(model)
                    wells?.update(dt: event.deltaTime,
                                  nearestHand: appModel.room.nearestFingertip(
                                    to: Self.wellAnchor))
                    syncBloom(dt: event.deltaTime)
                    // Constant display offset; every instrument is a child of
                    // `renderer.root`, so the whole lab travels together.
                    if let placement = appModel.placement(forLab: KinematicsModule.id) {
                        renderer?.root.position = placement
                    }
                }
            )

            renderer.tick(model)
            self.renderer = renderer
        }
        // An in-flight grab never gets its `onEnded` when the space closes;
        // clear it here.
        .onDisappear {
            renderer?.teardown()
            // `Bloom` is a class: a live grip would outlive the view.
            bloom.endGrip()
            drag = nil
            // A pending press sticks (`press` refuses to overwrite), so an
            // `onEnded` that never arrives would let the next gesture promote it
            // against a stale anchor.
            pressedBall.cancel()
            // A selection, so it does not survive the lab: the next entry
            // opens on a folded ring like every other module.
            ring.openID = nil
            model.aimTargetID = nil
            aimPicker.close()
            // Released, not merely forgotten: the model outlives this view.
            model.releaseAll()
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
                    if drag == nil {
                        if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                        // Born at the fingertips, and dragged by the
                        // same gesture that made it.
                        if let id = wells?.pull(value.entity, at: hand) {
                            drag = RelativeDrag(name: id.uuidString,
                                                target: hand, hand: hand)
                            // A hoop glows in the hand; a ball does through its own grab.
                            if model.rings.contains(where: { $0.id == id }) {
                                renderer?.carried.carry(id.uuidString, fromWell: true)
                            }
                            return
                        }
                        // A tap on a flying ball must not catch it: a bare press would freeze
                        // the ball and release it dead in mid-air. Only the ball needs this;
                        // the other targets are positional.
                        if let press = flightPress(on: value.entity) {
                            pressedBall.press(press, at: hand)
                        } else {
                            drag = beginDrag(entity: value.entity, hand: hand)
                            // The bead shows its reading while it is held.
                            renderer?.beadHeld = drag?.name == KinematicsRenderer.aimBeadName
                            renderer?.carried.carry(drag?.name)
                        }
                    }

                    // The promotion, once the hand has carried the ball: the drag pairs
                    // where the ball is now with where the hand is now, so the catch moves
                    // nothing.
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
                    bloom.endGrip()
                    renderer?.beadHeld = false
                    renderer?.carried.carry(nil)
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

    /// Resolves a pinch: launcher body, aim bead, a ball, or a hoop.

    /// The launcher's ring: Fire, the ball fan, Clear. Launch speed is not
    /// on it: the aim bead is the velocity, its distance the speed.
    private func syncBloom(dt: Double) {
        let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
        // A hoop's ring: the one Bloom retargets to whichever hoop is selected,
        // its anchor riding the hoop.
        if let id = ring.openID, id != Self.launcherRingID,
           let hoop = model.rings.first(where: { $0.id == id }) {
            // Three petals, `Petal`'s ceiling. Aim opens the fan of the two arcs
            // and is dim while the hoop is out of range; "Drop when fired" is the
            // monkey-and-hunter latch, whose state the hoop's own callout reads out.
            bloom.retarget(
                id,
                petals: [
                    .init(name: "Aim", symbol: "scope",
                          tint: UIColor(DesignTokens.Palette.kinematicsAccent),
                          isAvailable: { model.solutions(for: id) != nil }) { [aimPicker] in
                        aimPicker.toggle()
                    },
                    .init(name: "Drop when fired", symbol: "arrow.down.to.line",
                          tint: DesignTokens.Palette.neutralActionUI,
                          announce: {
                              model.rings.first { $0.id == id }?.dropOnFire == true
                                  ? "Drops when fired" : "Stays when fired"
                          }) {
                        let armed = model.rings.first { $0.id == id }?.dropOnFire ?? false
                        model.setDropOnFire(id: id, !armed)
                    },
                    // Red like every Delete petal in the house (`destructiveUI`).
                    .init(name: "Delete", symbol: "trash",
                          tint: DesignTokens.Palette.destructiveUI) { [ring, aimPicker] in
                        model.removeRing(id: id)
                        ring.openID = nil
                        aimPicker.close()
                    },
                ],
                grip: nil)
            bloom.update(anchor: SIMD3<Float>(hoop.position) + SIMD3(0, 0.12, 0),
                         viewer: viewer, revealTarget: 1, dt: dt)
            // The arc fan opens above the ring's petals, riding the hoop.
            let hoopAnchor = SIMD3<Float>(hoop.position) + SIMD3(0, 0.32, 0)
            aimPicker.update(anchor: hoopAnchor, viewer: viewer, dt: dt,
                             nearestHand: appModel.room.nearestFingertip(to: hoopAnchor))
            return
        }
        // No hoop selected: the arc fan is shut, wherever it was.
        aimPicker.close()
        aimPicker.update(anchor: SIMD3<Float>(model.launcherPosition), viewer: viewer,
                         dt: dt, nearestHand: nil)
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
                // Clear the volley. `isAvailable` must be a closure: `retarget`
                // rebuilds only when the id changes, and this ring's id is constant.
                // It confirms like the standing plates, and wears the red every
                // petal that removes something wears.
                .init(name: "Clear", symbol: "trash.slash",
                      tint: DesignTokens.Palette.destructiveUI,
                      isAvailable: { !model.flights.isEmpty },
                      confirms: true) {
                    model.clearFlights()
                },
            ],
            grip: nil)
        // Open only while selected — `Bloom` eases the fold itself, and a
        // grip mid-drag pins it open whatever this says.
        bloom.update(anchor: anchor, viewer: viewer,
                     revealTarget: ring.openID == Self.launcherRingID ? 1 : 0,
                     dt: dt)
        // Clear of the bloom's own petal arc, which reaches ~0.17 m up.
        let hand = appModel.room.nearestFingertip(to: anchor)
        ballPicker.update(anchor: anchor + Self.ballFanOffset,
                          viewer: viewer, dt: dt, nearestHand: hand)
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
                    + Double(KinematicsRenderer.beadDistance(forSpeed: model.launchSpeed))
                    * model.aimDirection
                return RelativeDrag(name: candidate.name, target: target, hand: hand)
            default:
                if let id = UUID(uuidString: candidate.name),
                   let ring = model.rings.first(where: { $0.id == id }) {
                    return RelativeDrag(name: candidate.name,
                                        target: ring.position, hand: hand)
                }
                // No flight branch. A ball is claimed by `flightPress`
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
            // The bead is the launch velocity: where it points is the aim,
            // how far it is from the launcher the speed.
            model.aim(toward: position)
            model.launchSpeed = KinematicsRenderer.speed(
                forBeadDistance: Float(simd_length(position - model.launcherPosition)))
        default:
            guard let id = UUID(uuidString: drag.name) else { return }
            if model.rings.contains(where: { $0.id == id }) {
                model.moveRing(id: id, to: position)
            } else {
                model.holdBall(id: id, at: position)
            }
        }
    }

    /// The tap routing, out of the gesture closure so VoiceOver reaches it
    /// too.
    private func handleObjectTap(on entity: Entity) {
        // The fan first: its discs sit above the launcher and
        // would otherwise be read as a tap on the launcher.
        if aimPicker.handleTap(entity) { return }
        if ballPicker.handleTap(entity) { return }
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
    /// was tapped. The launcher toggles it; the aim bead leaves it alone
    /// (aiming is the launcher's own verb); anything else folds it.
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

// MARK: The room, as the model is handed it

extension KinematicsSpaceView {
    /// What of the room the model was last handed, and from where.
    struct RoomFeed: Equatable {
        var tangible: RoomModel.Tangible
        var placement: SIMD3<Double>
    }

    /// The walls a ball bounces off and the box it is kept in, in module
    /// space (the room less the lab's placement). In deep space there are
    /// none: a ball flies on and is retired past `escapeRadius`. An
    /// unscanned room is the stand-in box; a scanned one its detected
    /// walls backed by its bounds, so a ball always bounces at the room's
    /// edge, ceiling included.
    static func roomFeed(_ tangible: RoomModel.Tangible, placement: SIMD3<Double>)
    -> (walls: [RoomWalls.Wall], bounds: RoomBox?) {
        switch tangible {
        case .openSpace:
            return ([], nil)
        case .unscanned:
            let box = RoomBox.unscanned.translated(by: -placement)
            return (RoomWalls.box(of: box), box)
        case .scanned(let walls, let bounds):
            return (walls.map { $0.translated(by: -placement) }, bounds.translated(by: -placement))
        }
    }
}
