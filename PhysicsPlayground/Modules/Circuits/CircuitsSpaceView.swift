//
//  CircuitsSpaceView.swift
//  Physics Playground — Circuits module
//
//  The circuit lab immersive scene. Component bodies are carried by a
//  `RelativeDrag`; the model owns where they end up. Terminals, wires
//  and switch levers are tap targets. Solver clock is SceneEvents.Update.
//

import PhysicsCore
import QuartzCore
import SwiftUI
import RealityKit
import RenderKit

/// Which lead or joint has its Cut ring open. A reference type, as
/// `RingState` is: the tap and the render loop must share one live value.
@MainActor
final class LeadRingState {
    var target: CircuitsSpaceView.LeadRing?
}

struct CircuitsSpaceView: View {
    @Environment(CircuitsModel.self) private var model
    @State private var renderer: CircuitsRenderer?
    @State private var bloom = Bloom()
    /// The AC source's frequency rail, present exactly while an AC source
    /// is selected. Parented to the renderer's `root`, not the zoomed
    /// bench, so it never grows out of reach.
    @State private var frequencyTrack: SpatialTrackControl?
    /// A rail mid-adjust swallows every `onChanged` until its `onEnded`,
    /// so a drag that starts on the rail cannot wander onto a part.
    @State private var activeTrack: SpatialTrackControl?
    /// Which component's ring is open — shared by the tap gesture and
    /// the render loop (see RingState's header).
    @State private var ring = RingState()
    /// The lead or joint whose Cut ring is open, if any. Never open with
    /// `ring` — one bloom serves both.
    @State private var leadRing = LeadRingState()
    /// The view's single `DragGesture(minimumDistance: 0)` runs on every
    /// tap, so a latch promotes to a pull only past `PressLatch.tapTravel`.
    @State private var leadPress = PressLatch<CircuitsModel.Terminal>()
    /// A part in each hand (2026-11-02): the drag is one recogniser and never
    /// hears the second hand, so parts on the bench are carried per pinch
    /// (`handleHands`). Leads, wires, the shelf, the stage and the meter stay
    /// the drag's.
    @State private var hands = HandGrabs<UUID>()
    @State private var holds = PartHolds()
    /// Kept for `handleHands`: a raw spatial event has no `value.convert`.
    @State private var sceneContent: RealityViewContent?
    /// A wire under a finger, and where it was pressed: which end lifts is
    /// decided once the hand has moved (`CircuitsModel.endToLift`).
    @State private var wirePress = PressLatch<CircuitsModel.WirePress>()
    /// A switch lever under a finger. Never promotes to a drag: it survives
    /// 12 mm of drift and toggles on `settle()` at gesture end. The
    /// TapGesture only selects, or a clean tap would toggle twice.
    @State private var leverPress = PressLatch<UUID>()
    /// A press on a shelf slot: it becomes a pull once the hand travels, so a
    /// tap on the shelf never spawns a part.
    @State private var sourcePress = PressLatch<Int>()
    /// A press on the stage — its rim turns the circuit, its deck's band
    /// carries it — and, once it travels, the hold it became.
    @State private var stagePress = PressLatch<StageHold>()
    @State private var stageDrag: StageHold?
    @State private var partDrag: RelativeDrag?
    /// The part a pull off the shelf just made, so the drag that made it
    /// keeps moving it.
    @State private var spawnedPartID: UUID?
    /// The parts shelf; geometry in `CircuitsPartsLayout`.
    @State private var palette: Well?
    /// Whether the shelf has coasted into place — once, on the lab's
    /// first frame on screen.
    @State private var shelfArrived = false

    /// Which probe a hand is carrying, if either.
    @State private var probeDrag: CircuitsModel.ProbeSlot?
    /// Carrying the meter itself: where its case was when the hand closed
    /// on it, and where the hand was, both in the renderer's frame.
    @State private var meterDrag: (start: SIMD3<Float>, hand: SIMD3<Float>)?
    @Environment(AppModel.self) private var appModel
    /// Two-handed zoom on the bench: into the copper is a pinch-and-spread.
    @State private var scaleRig = SpatialScaleRig(
        pivot: CircuitsRenderer.benchPivot, range: 0.6...8.0, allowsTurn: false)
    /// The bench's meter — a tool, not a layer. See `Multimeter`.
    @State private var meter: Multimeter?
    /// Identifies the floating readout above the selected part.
    private static let readoutCardID = "circuit-readout"

    /// Where the meter starts (right flank); it moves with the hand after.
    private static let meterAnchor = CircuitsRenderer.benchPivot
        + SIMD3<Float>(0.62, -0.03, 0.16)
    var body: some View {
        RealityView { content, attachments in
            let renderer = CircuitsRenderer()
            renderer.onTap = { handleTap(on: $0) }
            renderer.onTerminalAction = { model.voiceOverWire($0) }
            renderer.onLeverAction = { model.toggleSwitch(id: $0) }
            renderer.onWireAction = { model.voiceOverRemoveWire(id: $0) }
            renderer.onStageAction = { model.spinCircuit(by: .pi / 4) }
            content.add(renderer.root)
            sceneContent = content
            // Disabled here and raised by `Fade.tick`, so the apparatus arrives
            // rather than appears.
            renderer.root.isEnabled = false

            // What the selected part is doing, on the part.
            if let card = attachments.entity(for: Self.readoutCardID) {
                stripInput(from: card)
                renderer.selectedAnchor.addChild(card)
            }
            renderer.viewRoot.addChild(bloom.root)

            // The views of the current, Clear and the five authored circuits
            // live in the title bar's More (`CircuitsModule.more`): the room
            // holds the bench, the shelf and the meter.

            // Under `root`, not `viewRoot`: an instrument that grew with the
            // bench would leave reach exactly when you zoomed in to use it.
            let multimeter = Multimeter(
                accent: UIColor(DesignTokens.Palette.circuitsAccent),
                anchor: Self.meterAnchor)
            renderer.root.addChild(multimeter.root)
            multimeter.onTap = { [weak multimeter] entity in
                multimeter?.activate(entity, model: model)
            }
            multimeter.benchToRoom = { [weak renderer] point in
                renderer?.worldPosition(ofBenchPoint: point) ?? SIMD3<Float>(point)
            }
            self.meter = multimeter

            // The parts in one column: `CircuitsPartsLayout` says which and in
            // what order (sources and interrupters, then loads).
            let partSpecs: [Well.Spec] = CircuitsPartsLayout.Flank.allCases
                .flatMap { CircuitsPartsLayout.kinds(on: $0) }
                .enumerated()
                .map { index, kind in
                    Well.Spec(
                        name: kind.rawValue,
                        tint: UIColor(DesignTokens.Palette.circuitsAccent),
                        label: kind.displayName,
                        preview: { CircuitsRenderer.partPreview(for: kind) },
                        position: CircuitsPartsLayout.rightSlot(index: index),
                        spawn: { model.add(kind, at: $0) })
                }
            // The meter is the last slot. `handOver`, not `spawn`: there is
            // exactly one multimeter.
            let meterSlot = Well.Spec(
                name: "multimeter",
                tint: UIColor(DesignTokens.Palette.circuitsAccent),
                label: "Multimeter",
                preview: { Multimeter.miniature() },
                position: CircuitsPartsLayout.rightSlot(index: partSpecs.count),
                spawn: { _ in nil },
                // Captures the instrument, not the view (a View is a struct).
                handOver: { [weak multimeter] hand in
                    // Out of the rack, into the hand, and made visible.
                    multimeter?.place(at: SIMD3<Float>(hand))
                    multimeter?.root.isEnabled = true
                })

            // Hidden until pulled: the slot shows a miniature, and two meters in
            // the room would be one too many.
            multimeter.root.isEnabled = false

            let parts = Well(partSpecs + [meterSlot])
            // A shelf, not a wall: six slots in the window, the rest a
            // drag away. Faced at a standing viewer so the pane and the
            // parts on it read square from where you stand.
            parts.facing = CircuitsPartsLayout.viewer
            parts.windowTitle = "Parts"
            parts.visibleCount = CircuitsPartsLayout.rightVisibleRows
            // A part is born in the bench's frame, as a hand is converted into it.
            parts.spawnSpace = renderer.viewRoot
            renderer.root.addChild(parts.root)
            self.palette = parts

            // The lab shows once its scene has taken in the build (`Settle`):
            // it starts hidden and fades up then, rather than popping in and
            // stuttering through the long first frames after a mount.
            renderer.root.components.set(OpacityComponent(opacity: Settle.hiddenOpacity))
            var settle = Settle()
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's arrival and departure, on the shell's one flag.
                    // `Fade.tick` settles to a no-op once landed.
                    if let renderer {
                        appModel.doorTick(renderer.root, lab: CircuitsModule.id,
                                          settled: settle.tick(dt: event.deltaTime))
                    }
                    // The lab's placement in the room: a constant display offset, safe
                    // because grabs move a body by hand displacement. Every instrument is
                    // a child of `renderer.root`, so it rides along.
                    if let placement = appModel.placement(forLab: CircuitsModule.id) {
                        renderer?.root.position = placement
                    }
                    model.step(dt: event.deltaTime)
                    let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
                    meter?.update(viewer: viewer, model: model,
                                  resetNonce: appModel.resetNonce)
                    // Idle breath, recoil on giving up a part, and a
                    // refusal fade at the component budget.
                    palette?.update(
                        dt: event.deltaTime,
                        nearestHand: appModel.room.nearestFingertip(
                            to: CircuitsPartsLayout.rightSlot(index: 0)))
                    // The column arrives coasting, the crown rolling with it,
                    // once the lab is on screen to be seen doing it.
                    if !shelfArrived, renderer?.root.isEnabled == true {
                        shelfArrived = true
                        palette?.arrive()
                    }
                    // Ticked every frame, not via observation: a steady DC circuit mutates
                    // nothing, but its electrons must keep drifting.
                    renderer?.handZoom = scaleRig.liveScale
                    renderer?.tick(dt: event.deltaTime, model: model)
                    if let renderer {
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                        syncFrequencyRail(renderer: renderer)
                    }
                }
            )
            #if DEBUG
            if UserDefaults.standard.double(forKey: "trueSpeed") > 0 {
                model.trueSpeedMode = true
            }
            // `-skyline 1` raises the voltage towers (a More toggle, needs a hand).
            if UserDefaults.standard.bool(forKey: "skyline") {
                model.showVoltageHeights = true
            }
            let forcedScale = UserDefaults.standard.double(forKey: "viewScale")
            if forcedScale > 0 {
                scaleRig.updateMagnification(Float(forcedScale))
                scaleRig.endGesture()
            }
            #endif

            #if DEBUG
            // `-circRing 1` opens the selected part's control ring at launch
            // (the one `-circHeat`, `-circLED` and the like select), or the
            // first part's, for CLI screenshots.
            if UserDefaults.standard.bool(forKey: "circRing"),
               let part = model.selectedComponent ?? model.components.first {
                model.select(id: part.id)
                ring.openID = part.id
            }
            // `-circSameNet 1` holds the refusal on screen: a lead pulled
            // onto a terminal already on its own net (recoils red, no wire).
            if UserDefaults.standard.bool(forKey: "circSameNet") {
                model.clearBench()
                let anchor = CircuitsModel.buildCenter
                if let battery = model.add(.battery, at: anchor),
                   let bulb = model.add(.bulb, at: anchor + SIMD3(0.3, 0, 0)) {
                    model.connectTerminals(.init(componentID: battery, end: 1),
                                           .init(componentID: bulb, end: 0))
                    // Now pull from the battery's + lead onto the
                    // bulb's — already one net through that wire.
                    let source = CircuitsModel.Terminal(componentID: battery, end: 1)
                    let target = model.components
                        .first { $0.id == bulb }!.terminalPosition(0)
                    model.beginLeadPull(from: source, hand: target)
                }
            }
            // `-circAlign 1` drops two parts a few centimetres apart and fires the
            // release on the second, so the snapped chain is what the screenshot
            // holds. `-circSnapAt <s>` stages the same drop and holds the bulb's
            // glide onto its seat that many seconds in (0 … 0.12): a part mid-snap.
            let snapAt = UserDefaults.standard.double(forKey: "circSnapAt")
            if UserDefaults.standard.bool(forKey: "circAlign") || snapAt > 0 {
                model.clearBench()
                let anchor = CircuitsModel.buildCenter
                model.add(.battery, at: anchor)
                if let battery = model.components.first {
                    // Inside `leadReach` (0.06): 3 cm along + 2 cm up, crooked enough to
                    // exercise the rotation.
                    let landing = battery.terminalPosition(1)
                        + SIMD3(0.03 + CircuitsModel.terminalOffset, 0.02, 0)
                    if let bulb = model.add(.bulb, at: landing),
                       let before = model.components.first(where: { $0.id == bulb }) {
                        model.release(id: bulb)
                        if snapAt > 0 {
                            renderer.pinnedLandingTime = snapAt
                            renderer.easeLanding(id: bulb, from: before.position, axis: before.axis)
                        }
                    }
                }
            }
            // `-circPreset series|parallel|divider|rcCharger|shortCircuit`
            // loads one of the authored circuits.
            if let name = UserDefaults.standard.string(forKey: "circPreset"),
               let preset = CircuitsModel.Preset(rawValue: name) {
                model.loadPreset(preset)
            }
            // `-circStageShift <dx>,<dy>,<dz>` carries the whole circuit and its
            // turntable — set back, the simulator's camera can see down onto it.
            if let spec = UserDefaults.standard.string(forKey: "circStageShift") {
                let values = spec.split(separator: ",").compactMap { Double($0) }
                if values.count == 3 {
                    model.moveCircuit(by: SIMD3(values[0], values[1], values[2]))
                }
            }
            // `-circStageYaw <degrees>` turns the circuit on its stage, and
            // `-circStageCoast <degrees/s>` sets it coasting, as a let-go
            // flick of the rim would.
            let stageYaw = UserDefaults.standard.double(forKey: "circStageYaw")
            if stageYaw != 0 { model.spinCircuit(by: stageYaw * .pi / 180) }
            let stageCoast = UserDefaults.standard.double(forKey: "circStageCoast")
            if stageCoast != 0 { model.setStageCoast(rate: stageCoast * .pi / 180) }

            // The index-naming arguments below must run after the bench-shaping
            // ones: `-circPreset` starts with `clearBench`.
            // `-circLead <componentIndex>,<end>` pulls a lead out toward open air.
            if let spec = UserDefaults.standard.string(forKey: "circLead") {
                let parts = spec.split(separator: ",")
                if let index = parts.first.flatMap({ Int($0) }),
                   index < model.components.count {
                    let end = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
                    let source = CircuitsModel.Terminal(
                        componentID: model.components[index].id, end: end)
                    let from = model.components[index].terminalPosition(end)
                    model.beginLeadPull(from: source, hand: from + SIMD3(0.18, 0.16, 0.05))
                }
            }
            // `-circHighlight <componentIndex>,<end>` lights that
            // terminal's whole net.
            if let spec = UserDefaults.standard.string(forKey: "circHighlight") {
                let parts = spec.split(separator: ",")
                if let index = parts.first.flatMap({ Int($0) }),
                   index < model.components.count {
                    let end = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
                    model.highlightNet(containing: .init(
                        componentID: model.components[index].id, end: end))
                }
            }
            // `-circLeadRing <componentIndex>,<end>` opens that lead's Cut ring,
            // as a tap on its dot would.
            if let spec = UserDefaults.standard.string(forKey: "circLeadRing") {
                let parts = spec.split(separator: ",")
                if let index = parts.first.flatMap({ Int($0) }),
                   index < model.components.count {
                    let end = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
                    let terminal = CircuitsModel.Terminal(
                        componentID: model.components[index].id, end: end)
                    model.select(id: terminal.componentID)
                    model.highlightNet(containing: terminal)
                    leadRing.target = Self.leadRing(for: .lead(terminal), on: model)
                }
            }
            // `-circUnplug <wireIndex>,<end>` lifts that wire end into the
            // air and holds it there, the circuit dark.
            if let spec = UserDefaults.standard.string(forKey: "circUnplug") {
                let parts = spec.split(separator: ",")
                if let index = parts.first.flatMap({ Int($0) }),
                   index < model.wires.count {
                    let end = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
                    let wire = model.wires[index]
                    let lifted = end == 0 ? wire.from : wire.to
                    if let component = model.components
                        .first(where: { $0.id == lifted.componentID }) {
                        model.beginRewire(
                            wire: wire.id, grabbing: end,
                            hand: component.terminalPosition(lifted.end)
                                + SIMD3(0.05, 0.22, 0.04))
                    }
                }
            }
            // `-circScroll <n>` scrolls the parts rack n slots.
            let scroll = UserDefaults.standard.integer(forKey: "circScroll")
            if scroll != 0 { parts.scroll(by: scroll) }

            // `-circField 1` switches on the bench's own magnetic field.
            if UserDefaults.standard.bool(forKey: "circField") {
                model.showMagneticField = true
            }
            #endif
            self.renderer = renderer
        } attachments: {
            Attachment(id: Self.readoutCardID) {
                CircuitsSelectedReadout()
                    // Never intercept a pinch: this floats above a part whose body and
                    // terminals are grab targets.
                    .allowsHitTesting(false)
                    .environment(model)
            }
        }
        // An in-flight grab never gets its `onEnded` when the space closes;
        // clear it here or it re-targets every later drag.
        .onDisappear {
            renderer?.teardown()
            // `Bloom` is a class: a live grip would outlive the view.
            bloom.endGrip()
            activeTrack = nil
            // Set down where they are, not merely forgotten: the model outlives
            // this view.
            hands.releaseAll { session in
                if holds.byPart.removeValue(forKey: session.target)?.drag != nil {
                    model.release(id: session.target)
                    renderer?.previewComponentIDs.remove(session.target)
                    renderer?.flashRelease(id: session.target)
                }
            }
        }
        .simultaneousGesture(
            SpatialEventGesture()
                .onChanged { handleHands($0) }
                .onEnded { handleHands($0) }
        )
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // Instruments first, then the bench's own tap grammar.
                    // Meter before `handleTap(on:)`: its dial stands among the terminals
                    // and must not count as probing what is behind it.
                    if meter?.handleTap(value.entity, model: model) == true { return }
                    if bloom.handleTap(value.entity) { return }
                    // The shelf's crown swallows a tap, so a miss at a part
                    // does not fold the ring behind it.
                    if palette?.handleTap(value.entity) == true { return }
                    handleTap(on: value.entity)
                }
        )
        // One drag gesture, four grabs, all relative: a terminal pulls a wire,
        // a lead aims its part, a shelf slot hands you a new part, a body
        // carries the part.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    // Into the bench's frame: converting through viewRoot inverts zoom and
                    // placement, so a part tracks the hand 1:1 at any zoom.
                    let handF = renderer.viewRoot.convert(
                        position: SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene)),
                        from: nil)
                    let hand = SIMD3<Double>(handF)

                    // The frequency rail is in room coordinates (it hangs off `root`), and
                    // a gesture already in it is not re-claimed by anything under it.
                    let world = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    // The shelf hangs off `root` too, outside the zoom: its crown
                    // must ride the hand at any magnification.
                    let roomHand = renderer.root.convert(
                        position: SIMD3<Float>(world), from: nil)
                    if let track = activeTrack {
                        guard track.isEnabled else {
                            activeTrack = nil
                            return
                        }
                        track.adjust(hand: world)
                        return
                    }
                    if partDrag == nil, model.leadPull == nil, probeDrag == nil,
                       let track = frequencyTrack, track.isEnabled, track.owns(value.entity) {
                        activeTrack = track
                        track.adjust(hand: world)
                        return
                    }

                    // Probes first: a probe carried across a terminal must
                    // not also start dragging that terminal's wire.
                    if probeDrag == nil, let meter,
                       let slot = meter.probeSlot(for: value.entity) {
                        probeDrag = slot
                        if let probe = meter.probe(slot) { Grasp.take(probe) }
                    }
                    if let slot = probeDrag, let meter {
                        let world = SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene))
                        meter.moveProbe(
                            slot,
                            local: meter.root.convert(position: world, from: nil),
                            bench: hand, model: model)
                        return
                    }

                    // Meter next, in the renderer's frame: it hangs off `root`, so the
                    // zoom cannot carry it out of reach.
                    if let meter {
                        let world = SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene))
                        let local = renderer.root.convert(position: world, from: nil)
                        if meterDrag == nil, meter.isBody(value.entity) {
                            meterDrag = (meter.anchor, local)
                            Grasp.take(meter.caseEntity)
                        }
                        if let drag = meterDrag {
                            meter.place(at: drag.start + (local - drag.hand))
                            return
                        }
                    }

                    if bloom.updateGrip(hand: handF) { return }
                    if model.leadPull == nil, partDrag == nil, stageDrag == nil,
                       !leadPress.isPending,
                       !wirePress.isPending, !leverPress.isPending,
                       !sourcePress.isPending, !stagePress.isPending {
                        if bloom.beginGrip(value.entity, hand: handF) { return }
                        beginCircuitDrag(entity: value.entity, hand: hand,
                                         roomHand: roomHand, renderer: renderer)
                    }
                    // A pressed lead becomes a pull only once the hand
                    // has moved; until then it is still a tap.
                    if let source = leadPress.promote(hand: hand) {
                        model.beginLeadPull(from: source, hand: hand)
                    }
                    // A joint pulled at strains toward the hand until the
                    // press gives: drawn only, the model's joint is whole.
                    if let press = wirePress.pendingPayload, let travel = wirePress.travel(to: hand) {
                        renderer.jointStrain = (press.wire, SIMD3<Float>(travel))
                    } else {
                        renderer.jointStrain = nil
                    }
                    if let grabbed = wirePress.promote(hand: hand),
                       let end = model.endToLift(of: grabbed.wire,
                                                 pressedAt: grabbed.pressedAt, hand: hand) {
                        model.beginRewire(wire: grabbed.wire, grabbing: end, hand: hand)
                    }
                    // A lever press that travels is a drag to nowhere: consume and discard
                    // it.
                    _ = leverPress.promote(hand: hand)
                    // A stage press that travels takes hold: the rim turns the
                    // circuit about the stage's axis, the deck's band carries it.
                    // Not while a hand carries a part: the stage moves the parts under it.
                    if let hold = stagePress.promote(hand: hand), !holds.isCarrying {
                        let took = hold == .rim
                            ? model.beginSpin(hand: hand, at: CACurrentMediaTime())
                            : model.beginStageCarry(hand: hand)
                        if took { stageDrag = hold }
                    }
                    // A slot press that travels is the pull: the part is born at the
                    // hand and carried from this frame.
                    if let index = sourcePress.promote(hand: hand),
                       let palette, let source = palette.source(at: index),
                       let id = palette.pull(source, at: hand) {
                        spawnedPartID = id
                        partDrag = RelativeDrag(name: id.uuidString, target: hand, hand: hand)
                        renderer.previewComponentIDs.insert(id)
                        // Carried like any part from its first frame: the glow, the
                        // lift and the lean. The shelf's pop is its grab sound.
                        renderer.flashPickup(id: id, tick: false)
                    }
                    switch Self.carryDispatch(
                        leadPullActive: model.leadPull != nil,
                        partDragActive: partDrag != nil,
                        stageHeld: stageDrag != nil,
                        rackDragging: palette?.isDragging == true
                    ) {
                    case .leadPull:
                        model.updateLeadPull(hand: hand)
                    case .carry:
                        // A live carry outranks the shelf: its gesture stays "dragging" after
                        // the one-shot pull, and the part it spawned must follow the hand from
                        // its first frame.
                        if let partDrag { applyCircuitDrag(partDrag, hand: hand) }
                    case .stage:
                        if stageDrag == .rim {
                            model.updateSpin(hand: hand, at: CACurrentMediaTime())
                        } else {
                            model.updateStageCarry(hand: hand)
                        }
                    case .rack:
                        // The crown rides the hand; nothing spawns from it.
                        palette?.updateDrag(hand: roomHand)
                    case .idle:
                        break
                    }
                }
                .onEnded { value in
                    if let track = activeTrack {
                        track.endAdjust()
                        activeTrack = nil
                        return
                    }
                    if let slot = probeDrag, let probe = meter?.probe(slot) { Grasp.letGo(probe) }
                    if meterDrag != nil, let meter { Grasp.letGo(meter.caseEntity) }
                    probeDrag = nil
                    meterDrag = nil
                    palette?.endDrag()
                    bloom.endGrip()
                    // A lever press that never travelled was a flick with up to 12 mm of
                    // drift. The TapGesture only selects, so this is the one physical path
                    // that toggles.
                    if let id = leverPress.settle() {
                        model.toggleSwitch(id: id)
                    }
                    switch stageDrag {
                    case .rim: model.endSpin(coasts: !Motion.isReduced, at: CACurrentMediaTime())
                    case .deck: model.endStageCarry()
                    case nil: break
                    }
                    defer {
                        stagePress.cancel()
                        stageDrag = nil
                        // Only this drag's own part: a hand may be carrying another.
                        if let id = spawnedPartID ?? partDrag.flatMap({ UUID(uuidString: $0.name) }) {
                            renderer?.previewComponentIDs.remove(id)
                        }
                        renderer?.jointStrain = nil
                        leadPress.cancel()
                        wirePress.cancel()
                        leverPress.cancel()
                        sourcePress.cancel()
                        partDrag = nil
                        spawnedPartID = nil
                    }
                    guard let renderer else { return }
                    // Into the bench's frame, as in `onChanged`.
                    let handF = renderer.viewRoot.convert(
                        position: SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene)),
                        from: nil)
                    let hand = SIMD3<Double>(handF)
                    // A lead in flight lands, refuses, or springs back. A
                    // lead that never promoted was a tap, and taps don't wire.
                    if model.leadPull != nil {
                        model.updateLeadPull(hand: hand)
                        model.endLeadPull()
                        return
                    }
                    guard let partDrag else { return }
                    applyCircuitDrag(partDrag, hand: hand)
                    if let id = spawnedPartID ?? UUID(uuidString: partDrag.name) {
                        // A part snapped onto a neighbour glides the last few
                        // centimetres rather than jumping there.
                        let before = model.components.first { $0.id == id }
                        model.release(id: id)
                        if let before {
                            renderer.easeLanding(id: id, from: before.position, axis: before.axis)
                        }
                        renderer.flashRelease(id: id)
                    }
                }
        )
        .spatialScale(scaleRig)
    }

    /// The frequency rail exists exactly while an AC source is selected,
    /// hung 0.14 m under it through the zoom rig without scaling with it.
    /// Built on first need as a child of the renderer's root.
    private func syncFrequencyRail(renderer: CircuitsRenderer) {
        let source = model.selectedComponent.flatMap { $0.kind == .acSource ? $0 : nil }
        if frequencyTrack == nil, source != nil {
            let track = SpatialTrackControl(
                name: "Frequency",
                center: .zero,
                normal: SIMD3(0, 0, 1),
                accent: UIColor(DesignTokens.Palette.circuitsAccent),
                range: CircuitsModel.acFrequencyRange,
                read: { model.selectedComponent?.acFrequency ?? CircuitsModel.acFrequency },
                write: { hertz in
                    if let id = model.selectedComponent?.id {
                        model.setACFrequency(id: id, hertz)
                    }
                },
                format: { PhysicsFormat.measurement(($0 * 10).rounded() / 10, "Hz", decimals: 1) })
            renderer.root.addChild(track.root)
            frequencyTrack = track
        }
        guard let track = frequencyTrack else { return }
        track.isEnabled = source != nil
        if let source {
            track.root.position = renderer.worldPosition(
                ofBenchPoint: source.position + SIMD3(0, -0.14, 0))
            track.refresh()
        }
    }

    private func syncBloom(renderer: CircuitsRenderer, dt: Double) {
        if let openID = ring.openID,
           !model.components.contains(where: { $0.id == openID }) {
            ring.openID = nil     // deleted out from under the ring
        }
        // The ring, the lit outline and the readout name one part: a selection that
        // moves to another part (a tap on its lead or lever, a carry, a new
        // part from the shelf) folds the ring rather than leave it on the old.
        if let openID = ring.openID, model.selectedID != openID {
            ring.openID = nil
        }
        renderer.ringPartID = ring.openID
        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        if let lead = leadRing.target,
           ring.openID != nil || model.leadPull != nil || !Self.isLive(lead, on: model)
            || model.selectedID != Self.partID(of: lead, on: model) {
            // Cut, unwired, a lead in the hand, or the selection moved on.
            leadRing.target = nil
        }
        if let lead = leadRing.target,
           let anchor = Self.anchor(of: lead, on: model, renderer: renderer) {
            bloom.retarget(lead, petals: [Self.cutPetal(for: lead, on: model)],
                           grip: nil, lift: Bloom.leadRingLift)
            bloom.update(anchor: anchor, viewer: viewer, revealTarget: 1, dt: dt)
            return
        }
        guard let uuid = ring.openID,
              let part = model.components.first(where: { $0.id == uuid }) else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }

        // A switch is opened and closed by its lever; the ring does not
        // offer the same act twice.
        var petals: [Bloom.Petal] = []
        if part.failed {
            // A blown bulb's most-wanted action, finally reachable.
            petals.append(.init(name: "Replace", symbol: "arrow.triangle.2.circlepath",
                                tint: UIColor(red: 0.95, green: 0.60, blue: 0.15, alpha: 1)) {
                model.replaceFailed(id: uuid)
            })
        } else if model.isWired(id: uuid) {
            petals.append(.init(name: "Detach", symbol: "scissors",
                                tint: DesignTokens.Palette.neutralActionUI) {
                model.detachComponent(id: uuid)
            })
        }
        petals.append(.init(name: "Delete", symbol: "trash",
                            tint: DesignTokens.Palette.destructiveUI) {
            model.removeComponent(id: uuid)
        })

        let range = CircuitsModel.valueRange(for: part.kind)
        bloom.retarget(
            uuid,
            petals: petals,
            grip: range.upperBound > range.lowerBound
                ? .init(name: "Value",
                        range: range,
                        read: { model.componentValue(id: uuid) },
                        write: { model.setComponentValue(id: uuid, $0) },
                        format: { CircuitsModel.formatValue($0, for: part.kind) },
                        radius: { 0.05 },
                        track: Self.valueTrack(for: part.kind) { [weak renderer] toward in
                            renderer?.targetReachBelow(of: uuid, towardViewer: toward) ?? 0
                        })
                : nil)

        bloom.update(anchor: SIMD3<Float>(part.position),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }

    /// A part's calm track (2026-11-02): logarithmic, clicking at the values
    /// parts are sold in (`CircuitsModel.valueDetents`), numbered at each
    /// decade, and run under the part, clear of its leads. It replaced a
    /// linear 14 cm handle that put a resistor's 10–470 Ω in its first
    /// 1.3 cm. Given `clearsBelow` — the part's own targets' reach as the
    /// wearer sees them — it hangs `trackGap` below that rather than a fixed
    /// drop under the centre, where the part's carry box covered the rail's
    /// first few centimetres and took the pinch (2026-11-02).
    static func valueTrack(for kind: CircuitsModel.ComponentKind,
                           clearsBelow: ((SIMD3<Float>) -> Float)? = nil) -> Bloom.Grip.Track {
        Bloom.Grip.Track(
            detents: CircuitsModel.valueDetents(for: kind).map {
                .init(value: $0, label: tickLabel($0, for: kind))
            },
            drop: clearsBelow == nil ? Bloom.calmTrackDrop : trackGap,
            clearsBelow: clearsBelow)
    }

    /// How far under a part's own targets its value track hangs, at one
    /// metre: the bead's pinch target and a few millimetres of air.
    static let trackGap: Float = 0.03

    /// A tick's number, where it carries one: every cell size a battery
    /// stacks to but 4.5 V (too near its neighbours to read), and elsewhere
    /// each decade and the top of the series, with its SI prefix.
    static func tickLabel(_ value: Double, for kind: CircuitsModel.ComponentKind) -> String? {
        switch kind {
        case .battery, .acSource:
            return value == 4.5 ? nil : PhysicsFormat.compact(value)
        case .led, .switcher:
            return nil
        default:
            let detents = CircuitsModel.valueDetents(for: kind)
            let exponent = log10(value)
            guard abs(exponent - exponent.rounded()) < 1e-9 || value == detents.last
            else { return nil }
            switch value {
            case ..<1e-3 where kind == .capacitor: return PhysicsFormat.compact(value * 1e6) + "µ"
            case ..<1 where kind == .capacitor: return PhysicsFormat.compact(value * 1e3) + "m"
            case 1000...: return PhysicsFormat.compact(value / 1000) + "k"
            default: return PhysicsFormat.compact(value)
            }
        }
    }

    /// What a pinch landed on: a pure static over entity names (the
    /// entity's own, then its ancestors', nearest first), so the priority
    /// is testable without a headset. No distance fallback: a part's two
    /// leads are 17 cm apart.
    enum Grab: Equatable {
        case lead(CircuitsModel.Terminal)
        case body(UUID)
        case wire(UUID)
        case lever(UUID)
        /// The stage, lowest of all: its rim turns the circuit, its deck's
        /// band carries it (2026-10-18).
        case stageRim
        case stageDeck
        case none
    }

    /// Which part of the stage a hand holds.
    enum StageHold: Equatable, Sendable { case rim, deck }

    /// A node's ring (2026-11-03, owner's call): tap a wired dot, or a
    /// joint's junction, and one petal stands over it — Cut. The part's own
    /// ring keeps Detach, which takes every wire on the part.
    enum LeadRing: Hashable {
        /// A lead dot: Cut takes every wire on that end, and only that end.
        case lead(CircuitsModel.Terminal)
        /// A joint's junction, one target for two leads: Cut parts them.
        case joint(UUID)
    }

    /// The ring a tap on `grab` opens: a lead with a wire on it, or a
    /// joint. A bare lead has nothing to cut, and a cable is not a node.
    static func leadRing(for grab: Grab, on model: CircuitsModel) -> LeadRing? {
        switch grab {
        case .lead(let terminal):
            return model.wires(at: terminal).isEmpty ? nil : .lead(terminal)
        case .wire(let id):
            guard let wire = model.wires.first(where: { $0.id == id }),
                  model.isJoint(wire) else { return nil }
            return .joint(id)
        default:
            return nil
        }
    }

    /// Whether the ring still has something to cut; once it is cut, it folds.
    static func isLive(_ ring: LeadRing, on model: CircuitsModel) -> Bool {
        switch ring {
        case .lead(let terminal):
            !model.wires(at: terminal).isEmpty
        case .joint(let id):
            model.wires.first { $0.id == id }.map(model.isJoint) ?? false
        }
    }

    /// The part the ring belongs to: a selection that moves off it folds it.
    static func partID(of ring: LeadRing, on model: CircuitsModel) -> UUID? {
        switch ring {
        case .lead(let terminal): terminal.componentID
        case .joint(let id): model.wires.first { $0.id == id }?.from.componentID
        }
    }

    /// The ring's one petal. It never arms: undo is a new wire, as a part's
    /// Delete is undone by the shelf.
    static func cutPetal(for ring: LeadRing, on model: CircuitsModel) -> Bloom.Petal {
        .init(name: "Cut", symbol: "scissors", tint: DesignTokens.Palette.neutralActionUI) {
            cut(ring, on: model)
        }
    }

    /// What the Cut petal does.
    static func cut(_ ring: LeadRing, on model: CircuitsModel) {
        switch ring {
        case .lead(let terminal):
            model.cutWires(at: terminal)
        case .joint(let id):
            model.deleteWire(id: id)
            model.clearNetHighlight()
        }
    }

    /// Where the ring stands: on the dot as drawn, or between a joint's leads.
    private static func anchor(of ring: LeadRing, on model: CircuitsModel,
                               renderer: CircuitsRenderer) -> SIMD3<Float>? {
        switch ring {
        case .lead(let terminal):
            return renderer.terminalWorld(terminal, model)
        case .joint(let id):
            guard let wire = model.wires.first(where: { $0.id == id }),
                  let a = renderer.terminalWorld(wire.from, model),
                  let b = renderer.terminalWorld(wire.to, model) else { return nil }
            return (a + b) / 2
        }
    }

    static func resolveGrab(names: [String], on model: CircuitsModel) -> Grab {
        let grab = resolvePartGrab(names: names, on: model)
        guard grab == .none else { return grab }
        if names.contains(CircuitsRenderer.stageRimName) { return .stageRim }
        if names.contains(CircuitsRenderer.stageDeckName) { return .stageDeck }
        return .none
    }

    private static func resolvePartGrab(names: [String], on model: CircuitsModel) -> Grab {
        for name in names {
            if name.hasPrefix("t0-") || name.hasPrefix("t1-"),
               let id = UUID(uuidString: String(name.dropFirst(3))),
               model.components.contains(where: { $0.id == id }) {
                return .lead(.init(componentID: id, end: name.hasPrefix("t0-") ? 0 : 1))
            }
            if name.hasPrefix("w-"), let id = UUID(uuidString: String(name.dropFirst(2))),
               model.wires.contains(where: { $0.id == id }) {
                return .wire(id)
            }
            if name.hasPrefix("k-"), let id = UUID(uuidString: String(name.dropFirst(2))),
               model.components.contains(where: { $0.id == id }) {
                return .lever(id)
            }
            if let id = UUID(uuidString: name),
               model.components.contains(where: { $0.id == id }) {
                return .body(id)
            }
        }
        return .none
    }

    /// Which branch owns this frame of the one drag gesture, as a pure
    /// static. A live carry outranks the shelf, whose `isDragging` stays
    /// true after its one-shot pull; the shelf still gets the spawn frame,
    /// when no carry exists yet.
    enum CarryPhase: Equatable {
        case leadPull, carry, stage, rack, idle
    }

    /// The stage held by its rim or deck ranks after a part's carry and
    /// before the shelf: a hand cannot hold the stage and a part at once,
    /// and the shelf's `isDragging` outlives its pull.
    static func carryDispatch(
        leadPullActive: Bool, partDragActive: Bool, stageHeld: Bool = false,
        rackDragging: Bool
    ) -> CarryPhase {
        if leadPullActive { return .leadPull }
        if partDragActive { return .carry }
        if stageHeld { return .stage }
        if rackDragging { return .rack }
        return .idle
    }

    /// The entity's name and its ancestors', nearest first.
    private static func nameChain(from entity: Entity) -> [String] {
        var names: [String] = []
        var current: Entity? = entity
        while let candidate = current {
            names.append(candidate.name)
            current = candidate.parent
        }
        return names
    }

    /// `hand` is in the bench's frame, for the parts; `roomHand` in the
    /// renderer's root frame, for the shelf that stands outside the zoom.
    private func beginCircuitDrag(
        entity: Entity, hand: SIMD3<Double>, roomHand: SIMD3<Float>,
        renderer: CircuitsRenderer
    ) {
        let grab = Self.resolveGrab(names: Self.nameChain(from: entity), on: model)
        switch grab {
        case .lead, .body, .wire, .lever:
            // A hand on any part wants the circuit still.
            model.stopStageCoast()
        default:
            break
        }
        switch grab {
        case .lead(let terminal):
            // Pressed, not pulled: it becomes a lead pull only once the hand
            // travels.
            leadPress.press(terminal, at: hand)
            return
        case .body:
            // A part on the bench is a hand's (`handleHands`), not this drag's.
            return
        case .stageRim:
            stagePress.press(.rim, at: hand)
            return
        case .stageDeck:
            stagePress.press(.deck, at: hand)
            return
        case .wire(let id):
            // Grab the cable (or a joint's collar) to move a wire, a lead to
            // make one: their targets never overlap.
            wirePress.press(.init(wire: id, pressedAt: hand), at: hand)
            return
        case .lever(let id):
            // Pressed and never promoted: a lever is a toggle, and the press
            // settles into the flip at gesture end.
            leverPress.press(id, at: hand)
            return
        case .none:
            break
        }
        // The shelf: its crown scrolls, and a slot is pressed — it pulls once
        // the hand travels. A crown already held keeps its grab: this runs
        // every frame of the gesture, and a second press would re-anchor it.
        guard palette?.isDragging != true else { return }
        var current: Entity? = entity
        while let candidate = current {
            if palette?.beginDrag(candidate, hand: roomHand) == true { return }
            if let index = palette?.sourceIndex(of: candidate) {
                sourcePress.press(index, at: hand)
                return
            }
            current = candidate.parent
        }
    }

    // MARK: A part in each hand (2026-11-02)
    // A press on a part is a tap until it has travelled `PressLatch.tapTravel`
    // — a tap selects, and a pinch that never moved must not lift the part —
    // so the table hands this view the hand itself, and each hold keeps its
    // own press and drag. Bring two parts together, one in each hand, and
    // each previews, leans and seats on its own.

    struct PartHold {
        let press: SIMD3<Double>
        var drag: RelativeDrag?
    }

    /// Reference storage, so a hold's per-frame writes do not invalidate the
    /// view.
    final class PartHolds {
        var byPart: [UUID: PartHold] = [:]
        /// Whether a hand has taken a part (past the tap's travel).
        var isCarrying: Bool { byPart.values.contains { $0.drag != nil } }
    }

    private func handleHands(_ events: SpatialEventCollection) {
        guard let renderer, let content = sceneContent else { return }
        hands.handle(
            events,
            locate: { event in
                // Into the bench's frame, as the drag converts: a part tracks the
                // hand 1:1 at any zoom.
                SIMD3<Double>(renderer.viewRoot.convert(
                    position: SIMD3<Float>(content.convert(event.location3D,
                                                           from: .local, to: .scene)),
                    from: nil))
            },
            begin: { entity, hand in pressPart(entity, hand: hand) },
            move: { id, hand in carryPart(id, hand: hand, renderer: renderer) },
            end: { session in letGoOfPart(session.target, hand: session.hand, renderer: renderer) })
    }

    private func pressPart(_ entity: Entity?, hand: SIMD3<Double>) -> (UUID, SIMD3<Double>)? {
        guard let entity,
              case .body(let id) = Self.resolveGrab(names: Self.nameChain(from: entity), on: model)
        else { return nil }
        // One hand to a part; and none while the stage is held or a lead is in
        // flight, both of which move the parts under it.
        guard holds.byPart[id] == nil, spawnedPartID != id, stageDrag == nil,
              model.leadPull == nil else { return nil }
        // A hand on any part wants the circuit still.
        model.stopStageCoast()
        holds.byPart[id] = PartHold(press: hand)
        return (id, hand)
    }

    private func carryPart(_ id: UUID, hand: SIMD3<Double>, renderer: CircuitsRenderer) {
        guard var hold = holds.byPart[id] else { return }
        defer { holds.byPart[id] = hold }
        guard let drag = hold.drag else {
            guard simd_distance(hand, hold.press) > PressLatch<UUID>.tapTravel,
                  stageDrag == nil,
                  let component = model.components.first(where: { $0.id == id }) else { return }
            hold.drag = RelativeDrag(name: id.uuidString, target: component.position, hand: hand)
            renderer.previewComponentIDs.insert(id)
            model.select(id: id)
            renderer.flashPickup(id: id)
            return
        }
        // The grab offset survives; the model composes the rest (swing or rigid
        // move) in `CircuitsModel.drag`.
        model.drag(id: id, toward: drag.position(forHand: hand))
    }

    private func letGoOfPart(_ id: UUID, hand: SIMD3<Double>, renderer: CircuitsRenderer) {
        // A press that never travelled was a tap, and the tap recogniser owns it.
        guard let hold = holds.byPart.removeValue(forKey: id), let drag = hold.drag else { return }
        model.drag(id: id, toward: drag.position(forHand: hand))
        // A part snapped onto a neighbour glides the last few centimetres rather
        // than jumping there.
        let before = model.components.first { $0.id == id }
        model.release(id: id)
        if let before { renderer.easeLanding(id: id, from: before.position, axis: before.axis) }
        renderer.previewComponentIDs.remove(id)
        renderer.flashRelease(id: id)
    }

    private func applyCircuitDrag(_ drag: RelativeDrag, hand: SIMD3<Double>) {
        // The grab offset survives; the model composes the rest (swing or rigid
        // move) in `CircuitsModel.drag`, so a test can drive the real sequence.
        let position = drag.position(forHand: hand)
        guard let id = spawnedPartID ?? UUID(uuidString: drag.name) else { return }
        model.drag(id: id, toward: position)
    }

    /// A tap only selects — it never wires and never deletes.
    private func handleTap(on entity: Entity) {
        let grab = Self.resolveGrab(names: Self.nameChain(from: entity), on: model)
        switch grab {
        case .lead(let terminal):
            // An armed meter is a question and the terminal is the answer.
            if model.multimeterArmed {
                model.probeTap(terminal)
            } else {
                model.select(id: terminal.componentID)
                // "What is this connected to?" — answered by lighting the net,
                // and a wired lead offers its Cut.
                toggleLeadRing(Self.leadRing(for: grab, on: model), on: entity) {
                    model.highlightNet(containing: terminal)
                }
            }
            return
        case .wire(let id):
            // A joint's leads give their targets to its collar, so an armed
            // meter probes the joint there.
            if model.multimeterArmed, let wire = model.wires.first(where: { $0.id == id }),
               model.isJoint(wire) {
                model.probeTap(wire.from)
                return
            }
            // A joint's junction is a node too: it offers its Cut. Along a
            // cable a tap only lights the net.
            toggleLeadRing(Self.leadRing(for: grab, on: model), on: entity) {
                model.selectWire(id: id)
            }
            return
        case .lever(let id):
            // Select only: the toggle lives on the drag path's settled press, since
            // both gestures complete on a clean tap. VoiceOver toggles through
            // `onLeverAction`.
            leadRing.target = nil
            model.select(id: id)
            return
        case .stageRim, .stageDeck:
            // A tap on the stage is a tap on empty space.
            break
        case .body(let id):
            leadRing.target = nil
            model.clearNetHighlight()
            if ring.openID == id {
                ring.openID = nil
                SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
            } else {
                // The ring, the lit outline and the readout name one part.
                model.select(id: id)
                ring.openID = id
                SoundPalette.play(.pop, on: entity, volume: 0.35)
            }
            return
        case .none:
            break
        }
        // Tapping nothing folds the ring and clears the lit net.
        if ring.openID != nil || leadRing.target != nil || model.highlightedNet != nil {
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
        }
        ring.openID = nil
        leadRing.target = nil
        model.clearNetHighlight()
    }

    /// A tap on a lead or a joint: a second tap on the one whose ring is
    /// open folds it and its lit net; otherwise `select` lights the net and
    /// `opening`, when there is something to cut, opens its ring.
    private func toggleLeadRing(_ opening: LeadRing?, on entity: Entity,
                                select: () -> Void) {
        if let opening, leadRing.target == opening {
            leadRing.target = nil
            model.clearNetHighlight()
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
            return
        }
        select()
        leadRing.target = opening
        if opening != nil {
            ring.openID = nil
            SoundPalette.play(.pop, on: entity, volume: 0.35)
        }
    }


}

