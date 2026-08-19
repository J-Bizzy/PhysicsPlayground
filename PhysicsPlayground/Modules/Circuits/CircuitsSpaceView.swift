//
//  CircuitsSpaceView.swift
//  Physics Playground — Circuits module
//
//  The circuit lab immersive scene. Component bodies are carried by a
//  `RelativeDrag`; the model owns where they end up. Terminals, wires
//  and switch levers are tap targets. Solver clock is SceneEvents.Update.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct CircuitsSpaceView: View {
    @Environment(CircuitsModel.self) private var model
    @State private var renderer: CircuitsRenderer?
    @State private var bloom = Bloom()
    /// Which component's ring is open — shared by the tap gesture and
    /// the render loop (see RingState's header).
    @State private var ring = RingState()
    /// Press-before-drag: the view's single `DragGesture(minimumDistance: 0)`
    /// means every tap also runs the drag, so a latch only promotes to a
    /// pull past `PressLatch.tapTravel` — a zero-travel press wires nothing.
    @State private var leadPress = PressLatch<CircuitsModel.Terminal>()
    @State private var partPress = PressLatch<UUID>()
    /// A wire end being lifted off its terminal. The payload is the
    /// wire and which of its two ends the hand was nearer to.
    @State private var wirePress = PressLatch<CircuitsModel.WireEnd>()
    @State private var partDrag: RelativeDrag?
    /// The part a pull off the palette just made, so the drag that made
    /// it can go on moving it. It outlives the `RelativeDrag`'s name,
    /// which for a new part is the well's, not a UUID.
    @State private var spawnedPartID: UUID?
    /// The parts palette: blocks of sources on the flanks, one per
    /// component kind. Geometry in `CircuitsPartsLayout`.
    @State private var palette: Well?

    /// Which probe a hand is carrying, if either.
    @State private var probeDrag: CircuitsModel.ProbeSlot?
    /// Carrying the meter itself: where its case was when the hand closed
    /// on it, and where the hand was, both in the renderer's frame.
    @State private var meterDrag: (start: SIMD3<Float>, hand: SIMD3<Float>)?
    @Environment(AppModel.self) private var appModel
    /// Two-handed zoom on the bench. Electron View raises this same
    /// number's floor rather than being a competing 1x/4x flip.
    @State private var scaleRig = SpatialScaleRig(
        pivot: CircuitsRenderer.benchPivot, range: 0.6...8.0, allowsTurn: false)
    /// The layers bank: which views of the current are switched on;
    /// also the door to Electron View (`model.electronView`).
    @State private var layers: SpatialLayerBank?
    /// The bench's meter — a tool, not a layer. See `Multimeter`.
    @State private var meter: Multimeter?
    /// The bench's one standing verb: clear it. See `clearAnchor`.
    @State private var verbs: SpatialActionBank?

    /// The five authored circuits (`CircuitsModel.Preset`), behind a
    /// `SummonHandle` that folds to one tab reading out the last loaded.
    @State private var presetsHandle = SummonHandle(
        title: "Presets", symbol: "square.grid.2x2",
        accent: UIColor(DesignTokens.Palette.circuitsAccent))
    @State private var presets: SpatialActionBank?
    /// What the handle reads out when folded.
    @State private var lastPreset: CircuitsModel.Preset?

    /// Identifies the floating readout above the selected part.
    private static let readoutCardID = "circuit-readout"

    /// Where the meter starts (right flank); it moves with the hand after.
    private static let meterAnchor = CircuitsRenderer.benchPivot
        + SIMD3<Float>(0.62, -0.03, 0.16)
    /// The Clear plate, on the bench's far left flank. The most dangerous
    /// verb: the bench persists across launches, so it `confirms`.
    private static let clearAnchor = CircuitsRenderer.benchPivot
        + SIMD3<Float>(-1.02, -0.02, 0.10)

    /// The layers bank, on the bench's left flank. A named static so
    /// `InstrumentReachCriterionTests` can measure it.
    static let bankAnchor = CircuitsRenderer.benchPivot
        + SIMD3<Float>(-0.62, -0.06, 0.16)

    /// Beside the Clear plate, unfolding UPWARD: presets and layers are
    /// both five-plate columns and can't stack inside the 0.70…1.80 band,
    /// so they share the far-left flank. Clearance checked by
    /// `CircuitsInstrumentClearanceTests`.
    private static let presetsAnchor = CircuitsRenderer.benchPivot
        + SIMD3<Float>(-1.02, 0.15, 0.10)
    /// The column hangs below the tab, centred on this point — a bank
    /// centres its plates on its anchor rather than stacking down from
    /// it, which is how the first attempt put the tab inside its own
    /// column.
    private static let presetsBankAnchor = CircuitsRenderer.benchPivot
        + SIMD3<Float>(-1.02, 0.39, 0.10)

    var body: some View {
        RealityView { content, attachments in
            let renderer = CircuitsRenderer()
            renderer.onTap = { handleTap(on: $0) }
            renderer.onTerminalAction = { model.voiceOverWire($0) }
            content.add(renderer.root)

            // What the selected part is doing, on the part. The anchor
            // has been repositioned above it every frame since the
            // renderer was written and carried nothing; the card was in
            // the window panel's "Selected part" dropdown.
            if let card = attachments.entity(for: Self.readoutCardID) {
                stripInput(from: card)
                renderer.selectedAnchor.addChild(card)
            }
            renderer.viewRoot.addChild(bloom.root)

            let bank = SpatialLayerBank(
                accent: UIColor(DesignTokens.Palette.circuitsAccent),
                layers: [
                    .init(id: "flow", label: "Electron flow", symbol: "circle.dotted",
                          isOn: { model.showElectronFlow },
                          toggle: { model.showElectronFlow.toggle() }),
                    .init(id: "truespeed", label: "True speed", symbol: "tortoise",
                          isOn: { model.trueSpeedMode },
                          toggle: { model.trueSpeedMode.toggle() }),
                    // The bench's own field. It replaces the
                    // electromagnet annex, and it makes the smaller,
                    // truer claim: EVERY wire here has a field around
                    // it, not just one wound into a coil.
                    .init(id: "bfield", label: "Magnetic field",
                          symbol: "circle.hexagongrid",
                          isOn: { model.showMagneticField },
                          toggle: { model.showMagneticField.toggle() }),
                    .init(id: "skyline", label: "Voltage skyline", symbol: "building.2",
                          isOn: { model.showVoltageHeights },
                          toggle: { model.showVoltageHeights.toggle() }),
                    .init(id: "electron", label: "Electron view", symbol: "arrow.down.left.and.arrow.up.right",
                          isOn: { model.electronView },
                          toggle: { model.electronView.toggle() }),
                ])
            // Under `root`, NOT `viewRoot`: the zoom reaches 8x, and a
            // control that grew with the bench would be a metre wide —
            // and Electron View's own switch would swell out of reach the
            // moment you used it.
            renderer.root.addChild(bank.root)
            self.layers = bank

            // Both under `root` for the same reason the layers bank is:
            // the zoom reaches 8×, and an instrument that grew with the
            // bench would put itself out of reach exactly when you had
            // zoomed in to use it.
            let multimeter = Multimeter(
                accent: UIColor(DesignTokens.Palette.circuitsAccent),
                anchor: Self.meterAnchor)
            renderer.root.addChild(multimeter.root)
            multimeter.onTap = { [weak multimeter] entity in
                _ = multimeter?.handleTap(entity, model: model)
            }
            self.meter = multimeter

            // Clearing the bench, off the window panel. Same parenting
            // rule as everything above: under `root`, so an 8× zoom
            // cannot carry it away.
            let benchVerbs = SpatialActionBank(
                accent: UIColor(DesignTokens.Palette.circuitsAccent),
                actions: [
                    .init(id: "clear", label: "Clear bench",
                          symbol: "trash.slash",
                          isAvailable: { !model.components.isEmpty },
                          confirms: true,
                          fire: { model.clearBench() }),
                ])
            renderer.root.addChild(benchVerbs.root)
            self.verbs = benchVerbs

            // Every preset confirms: `loadPreset` opens with `clearBench()`
            // and the bench persists across launches, so one tap would
            // destroy a previous session's work.
            let presetBank = SpatialActionBank(
                accent: UIColor(DesignTokens.Palette.circuitsAccent),
                actions: CircuitsModel.Preset.allCases.map { preset in
                    .init(id: preset.rawValue, label: preset.displayName,
                          symbol: "bolt.horizontal",
                          confirms: true,
                          fire: {
                              model.loadPreset(preset)
                              lastPreset = preset
                              presetsHandle.close()
                          })
                })
            presetBank.root.isEnabled = false
            renderer.root.addChild(presetBank.root)
            self.presets = presetBank

            // The handle reads out which circuit is on the bench.
            presetsHandle.summary = { lastPreset?.displayName ?? "your bench" }
            renderer.root.addChild(presetsHandle.root)

            // The parts, in one block on the right. `CircuitsPartsLayout`
            // says which parts and in what order (sources, passives, then
            // active parts) via `rightSlot`; the two `kinds(on:)` lists
            // are concatenated, not merged, to keep that grouping.
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
            // The meter is the twelfth slot, parked in the rack. `handOver`
            // not `spawn`: there is exactly one multimeter, not a fresh one
            // per pull.
            let meterSlot = Well.Spec(
                name: "multimeter",
                tint: UIColor(DesignTokens.Palette.circuitsAccent),
                label: "Multimeter",
                preview: { Multimeter.miniature() },
                position: CircuitsPartsLayout.rightSlot(index: partSpecs.count),
                spawn: { _ in nil },
                // Captures the instrument, not the view (a SwiftUI View is
                // a struct, no `self` to hold weakly).
                handOver: { [weak multimeter] hand in
                    // Out of the rack, into the hand, and made visible.
                    multimeter?.place(at: SIMD3<Float>(hand))
                    multimeter?.root.isEnabled = true
                })

            // Hidden until pulled: the slot shows a miniature, so leaving
            // the real instrument out too would put two meters in the room.
            multimeter.root.isEnabled = false

            let parts = Well(partSpecs + [meterSlot])
            // A window, not a wall: six of the twelve visible, the rest a
            // drag away.
            parts.visibleCount = CircuitsPartsLayout.rightVisibleRows
            renderer.root.addChild(parts.root)
            self.palette = parts

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's placement in the user's room — a pure
                    // Constant display offset — safe because grabs move a
                    // body by hand displacement. The bank, meter and verb
                    // plate are children of `renderer.root`, so they ride it.
                    renderer?.root.position = appModel.labPlacement.offset
                    model.step(dt: event.deltaTime)
                    let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
                    layers?.update(
                        // bankAnchor x −0.62 is inside the ±0.70 build
                        // volume: no position clears the margin, reach and
                        // off-axis limits at once until the bench narrows —
                        // an owner call with a real cost (saved circuits
                        // wider than 0.60 would fall outside the bench).
                        anchor: Self.bankAnchor,
                        viewer: viewer,
                        dt: event.deltaTime)
                    meter?.update(viewer: viewer, model: model)
                    // Idle breath, recoil on giving up a part, and a
                    // refusal fade at the component budget.
                    palette?.update(
                        dt: event.deltaTime,
                        nearestHand: appModel.room.nearestFingertip(
                            to: CircuitsPartsLayout.rightSlot(index: 0)))
                    verbs?.update(anchor: Self.clearAnchor, viewer: viewer,
                                  dt: event.deltaTime,
                                  resetNonce: appModel.resetNonce,
                                  nearestHand: appModel.room.nearestFingertip(
                                    to: Self.clearAnchor))
                    presetsHandle.update(
                        anchor: Self.presetsAnchor, viewer: viewer,
                        dt: event.deltaTime,
                        nearestHand: appModel.room.nearestFingertip(
                            to: Self.presetsAnchor))
                    presets?.root.isEnabled = presetsHandle.isOpen
                    if presetsHandle.isOpen {
                        presets?.update(anchor: Self.presetsBankAnchor,
                                        viewer: viewer, dt: event.deltaTime,
                                        resetNonce: appModel.resetNonce,
                                        nearestHand: appModel.room.nearestFingertip(
                                            to: Self.presetsBankAnchor))
                    }
                    // Ticked every frame, NOT via the observation loop: a
                    // steady DC circuit mutates nothing observation re-fires
                    // on, but its electrons must keep drifting.
                    renderer?.handZoom = scaleRig.liveScale
                    renderer?.tick(dt: event.deltaTime, model: model)
                    if let renderer {
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                    }
                }
            )
            #if DEBUG
            if UserDefaults.standard.double(forKey: "trueSpeed") > 0 {
                model.trueSpeedMode = true
            }
            // `-electronView 1` shrinks the bench into the copper (the
            // switch is a bank plate the simulator can't press).
            if UserDefaults.standard.bool(forKey: "electronView") {
                model.electronView = true
            }
            // `-skyline 1` raises the voltage towers (bank toggle, needs a hand).
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
            // `-circRing 1` opens the first component's control ring
            // at launch, for CLI screenshots.
            if UserDefaults.standard.bool(forKey: "circRing"),
               let first = model.components.first {
                ring.openID = first.id
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
            // `-circAlign 1` drops two parts a few centimetres apart
            // and fires the release on the second, so the SNAPPED
            // chain is what the screenshot holds. The ghost preview is
            // a carry state and needs a hand; this is the landing.
            if UserDefaults.standard.bool(forKey: "circAlign") {
                model.clearBench()
                let anchor = CircuitsModel.buildCenter
                model.add(.battery, at: anchor)
                if let battery = model.components.first {
                    // Offset is the near lead's and must stay inside
                    // `leadReach` (0.06): 3 cm along + 2 cm up = 3.6 cm,
                    // crooked enough to exercise the rotation.
                    let landing = battery.terminalPosition(1)
                        + SIMD3(0.03 + CircuitsModel.terminalOffset, 0.02, 0)
                    if let bulb = model.add(.bulb, at: landing) {
                        model.release(id: bulb)
                    }
                }
            }
            // `-circPreset series|parallel|divider|rcCharger|shortCircuit`
            // loads one of the authored circuits.
            if let name = UserDefaults.standard.string(forKey: "circPreset"),
               let preset = CircuitsModel.Preset(rawValue: name) {
                model.loadPreset(preset)
                lastPreset = preset
            }

            // The index-naming args below MUST run after the bench-shaping
            // args: `-circPreset` starts with `clearBench`, so run earlier
            // they would name parts a preset then deleted.
            // `-circLead <componentIndex>,<end>` pulls a lead out toward
            // open air (a gesture state the simulator can only be handed).
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
            // `-circPresetsOpen 1` unfolds the presets tab.
            if UserDefaults.standard.bool(forKey: "circPresetsOpen") {
                presetsHandle.setOpen(true)
            }
            // `-circScroll <n>` scrolls the parts rack n slots.
            let scroll = UserDefaults.standard.integer(forKey: "circScroll")
            if scroll != 0 { parts.scroll(by: scroll) }

            // `-circField 1` switches on the bench's own magnetic field.
            if UserDefaults.standard.bool(forKey: "circField") {
                model.showMagneticField = true
            }
            // `-circClear 1` ARMS the Clear plate without firing — firing
            // photographs an empty bench, indistinguishable from an unused one.
            if UserDefaults.standard.bool(forKey: "circClear") {
                benchVerbs.arm("clear", holds: true)
            }
            #endif
            self.renderer = renderer
        } attachments: {
            Attachment(id: Self.readoutCardID) {
                CircuitsSelectedReadout()
                    // Never intercept a pinch: this floats 14 cm above a
                    // part whose body, terminals and end grips are all
                    // grab targets.
                    .allowsHitTesting(false)
                    .environment(model)
            }
        }
        // Leaving the lab must not leave anything running or held: an
        // in-flight grab never gets its `onEnded` when the space closes,
        // so it must be cleared here or it strands and re-targets every
        // later drag.
        .onDisappear {
            renderer?.teardown()
            // MUST clear: `Bloom` is a class, so a live grip outlives the
            // view and would claim every subsequent drag in the module.
            bloom.endGrip()
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // Ring petals first; then the bench's own tap
                    // grammar (terminals wire, wires delete, levers
                    // flip, bodies toggle their control ring).
                    if layers?.handleTap(value.entity) == true { return }
                    // Meter before `handleTap(on:)` (which reads a terminal):
                    // it stands among the terminals, so its dial must not
                    // count as probing what's behind it.
                    if meter?.handleTap(value.entity, model: model) == true { return }
                    if bloom.handleTap(value.entity) { return }
                    // Verb plates before the bench, by the same rule: a plate
                    // is never also a reach for the bench behind it.
                    if verbs?.handleTap(value.entity) == true { return }
                    // The rack's carets, before the flank behind them.
                    if palette?.handleTap(value.entity) == true { return }
                    if presetsHandle.handleTap(value.entity) { return }
                    if presetsHandle.isOpen,
                       presets?.handleTap(value.entity) == true { return }
                    handleTap(on: value.entity)
                }
        )
        // One drag gesture, four grabs, all relative: a terminal pulls a
        // wire; a lead aims its part; a palette source hands you a new
        // part; a body carries the part.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    // Into the bench's frame, not the room's: converting
                    // through viewRoot inverts zoom and lab placement, so a
                    // part tracks the hand 1:1 on screen at any zoom.
                    let handF = renderer.viewRoot.convert(
                        position: SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene)),
                        from: nil)
                    let hand = SIMD3<Double>(handF)

                    // Probes first: a probe carried across a terminal must
                    // not also start dragging that terminal's wire.
                    if probeDrag == nil, let meter,
                       let slot = meter.probeSlot(for: value.entity) {
                        probeDrag = slot
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

                    // Meter next, in the RENDERER's frame not the bench's:
                    // it hangs off `root` (not `viewRoot`) so Electron View
                    // zoom cannot carry it out of reach.
                    if let meter {
                        let world = SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene))
                        let local = renderer.root.convert(position: world, from: nil)
                        if meterDrag == nil, meter.isBody(value.entity) {
                            meterDrag = (meter.anchor, local)
                        }
                        if let drag = meterDrag {
                            meter.place(at: drag.start + (local - drag.hand))
                            return
                        }
                    }

                    if bloom.updateGrip(hand: handF) { return }
                    if model.leadPull == nil, partDrag == nil,
                       !leadPress.isPending, !partPress.isPending, !wirePress.isPending {
                        if bloom.beginGrip(value.entity, hand: handF) { return }
                        beginCircuitDrag(entity: value.entity, hand: hand, renderer: renderer)
                    }
                    // A pressed lead becomes a PULL only once the hand
                    // has moved; until then it is still a tap.
                    if let source = leadPress.promote(hand: hand) {
                        model.beginLeadPull(from: source, hand: hand)
                    }
                    if let id = partPress.promote(hand: hand) {
                        beginCarrying(id, hand: hand, renderer: renderer)
                    }
                    if let grabbed = wirePress.promote(hand: hand) {
                        model.beginRewire(wire: grabbed.wire,
                                          grabbing: grabbed.end, hand: hand)
                    }
                    if model.leadPull != nil {
                        model.updateLeadPull(hand: hand)
                    } else if let palette, palette.isDragging {
                        // Browsing, or the frame a pull commits on. The
                        // slot comes back exactly once — returning it
                        // every frame would put one part on the bench
                        // per frame.
                        if let slot = palette.updateDrag(hand: handF),
                           let source = palette.source(at: slot) {
                            if let id = palette.pull(source, at: hand) {
                                spawnedPartID = id
                                partDrag = RelativeDrag(name: id.uuidString,
                                                        target: hand, hand: hand)
                                renderer.previewComponentID = id
                                model.beginCarry(id: id)
                            }
                        }
                    } else if let partDrag {
                        applyCircuitDrag(partDrag, hand: hand)
                    }
                }
                .onEnded { value in
                    probeDrag = nil
                    meterDrag = nil
                    palette?.endDrag()
                    bloom.endGrip()
                    defer {
                        renderer?.previewComponentID = nil
                        leadPress.cancel()
                        partPress.cancel()
                        wirePress.cancel()
                        partDrag = nil
                        spawnedPartID = nil
                        model.endCarry()
                    }
                    guard let renderer else { return }
                    // Into the bench's frame, not the room's: converting
                    // through viewRoot inverts zoom and lab placement, so a
                    // part tracks the hand 1:1 on screen at any zoom.
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
                        model.release(id: id)
                    }
                    renderer.flashRelease()
                }
        )
        .spatialScale(scaleRig)
    }

    /// A part's own controls: a value grip (a bulb dims, a battery's
    /// drift quickens as you pull) and petals for the discrete actions.
    private func syncBloom(renderer: CircuitsRenderer, dt: Double) {
        if let openID = ring.openID,
           !model.components.contains(where: { $0.id == openID }) {
            ring.openID = nil     // deleted out from under the ring
        }
        guard let uuid = ring.openID,
              let part = model.components.first(where: { $0.id == uuid }) else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }

        var petals: [Bloom.Petal] = []
        if part.kind == .switcher {
            petals.append(.init(name: "Open or close", symbol: "power",
                                tint: DesignTokens.Palette.neutralActionUI) {
                model.toggleSwitch(id: uuid)
            })
        }
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
                        radius: { 0.05 })
                : nil)

        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(part.position),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }

    /// What a pinch landed on. A pure static over entity NAMES (the
    /// entity's own then its ancestors', nearest first) so the six-way
    /// priority is testable without a headset. NO distance fallback: a
    /// part's two leads are 17 cm apart, so a fallback wires the wrong end.
    enum Grab: Equatable {
        case lead(CircuitsModel.Terminal)
        case body(UUID)
        case wire(UUID)
        case lever(UUID)
        case none
    }

    static func resolveGrab(names: [String], on model: CircuitsModel) -> Grab {
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

    private func beginCircuitDrag(
        entity: Entity, hand: SIMD3<Double>, renderer: CircuitsRenderer
    ) {
        switch Self.resolveGrab(names: Self.nameChain(from: entity), on: model) {
        case .lead(let terminal):
            // PRESSED, not pulled. It becomes a lead pull only once
            // the hand travels; a press that never moves is a tap.
            leadPress.press(terminal, at: hand)
            return
        case .body(let id):
            partPress.press(id, at: hand)
            return
        case .wire(let id):
            // Grab the CABLE to move a wire, the copper to make one.
            // The bead (r 0.026) is fatter than the cable (r 0.016)
            // and sits at its endpoint, so a pinch at the joint takes
            // the lead and a pinch along the run takes the wire.
            if let end = model.nearerEnd(of: id, to: hand) {
                wirePress.press(.init(wire: id, end: end), at: hand)
            }
            return
        case .lever, .none:
            break
        }
        // The rack claims the drag before knowing if it's a scroll or a
        // take — that resolves in `onChanged` once the hand has travelled.
        var current: Entity? = entity
        while let candidate = current {
            if palette?.beginDrag(candidate, hand: SIMD3<Float>(hand)) == true { return }
            current = candidate.parent
        }
    }

    /// A body press that travelled: start carrying it.
    private func beginCarrying(_ id: UUID, hand: SIMD3<Double>, renderer: CircuitsRenderer) {
        guard let component = model.components.first(where: { $0.id == id }) else { return }
        partDrag = RelativeDrag(name: id.uuidString, target: component.position, hand: hand)
        renderer.previewComponentID = id
        model.select(id: id)
        model.beginCarry(id: id)
        renderer.flashPickup(id: id)
    }

    private func applyCircuitDrag(_ drag: RelativeDrag, hand: SIMD3<Double>) {
        let position = drag.position(forHand: hand)
        guard let id = spawnedPartID ?? UUID(uuidString: drag.name) else { return }
        model.move(id: id, to: position)
        // A part hanging by one lead swings about it while carried.
        model.swing(id: id, hand: position)
        model.breakOverstretchedWires(id: id)
    }

    /// A tap only SELECTS — it never wires and never deletes (wiring is a
    /// pull, a wire comes off by being pulled off). It says "this one" and
    /// the room answers with the readout and the ring.
    private func handleTap(on entity: Entity) {
        switch Self.resolveGrab(names: Self.nameChain(from: entity), on: model) {
        case .lead(let terminal):
            // The probes are the one thing that still consumes a
            // terminal tap, because an armed meter is a question you
            // are asking and the terminal is the answer.
            if model.multimeterArmed {
                model.probeTap(terminal)
            } else {
                model.select(id: terminal.componentID)
                // "What is this connected to?" — answered by lighting the net.
                model.highlightNet(containing: terminal)
            }
            return
        case .wire(let id):
            model.selectWire(id: id)
            return
        case .lever(let id):
            model.toggleSwitch(id: id)
            return
        case .body(let id):
            model.clearNetHighlight()
            if ring.openID == id {
                ring.openID = nil
                SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
            } else {
                ring.openID = id
                SoundPalette.play(.pop, on: entity, volume: 0.35)
            }
            return
        case .none:
            break
        }
        // Tapping nothing folds the ring and clears the lit net.
        if ring.openID != nil || model.highlightedNet != nil {
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
        }
        ring.openID = nil
        model.clearNetHighlight()
    }


    /// Component bodies (named by UUID) are carried directly; a palette
    /// source makes a part at the hand and hands it to the same drag. The
    /// palette resolves by ENTITY through `Well.pull`, not by name-parsing
    /// (a renamed entity would fail silently).
}

