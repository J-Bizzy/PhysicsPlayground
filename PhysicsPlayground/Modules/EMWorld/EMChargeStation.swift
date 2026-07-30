//
//  EMChargeStation.swift
//  Physics Playground — Electricity & Magnetism
//
//  The electrostatics volume, as the third station of the E&M world.
//
//  FieldSpaceView's body turned inside out, for the same reason the
//  bench and the field were: one RealityView, one set of gestures,
//  three apparatus that each have their own grab grammar.
//
//  This one completes the world's argument. A circuit bench makes a
//  current, a current makes a magnet, and a charge is what both of
//  them are made of — but the module that drew charges was a separate
//  catalog entry, so the app told you they were the same subject and
//  then made you leave the room to check. Now the E&M world is E&M:
//  charges on the centre line, the bench on the left, the field on the
//  right, and one cable proving the middle claim.
//
//  Nothing about the electrostatics coordinates changed. It still
//  believes it is centred on FieldModel.regionCenter; the world
//  translates its display root onto the arc.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

@MainActor
final class EMChargeStation: Station {
    let model: FieldModel
    let renderer = FieldRenderer()

    /// Two-hand scale and turn: grow the field until its lines arch
    /// over your head, or turn it to look down the dipole's axis. A
    /// pure view transform, so every volt and newton stays honest.
    private let rig = SpatialScaleRig(
        pivot: SIMD3<Float>(FieldModel.regionCenter), range: 0.5...4.0)

    var scaleRig: SpatialScaleRig? { rig }

    /// The per-charge control ring: flip, delete, and the strength grip
    /// you pull. One instance, opened by tapping a charge.
    private let bloom = Bloom()
    /// Which charge's ring is open — shared by the tap gesture and the
    /// render loop (see RingState's header for why it's a reference).
    private let ring = RingState()
    private var drag: RelativeDrag?

    var root: Entity { renderer.root }

    init(model: FieldModel) {
        self.model = model
    }

    // MARK: Installation

    func install(into content: RealityViewContent) {
        content.add(renderer.root)
        renderer.viewRoot.addChild(bloom.root)

        #if DEBUG
        // `-emRing 1` opens the selected charge's control ring at
        // launch — the simulator has no hand to tap it with, and the
        // ring's layout can only be checked by seeing it.
        if UserDefaults.standard.bool(forKey: "emRing"),
           let id = model.selectedChargeID {
            ring.openID = id
        }
        // `-viewScale.charges 2.5` bakes a committed scale in at launch.
        // Addressed, because three stations now read this key.
        if let forced = StationDebug.forcedScale(EMStation.charges.rawValue) {
            rig.updateMagnification(forced)
            rig.endGesture()
        }
        #endif
    }

    // MARK: Per-frame

    func tick(dt: Double, appModel: AppModel) {
        rig.apply(to: renderer.viewRoot)
        model.stepProbe(dt: dt)
        model.stepFreeCharges(dt: dt)

        // Look-to-measure: the Gauss surface follows the direction the
        // head is facing (panel toggle; device-only, the simulator has
        // no look ray).
        if model.gaussSurfaceOn, model.lookToPlace,
           let ray = appModel.room.lookRay {
            let origin = renderer.displayPoint(fromWorld: SIMD3<Float>(ray.origin))
            if let point = model.lookRegion.point(
                onRay: origin, direction: ray.direction, reach: model.lookReach) {
                model.moveGaussSurface(to: point)
            }
        }

        syncBloom(dt: dt, appModel: appModel)
        renderer.tick(model, room: appModel.room.bounds)
        // Lab placement plus this station's seat on the arc — a pure
        // display offset, safe because every grab here moves a body by
        // hand DISPLACEMENT, which a constant translation leaves
        // untouched.
        renderer.root.position =
            appModel.labPlacement.offset + EMStationLayout.offset(.charges)
    }

    /// Keeps the ring on its charge: anchored to it every frame (it
    /// follows a dragged charge), folded away the moment the charge is
    /// gone, rebuilt only when the target changes.
    private func syncBloom(dt: Double, appModel: AppModel) {
        if let openID = ring.openID,
           !model.charges.contains(where: { $0.id == openID }) {
            ring.openID = nil     // deleted out from under the ring
        }
        guard let openID = ring.openID,
              let charge = model.charges.first(where: { $0.id == openID }) else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }

        bloom.retarget(
            openID,
            petals: [
                .init(name: "Delete", symbol: "trash",
                      tint: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)) {
                    [model] in model.removeCharge(id: openID)
                },
            ],
            grip: .init(
                name: "Strength",
                range: FieldModel.magnitudeRange,
                read: { [model] in model.magnitudeMicroCoulombs(id: openID) },
                write: { [model] in model.setMagnitude(id: openID, microCoulombs: $0) },
                format: { String(format: "%.1f \u{00B5}C", $0) },
                // The grip rides the charge's own surface, so the
                // handle moves outward as the charge grows.
                radius: { [renderer] in
                    renderer.displayRadius(forChargeID: openID) + 0.02
                }))

        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(charge.position),
                     viewer: viewer,
                     revealTarget: 1,
                     dt: dt)
    }

    // MARK: Gestures

    @discardableResult
    func handleTap(_ entity: Entity) -> Bool {
        // Petals first — a tap on Delete is theirs.
        if bloom.handleTap(entity) { return true }
        // A tap on a charge selects it and toggles its control ring
        // open; a tap on anything else folds the ring away.
        for name in Self.ancestorNames(of: entity) {
            if let id = UUID(uuidString: name),
               model.charges.contains(where: { $0.id == id }) {
                model.select(id: id)
                if ring.openID == id {
                    ring.openID = nil
                } else {
                    ring.openID = id
                    SoundPalette.play(.pop, on: entity, volume: 0.35)
                }
                return true
            }
        }
        ring.openID = nil
        return false
    }

    // Relative dragging, no system manipulation: the charge (or probe,
    // or plate) moves by exactly the hand's displacement — it never
    // lurches toward the hand, and the per-frame tick moves its field
    // with it in the same frame.
    func dragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
            value.location3D, from: .local, to: .scene)))
        // Pulling the ring's strength grip beats everything: it is the
        // only gesture already in flight.
        if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
        if drag == nil {
            if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
            drag = beginDrag(entity: value.entity, hand: hand)
        }
        guard let drag else { return }
        apply(drag: drag, hand: hand)
    }

    func dragEnded(_ value: EntityTargetValue<DragGesture.Value>) {
        let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
            value.location3D, from: .local, to: .scene)))
        if let drag {
            apply(drag: drag, hand: hand)
            if drag.name == FieldRenderer.probeEntityName {
                model.releaseProbe()
            }
        }
        bloom.endGrip()
        drag = nil
        model.heldChargeID = nil
    }

    /// Resolves what was pinched and anchors a relative-drag session.
    private func beginDrag(entity: Entity, hand: SIMD3<Double>) -> RelativeDrag? {
        let names = Self.ancestorNames(of: entity)
        for name in names {
            if name == "plate-0" || name == "plate-1" {
                let index = name == "plate-0" ? 0 : 1
                let offset = (index == 0 ? -1.0 : 1.0) * model.plateSeparation / 2
                return RelativeDrag(
                    name: name,
                    target: model.capacitorCenter + SIMD3(offset, 0, 0),
                    hand: hand)
            }
            if name == "gauss-surface" {
                return RelativeDrag(name: name, target: model.gaussSurfaceCenter, hand: hand)
            }
            if name == FieldRenderer.probeEntityName {
                let target = model.probe?.position ?? hand
                model.holdProbe(at: target)
                return RelativeDrag(name: name, target: target, hand: hand)
            }
        }
        if let id = Self.resolveCharge(
                names: names, hand: hand,
                charges: model.charges.map { ($0.id, $0.position) }),
           let charge = model.charges.first(where: { $0.id == id }) {
            model.select(id: id)
            return RelativeDrag(name: id.uuidString, target: charge.position, hand: hand)
        }
        return nil
    }

    private func apply(drag: RelativeDrag, hand: SIMD3<Double>) {
        let position = drag.position(forHand: hand)
        if drag.name == "plate-0" || drag.name == "plate-1" {
            model.movePlate(drag.name == "plate-0" ? 0 : 1, toWorld: position)
        } else if drag.name == "gauss-surface" {
            model.moveGaussSurface(to: position)
        } else if drag.name == FieldRenderer.probeEntityName {
            model.holdProbe(at: position)
        } else if let id = UUID(uuidString: drag.name) {
            model.heldChargeID = id
            model.moveCharge(id: id, to: position)
        }
    }

    /// Names of the entity and its ancestors, nearest first.
    private static func ancestorNames(of entity: Entity) -> [String] {
        var names: [String] = []
        var current: Entity? = entity
        while let candidate = current {
            names.append(candidate.name)
            current = candidate.parent
        }
        return names
    }

    /// Resolves a pinch to a charge. An ancestor named with a charge's
    /// UUID wins outright; failing that, the nearest charge within
    /// `fallbackRadius` of the hand — so a near-miss pinch on a charge
    /// still grabs it instead of silently doing nothing.
    static func resolveCharge(names: [String], hand: SIMD3<Double>,
                              charges: [(id: UUID, position: SIMD3<Double>)],
                              fallbackRadius: Double = 0.12) -> UUID? {
        for name in names {
            if let id = UUID(uuidString: name),
               charges.contains(where: { $0.id == id }) {
                return id
            }
        }
        return charges
            .map { ($0.id, simd_distance($0.position, hand)) }
            .filter { $0.1 <= fallbackRadius }
            .min { $0.1 < $1.1 }?
            .0
    }
}
