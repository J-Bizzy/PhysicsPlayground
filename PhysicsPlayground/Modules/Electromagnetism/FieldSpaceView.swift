//
//  FieldSpaceView.swift
//  Physics Playground — Electromagnetism module
//
//  The electrostatics immersive scene, hosted by PlaygroundSpaceView, and
//  since 2026-07-31 the module's ONLY control surface. The window panel
//  next door reports numbers and does not set anything.
//
//  The room, left to right:
//
//    · A LAYERS BANK off the left flank — five plates saying what exists:
//      field lines, free charges, the plates, the uniform B, the flux
//      meter. Flick one and its apparatus arrives WITH its instrument
//      attached, which is the whole delight of the arrangement.
//    · A B-STRENGTH RAIL under the bank, present only while B is.
//    · THREE WELLS on the right — pull a +, a −, or the test charge out
//      and it is already in your hand; creating and aiming are one motion.
//    · A PARTICLE BANK under them: + ball, − ball, electron, positron.
//      One physically honest question — what am I firing? — in place of a
//      polarity picker and an "electron mode" toggle that were secretly
//      the same decision.
//    · A ΔV RAIL bolted under the capacitor, carried with it.
//
//  And on the objects themselves: tap a charge or the probe for its ring
//  (delete, and a strength bead), grab a plate to set d, grab the flux
//  meter's rim to set its radius and — if it is a disc — its facing.
//
//  THE ORDER OF THE GESTURE CHAINS BELOW IS LOAD-BEARING. This module has
//  been broken once by a collider that shielded the field from every pinch
//  (`SpatialScaleHandle`, DECISIONS 2026-07-29), and the rules that came
//  out of it govern everything here: an input-targetable collider is never
//  larger than the thing it represents, and nothing sits between the pinch
//  ray and the object it decorates. `FieldInstrumentLayout` keeps the
//  furniture 12 cm clear of the physics so contention is impossible by
//  geometry rather than by care.
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
        /// The `electron` payload is not decoration. `Bloom.retarget`
        /// early-outs on an unchanged id, so without it, switching the
        /// particle while the probe's ring is open would leave a
        /// "Strength" grip attached to q = e — a constant of nature
        /// wearing a control.
        case probe(electron: Bool)
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

    /// What the test particle IS — the polarity picker and the electron
    /// toggle, merged, because they were never independent: electron mode
    /// rewrites q, m, the display clock AND the usable field range all at
    /// once, which is one particle choice wearing a toggle's clothes.
    @State private var particles = SpatialPicker(
        accessibilityNoun: "Test particle",
        // Labels kept SHORT because the discs are close together: at this
        // fan's spacing (~7.5 cm) a label much over 5 cm wide runs into its
        // neighbour's, and "Electron e⁻" did. The symbol on each disc
        // already carries the sign, so the word only has to carry the
        // particle.
        choices: [
            PickerChoice(id: "plus", label: "Ball +", symbol: "plus.circle.fill"),
            PickerChoice(id: "minus", label: "Ball −", symbol: "minus.circle.fill"),
            PickerChoice(id: "electron", label: "Electron", symbol: "e.circle.fill"),
            PickerChoice(id: "positron", label: "Positron", symbol: "e.circle"),
        ],
        staysOpen: true,
        accent: UIColor(DesignTokens.Palette.probePositive),
        // A bank is a row, not a fan — the same reshaping Gravity Lab's
        // clock bank needed, and for the same reason: a 150° arc is built
        // for a menu that folds away, and reads as scattered debris when
        // it never does.
        layout: FanLayout(span: 50 * .pi / 180, reach: 0.26,
                          verticalScale: 0.25, lift: 0, stagger: 0))

    /// ΔV across the plates. Bolted to the capacitor and carried with it.
    @State private var voltageTrack: SpatialTrackControl?
    /// B strength — TWO instruments of which at most one is ever present.
    ///
    /// Not one rail with a switching range: `SpatialTrackControl.range` is
    /// a stored `let`, and more importantly the two are not the same
    /// measurement. Ball mode runs at ~50 kT, a field a thousand times the
    /// strongest ever built, and electron mode at a tenth of a millitesla,
    /// which is a real bench magnet. They deserve their own units, their
    /// own labels, and — for the fictional one — the disclosure that says
    /// so on the panel beside it.
    @State private var ballFieldTrack: SpatialTrackControl?
    @State private var electronFieldTrack: SpatialTrackControl?
    /// The rail a hand is currently dragging, if any.
    @State private var activeTrack: SpatialTrackControl?
    /// True while a hand is holding the flux meter's rim.
    @State private var gaussRimDrag = false

    /// The hand's recent travel, for the throw that launches the probe.
    @State private var flick = ThrowSampler(window: 0.12)

    /// Identifies the test-charge well mouth. `Well.pull` hands back only
    /// the id its `spawn` closure returned, so the probe — which has no
    /// UUID of its own — needs a stable one to be recognised by.
    private static let probeWellID = UUID()

    @State private var scaleRig = SpatialScaleRig(
        pivot: SIMD3<Float>(FieldModel.regionCenter), range: 0.5...4.0)

    var body: some View {
        RealityView { content in
            let renderer = FieldRenderer()
            content.add(renderer.root)
            renderer.viewRoot.addChild(bloom.root)

            install(into: renderer)

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    if let renderer { scaleRig.apply(to: renderer.viewRoot) }
                    model.stepProbe(dt: event.deltaTime)
                    model.stepFreeCharges(dt: event.deltaTime)
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
        }
        .spatialScale(scaleRig)
        .simultaneousGesture(tap)
        .simultaneousGesture(drags)
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
                .init(id: "gauss", label: "Flux meter", symbol: "circle.dashed",
                      isOn: { model.gaussSurfaceOn },
                      toggle: { model.gaussSurfaceOn.toggle() }),
            ])
        renderer.root.addChild(bank.root)
        self.bank = bank

        // "Clear the field", off the window panel and onto the head of
        // the well column — the wells made every charge in the room, so
        // the one control that removes them all belongs with them.
        //
        // It CONFIRMS. The panel guarded this with `.disabled` plus a
        // destructive button role and nothing else, which was survivable
        // while it lived behind a window you had to look at on purpose.
        // A plate standing in the room beside the thing it empties is one
        // stray pinch from wiping a field somebody spent minutes
        // arranging, and there is no window left to put a dialog in.
        let verbs = SpatialActionBank(
            accent: DesignTokens.Palette.negativeUI,
            actions: [
                .init(id: "clear", label: "Clear all", symbol: "trash.slash",
                      // Unlike the launcher's Clear petal, this one CAN
                      // track its condition: `SpatialActionBank` reads
                      // `isAvailable` every frame rather than at build
                      // time, which is the whole reason it takes a
                      // closure instead of a Bool.
                      isAvailable: { !model.charges.isEmpty },
                      confirms: true,
                      fire: { model.removeAllCharges() }),
            ])
        renderer.root.addChild(verbs.root)
        self.verbs = verbs

        renderer.root.addChild(particles.root)
        particles.selectedID = {
            switch (model.electronMode, model.probeIsPositive) {
            case (false, true): "plus"
            case (false, false): "minus"
            case (true, false): "electron"
            case (true, true): "positron"
            }
        }
        particles.onSelect = { id in
            model.electronMode = id == "electron" || id == "positron"
            model.probeIsPositive = id == "plus" || id == "positron"
        }

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
            .init(name: "Test charge", tint: DesignTokens.Palette.probePositiveUI,
                  label: "Test charge",
                  preview: { FieldRenderer.probePreview() },
                  position: SIMD3<Float>(FieldInstrumentLayout.wellAnchor(index: 2)),
                  spawn: { point in
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
            write: { model.plateVoltage = $0 },
            format: { String(format: "%.0f kV", $0 / 1000) })
        renderer.viewRoot.addChild(voltage.root)
        self.voltageTrack = voltage

        let ball = SpatialTrackControl(
            name: "Magnetic field",
            center: SIMD3<Float>(FieldInstrumentLayout.fieldTrackAnchor),
            normal: SIMD3<Float>(FieldInstrumentLayout.fieldTrackNormal),
            accent: DesignTokens.Palette.probeNegativeUI,
            range: FieldModel.magneticFieldRange,
            read: { model.magneticFieldTesla },
            write: { model.magneticFieldTesla = $0 },
            format: { String(format: "%.0f kT", $0 / 1000) })
        renderer.viewRoot.addChild(ball.root)
        self.ballFieldTrack = ball

        let electron = SpatialTrackControl(
            name: "Magnetic field",
            center: SIMD3<Float>(FieldInstrumentLayout.fieldTrackAnchor),
            normal: SIMD3<Float>(FieldInstrumentLayout.fieldTrackNormal),
            accent: DesignTokens.Palette.probeNegativeUI,
            range: FieldModel.electronFieldRange,
            read: { model.electronFieldTesla },
            write: { model.electronFieldTesla = $0 },
            format: { String(format: "%.2f mT", $0 * 1000) })
        renderer.viewRoot.addChild(electron.root)
        self.electronFieldTrack = electron
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
        bank?.update(anchor: SIMD3<Float>(FieldInstrumentLayout.bankAnchor),
                     viewer: headInRoot, dt: dt)
        particles.update(anchor: SIMD3<Float>(FieldInstrumentLayout.particlePickerAnchor),
                         viewer: headInRoot, dt: dt)
        verbs?.update(anchor: SIMD3<Float>(FieldInstrumentLayout.clearPlateAnchor),
                      viewer: headInRoot, dt: dt)
        wells?.update(dt: dt)

        // Each rail exists exactly when its apparatus does.
        voltageTrack?.isEnabled = model.capacitorOn
        ballFieldTrack?.isEnabled = model.magneticFieldOn && !model.electronMode
        electronFieldTrack?.isEnabled = model.magneticFieldOn && model.electronMode

        if model.capacitorOn, let voltage = voltageTrack {
            voltage.root.position = SIMD3<Float>(
                FieldInstrumentLayout.voltageTrackCenter(
                    capacitorCenter: model.capacitorCenter))
            voltage.refresh()
        }
        // `refresh()` is the caller's job — the control ticks nothing of
        // its own. Without these the beads would show the last value a
        // hand dragged them to and ignore a reset or a launch argument.
        if ballFieldTrack?.isEnabled == true { ballFieldTrack?.refresh() }
        if electronFieldTrack?.isEnabled == true { electronFieldTrack?.refresh() }
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
        case .probe(let electron) where electron != model.electronMode:
            // Same object, different particle — retarget rather than fold,
            // so the grip can appear or vanish with it.
            ring.target = .probe(electron: model.electronMode)
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
                          tint: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)) {
                        model.removeCharge(id: id)
                    },
                ],
                grip: .init(
                    name: "Strength",
                    range: FieldModel.magnitudeRange,
                    read: { model.magnitudeMicroCoulombs(id: id) },
                    write: { model.setMagnitude(id: id, microCoulombs: $0) },
                    format: { String(format: "%.1f \u{00B5}C", $0) },
                    // Rides the charge's own surface, so the handle moves
                    // outward as the charge grows.
                    radius: { renderer.displayRadius(forChargeID: id) + 0.02 }))
            bloom.update(anchor: SIMD3<Float>(charge.position),
                         viewer: viewer, revealTarget: 1, dt: dt)

        case .probe(let electron):
            guard let probe = model.probe else { return }
            bloom.retarget(
                ring.target,
                petals: [
                    .init(name: "Delete", symbol: "trash",
                          tint: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)) {
                        model.removeProbe()
                    },
                ],
                // No grip in electron mode. An electron's charge is e —
                // a constant of nature, not a setting — and offering a
                // bead to change it would be the app telling a lie about
                // the physics it is otherwise exact about.
                grip: electron ? nil : .init(
                    name: "Charge",
                    range: FieldModel.probeChargeRange,
                    read: { model.probeChargeMagnitude },
                    write: { model.setProbeMagnitude($0) },
                    format: { String(format: "%.0f nC", $0 * 1e9) },
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
            .onEnded { value in
                if bloom.handleTap(value.entity) { return }
                if bank?.handleTap(value.entity) == true { return }
                if verbs?.handleTap(value.entity) == true { return }
                if particles.handleTap(value.entity) { return }

                for name in Self.ancestorNames(of: value.entity) {
                    if name == FieldRenderer.probeEntityName, model.probe != nil {
                        toggleRing(.probe(electron: model.electronMode),
                                   on: value.entity)
                        return
                    }
                    if let id = UUID(uuidString: name),
                       model.charges.contains(where: { $0.id == id }) {
                        model.select(id: id)
                        toggleRing(.charge(id), on: value.entity)
                        return
                    }
                }
                ring.target = nil
            }
    }

    private func toggleRing(_ target: FieldRingState.Target, on entity: Entity) {
        if ring.target == target {
            ring.target = nil
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
                if gaussRimDrag {
                    adjustGaussSurface(hand: hand)
                    return
                }

                // B — beginnings.
                if drag == nil {
                    if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                    for track in [voltageTrack, ballFieldTrack, electronFieldTrack] {
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
                gaussRimDrag = false
                drag = nil
                flick.reset()
                model.heldChargeID = nil
                // A charge pulled from a well is exempt from the station
                // walls until it gets inside them; letting go spends the
                // exemption either way. See `FieldModel.addCharge`.
                model.endEscort()
            }
    }

    /// The flux meter's own gesture: the surface passes through the
    /// fingertip, and a disc turns so the fingertip is on its rim.
    private func adjustGaussSurface(hand: SIMD3<Double>) {
        let center = model.gaussSurfaceCenter
        if model.gaussSurfaceKind == .disc {
            model.setGaussNormal(GaussGrab.normal(forHand: hand, center: center,
                                                  normal: model.gaussSurfaceNormal))
        }
        model.setGaussRadius(GaussGrab.radius(
            forHand: hand, center: center, range: FieldModel.gaussRadiusRange))
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
            if name == FieldRenderer.probeEntityName {
                let target = model.probe?.position ?? hand
                model.holdProbe(at: target)
                return RelativeDrag(name: name, target: target, hand: hand)
            }
            if name == "gauss-surface" {
                // THE SURFACE IS A CONTAINER; THE THING INSIDE IT IS THE
                // SUBJECT. This check used to come first and win outright,
                // so a 55 cm bubble beat everything within it — and only
                // the 12 cm proximity fallback below rescued a charge
                // inside one, by accident. Now the accident is a rule.
                switch GaussGrab.classify(hand: hand, center: model.gaussSurfaceCenter,
                                          radius: model.gaussSurfaceRadius) {
                case .skin:
                    gaussRimDrag = true
                    adjustGaussSurface(hand: hand)
                    return nil
                case .inside:
                    break        // fall through to whatever is in there
                case .miss:
                    return RelativeDrag(name: name, target: model.gaussSurfaceCenter,
                                        hand: hand)
                }
            }
        }
        if let id = Self.resolveCharge(
                names: names, hand: hand,
                charges: model.charges.map { ($0.id, $0.position) }),
           let charge = model.charges.first(where: { $0.id == id }) {
            model.select(id: id)
            return RelativeDrag(name: id.uuidString, target: charge.position, hand: hand)
        }
        // Inside the bubble with nothing in reach: move the bubble.
        if names.contains("gauss-surface") {
            return RelativeDrag(name: "gauss-surface",
                                target: model.gaussSurfaceCenter, hand: hand)
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
                ring.target = .probe(electron: model.electronMode)
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
}
