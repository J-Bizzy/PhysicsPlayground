//
//  KinematicsSpaceView.swift
//  Physics Playground — Kinematics module
//
//  The room-scale immersive scene. Manipulation events route by entity
//  name: the launcher body (move it), the aim bead (point it), any ball
//  (grab and THROW — release velocity comes from the hand's motion), and
//  any hoop (place it). The flight clock is SceneEvents.Update.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct KinematicsSpaceView: View {
    @Environment(KinematicsModel.self) private var model
    @State private var renderer: KinematicsRenderer?
    @State private var drag: RelativeDrag?
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
                    if appModel.room.hasScannedRoom {
                        // Detected walls backed by the room's boundary
                        // box, so a ball ALWAYS bounces at the room's
                        // edge — including walls never looked at, and
                        // the ceiling. The bounds also feed the
                        // containment clamp: no escape, ever.
                        model.roomWalls = appModel.room.collisionWalls
                        model.roomBounds = appModel.room.bounds
                    }
                    model.step(dt: event.deltaTime)
                    // A ball that reaches an open hand is caught: the
                    // one moment in the module where the simulation
                    // reaches back to you. Device-only — the simulator
                    // reports no fingertips, so this is simply inert
                    // there.
                    model.catchBalls(atFingertips: appModel.room.fingertips)
                    renderer?.tick(model)
                    syncBloom(dt: event.deltaTime)
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

            renderer.tick(model)
            self.renderer = renderer
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
                        drag = beginDrag(entity: value.entity, hand: hand)
                    }
                    guard let drag else { return }
                    apply(drag: drag, hand: hand)
                }
                .onEnded { value in
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
                if let id = UUID(uuidString: candidate.name) {
                    if let ring = model.rings.first(where: { $0.id == id }) {
                        return RelativeDrag(name: candidate.name,
                                            target: ring.position, hand: hand)
                    }
                    if let flight = model.flights.first(where: { $0.id == id }) {
                        model.grabBall(id: id)
                        return RelativeDrag(name: candidate.name,
                                            target: flight.state.position, hand: hand)
                    }
                }
                current = candidate.parent
            }
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
