//
//  EMFieldStation.swift
//  Physics Playground — Electricity & Magnetism
//
//  The magnetic field volume, as one station of the E&M world.
//
//  MagnetismSpaceView's body, turned inside out for the same reason
//  the bench was: one RealityView, one set of gestures, two apparatus
//  that each have their own grab grammar.
//
//  The line this station used to reach across a module boundary for is
//  now a wire in the same room. `setCoilCurrent` still takes whatever
//  the bench's inductors carry, but the bench is thirteen hundred
//  millimetres to the left rather than behind a hub, a card, and a
//  loading screen — so "open the switch and the electromagnet dies" is
//  something you can watch happen instead of something you're told.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

@MainActor
final class EMFieldStation: Station {
    let model: MagnetismModel
    let renderer = MagnetismRenderer()

    /// Two-hand scale and turn: grow the dipole field from a desk demo
    /// to loops you stand inside, or turn the whole field to see it
    /// side-on. A pure view transform — the tesla stay honest.
    private let rig = SpatialScaleRig(
        pivot: SIMD3<Float>(MagnetismModel.regionCenter), range: 0.5...4.0)

    /// `Station`'s accessor. Optional in the protocol because an
    /// apparatus may refuse to be scaled at all; the field has one.
    var scaleRig: SpatialScaleRig? { rig }

    private let bloom = Bloom()
    /// Which magnet's ring is open — shared by the tap gesture and the
    /// render loop (see RingState's header for why it's a reference).
    private let ring = RingState()
    private var wells: Well?
    private var drag: RelativeDrag?

    var root: Entity { renderer.root }

    init(model: MagnetismModel) {
        self.model = model
    }

    // MARK: Installation

    func install(into content: RealityViewContent) {
        content.add(renderer.root)

        // On the station's OUTBOARD flank. The well used to sit at
        // −0.72 in x, which was the free side when this bench owned the
        // room; in the world that side faces the circuit bench, and a
        // spawn well hanging into the middle would collide with the
        // bench's layers bank.
        let sources = Well([
            .init(name: "Magnet",
                  tint: UIColor(DesignTokens.Palette.magnetismAccent),
                  glyph: "N",
                  position: SIMD3<Float>(MagnetismModel.regionCenter)
                      + SIMD3(0.72 * Float(EMStationLayout.outboard(.field)),
                              -0.20, 0.34),
                  spawn: { [model] point in model.addMagnet(at: point) }),
        ])
        renderer.viewRoot.addChild(sources.root)
        renderer.viewRoot.addChild(bloom.root)
        wells = sources

        #if DEBUG
        // `-viewScale.field 2.5` bakes a committed scale in at launch,
        // so the scaled view can be screenshot-verified from the CLI —
        // the simulator has no second hand to pinch with. Addressed,
        // because the bench station reads the same key (StationDebug).
        if let forced = StationDebug.forcedScale(EMStation.field.rawValue) {
            rig.updateMagnification(forced)
            rig.endGesture()
        }
        // `-magRing 1` opens the first magnet's control ring at launch,
        // so the ring can be screenshot from the CLI.
        if UserDefaults.standard.bool(forKey: "magRing"),
           let first = model.magnets.first {
            ring.openID = first.id
        }
        #endif

        renderer.tick(model, viewer: nil)
    }

    // MARK: Per-frame

    func tick(dt: Double, appModel: AppModel, coilCurrent: Double) {
        rig.apply(to: renderer.viewRoot)
        wells?.update(dt: dt)
        syncBloom(dt: dt, appModel: appModel)
        model.step(dt: dt)
        // The link, now a wire and not a rumour: whatever current the
        // bench's inductors are carrying right now is the current in
        // this coil.
        if model.electromagnetOn {
            model.setCoilCurrent(coilCurrent)
        }
        renderer.tick(model, viewer: appModel.room.headPosition.map {
            renderer.displayPoint(fromWorld: SIMD3<Float>($0))
        })
        // Lab placement plus this station's seat on the arc — a pure
        // display offset, safe because every grab here moves a body by
        // hand DISPLACEMENT, which a constant translation leaves
        // untouched.
        //
        // …but the control pods do NOT go with it: the user parked them
        // where they wanted them, and moving the apparatus is not a
        // request to move the controls.
        renderer.root.position =
            appModel.labPlacement.offset + EMStationLayout.offset(.field)
    }

    // MARK: The far end of the circuit

    /// Where the feed line meets the coil, in SCENE space — two points
    /// on the coil's rim, a little either side of its mid-plane, so the
    /// cable arrives at the winding rather than at a floating point.
    ///
    /// Nil when the electromagnet is switched off: there is no coil to
    /// feed, so there is no cable.
    var coilLeads: (SIMD3<Float>, SIMD3<Float>)? {
        guard model.electromagnetOn else { return nil }
        let axis = SIMD3<Float>(simd_normalize(model.electromagnetAxis))
        let centre = SIMD3<Float>(model.electromagnetPosition)
        let radius = Float(MagnetismModel.coilRadius)
        // Any direction square to the axis will do; pick one that can't
        // degenerate when the coil is aimed straight up.
        let reference: SIMD3<Float> =
            abs(axis.y) > 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
        let rim = simd_normalize(simd_cross(axis, reference))
        return (renderer.viewRoot.convert(
                    position: centre + rim * radius + axis * radius * 0.35, to: nil),
                renderer.viewRoot.convert(
                    position: centre + rim * radius - axis * radius * 0.35, to: nil))
    }

    // MARK: Gestures

    /// A tap on a magnet toggles its control ring; a tap on anything
    /// else folds it away.
    func handleTap(_ entity: Entity) -> Bool {
        if bloom.handleTap(entity) { return true }
        var current: Entity? = entity
        while let candidate = current {
            if let id = UUID(uuidString: candidate.name),
               model.magnets.contains(where: { $0.id == id }) {
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
        return true
    }

    func dragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        // Through the scaled root: at 3× a hand moving a metre moves a
        // magnet a third of one, so what you hold stays under your
        // fingers at every scale.
        let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
            value.location3D, from: .local, to: .scene)))
        if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
        if drag == nil {
            if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
            if let id = wells?.pull(value.entity, at: hand) {
                drag = RelativeDrag(name: id.uuidString, target: hand, hand: hand)
                return
            }
            drag = beginDrag(entity: value.entity, hand: hand)
        }
        guard let drag else { return }
        if drag.name == MagnetismRenderer.electromagnetName {
            model.moveElectromagnet(to: drag.position(forHand: hand))
        } else if drag.name == MagnetismRenderer.handCompassName {
            model.moveCompass(to: drag.position(forHand: hand))
        } else if let id = UUID(uuidString: drag.name) {
            model.move(id: id, to: drag.position(forHand: hand))
        }
    }

    func dragEnded(_ value: EntityTargetValue<DragGesture.Value>) {
        bloom.endGrip()
        model.release()
        renderer.isCarryingCompass = false
        renderer.isCarryingCoil = false
        drag = nil
    }

    // MARK: The magnet ring

    /// Tap a magnet and it offers exactly what a magnet offers:
    /// reverse its poles, remove it, or pull its strength up — and the
    /// field loops thicken and reach further as you pull, which is the
    /// only readout that matters.
    private func syncBloom(dt: Double, appModel: AppModel) {
        if let openID = ring.openID,
           !model.magnets.contains(where: { $0.id == openID }) {
            ring.openID = nil     // deleted out from under the ring
        }
        guard let uuid = ring.openID,
              let magnet = model.magnets.first(where: { $0.id == uuid }) else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }

        bloom.retarget(
            uuid,
            petals: [
                .init(name: "Flip poles", symbol: "arrow.triangle.2.circlepath",
                      tint: UIColor(white: 0.45, alpha: 1)) { [model] in
                    model.flipMagnet(id: uuid)
                },
                .init(name: "Delete", symbol: "trash",
                      tint: UIColor(red: 0.85, green: 0.25,
                                    blue: 0.25, alpha: 1)) { [model] in
                    model.removeMagnet(id: uuid)
                },
            ],
            grip: .init(
                name: "Strength",
                range: MagnetismModel.strengthRange,
                read: { [model] in model.strength(id: uuid) },
                write: { [model] in model.setStrength(id: uuid, $0) },
                format: { String(format: "%.1f A\u{00B7}m\u{00B2}", $0) },
                radius: { Float(MagnetismModel.magnetLength) * 0.6 }))

        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(magnet.position),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }

    private func beginDrag(entity: Entity, hand: SIMD3<Double>) -> RelativeDrag? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name == MagnetismRenderer.electromagnetName {
                renderer.isCarryingCoil = true
                return RelativeDrag(name: candidate.name,
                                    target: model.electromagnetPosition, hand: hand)
            }
            if candidate.name == MagnetismRenderer.handCompassName {
                renderer.isCarryingCompass = true
                return RelativeDrag(name: candidate.name,
                                    target: model.compassPosition, hand: hand)
            }
            if let id = UUID(uuidString: candidate.name),
               let magnet = model.magnets.first(where: { $0.id == id }) {
                model.grab(id: id)
                return RelativeDrag(name: candidate.name,
                                    target: magnet.position, hand: hand)
            }
            current = candidate.parent
        }
        return nil
    }
}
