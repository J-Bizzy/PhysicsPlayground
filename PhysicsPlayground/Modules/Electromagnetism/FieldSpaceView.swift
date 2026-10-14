//
//  FieldSpaceView.swift
//  Physics Playground — Electromagnetism module
//
//  The electrostatics immersive scene — the module's only surface.
//  Everything stands off the left shoulder, split by depth: deep at the
//  station's plane, a layers bank with a B-strength rail under it; fore
//  of it, four wells with the Clear plate at their base; and a ΔV rail
//  over the capacitor. The gesture chains' order is load-bearing, and
//  `FieldInstrumentLayout` keeps the furniture 12 cm clear of the physics.
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

    /// The per-object control ring: delete, and the strength bead.
    @State private var bloom = Bloom()
    @State private var ring = FieldRingState()

    /// What exists. Built in the make closure because every switch reads
    /// and writes the model.
    @State private var bank: SpatialLayerBank?
    /// The module's one standing verb: clear every charge. See `install`.
    @State private var verbs: SpatialActionBank?
    /// What you make.
    @State private var wells: Well?

    /// ΔV across the plates. Bolted to the capacitor and carried with it.
    @State private var voltageTrack: SpatialTrackControl?
    /// B strength, under the bank plate that summons the field.
    @State private var fieldTrack: SpatialTrackControl?
    /// The rail a hand is currently dragging, if any.
    @State private var activeTrack: SpatialTrackControl?

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

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's arrival and departure, on the shell's one flag; `Fade.tick`
                    // settles to a no-op once landed.
                    if let renderer {
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
        .simultaneousGesture(secondHandTap)
        .simultaneousGesture(tap)
        .simultaneousGesture(drags)
    }

    /// The pinches currently down, for `secondHandTap`.
    @State private var activePinchIDs: Set<SpatialEventCollection.Event.ID> = []

    /// The two-handed tap the recognisers cannot see: while one hand holds
    /// a drag, SwiftUI never delivers the other hand's pinch to the
    /// `TapGesture`. A passive `SpatialEventGesture` hands a second pinch on
    /// the layers bank to the bank directly; a lone pinch stays the
    /// TapGesture's.
    private var secondHandTap: some Gesture {
        SpatialEventGesture()
            .onChanged { events in
                for event in events {
                    if event.phase == .active {
                        guard !activePinchIDs.contains(event.id) else { continue }
                        if !activePinchIDs.isEmpty,
                           let target = event.targetedEntity {
                            _ = bank?.handleTap(target)
                        }
                        activePinchIDs.insert(event.id)
                    } else {
                        activePinchIDs.remove(event.id)
                    }
                }
            }
            .onEnded { events in
                for event in events where event.phase != .active {
                    activePinchIDs.remove(event.id)
                }
            }
    }

    // MARK: Installing the instruments
    // The parenting rule: tap-only furniture goes under `root`, which the
    // two-hand rig does not scale; anything a hand drags or spawns from goes
    // under `viewRoot`, so its coordinates and the hand's agree.

    private func install(into renderer: FieldRenderer) {
        let bank = SpatialLayerBank(
            accent: UIColor(DesignTokens.Palette.fieldLine),
            layers: [
                .init(id: "lines", label: "Field lines", symbol: "scribble",
                      isOn: { model.showLines },
                      toggle: { model.showLines.toggle() }),
                .init(id: "free", label: "Free charges", symbol: "arrow.left.and.right",
                      isOn: { model.chargesRespond },
                      toggle: { model.chargesRespond.toggle() }),
                // "Capacitor", not "Parallel plates": the bank's own switches are also
                // plates, and two things in one room called the same word was
                // unfindable on device.
                .init(id: "plates", label: "Capacitor", symbol: "square.split.2x1",
                      isOn: { model.capacitorOn },
                      toggle: { model.capacitorOn.toggle() }),
                .init(id: "bfield", label: "Uniform B", symbol: "arrow.up",
                      isOn: { model.magneticFieldOn },
                      toggle: { model.magneticFieldOn.toggle() }),
            ])
        renderer.root.addChild(bank.root)
        self.bank = bank

        // Clear, at the head of the well column that made every charge. It
        // confirms: a plate beside the thing it empties is otherwise one stray
        // pinch from wiping the room.
        let verbs = SpatialActionBank(
            accent: DesignTokens.Palette.negativeUI,
            actions: [
                .init(id: "clear", label: "Clear all", symbol: "trash.slash",
                      // Read every frame; available while anything placed is in the room,
                      // the probe included.
                      isAvailable: { !model.charges.isEmpty || model.probe != nil },
                      confirms: true,
                      fire: { model.clearEverything() }),
                // The CRT demo: fire the test charge crosswise through the gap. With
                // the verbs because it places the probe, but it does not confirm:
                // re-firing is the point.
                .init(id: "deflect", label: "Deflect shot",
                      symbol: "arrow.turn.down.right",
                      isAvailable: { model.capacitorOn },
                      fire: { model.launchProbeThroughGap() }),
            ])
        renderer.root.addChild(verbs.root)
        self.verbs = verbs

        // Wells hang off `viewRoot`: a charge is born at the fingertips and
        // handed to a drag, so mouth and hand must agree about where they are.
        let wells = Well([
            .init(name: "Positive", tint: DesignTokens.Palette.positiveUI,
                  label: "Add +",
                  preview: { FieldRenderer.chargePreview(isPositive: true) },
                  position: SIMD3<Float>(FieldInstrumentLayout.wellAnchor(index: 0)),
                  spawn: { model.addCharge(positive: true, at: $0) }),
            .init(name: "Negative", tint: DesignTokens.Palette.negativeUI,
                  label: "Add −",
                  preview: { FieldRenderer.chargePreview(isPositive: false) },
                  position: SIMD3<Float>(FieldInstrumentLayout.wellAnchor(index: 1)),
                  spawn: { model.addCharge(positive: false, at: $0) }),
            // Two test-charge mouths, one per polarity: the probe's sign is chosen
            // by which mouth you pull from.
            .init(name: "Test +", tint: DesignTokens.Palette.probePositiveUI,
                  label: "Test +",
                  preview: { FieldRenderer.probePreview(isPositive: true) },
                  position: SIMD3<Float>(FieldInstrumentLayout.wellAnchor(index: 2)),
                  spawn: { point in
                      model.probeIsPositive = true
                      model.holdProbe(at: point)
                      return Self.probeWellID
                  }),
            .init(name: "Test −", tint: DesignTokens.Palette.probeNegativeUI,
                  label: "Test −",
                  preview: { FieldRenderer.probePreview(isPositive: false) },
                  position: SIMD3<Float>(FieldInstrumentLayout.wellAnchor(index: 3)),
                  spawn: { point in
                      model.probeIsPositive = false
                      model.holdProbe(at: point)
                      return Self.probeWellID
                  }),
        ])
        renderer.viewRoot.addChild(wells.root)
        self.wells = wells

        let voltage = SpatialTrackControl(
            name: "Plate voltage",
            center: SIMD3<Float>(FieldInstrumentLayout.voltageTrackCenter(
                capacitorCenter: model.capacitorCenter)),
            normal: [0, 0, 1],
            accent: DesignTokens.Palette.positiveUI,
            range: FieldModel.plateVoltageRange,
            read: { model.plateVoltage },
            // Snapped to 500 V so the bead lands on honest values.
            write: { model.setPlateVoltage($0) },
            format: { PhysicsFormat.measurement($0 / 1000, "kV", decimals: 0) },
            // E = V/d, live under the rail; follows a plate drag (d) as well as the
            // bead (V).
            subtitle: { _ in
                "E = " + PhysicsFormat.measurement(model.plateFieldkVPerM, "kV/m", decimals: 1)
            })
        renderer.viewRoot.addChild(voltage.root)
        self.voltageTrack = voltage

        let field = SpatialTrackControl(
            name: "Magnetic field",
            center: SIMD3<Float>(FieldInstrumentLayout.fieldTrackAnchor),
            normal: SIMD3<Float>(FieldInstrumentLayout.fieldTrackNormal),
            accent: DesignTokens.Palette.probeNegativeUI,
            range: FieldModel.magneticFieldRange,
            read: { model.magneticFieldTesla },
            write: { model.magneticFieldTesla = $0 },
            format: { PhysicsFormat.measurement($0 / 1000, "kT", decimals: 0) })
        renderer.viewRoot.addChild(field.root)
        self.fieldTrack = field
    }

    // MARK: Per frame

    private func syncInstruments(renderer: FieldRenderer, dt: Double) {
        let head = appModel.room.headPosition.map { SIMD3<Float>($0) }

        // The bank and the picker live under `root`, which carries the
        // lab-placement offset, so the viewer is converted into that frame.
        let headInRoot = head.map {
            renderer.root.convert(position: $0, from: nil)
        }
        // World space, unlike `headInRoot`: recession compares the hand against
        // each instrument's own world position.
        let hand = appModel.room.nearestFingertip(
            to: renderer.root.convert(
                position: SIMD3<Float>(FieldInstrumentLayout.bankAnchor), to: nil))
        bank?.update(anchor: SIMD3<Float>(FieldInstrumentLayout.bankAnchor),
                     viewer: headInRoot, dt: dt, nearestHand: hand)
        verbs?.update(anchor: SIMD3<Float>(FieldInstrumentLayout.clearPlateAnchor),
                      viewer: headInRoot, dt: dt,
                      resetNonce: appModel.resetNonce, nearestHand: hand)
        wells?.update(dt: dt, nearestHand: hand)

        // Each rail exists exactly when its apparatus does.
        voltageTrack?.isEnabled = model.capacitorOn
        fieldTrack?.isEnabled = model.magneticFieldOn

        if model.capacitorOn, let voltage = voltageTrack {
            voltage.root.position = SIMD3<Float>(
                FieldInstrumentLayout.voltageTrackCenter(
                    capacitorCenter: model.capacitorCenter))
            voltage.refresh()
        }
        // `refresh()` is the caller's job: a rail ticks nothing of its own, and
        // would show a stale value after a reset.
        if fieldTrack?.isEnabled == true { fieldTrack?.refresh() }
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
                    .init(name: "Delete", symbol: "trash",
                          tint: DesignTokens.Palette.destructiveUI) {
                        model.removeCharge(id: id)
                    },
                ],
                grip: .init(
                    name: "Strength",
                    range: FieldModel.magnitudeRange,
                    read: { model.magnitudeMicroCoulombs(id: id) },
                    write: { model.setMagnitude(id: id, microCoulombs: $0) },
                    format: { PhysicsFormat.measurement($0, "\u{00B5}C", decimals: 1) },
                    // Rides the charge's own surface, so the handle moves
                    // outward as the charge grows.
                    radius: { renderer.displayRadius(forChargeID: id) + 0.02 }))
            bloom.update(anchor: SIMD3<Float>(charge.position),
                         viewer: viewer, revealTarget: 1, dt: dt)

        case .probe:
            guard let probe = model.probe else { return }
            bloom.retarget(
                ring.target,
                petals: [
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
                    radius: { 0.05 }))
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
                if let track = activeTrack {
                    // A rail can go away under a live drag (switch the capacitor off while
                    // pulling its ΔV bead); the hand must not stay captured by a dead
                    // instrument.
                    guard track.isEnabled else {
                        activeTrack = nil
                        return
                    }
                    track.adjust(hand: hand)
                    return
                }

                // B — beginnings.
                if drag == nil {
                    if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                    for track in [voltageTrack, fieldTrack] {
                        if let track, track.owns(value.entity) {
                            activeTrack = track
                            track.adjust(hand: hand)
                            return
                        }
                    }
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
                activeTrack?.endAdjust()
                activeTrack = nil
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
    // Every instrument is an object in the room and the simulator has no
    // hand, so each apparatus and each continuous quantity needs a launch
    // argument. The value arguments matter as much as the on/off ones.

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

        // `-emClear 1` arms the Clear plate rather than firing it: an emptied
        // room photographs like an unused one, and the armed state is the half
        // that cannot otherwise be seen.
        if defaults.bool(forKey: "emClear") {
            verbs?.arm("clear", holds: true)
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
        if bank?.handleTap(entity) == true { return }
        if verbs?.handleTap(entity) == true { return }

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
