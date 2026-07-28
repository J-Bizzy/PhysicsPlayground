//
//  FieldSpaceView.swift
//  Physics Playground — Electromagnetism module
//
//  The electrostatics immersive scene, hosted by PlaygroundSpaceView.
//  RealityView's make closure installs the entity tree; from then on
//  FieldRenderer is ticked every frame from SceneEvents.Update.
//
//  Manipulation events arrive through Core's ManipulationRouter: charges
//  are keyed by UUID name, the probe by its fixed name. The probe
//  simulation pauses while held and resumes from rest at the drop point.
//  The probe's clock is RealityKit's per-frame SceneEvents.Update.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct FieldSpaceView: View {
    @Environment(FieldModel.self) private var model
    @Environment(AppModel.self) private var appModel
    @State private var renderer: FieldRenderer?
    @State private var drag: RelativeDrag?
    /// The object-anchored control. One instance, moved to whichever
    /// charge you are looking at — there is only ever one open.
    @State private var bloom = Bloom()
    /// Look-reveal drives the bloom: turn toward a charge, it unfolds.
    @State private var look = LookReveal(coneDegrees: 15)
    @State private var wells: Well?
    /// Two-hand scale: grow the dipole field until its lines arc over
    /// your head. Turn stays OFF here — the field lines clip against
    /// the real room's box, and an axis-aligned box cannot survive a
    /// yawed view without lying about where the walls are.
    @State private var scaleRig = SpatialScaleRig(
        pivot: SIMD3<Float>(0, 1.35, -0.55), range: 0.5...3.5, allowsTurn: false)

    var body: some View {
        RealityView { content, attachments in
            let renderer = FieldRenderer()
            content.add(renderer.root)

            // Creation, as a physical act: two sources you reach into
            // and pull a charge out of. The new charge is born at your
            // fingertips and follows the same drag that made it, so
            // placing and moving are one gesture.
            //
            // They FLANK the field at its own height. The first pass put
            // them low and close, where a seated user has to drop their
            // chin 30 degrees to find them — comfortable to reach, but
            // out of sight is out of mind for something whose whole job
            // is to invite you to make things.
            let sources = Well([
                .init(name: "Positive",
                      tint: UIColor(DesignTokens.Palette.positive),
                      glyph: "+",
                      position: SIMD3(-0.72, 1.30, -1.00),
                      spawn: { point in model.addCharge(positive: true, at: point) }),
                .init(name: "Negative",
                      tint: UIColor(DesignTokens.Palette.negative),
                      glyph: "\u{2212}",
                      position: SIMD3(0.72, 1.30, -1.00),
                      spawn: { point in model.addCharge(positive: false, at: point) }),
            ])
            renderer.viewRoot.addChild(sources.root)
            wells = sources

            renderer.viewRoot.addChild(bloom.root)


            // Simulation clock: step the probe every rendered frame, then
            // move its entity in the same tick — buttery motion that never
            // waits for the observation round-trip.
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.stepProbe(dt: event.deltaTime)
                    model.stepFreeCharges(dt: event.deltaTime)
                    // Look-to-measure: with this on, the Gauss surface
                    // follows the direction the head is facing, so you
                    // carry the flux meter with your gaze rather than
                    // your hand.
                    if let renderer { scaleRig.apply(to: renderer.viewRoot) }
                    wells?.update(dt: event.deltaTime)
                    if let renderer {
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                    }
                    if model.gaussSurfaceOn, model.lookToPlace,
                       let ray = appModel.room.lookRay,
                       let renderer {
                        // The gaze ray lives in the room; the Gauss
                        // surface lives in the model. Under a scaled
                        // view they differ — convert the ray, and give
                        // the arm's reach in model metres too.
                        let origin = renderer.displayPoint(fromWorld: SIMD3<Float>(ray.origin))
                        let scale = Double(max(scaleRig.liveScale, 0.01))
                        if let point = model.lookRegion.point(
                            onRay: origin, direction: ray.direction,
                            reach: model.lookReach / scale) {
                            model.moveGaussSurface(to: point)
                        }
                    }
                    // The room's clip box, pulled into model space: at
                    // 2x the walls are HALF as far away in model metres.
                    let scale = Double(max(scaleRig.liveScale, 0.01))
                    let pivot = SIMD3<Double>(0, 1.35, -0.55)
                    let bounds = appModel.room.bounds
                    renderer?.tick(model, room: RoomBox(
                        center: pivot + (bounds.center - pivot) / scale,
                        halfExtents: bounds.halfExtents / scale))
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                }
            )

            #if DEBUG
            // double(forKey:) coerces the string the launch-argument
            // domain actually stores; `object as? Double` does not.
            let forced = UserDefaults.standard.double(forKey: "viewScale")
            if forced > 0 {
                scaleRig.updateMagnification(Float(forced))
                scaleRig.endGesture()
            }
            #endif
            renderer.tick(model)
            self.renderer = renderer
        } attachments: {
        }
        // Relative dragging, no system manipulation: the charge (or
        // probe, or plate) moves by exactly the hand's displacement —
        // it never lurches toward the hand, and the per-frame tick
        // moves its field with it in the same frame.
        .spatialScale(scaleRig)
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    _ = bloom.handleTap(value.entity)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    // Pulling the bloom's grip beats everything: it is
                    // the only gesture that is already in flight.
                    if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                    if drag == nil {
                        if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                        // A pull on a well is a birth followed by a drag
                        // — the charge arrives already in your hand.
                        if let id = wells?.pull(value.entity, at: hand) {
                            drag = RelativeDrag(name: id.uuidString,
                                                target: hand, hand: hand)
                            model.heldChargeID = id
                            return
                        }
                        drag = beginDrag(entity: value.entity, hand: hand)
                    }
                    guard let drag else { return }
                    apply(drag: drag, hand: hand)
                }
                .onEnded { value in
                    guard let renderer else { return }
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
        )
    }

    /// Points the one bloom at whichever charge you are looking at (or
    /// holding), and rebuilds its controls when the target changes.
    private func syncBloom(renderer: FieldRenderer, dt: Double) {
        let candidates = model.charges.map {
            (id: $0.id.uuidString, position: SIMD3<Float>($0.position))
        }
        var ray: (origin: SIMD3<Float>, direction: SIMD3<Float>)?
        if let look = appModel.room.lookRay {
            ray = (renderer.viewRoot.convert(position: SIMD3<Float>(look.origin), from: nil),
                   renderer.viewRoot.convert(direction: SIMD3<Float>(look.direction), from: nil))
        }
        look.update(dt: dt, ray: ray, candidates: candidates)

        // A charge in your hand keeps the bloom, whatever you look at.
        let heldID = model.heldChargeID?.uuidString
        let winnerID = heldID ?? look.focusedID
        guard let winnerID, let uuid = UUID(uuidString: winnerID),
              let charge = model.charges.first(where: { $0.id == uuid }) else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }

        bloom.retarget(
            uuid,
            petals: [
                    .init(name: "Flip polarity", symbol: "plusminus",
                          tint: UIColor(white: 0.45, alpha: 1)) {
                        model.flipCharge(id: uuid)
                    },
                    .init(name: "Delete", symbol: "trash",
                          tint: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)) {
                        model.removeCharge(id: uuid)
                    },
            ],
            grip: .init(
                    name: "Magnitude",
                    range: FieldModel.magnitudeRange,
                    read: { model.magnitudeMicroCoulombs(id: uuid) },
                    write: { model.setMagnitude(id: uuid, microCoulombs: $0) },
                    format: { String(format: "%.1f \u{00B5}C", $0) },
                    // The grip rides the charge's own surface, so the
                    // handle moves outward as the charge grows.
                    radius: { renderer.displayRadius(forChargeID: uuid) + 0.02 }))

        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(charge.position),
                     viewer: viewer,
                     revealTarget: 1,
                     dt: dt)
    }

    /// Resolves what was pinched and anchors a relative-drag session.
    private func beginDrag(entity: Entity, hand: SIMD3<Double>) -> RelativeDrag? {
        var current: Entity? = entity
        while let candidate = current {
            let name = candidate.name
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
            if let id = UUID(uuidString: name),
               let charge = model.charges.first(where: { $0.id == id }) {
                model.select(id: id)
                return RelativeDrag(name: name, target: charge.position, hand: hand)
            }
            current = candidate.parent
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


}
