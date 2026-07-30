//
//  MechanicsWorldSpaceView.swift
//  Physics Playground — Mechanics & Energy
//
//  The merged Mechanics world: a launcher and its hoops dead centre, a
//  pendulum rig to the left, and one of them focused at a time.
//
//  Same shape as `EMWorldSpaceView` — one RealityView, one
//  SceneEvents.Update tick, gestures routed by whichever station owns
//  the entity the hands landed on — and deliberately a copy rather than
//  a shared generic. About sixty lines of routing are identical and
//  about sixty are not: this world reads the room, has no feed line,
//  and has a station that refuses to be scaled. A generic host would
//  need an escape hatch for exactly the part that differs, and would
//  end up longer than the copy while making the tick order harder to
//  read — which is the one thing the world exists to keep legible.
//
//  ROOM SENSING LIVES HERE, ONCE. It used to sit inside the projectile
//  module's own tick, because that module was the only one that wanted
//  it. There is one room; there is one place that reads it.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct MechanicsWorldSpaceView: View {
    @Environment(KinematicsModel.self) private var kinematics
    @Environment(PendulumsModel.self) private var pendulums
    @Environment(AppModel.self) private var appModel

    @State private var projectile: MechanicsProjectileStation?
    @State private var pendulum: MechanicsPendulumStation?
    @State private var subscription: EventSubscription?

    var body: some View {
        RealityView { content in
            let projectile = MechanicsProjectileStation(model: kinematics)
            let pendulum = MechanicsPendulumStation(model: pendulums)
            let focus = appModel.mechanicsFocus

            projectile.install(into: content)
            pendulum.install(into: content)

            for station in MechanicsStation.allCases where station.isBuilt {
                focus.register(station)
            }

            #if DEBUG
            // `-focusStation pendulum` commits the focus at launch: the
            // simulator has no hands to attend with, and `snap()` lands
            // on the settled emphasis so the captured frame is not
            // mid-fade.
            if let name = UserDefaults.standard.string(forKey: "focusStation"),
               let station = MechanicsStation(rawValue: name), station.isBuilt {
                focus.focus(station)
                focus.snap()
            }
            #endif

            subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                Self.tick(dt: event.deltaTime, projectile: projectile,
                          pendulum: pendulum, focus: focus, appModel: appModel)
            }

            self.projectile = projectile
            self.pendulum = pendulum
        }
        // Routed, not stacked — and the projectile bench answers nil,
        // so a two-handed pinch there does nothing at all rather than
        // silently scaling a bench whose metres are the room's metres.
        .spatialScale(rigs: rigs, routing: rig(forEntity:))
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    switch station(owning: value.entity) {
                    case .projectile:
                        attend(.projectile)
                        _ = projectile?.handleTap(value.entity)
                    case .pendulum:
                        attend(.pendulum)
                        _ = pendulum?.handleTap(value.entity)
                    // A tap on the room or on nothing folds both
                    // benches' rings away. It does NOT move focus:
                    // attention follows what you touched, and you
                    // touched neither.
                    default:
                        _ = projectile?.handleTap(value.entity)
                        _ = pendulum?.handleTap(value.entity)
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    // Focused AND forwarded, in that order and in the
                    // same event — a dim bench is dimmer, not harder to
                    // use.
                    switch station(owning: value.entity) {
                    case .projectile:
                        attend(.projectile)
                        projectile?.dragChanged(value)
                    case .pendulum:
                        attend(.pendulum)
                        pendulum?.dragChanged(value)
                    default: break
                    }
                }
                .onEnded { value in
                    // Ended goes to BOTH regardless of where the hand
                    // finished: a throw that begins on a bob and ends
                    // over the launcher must still release the bob, and
                    // each end-handler is a no-op with no drag in
                    // flight.
                    projectile?.dragEnded(value)
                    pendulum?.dragEnded(value)
                }
        )
    }

    // MARK: Focus

    private func attend(_ station: MechanicsStation) {
        appModel.mechanicsFocus.focus(station)
    }

    // MARK: Routing

    private var rigs: [SpatialScaleRig] {
        MechanicsStation.allCases.compactMap { rig(of: $0) }
    }

    private func station(owning entity: Entity) -> MechanicsStation? {
        if let projectile, entity.isDescendant(of: projectile.root) {
            return .projectile
        }
        if let pendulum, entity.isDescendant(of: pendulum.root) { return .pendulum }
        return nil
    }

    private func rig(of station: MechanicsStation) -> SpatialScaleRig? {
        switch station {
        case .projectile: projectile?.scaleRig ?? nil
        case .pendulum:   pendulum?.scaleRig ?? nil
        case .orbital:    nil
        }
    }

    private func rig(forEntity entity: Entity) -> SpatialScaleRig? {
        station(owning: entity).flatMap(rig(of:))
    }

    // MARK: The single tick

    private static func tick(
        dt: Double, projectile: MechanicsProjectileStation,
        pendulum: MechanicsPendulumStation,
        focus: StationFocus<MechanicsStation>, appModel: AppModel
    ) {
        // The room, read once, before anything solves against it.
        //
        // Detected walls backed by the room's boundary box, so a ball
        // ALWAYS bounces at the room's edge — including walls never
        // looked at, and the ceiling. The bounds also feed the
        // containment clamp: no escape, ever.
        if appModel.room.hasScannedRoom {
            projectile.model.roomWalls = appModel.room.collisionWalls
            projectile.model.roomBounds = appModel.room.bounds
        }

        // PROPERTY 1 of the focus contract: both benches solve every
        // frame, whichever one is being attended to. Skipping the dim
        // one is the cheap performance fix that would quietly turn this
        // back into a picker.
        projectile.tick(dt: dt, appModel: appModel)
        pendulum.tick(dt: dt, appModel: appModel)

        // Emphasis last, so it lands on this frame's scene. Opacity
        // only — never a transform.
        focus.tick(dt: dt)
        focus.apply(.projectile, to: projectile.root)
        focus.apply(.pendulum, to: pendulum.root)
    }
}
