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
            #if DEBUG
            // `-kinBalls 1` opens the ball fan at launch, so the picker is
            // screenshot-checkable from the CLI (no hand to pinch with).
            if UserDefaults.standard.bool(forKey: "kinBalls") {
                ballPicker.toggle()
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
                    if drag == nil {
                        if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                        drag = beginDrag(entity: value.entity, hand: hand)
                    }
                    guard let drag else { return }
                    apply(drag: drag, hand: hand)
                }
                .onEnded { value in
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
