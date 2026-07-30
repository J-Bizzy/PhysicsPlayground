//
//  MechanicsProjectileStation.swift
//  Physics Playground — Mechanics & Energy
//
//  The launcher, its hoops and its balls, as one station of the
//  Mechanics world. `KinematicsSpaceView`'s body turned inside out.
//
//  Two things make this station different from every other one in the
//  app, and both come from the same fact: its physics space IS the
//  user's room.
//
//  · It has NO scale rig. `DECISIONS.md` (2026-07-29) excludes
//    Projectiles from `SpatialScale` permanently — scale the display
//    and the metres stop being metres while balls keep bouncing off
//    real walls at real distances.
//  · Its display offset is zero, enforced by
//    `MechanicsStationLayout` and its tests.
//
//  Room sensing itself lives in the world view, not here: there is one
//  room and one place that reads it.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

@MainActor
final class MechanicsProjectileStation: Station {
    let model: KinematicsModel
    let renderer = KinematicsRenderer()

    /// Nil, and permanently so — see the header.
    var scaleRig: SpatialScaleRig? { nil }

    private let bloom = Bloom()
    /// Which ball you are throwing, chosen in the room instead of from a
    /// menu on a card. A golf ball and a table-tennis ball are 17× apart
    /// in mass and behave nothing alike in air, so this is the module's
    /// most consequential choice.
    private let ballPicker: SpatialPicker
    private var drag: RelativeDrag?

    var root: Entity { renderer.root }

    init(model: KinematicsModel) {
        self.model = model
        ballPicker = SpatialPicker(
            accessibilityNoun: "Ball",
            choices: KinematicsModel.ProjectileKind.allCases
                .filter { $0 != .custom }
                .map {
                    PickerChoice(id: $0.rawValue, label: $0.displayName,
                                 symbol: Self.symbol(for: $0))
                })
    }

    // MARK: Installation

    func install(into content: RealityViewContent) {
        content.add(renderer.root)
        renderer.root.addChild(bloom.root)
        renderer.root.addChild(ballPicker.root)
        ballPicker.onSelect = { [model] id in
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

        renderer.tick(model)
    }

    // MARK: Per-frame

    func tick(dt: Double, appModel: AppModel) {
        model.step(dt: dt)
        // A ball that reaches an open hand is caught: the one moment in
        // the module where the simulation reaches back to you.
        // Device-only — the simulator reports no fingertips, so this is
        // simply inert there.
        model.catchBalls(atFingertips: appModel.room.fingertips)
        renderer.tick(model)
        syncBloom(dt: dt, appModel: appModel)
        // Lab placement ONLY. No station offset: this bench's physics
        // space is the room itself, and a display offset would leave
        // every bounce drawn somewhere the wall is not.
        renderer.root.position = appModel.labPlacement.offset
    }

    /// The launcher's own control. Launch SPEED has no size of its own
    /// — but its consequence does: the predicted arc, already drawn,
    /// stretches across the room as you pull.
    private func syncBloom(dt: Double, appModel: AppModel) {
        let anchor = SIMD3<Float>(model.launcherPosition) + SIMD3(0, 0.12, 0)
        bloom.retarget(
            "launcher",
            petals: [
                .init(name: "Fire", symbol: "paperplane.fill",
                      tint: UIColor(DesignTokens.Palette.kinematicsAccent)) {
                    [model] in model.fire()
                },
                .init(name: "Balls", symbol: "circle.grid.2x2.fill",
                      tint: UIColor(white: 0.45, alpha: 1)) { [ballPicker] in
                    ballPicker.toggle()
                },
            ],
            grip: .init(
                name: "Launch speed",
                range: KinematicsModel.speedRange,
                read: { [model] in model.launchSpeed },
                write: { [model] in model.launchSpeed = $0 },
                format: { String(format: "%.1f m/s", $0) },
                radius: { 0.10 }))
        let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
        bloom.update(anchor: anchor, viewer: viewer, revealTarget: 1, dt: dt)
        // Clear of the bloom's own petal arc, which reaches ~0.17 m up.
        ballPicker.update(anchor: anchor + SIMD3(0, 0.20, 0),
                          viewer: viewer, dt: dt)
    }

    /// The glyph each ball wears on its disc — Kinematics vocabulary,
    /// not the picker's business.
    private static func symbol(for kind: KinematicsModel.ProjectileKind) -> String? {
        switch kind {
        case .tableTennisBall: "circle"
        case .basketball: "basketball.fill"
        case .golfBall: "circle.dotted"
        case .cannonball: "circle.fill"
        case .custom: nil
        }
    }

    // MARK: Gestures

    @discardableResult
    func handleTap(_ entity: Entity) -> Bool {
        // The fan first: its discs sit above the launcher and would
        // otherwise be read as a tap on the launcher.
        if ballPicker.handleTap(entity) { return true }
        return bloom.handleTap(entity)
    }

    func dragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
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

    func dragEnded(_ value: EntityTargetValue<DragGesture.Value>) {
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
