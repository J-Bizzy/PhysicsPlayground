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
    /// A charge in each hand (2026-11-02): the drag above is one recogniser
    /// and never hears the second hand, so charges are held per pinch here.
    @State private var hands = HandGrabs<UUID>()
    /// Kept for `handleHands`: a raw spatial event has no `value.convert`.
    @State private var sceneContent: RealityViewContent?

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
            sceneContent = content

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
                    if let renderer {
                        appModel.doorTick(renderer.root, lab: ElectromagnetismModule.id,
                                          settled: settle.tick(dt: event.deltaTime))
                    }
                    if let renderer { scaleRig.apply(to: renderer.viewRoot) }
                    model.step(dt: event.deltaTime)
                    if let renderer {
                        syncInstruments(renderer: renderer, dt: event.deltaTime)
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                    }
                    renderer?.tick(model, room: appModel.room.tangible.clipBox)
                    // The lab's placement: a pure display offset, safe because every grab
                    // moves a body by hand displacement.
                    if let placement = appModel.placement(forLab: ElectromagnetismModule.id) {
                        renderer?.root.position = placement
                    }
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
            hands.releaseAll { _ in }
            // Released, not merely forgotten: the model outlives this view.
            model.releaseAll()
        }
        .spatialScale(scaleRig)
        .simultaneousGesture(tap)
        .simultaneousGesture(
            SpatialEventGesture()
                .onChanged { handleHands($0) }
                .onEnded { handleHands($0) }
        )
        .simultaneousGesture(drags)
    }

    // MARK: A charge in each hand

    private func handleHands(_ events: SpatialEventCollection) {
        guard let renderer, let content = sceneContent else { return }
        hands.handle(
            events,
            locate: { event in
                // Through the scaled root, as the drag converts: what you hold
                // stays under your fingers at every scale.
                renderer.displayPoint(fromWorld: SIMD3<Float>(
                    content.convert(event.location3D, from: .local, to: .scene)))
            },
            begin: { entity, _ in beginHold(on: entity) },
            move: { id, position in model.moveCharge(id: id, to: position) },
            end: { session in model.heldChargeIDs.remove(session.target) })
    }

    /// A fresh pinch on a charge takes it. Anything else — the plates, the
    /// slab, the test charge, a well, a bead — is the drag's; and a second
    /// pinch on a held charge takes nothing (it is the resize, if it closed
    /// with the first).
    private func beginHold(on entity: Entity?) -> (UUID, SIMD3<Double>)? {
        guard let entity else { return nil }
        for name in Self.ancestorNames(of: entity) {
            guard let id = UUID(uuidString: name),
                  let charge = model.charges.first(where: { $0.id == id }) else { continue }
            guard !model.heldChargeIDs.contains(id) else { return nil }
            model.select(id: id)
            model.heldChargeIDs.insert(id)
            return (id, charge.position)
        }
        return nil
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
                  spawn: { model.addCharge(positive: true, at: $0) },
                  placeWithoutHands: { Self.placeCharge(positive: true, in: model) }),
            .init(name: "Negative charge", tint: DesignTokens.Palette.negativeUI,
                  label: "Charge −",
                  preview: { FieldRenderer.chargePreview(isPositive: false) },
                  position: SIMD3<Float>(FieldInstrumentLayout.wellAnchor(index: 1)),
                  spawn: { model.addCharge(positive: false, at: $0) },
                  placeWithoutHands: { Self.placeCharge(positive: false, in: model) }),
            .init(name: "Test charge", tint: DesignTokens.Palette.probePositiveUI,
                  label: "Test charge",
                  preview: { FieldRenderer.probePreview(isPositive: true) },
                  position: SIMD3<Float>(FieldInstrumentLayout.wellAnchor(index: 2)),
                  spawn: { point in
                      // Positive out of the well, as its preview promises.
                      model.probeIsPositive = true
                      model.holdProbe(at: point)
                      return Self.probeWellID
                  },
                  // A hand lets the probe fly; VoiceOver lets go of it at once.
                  settle: { _ in model.releaseProbe() }),
        ])
        wells.spawnSpace = renderer.viewRoot
        renderer.viewRoot.addChild(wells.root)
        self.wells = wells
    }

    /// VoiceOver's charge: on the ring round the field's centre that
    /// `addCharge(positive:)` walks, so a second does not land on the first.
    private static func placeCharge(positive: Bool, in model: FieldModel) -> UUID? {
        model.addCharge(positive: positive)
        return model.selectedChargeID
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
                              : DesignTokens.Palette.positiveUI,
                          announce: {
                              model.charges.first { $0.id == id }?.isPositive == true
                                  ? "Positive" : "Negative"
                          }) {
                        model.flipCharge(id: id)
                    },
                    .init(name: "Delete", symbol: "trash",
                          tint: DesignTokens.Palette.destructiveUI) {
                        model.removeCharge(id: id)
                    },
                ],
                // |q| is the charge's size, and the bead draws it out along
                // the calm track: logarithmic, clicking at the round values.
                grip: .init(
                    name: "Charge",
                    range: FieldModel.magnitudeRange,
                    read: { model.magnitudeMicroCoulombs(id: id) },
                    write: { model.setMagnitude(id: id, microCoulombs: $0) },
                    format: { PhysicsFormat.measurement($0, "\u{00B5}C", decimals: 1) },
                    radius: { renderer.displayRadius(forChargeID: id) },
                    track: Self.chargeTrack))
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
                              : DesignTokens.Palette.probePositiveUI,
                          announce: { model.probeIsPositive ? "Positive" : "Negative" }) {
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
                    radius: { renderer.probeDisplayRadius },
                    track: Self.probeTrack))
            bloom.update(anchor: SIMD3<Float>(probe.position),
                         viewer: viewer, revealTarget: 1, dt: dt)

        case nil:
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
        }
    }

    /// A charge's calm track: every round value clicks, and all but 5 µC
    /// carry their number (5 and 6 sit 8 mm apart).
    static let chargeTrack = Bloom.Grip.Track(
        detents: FieldModel.magnitudeDetents.map {
            .init(value: $0, label: $0 == 5 ? nil : PhysicsFormat.compact($0))
        })

    /// The test charge's, in nanocoulombs: 1, 2, 5, 10, 20, 50.
    static let probeTrack = Bloom.Grip.Track(
        detents: FieldModel.probeChargeDetents.map {
            .init(value: $0, label: PhysicsFormat.compact($0 * 1e9))
        })

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
                        // A charge glows through its own hold; the test charge here.
                        if id == Self.probeWellID {
                            renderer.carried.carry(FieldRenderer.probeEntityName, fromWell: true)
                        }
                        return
                    }
                    drag = beginDrag(entity: value.entity, hand: hand)
                    if let name = drag?.name, UUID(uuidString: name) == nil {
                        renderer.carried.carry(name)
                    }
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
                // Only this drag's own charge: the other hand may hold one.
                if let id = drag.flatMap({ UUID(uuidString: $0.name) }) {
                    model.heldChargeIDs.remove(id)
                }
                drag = nil
                renderer.carried.carry(nil)
                flick.reset()
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
        // A named charge is a hand's (`beginHold`); only an anonymous pinch
        // near one falls back to the nearest here.
        if names.contains(where: { name in
            UUID(uuidString: name).map { id in model.charges.contains { $0.id == id } } ?? false
        }) { return nil }
        if let id = Self.resolveCharge(
                names: names, hand: hand,
                charges: model.charges.map { ($0.id, $0.position) }),
           !model.heldChargeIDs.contains(id),
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
            model.heldChargeIDs.insert(id)
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
