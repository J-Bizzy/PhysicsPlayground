//
//  FieldSpaceView.swift
//  Physics Playground — Electromagnetism module
//
//  The electrostatics immersive scene. The room holds the charges, the
//  capacitor and two wells off the left shoulder — a charge and a test
//  charge; a charge's sign and size are the charge's own (Flip on its
//  ring, a handle on its surface). Its layers, ΔV, B and verbs are in
//  More. The gesture chains' order is load-bearing, and
//  `FieldInstrumentLayout` keeps the wells 12 cm clear of the physics.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

/// Which object's ring is open. A module-local class: `RingState.openID`
/// is a `UUID?` and the probe has none, and a `@State` struct read from
/// a RealityKit closure comes back stale.
@MainActor
final class FieldRingState {
    enum Target: Hashable {
        case charge(UUID)
        case probe
    }
    var target: Target?
}

struct FieldSpaceView: View {
    @Environment(FieldModel.self) private var model
    @Environment(AppModel.self) private var appModel
    @State private var renderer: FieldRenderer?
    @State private var drag: RelativeDrag?

    /// The per-object control ring: flip, delete, and the size handle.
    @State private var bloom = Bloom()
    @State private var ring = FieldRingState()

    /// What you make: a charge, and a test charge.
    @State private var wells: Well?

    /// The hand's recent travel, for the throw that launches the probe.
    @State private var flick = ThrowSampler(window: 0.12)

    /// Identifies the test-charge well mouth: the probe has no UUID of its
    /// own, so `Well.pull` needs a stable id to hand back.
    private static let probeWellID = UUID()

    @State private var scaleRig = SpatialScaleRig(
        pivot: SIMD3<Float>(FieldModel.regionCenter), range: 0.5...4.0)

    var body: some View {
        RealityView { content in
            let renderer = FieldRenderer()
            renderer.onObjectTap = { handleObjectTap(on: $0) }
            content.add(renderer.root)
            // Disabled here and raised by `Fade.tick`, so the apparatus arrives
            // rather than appears.
            renderer.root.isEnabled = false

            // No probe on arrival (owner's call, 2026-09-05): the dipole stands
            // alone, and a test charge comes out of its well when you want one.

            renderer.viewRoot.addChild(bloom.root)

            install(into: renderer)

            // The lab shows once its scene has taken in the build (`Settle`):
            // it starts hidden and fades up then, rather than popping in and
            // stuttering through the long first frames after a mount.
            renderer.root.components.set(OpacityComponent(opacity: Settle.hiddenOpacity))
            var settle = Settle()
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's arrival and departure, on the shell's one flag; `Fade.tick`
                    // settles to a no-op once landed.
                    if let renderer, settle.tick(dt: event.deltaTime) {
                        Fade.tick(renderer.root, visible: !appModel.isDeparting,
                                  duration: AppModel.departure)
                    }
                    if let renderer { scaleRig.apply(to: renderer.viewRoot) }
                    model.step(dt: event.deltaTime)
                    if let renderer {
                        syncInstruments(renderer: renderer, dt: event.deltaTime)
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                    }
                    renderer?.tick(model, room: appModel.room.bounds)
                    // The lab's placement: a pure display offset, safe because every grab
                    // moves a body by hand displacement.
                    renderer?.root.position = appModel.labPlacement.offset
                }
            )
            applyDebugArguments()
            self.renderer = renderer
        }
        // Leaving the lab must not leave anything running or held: `teardown`
        // cancels subscriptions and geometry jobs, and an in-flight grab that
        // never gets its `onEnded` would re-target every later drag.
        .onDisappear {
            renderer?.teardown()
            // `Bloom` is a class: a grip left set would claim every subsequent drag
            // in the module.
            bloom.endGrip()
            drag = nil
        }
        .spatialScale(scaleRig)
        .simultaneousGesture(tap)
        .simultaneousGesture(drags)
    }

    // MARK: Installing the instruments
    // The parenting rule: tap-only furniture goes under `root`, which the
    // two-hand rig does not scale; anything a hand drags or spawns from goes
    // under `viewRoot`, so its coordinates and the hand's agree.

    private func install(into renderer: FieldRenderer) {
        // Wells hang off `viewRoot`: a charge is born at the fingertips and
        // handed to a drag, so mouth and hand must agree about where they are.
        // A positive mouth and a negative one (2026-10-16, the owner's call:
        // a negative charge should not take a pull and a flip), and the
        // ring still flips either.
        let wells = Well([
            .init(name: "Positive charge", tint: DesignTokens.Palette.positiveUI,
                  label: "Charge +",
                  preview: { FieldRenderer.chargePreview(isPositive: true) },
                  position: SIMD3<Float>(FieldInstrumentLayout.wellAnchor(index: 0)),
                  spawn: { model.addCharge(positive: true, at: $0) }),
            .init(name: "Negative charge", tint: DesignTokens.Palette.negativeUI,
                  label: "Charge −",
                  preview: { FieldRenderer.chargePreview(isPositive: false) },
                  position: SIMD3<Float>(FieldInstrumentLayout.wellAnchor(index: 1)),
                  spawn: { model.addCharge(positive: false, at: $0) }),
            .init(name: "Test charge", tint: DesignTokens.Palette.probePositiveUI,
                  label: "Test charge",
                  preview: { FieldRenderer.probePreview(isPositive: true) },
                  position: SIMD3<Float>(FieldInstrumentLayout.wellAnchor(index: 2)),
                  spawn: { point in
                      // Positive out of the well, as its preview promises.
                      model.probeIsPositive = true
                      model.holdProbe(at: point)
                      return Self.probeWellID
                  }),
        ])
        renderer.viewRoot.addChild(wells.root)
        self.wells = wells
    }

    // MARK: Per frame

    private func syncInstruments(renderer: FieldRenderer, dt: Double) {
        // World space: recession compares the hand against the mouths' own
        // world positions.
        let hand = appModel.room.nearestFingertip(
            to: renderer.viewRoot.convert(
                position: SIMD3<Float>(FieldInstrumentLayout.wellAnchor(index: 1)), to: nil))
        wells?.update(dt: dt, nearestHand: hand)
    }

    /// Keeps the ring on its object: anchored every frame so it follows a
    /// drag, folded the moment the object is gone, rebuilt only on change.
    private func syncBloom(renderer: FieldRenderer, dt: Double) {
        // Folded out from under: the charge was deleted, or the probe was
        // removed, escaped or captured.
        switch ring.target {
        case .charge(let id) where !model.charges.contains(where: { $0.id == id }):
            ring.target = nil
        case .probe where model.probe == nil:
            ring.target = nil
        default:
            break
        }

        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }

        switch ring.target {
        case .charge(let id):
            guard let charge = model.charges.first(where: { $0.id == id }) else { return }
            bloom.retarget(
                ring.target,
                petals: [
                    .init(name: "Flip", symbol: "plusminus",
                          tint: charge.isPositive
                              ? DesignTokens.Palette.negativeUI
                              : DesignTokens.Palette.positiveUI) {
                        model.flipCharge(id: id)
                    },
                    .init(name: "Delete", symbol: "trash",
                          tint: DesignTokens.Palette.destructiveUI) {
                        model.removeCharge(id: id)
                    },
                ],
                // |q| is the charge's size: the handle sits on its surface and
                // drawing it out grows the sphere it is pulled from.
                grip: .init(
                    name: "Charge",
                    range: FieldModel.magnitudeRange,
                    read: { model.magnitudeMicroCoulombs(id: id) },
                    write: { model.setMagnitude(id: id, microCoulombs: $0) },
                    format: { PhysicsFormat.measurement($0, "\u{00B5}C", decimals: 1) },
                    radius: { renderer.displayRadius(forChargeID: id) + 0.02 },
                    stretch: .surface(
                        center: { model.charges.first { $0.id == id }
                            .map { SIMD3<Float>($0.position) } ?? .zero },
                        radius: { renderer.displayRadius(forChargeID: id) },
                        read: { model.magnitudeMicroCoulombs(id: id) })))
            bloom.update(anchor: SIMD3<Float>(charge.position),
                         viewer: viewer, revealTarget: 1, dt: dt)

        case .probe:
            guard let probe = model.probe else { return }
            bloom.retarget(
                ring.target,
                petals: [
                    .init(name: "Flip", symbol: "plusminus",
                          tint: model.probeIsPositive
                              ? DesignTokens.Palette.probeNegativeUI
                              : DesignTokens.Palette.probePositiveUI) {
                        model.probeIsPositive.toggle()
                    },
                    .init(name: "Delete", symbol: "trash",
                          tint: DesignTokens.Palette.destructiveUI) {
                        model.removeProbe()
                    },
                ],
                grip: .init(
                    name: "Charge",
                    range: FieldModel.probeChargeRange,
                    read: { model.probeChargeMagnitude },
                    write: { model.setProbeMagnitude($0) },
                    format: { PhysicsFormat.measurement($0 * 1e9, "nC", decimals: 0) },
                    radius: { renderer.probeDisplayRadius + 0.02 },
                    stretch: .surface(
                        center: { model.probe.map { SIMD3<Float>($0.position) } ?? .zero },
                        radius: { renderer.probeDisplayRadius },
                        read: { model.probeChargeMagnitude })))
            bloom.update(anchor: SIMD3<Float>(probe.position),
                         viewer: viewer, revealTarget: 1, dt: dt)

        case nil:
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
        }
    }

    // MARK: Tap
    // Folded-out chrome before the physics under it.

    private var tap: some Gesture {
        TapGesture()
            .targetedToAnyEntity()
            .onEnded { value in handleObjectTap(on: value.entity) }
    }

    private func toggleRing(_ target: FieldRingState.Target, on entity: Entity) {
        if ring.target == target {
            ring.target = nil
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
        } else {
            ring.target = target
            SoundPalette.play(.pop, on: entity, volume: 0.35)
        }
    }

    // MARK: Drag
    // Relative dragging: an object moves by exactly the hand's displacement
    // and its field moves with it in the same frame.

    private var drags: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToAnyEntity()
            .onChanged { value in
                guard let renderer else { return }
                let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                    value.location3D, from: .local, to: .scene)))
                flick.record(hand, at: CACurrentMediaTime())

                // Gestures already in flight first: a hand holding something is never
                // re-claimed.
                if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }

                // B — beginnings.
                if drag == nil {
                    if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                    if let id = wells?.pull(value.entity, at: hand) {
                        // Born at the fingertips and dragged by the gesture that made it; the
                        // probe has no UUID, so its well's id names the drag.
                        drag = RelativeDrag(
                            name: id == Self.probeWellID
                                ? FieldRenderer.probeEntityName : id.uuidString,
                            target: hand, hand: hand)
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
                        // The throw carries the aim: with B on, a probe released at rest has
                        // nothing for the field to bend.
                        model.releaseProbe(
                            flick: flick.velocity(at: CACurrentMediaTime()) ?? .zero)
                    }
                }
                bloom.endGrip()
                drag = nil
                flick.reset()
                model.heldChargeID = nil
            }
    }

    /// Resolves what was pinched and anchors a relative-drag session.
    private func beginDrag(entity: Entity, hand: SIMD3<Double>) -> RelativeDrag? {
        let names = Self.ancestorNames(of: entity)
        for name in names {
            if name == "dielectric-slab" {
                return RelativeDrag(
                    name: name,
                    target: model.dielectricSlabCenter,
                    hand: hand)
            }
            if name == "plate-0" || name == "plate-1" {
                let index = name == "plate-0" ? 0 : 1
                let offset = (index == 0 ? -1.0 : 1.0) * model.plateSeparation / 2
                return RelativeDrag(
                    name: name,
                    target: model.capacitorCenter + SIMD3(offset, 0, 0),
                    hand: hand)
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
        if drag.name == "dielectric-slab" {
            model.moveDielectric(toWorld: position)
        } else if drag.name == "plate-0" || drag.name == "plate-1" {
            model.movePlate(drag.name == "plate-0" ? 0 : 1, toWorld: position)
        } else if drag.name == FieldRenderer.probeEntityName {
            model.holdProbe(at: position)
        } else if let id = UUID(uuidString: drag.name) {
            model.heldChargeID = id
            model.moveCharge(id: id, to: position)
        }
    }

    // MARK: Debug entry points
    // The simulator has no hand, so each apparatus and each continuous
    // quantity needs a launch argument (or `-moreOpen 1` for what is in
    // More). The value arguments matter as much as the on/off ones.

    private func applyDebugArguments() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let target = defaults.string(forKey: "emRing") {
            switch target {
            case "probe":
                model.dropProbe()
                ring.target = .probe
            default:
                if let id = model.selectedChargeID { ring.target = .charge(id) }
            }
        } else if defaults.bool(forKey: "emRing"), let id = model.selectedChargeID {
            ring.target = .charge(id)
        }

        // `-emStrength 4` sets the selected charge's |q| in µC, which is its
        // size: a charge at the house 1 µC proves nothing about the mapping.
        let strength = defaults.double(forKey: "emStrength")
        if strength > 0, let id = model.selectedChargeID {
            model.setMagnitude(id: id, microCoulombs: strength)
        }

        // `-emDielectric 0.5` slides the slab half in; the crowding only exists
        // at partial insertion. `double(forKey:)` coerces the string the
        // argument domain stores; zero-if-absent is the parked default.
        let coverage = defaults.double(forKey: "emDielectric")
        if coverage > 0 {
            model.dielectricCoverage = min(coverage, 1)
        }
        // `-emLaunch 1` fires the deflection shot at launch, because a
        // parabola is a motion and the simulator cannot pinch the verb;
        // with `-startPaused` and `-pauseAfter` it freezes mid-bend.
        if defaults.bool(forKey: "emLaunch") {
            model.launchProbeThroughGap()
        }

        // `-viewScale 2.5` bakes a committed scale in at launch.
        // `double(forKey:)` coerces the stored string.
        let forced = defaults.double(forKey: "viewScale")
        if forced > 0 {
            scaleRig.updateMagnification(Float(forced))
            scaleRig.endGesture()
        }
        #endif
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

    /// Resolves a pinch to a charge: an ancestor named with a charge's UUID
    /// wins; failing that, the nearest charge within `fallbackRadius` of the
    /// hand. `FieldInstrumentLayout` keeps every instrument further than
    /// that from the physics.
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

    /// The tap routing, out of the gesture closure so VoiceOver reaches it
    /// too; only the module knows that pressing an object opens its ring.
    private func handleObjectTap(on entity: Entity) {
        if bloom.handleTap(entity) { return }

        for name in Self.ancestorNames(of: entity) {
            if name == FieldRenderer.probeEntityName, model.probe != nil {
                toggleRing(.probe, on: entity)
                return
            }
            if let id = UUID(uuidString: name),
               model.charges.contains(where: { $0.id == id }) {
                model.select(id: id)
                toggleRing(.charge(id), on: entity)
                return
            }
        }
        // Folding by tapping elsewhere answers, as in every other lab.
        if ring.target != nil {
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
        }
        ring.target = nil
    }

}
