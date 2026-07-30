//
//  MechanicsPendulumStation.swift
//  Physics Playground — Mechanics & Energy
//
//  The pendulum rig, as one station of the Mechanics world.
//  `PendulumsSpaceView`'s body turned inside out.
//
//  This is the station that MOVES, because the projectile bench cannot:
//  its seat is 1.75 m to the left of where the module authored it. The
//  rig knows nothing about the room — no walls, no fingertips — so a
//  constant translation costs it nothing, which is exactly why it is
//  the one that gives way.
//
//  Its spawn well moves with it, onto the station's outboard flank: the
//  well used to hang at x = −0.85, which was free when this rig owned
//  the room and is now inside the projectile bench.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit
import simd

@MainActor
final class MechanicsPendulumStation: Station {
    let model: PendulumsModel
    let renderer = PendulumsRenderer()

    /// A pendulum's length and period are read off a bench beside you;
    /// there is nothing here that wants to be the size of a room.
    var scaleRig: SpatialScaleRig? { nil }

    private let bloom = Bloom()
    /// Which bob's ring is open — shared by the tap gesture and the
    /// render loop (see RingState's header for why it's a reference).
    private let ring = RingState()
    private var wells: Well?
    private var drag: RelativeDrag?
    /// `PhysicsCore.ThrowSampler` — shared with Projectiles and Gravity
    /// Lab, which each kept their own copy of this buffer. The 0.14 s
    /// window is inherited from the hand-rolled version this replaced;
    /// a bob is released out of a swing rather than flicked, so the
    /// longer window is plausible enough to keep.
    private var handSampler = ThrowSampler(window: 0.14)

    var root: Entity { renderer.root }

    init(model: PendulumsModel) {
        self.model = model
    }

    // MARK: Installation

    func install(into content: RealityViewContent) {
        content.add(renderer.root)
        renderer.root.addChild(bloom.root)

        // Pull a pendulum out and hang it wherever you let go. The
        // pivot lands at your fingertips, so rigging one and moving one
        // are the same gesture.
        //
        // On the station's OUTBOARD flank: the well was authored at
        // x = −0.85, which was the free side when this rig owned the
        // room. In the world that side faces the projectile bench.
        let sources = Well([
            .init(name: "Pendulum",
                  tint: UIColor(DesignTokens.Palette.pendulumsAccent),
                  glyph: "+",
                  position: SIMD3<Float>(
                      PendulumsModel.defaultPivot
                          + SIMD3(0.85 * MechanicsStationLayout.outboard(.pendulum),
                                  -0.70, 0.15)),
                  spawn: { [model] point in model.addPendulum(at: point) }),
        ])
        renderer.root.addChild(sources.root)
        wells = sources

        #if DEBUG
        // `-penRing 1` opens the first bob's control ring at launch,
        // for CLI screenshots.
        if UserDefaults.standard.bool(forKey: "penRing"),
           let first = model.pendulums.first {
            ring.openID = first.id
        }
        #endif
    }

    // MARK: Per-frame

    func tick(dt: Double, appModel: AppModel) {
        renderer.tick(dt: dt, model: model)
        wells?.update(dt: dt)
        syncBloom(dt: dt, appModel: appModel)
        // Lab placement plus this station's seat — a pure display
        // offset, safe because every grab here moves a body by hand
        // DISPLACEMENT, which a constant translation leaves untouched.
        renderer.root.position =
            appModel.labPlacement.offset + MechanicsStationLayout.offset(.pendulum)
    }

    /// A bob's own controls. LENGTH is the grip, and its extent is the
    /// cable: pull the bead and the cable pays out, the bob falls with
    /// it, and the period tag over the pivot climbs as the square root
    /// of length while your hand is still moving.
    private func syncBloom(dt: Double, appModel: AppModel) {
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
                      tint: UIColor(white: 0.45, alpha: 1)) { [model] in
                    // Cycle light → medium → heavy → light. The period
                    // doesn't change — which is the lesson.
                    let masses = [0.5, 1.5, 3.0]
                    let current = model.pendulums.first(where: { $0.id == uuid })?.mass ?? 1
                    let next = masses.first(where: { $0 > current + 0.01 }) ?? masses[0]
                    model.setMass(id: uuid, next)
                },
                .init(name: "Delete", symbol: "trash",
                      tint: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)) {
                    [model] in model.removePendulum(id: uuid)
                },
            ],
            grip: .init(
                name: "Length",
                range: PendulumsModel.lengthRange,
                read: { [model] in
                    model.pendulums.first(where: { $0.id == uuid })?.length ?? 0.8
                },
                write: { [model] in model.setLength(id: uuid, $0) },
                format: { String(format: "%.2f m", $0) },
                radius: { Float(pendulum.bobRadius) + 0.03 }))

        let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
        bloom.update(anchor: SIMD3<Float>(pendulum.bobWorld),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }

    // MARK: Gestures

    @discardableResult
    func handleTap(_ entity: Entity) -> Bool {
        if bloom.handleTap(entity) { return true }
        // A tap on a bob selects it and toggles its control ring; a tap
        // on anything else folds the ring away.
        var current: Entity? = entity
        while let candidate = current {
            if let id = UUID(uuidString: candidate.name),
               model.pendulums.contains(where: { $0.id == id }) {
                model.select(id: id)
                if ring.openID == id {
                    ring.openID = nil
                } else {
                    ring.openID = id
                    SoundPalette.play(.pop, on: entity, volume: 0.35)
                }
                return true
            }
            current = candidate.parent
        }
        ring.openID = nil
        return false
    }

    func dragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
            value.location3D, from: .local, to: .scene)))
        if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
        if drag == nil {
            if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
            if let id = wells?.pull(value.entity, at: hand) {
                drag = RelativeDrag(name: "pivot-\(id.uuidString)",
                                    target: hand, hand: hand)
                return
            }

            var current: Entity? = value.entity
            while let candidate = current {
                if let id = UUID(uuidString: candidate.name),
                   let pendulum = model.pendulums.first(where: { $0.id == id }) {
                    renderer.grabbedID = id
                    renderer.clearTrail()
                    model.beginGrab(id: id)
                    drag = RelativeDrag(name: candidate.name,
                                        target: pendulum.bobWorld, hand: hand)
                    handSampler.reset()
                    handSampler.record(pendulum.bobWorld,
                                       at: Date.timeIntervalSinceReferenceDate)
                    break
                }
                current = candidate.parent
            }
        }
        // A pivot drag re-hangs the rig; a bob drag swings it.
        if drag?.name.hasPrefix("pivot-") == true, let drag,
           let id = UUID(uuidString: String(drag.name.dropFirst(6))) {
            model.movePivot(id: id, to: drag.position(forHand: hand))
            return
        }
        guard let drag, let id = UUID(uuidString: drag.name) else { return }
        let world = drag.position(forHand: hand)
        model.moveGrabbed(id: id, toWorld: world)
        handSampler.record(world, at: Date.timeIntervalSinceReferenceDate)
    }

    func dragEnded(_ value: EntityTargetValue<DragGesture.Value>) {
        defer {
            renderer.grabbedID = nil
            drag = nil
            handSampler.reset()
        }
        guard let drag, let id = UUID(uuidString: drag.name) else { return }
        let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
            value.location3D, from: .local, to: .scene)))
        let world = drag.position(forHand: hand)
        model.moveGrabbed(id: id, toWorld: world)
        // The release point is part of the throw, so it goes into the
        // sampler before the velocity is read.
        let now = Date.timeIntervalSinceReferenceDate
        handSampler.record(world, at: now)
        model.release(id: id, handVelocity: handSampler.velocity(at: now) ?? .zero)
    }
}

/// The card floating above the selected bob: the numbers behind the swing.
///
/// Lived at the bottom of `PendulumsSpaceView` until that file became a
/// station; it is a panel view and has nothing to do with the scene.
struct PendulumInfoCard: View {
    @Environment(PendulumsModel.self) private var model

    var body: some View {
        if let pendulum = model.selected {
            let speed = simd_length(pendulum.state.velocity)
            let angle = pendulum.state.angle(length: pendulum.length)
            let energies = pendulum.state.energies(
                length: pendulum.length, gravity: model.gravity, mass: pendulum.mass)
            VStack(alignment: .leading, spacing: 3) {
                Text("L \(pendulum.length, specifier: "%.2f") m   T \(pendulum.period(gravity: model.gravity), specifier: "%.2f") s")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                Text("θ \(angle * 180 / .pi, specifier: "%.0f")°   v \(speed, specifier: "%.2f") m/s")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                Text("KE \(energies.kinetic, specifier: "%.2f") J   PE \(energies.potential, specifier: "%.2f") J")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
