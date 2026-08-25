//
//  FieldSpaceView.swift
//  Physics Playground — Electromagnetism module
//
//  The electrostatics immersive scene — the module's ONLY surface (its
//  window is a title bar). Left to right: a layers bank (field lines, free
//  charges, capacitor, uniform B), a B-strength rail under it, four wells
//  that hand you a charge already in your grip, and a ΔV rail bolted under
//  the capacitor. On the objects: tap for a ring, grab a plate to set d.
//
//  THE ORDER OF THE GESTURE CHAINS BELOW IS LOAD-BEARING. An
//  input-targetable collider is never larger than the thing it represents,
//  and nothing sits between the pinch ray and the object it decorates;
//  `FieldInstrumentLayout` keeps the furniture 12 cm clear of the physics
//  so contention is impossible by geometry rather than by care.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

/// Which object's ring is open.
///
/// A module-local reference type, for two reasons. `RingState.openID` is a
/// `UUID?` shared by four modules and the probe is not a UUID, so widening
/// it would be a change to all of them for one module's benefit. And it
/// must be a CLASS for the same reason `RingState` is: a `@State` struct
/// read from inside a RealityKit closure comes back stale.
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

    /// Identifies the test-charge well mouth. `Well.pull` hands back only
    /// the id its `spawn` closure returned, so the probe — which has no
    /// UUID of its own — needs a stable one to be recognised by.
    private static let probeWellID = UUID()

    @State private var scaleRig = SpatialScaleRig(
        pivot: SIMD3<Float>(FieldModel.regionCenter), range: 0.5...4.0)

    /// Identifies the standing readout card. See `FieldReadoutCard`.
    private static let readoutCardID = "field-readout"
    /// Above the layers bank on the left flank. NOT in
    /// `FieldInstrumentLayout` — those invariants govern colliders and
    /// this carries none. Field lines cross it unavoidably (uniform B
    /// fills the region), so the fix is the MATERIAL, not the position.
    private static let readoutCardAnchor = SIMD3<Double>(-1.08, 1.68, -0.86)

    var body: some View {
        RealityView { content, attachments in
            let renderer = FieldRenderer()
            renderer.onObjectTap = { handleObjectTap(on: $0) }
            content.add(renderer.root)
            // ARRIVES, NEVER APPEARS. Disabled here and raised by
            // `Fade.tick` below, so the apparatus resolves into the room
            // instead of being there between one frame and the next.
            renderer.root.isEnabled = false

            // A LAB WITH NOTHING MOVING IN IT IS A DIAGRAM. `reset()` seeds
            // a dipole with `chargesRespond` off and no probe, so the field
            // portrait was correct, beautiful and completely still until the
            // wearer thought to do something. The probe rides the dipole on
            // arrival instead.
            //
            // HERE AND NOT IN `reset()`, for two reasons. The shell gives
            // each module fresh view identity, so `make` runs on EVERY entry
            // while the model persists on `AppModel` — which is the only hook
            // that reaches a second visit. And `FieldModelTests` asserts
            // `probe == nil` after a reset; that contract is right and stays.
            //
            // Not `chargesRespond = true` instead: the two dipole charges
            // would accelerate into each other and destroy the recognisable
            // picture inside a second, and its plate would be lit over a
            // claim that is false at rest.
            if model.probeStatus != .running { model.dropProbe() }

            // Everything this module measures, on one billboarded card.
            // Parented to `root`, NOT `viewRoot`: the rig reaches 4×, and a
            // readout that grew with the field would leave the frame.
            if let card = attachments.entity(for: Self.readoutCardID) {
                card.components.set(BillboardComponent())
                card.position = SIMD3<Float>(Self.readoutCardAnchor)
                stripInput(from: card)
                renderer.root.addChild(card)
            }
            renderer.viewRoot.addChild(bloom.root)

            install(into: renderer)

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's own arrival and departure, on the shell's
                    // one flag. `Fade.tick` settles to a no-op — it drops its
                    // clock and its OpacityComponent once landed — so this
                    // costs one comparison for all the frames that are not a
                    // transition.
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
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab moves a
                    // body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                }
            )
            applyDebugArguments()
            self.renderer = renderer
        } attachments: {
            Attachment(id: Self.readoutCardID) {
                FieldReadoutCard()
                    // A readout, not an instrument: no hit testing, so it
                    // can never contend for a pinch with the charges it
                    // reports on. This is the distinction that keeps it
                    // out of `FieldInstrumentLayout`'s clearance rules.
                    .allowsHitTesting(false)
                    .environment(model)
            }
        }
        // Leaving the lab must not leave anything running or held.
        //
        // `teardown` cancels the renderer's event subscriptions and any
        // geometry job in flight (see `GeometryPipeline.cancel`), and the
        // drag state is cleared because NOTHING ELSE CAN CLEAR IT: an
        // in-flight grab that never receives its `onEnded` — the space
        // closing under it is the ordinary way that happens — otherwise
        // strands the object wherever the hand left it and re-targets
        // every later drag at the same one, with no exit but leaving.
        .onDisappear {
            renderer?.teardown()
            // A GRIP SURVIVES THE SPACE CLOSING, and that is worse than
            // it sounds. `Bloom` is a class, so `gripDrag` outlives this
            // view; left set, `updateGrip` claims EVERY subsequent drag
            // in the module and nothing at all can be grabbed. That
            // exact failure is documented in PendulumsSpaceView's
            // `onEnded` — it cost this module every one of its verbs
            // once already.
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

    /// The two-handed tap the recognisers cannot see.
    ///
    /// "Switch the Capacitor plate OFF while dragging its ΔV bead" was
    /// unactionable on device (owner, 2026-08-03): while one hand holds
    /// a drag, SwiftUI never delivers the other hand's pinch to the
    /// `TapGesture` — one recogniser, one gesture. So a passive
    /// `SpatialEventGesture` watches the raw pinches, and a NEW pinch
    /// that lands on the layers bank while another pinch is already
    /// down is handed to the bank directly. Only the second-hand case:
    /// a lone pinch stays the TapGesture's, so nothing fires twice.
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
    //
    // THE PARENTING RULE, which is not obvious and bites silently:
    // tap-only furniture goes under `root`, which the two-hand rig does
    // NOT scale — a bank that grew to 4× along with the field would put
    // its own switches out of reach the moment you used them. Anything a
    // hand drags or spawns from goes under `viewRoot`, so its coordinates
    // and the hand's (which arrive via `displayPoint(fromWorld:)`) are the
    // same space. Gravity Lab is parented exactly this way.

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
                // "Capacitor", not "Parallel plates". An on-device pass
                // could not find this switch at all — and the copy is
                // why: the panel and the module blurb both say "the
                // plates on your left decide what exists", where THE
                // PLATES means these five bank switches, while the thing
                // this one summons is also a pair of plates. Two objects
                // in one room called the same word, on opposite walls.
                // The apparatus keeps the name it is; the switch takes
                // the name of what it makes.
                .init(id: "plates", label: "Capacitor", symbol: "square.split.2x1",
                      isOn: { model.capacitorOn },
                      toggle: { model.capacitorOn.toggle() }),
                .init(id: "bfield", label: "Uniform B", symbol: "arrow.up",
                      isOn: { model.magneticFieldOn },
                      toggle: { model.magneticFieldOn.toggle() }),
            ])
        renderer.root.addChild(bank.root)
        self.bank = bank

        // "Clear the field", at the head of the well column that made every
        // charge. It CONFIRMS: a plate standing beside the thing it empties
        // is otherwise one stray pinch from wiping the whole arrangement.
        let verbs = SpatialActionBank(
            accent: DesignTokens.Palette.negativeUI,
            actions: [
                .init(id: "clear", label: "Clear all", symbol: "trash.slash",
                      // `isAvailable` is read every frame, so it tracks its
                      // condition. Available while ANYTHING placed is in
                      // the room — the probe counts.
                      isAvailable: { !model.charges.isEmpty || model.probe != nil },
                      confirms: true,
                      fire: { model.clearEverything() }),
                // The CRT demo: fire the test charge crosswise through
                // the gap and watch the parabola. Lives with the verbs
                // because it PLACES the probe — it is a launch, not a
                // display layer — but it does not confirm: re-firing is
                // the point, and nothing is destroyed but the previous
                // flight.
                .init(id: "deflect", label: "Deflect shot",
                      symbol: "arrow.turn.down.right",
                      isAvailable: { model.capacitorOn },
                      fire: { model.launchProbeThroughGap() }),
            ])
        renderer.root.addChild(verbs.root)
        self.verbs = verbs

        // Wells hang off `viewRoot`: a charge is born at the fingertips
        // and handed straight to a drag, so the mouth and the hand have to
        // agree about where they are.
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
            // TWO test-charge mouths, one per polarity. The probe's sign
            // used to be set on a particle bank AFTER it existed, so
            // what came out of the well was whatever the bank happened to
            // be on — the one object whose sign you could not choose
            // while making it. The bank is gone (2026-08-03); the choice
            // lives entirely in which mouth you pull from.
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
            // E = V/d, live under the rail — the physics this apparatus
            // teaches, previously visible only on the card across the
            // room. Follows a plate drag (d) as well as the bead (V).
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
        // lab-placement offset — so the viewer has to be converted into
        // that frame or they would yaw toward a head that appears to be
        // somewhere it is not.
        let headInRoot = head.map {
            renderer.root.convert(position: $0, from: nil)
        }
        // WORLD SPACE, unlike `headInRoot` above: recession compares the
        // hand against each instrument's own world position, so the hand
        // must not be converted into the renderer's frame.
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
        // `refresh()` is the caller's job — the control ticks nothing of
        // its own. Without these the beads would show the last value a
        // hand dragged them to and ignore a reset or a launch argument.
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
    //
    // Folded-out chrome before the physics under it: the bank, the picker
    // and the ring's petals all sit visually on top of the field, so a tap
    // that lands on one is theirs.

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
    //
    // Relative dragging, no system manipulation: an object moves by exactly
    // the hand's displacement — it never lurches toward the hand, and the
    // per-frame tick moves its field with it in the same frame.

    private var drags: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToAnyEntity()
            .onChanged { value in
                guard let renderer else { return }
                let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                    value.location3D, from: .local, to: .scene)))
                flick.record(hand, at: CACurrentMediaTime())

                // A — gestures already in flight. Nothing may re-claim a
                // hand that is already holding something, or a drag that
                // starts on a rail and wanders over a charge would begin
                // dragging the charge halfway through.
                if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                if let track = activeTrack {
                    // A rail can go away underneath a live drag — switch
                    // the capacitor off while pulling its ΔV bead and the
                    // ΔV rail is disabled the same frame. `adjust` then
                    // no-ops correctly but the hand stays captured by a
                    // dead instrument for the rest of the gesture, and
                    // nothing else can claim it.
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
                        // Born at the fingertips, and dragged by the same
                        // gesture that made it. The probe has no UUID of
                        // its own, so its well's id maps to the drag name
                        // the rest of this file already understands.
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
                        // The throw carries the aim: with B on, a probe
                        // released at rest has nothing for the field to
                        // bend (F = qv×B is zero when v is).
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
    //
    // Every instrument above is an object in the room, and the simulator
    // has no hand to press one with — `simctl` has no tap verb. So each
    // apparatus and each continuous quantity needs a launch argument, or
    // this migration cannot be screenshot at all. A rail whose bead is
    // always at its default proves nothing about the mapping, which is why
    // the value args matter as much as the on/off ones.

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

        // `-emClear 1` ARMS the Clear plate rather than firing it.
        //
        // Firing would be the useless argument: the plate's resting look
        // is already in every launch screenshot, and an empty room
        // photographs as an empty room whether a control emptied it or
        // nothing ever filled it. The armed state is the half that
        // cannot otherwise be seen — the lit lamp, the nameplate swapped
        // to "Tap again" — and it is the half that carries the whole
        // safety argument for putting a destructive verb in the room.
        if defaults.bool(forKey: "emClear") {
            verbs?.arm("clear", holds: true)
        }

        // `-emDielectric 0.5` slides the slab half in — the value arg
        // matters more than an on/off: a slab parked at zero coverage
        // photographs identically to no slab feature at all, and the
        // charge crowding it causes only exists at partial insertion.
        // `double(forKey:)` coerces the STRING the launch-argument
        // domain stores, exactly as `-viewScale` below already
        // documents — an `object as? NSNumber` cast fails silently, and
        // did, with C reading the bare 11.2 pF in the first screenshot.
        // Zero-if-absent is the parked default, so no presence check.
        let coverage = defaults.double(forKey: "emDielectric")
        if coverage > 0 {
            model.dielectricCoverage = min(coverage, 1)
        }
        // `-emLaunch 1` fires the deflection shot at launch, because a
        // parabola is a MOTION and the simulator cannot pinch the verb;
        // with `-startPaused` and `-pauseAfter` it freezes mid-bend.
        if defaults.bool(forKey: "emLaunch") {
            model.launchProbeThroughGap()
        }

        // `-viewScale 2.5` bakes a committed scale in at launch so the
        // scaled field can be screenshot-verified from the CLI — the
        // simulator has no second hand to pinch with. `double(forKey:)`
        // coerces the string the launch-argument domain stores;
        // `object as? Double` does not.
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

    /// Resolves a pinch to a charge. An ancestor named with a charge's
    /// UUID wins outright; failing that, the nearest charge within
    /// `fallbackRadius` of the hand — so a near-miss pinch on a charge
    /// still grabs it instead of silently doing nothing.
    ///
    /// This fallback is load-bearing rather than decorative: the capacitor
    /// plates carry 26 cm collision spheres that overlap in the middle of
    /// the gap, and the flux meter carries one of its full radius. Without
    /// it, a charge sitting inside either apparatus could not be grabbed at
    /// all. `FieldInstrumentLayout` keeps every instrument further than
    /// `fallbackRadius` from the physics for exactly this reason.
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

    /// EXTRACTED FROM THE TAP CLOSURE, 2026-08-08, so VoiceOver reaches
    /// the same routing a pinch does.
    ///
    /// `Grabbable` has taken an `activate` closure since the mechanism
    /// moved into RenderKit, and every call site passed nothing — so the
    /// objects a hand can carry could be reached no other way. It is not
    /// a sweep: the helper configures entities it did not build and
    /// cannot know what pressing one should mean. Only the module knows
    /// that, so the routing had to come out of the gesture first.
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
        ring.target = nil
    
    }

}
