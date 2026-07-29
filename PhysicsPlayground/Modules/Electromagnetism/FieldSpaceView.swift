//
//  FieldSpaceView.swift
//  Physics Playground — Electromagnetism module
//
//  The electrostatics immersive scene, hosted by PlaygroundSpaceView.
//  RealityView's make closure installs the entity tree; from then on
//  FieldRenderer is ticked every frame from SceneEvents.Update.
//
//  DELIBERATELY SIMPLE. This scene once carried gaze-revealed wells,
//  a gaze-gated bloom, and a two-hand scale rig with an invisible
//  metre-wide input plate that shielded the whole field from every
//  pinch (hit-testing uses colliders, not visible geometry). Now there
//  are two verbs — DRAG a thing to move it, TAP a charge to open its
//  own ring of controls — and the ring is driven by the TAP, never by
//  gaze, so it works identically with a mouse in the simulator and a
//  pinch on device. Tap the charge again and it folds away. Global
//  controls (add, clear, the imposed fields) live on the window panel.
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
    /// The per-charge control ring: flip, delete, and the strength
    /// grip you pull. One instance, opened by tapping a charge.
    @State private var bloom = Bloom()
    /// Which charge's ring is open. A reference type on purpose: a
    /// @State VALUE read from a RealityKit update closure is stale
    /// (the trap documented in Bloom's header) — the render loop and
    /// the tap gesture must share one live object.
    @State private var ring = RingState()

    @MainActor
    final class RingState {
        var openID: UUID?
    }

    var body: some View {
        RealityView { content in
            let renderer = FieldRenderer()
            content.add(renderer.root)
            renderer.viewRoot.addChild(bloom.root)

            // Simulation clock: step the physics every rendered frame,
            // then move entities in the same tick.
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.stepProbe(dt: event.deltaTime)
                    model.stepFreeCharges(dt: event.deltaTime)
                    // Look-to-measure: the Gauss surface follows the
                    // direction the head is facing (panel toggle;
                    // device-only, the simulator has no look ray).
                    if model.gaussSurfaceOn, model.lookToPlace,
                       let ray = appModel.room.lookRay,
                       let renderer {
                        let origin = renderer.displayPoint(
                            fromWorld: SIMD3<Float>(ray.origin))
                        if let point = model.lookRegion.point(
                            onRay: origin, direction: ray.direction,
                            reach: model.lookReach) {
                            model.moveGaussSurface(to: point)
                        }
                    }
                    if let renderer {
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                    }
                    renderer?.tick(model, room: appModel.room.bounds)
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab moves a
                    // body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                }
            )
            #if DEBUG
            // `-emRing 1` opens the selected charge's control ring at
            // launch — the simulator has no hand to tap it with, and
            // the ring's layout can only be checked by seeing it.
            if UserDefaults.standard.bool(forKey: "emRing"),
               let id = model.selectedChargeID {
                ring.openID = id
            }
            // `-emFlip 1` flips the selected charge 3 s in, so the
            // flip's visual aftermath can be screenshot from the CLI.
            if UserDefaults.standard.bool(forKey: "emFlip"),
               let id = model.selectedChargeID {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    model.flipCharge(id: id)
                }
            }
            #endif
            self.renderer = renderer
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // Petals first — a tap on Flip or Delete is theirs.
                    if bloom.handleTap(value.entity) { return }
                    // A tap on a charge selects it and toggles its
                    // control ring open; a tap on anything else folds
                    // the ring away.
                    for name in Self.ancestorNames(of: value.entity) {
                        if let id = UUID(uuidString: name),
                           model.charges.contains(where: { $0.id == id }) {
                            model.select(id: id)
                            if ring.openID == id {
                                ring.openID = nil
                            } else {
                                ring.openID = id
                                SoundPalette.play(.pop, on: value.entity, volume: 0.35)
                            }
                            return
                        }
                    }
                    ring.openID = nil
                }
        )
        // Relative dragging, no system manipulation: the charge (or
        // probe, or plate) moves by exactly the hand's displacement —
        // it never lurches toward the hand, and the per-frame tick
        // moves its field with it in the same frame.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    // Pulling the ring's strength grip beats everything:
                    // it is the only gesture already in flight.
                    if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                    if drag == nil {
                        if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
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

    /// Keeps the ring on its charge: anchored to it every frame (it
    /// follows a dragged charge), folded away the moment the charge is
    /// gone, rebuilt only when the target changes.
    private func syncBloom(renderer: FieldRenderer, dt: Double) {
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
                .init(name: "Flip polarity", symbol: "plusminus",
                      tint: UIColor(white: 0.45, alpha: 1)) {
                    model.flipCharge(id: openID)
                },
                .init(name: "Delete", symbol: "trash",
                      tint: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)) {
                    model.removeCharge(id: openID)
                },
            ],
            grip: .init(
                name: "Strength",
                range: FieldModel.magnitudeRange,
                read: { model.magnitudeMicroCoulombs(id: openID) },
                write: { model.setMagnitude(id: openID, microCoulombs: $0) },
                format: { String(format: "%.1f \u{00B5}C", $0) },
                // The grip rides the charge's own surface, so the
                // handle moves outward as the charge grows.
                radius: { renderer.displayRadius(forChargeID: openID) + 0.02 }))

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
