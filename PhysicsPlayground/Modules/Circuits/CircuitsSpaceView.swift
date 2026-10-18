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
    /// The view's single `DragGesture(minimumDistance: 0)` runs on every
    /// tap, so a latch promotes to a pull only past `PressLatch.tapTravel`.
    @State private var leadPress = PressLatch<CircuitsModel.Terminal>()
    @State private var partPress = PressLatch<UUID>()
    /// A wire end being lifted off its terminal. The payload is the
    /// wire and which of its two ends the hand was nearer to.
    @State private var wirePress = PressLatch<CircuitsModel.WireEnd>()
    /// A switch lever under a finger. Never promotes to a drag: it survives
    /// 12 mm of drift and toggles on `settle()` at gesture end. The
    /// TapGesture only selects, or a clean tap would toggle twice.
    @State private var leverPress = PressLatch<UUID>()
    /// A press on a shelf slot: it becomes a pull once the hand travels, so a
    /// tap on the shelf never spawns a part.
    @State private var sourcePress = PressLatch<Int>()
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
            content.add(renderer.root)
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
                _ = multimeter?.handleTap(entity, model: model)
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
            renderer.root.addChild(parts.root)
            self.palette = parts

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's arrival and departure, on the shell's one flag.
                    // `Fade.tick` settles to a no-op once landed.
                    if let renderer {
                        Fade.tick(renderer.root, visible: !appModel.isDeparting,
                                  duration: AppModel.departure)
                    }
                    // The lab's placement in the room: a constant display offset, safe
                    // because grabs move a body by hand displacement. Every instrument is
                    // a child of `renderer.root`, so it rides along.
                    renderer?.root.position = appModel.labPlacement.offset
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
            // `-circAlign 1` drops two parts a few centimetres apart and fires the
            // release on the second, so the snapped chain is what the screenshot
            // holds.
            if UserDefaults.standard.bool(forKey: "circAlign") {
                model.clearBench()
                let anchor = CircuitsModel.buildCenter
                model.add(.battery, at: anchor)
                if let battery = model.components.first {
                    // Inside `leadReach` (0.06): 3 cm along + 2 cm up, crooked enough to
                    // exercise the rotation.
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
            }

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
        }
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
                        }
                        if let drag = meterDrag {
                            meter.place(at: drag.start + (local - drag.hand))
                            return
                        }
                    }

                    if bloom.updateGrip(hand: handF) { return }
                    if model.leadPull == nil, partDrag == nil,
                       !leadPress.isPending, !partPress.isPending,
                       !wirePress.isPending, !leverPress.isPending,
                       !sourcePress.isPending {
                        if bloom.beginGrip(value.entity, hand: handF) { return }
                        beginCircuitDrag(entity: value.entity, hand: hand,
                                         roomHand: roomHand, renderer: renderer)
                    }
                    // A pressed lead becomes a pull only once the hand
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
                    // A lever press that travels is a drag to nowhere: consume and discard
                    // it.
                    _ = leverPress.promote(hand: hand)
                    // A slot press that travels is the pull: the part is born at the
                    // hand and carried from this frame.
                    if let index = sourcePress.promote(hand: hand),
                       let palette, let source = palette.source(at: index),
                       let id = palette.pull(source, at: hand) {
                        spawnedPartID = id
                        partDrag = RelativeDrag(name: id.uuidString, target: hand, hand: hand)
                        renderer.previewComponentID = id
                    }
                    switch Self.carryDispatch(
                        leadPullActive: model.leadPull != nil,
                        partDragActive: partDrag != nil,
                        rackDragging: palette?.isDragging == true
                    ) {
                    case .leadPull:
                        model.updateLeadPull(hand: hand)
                    case .carry:
                        // A live carry outranks the shelf: its gesture stays "dragging" after
                        // the one-shot pull, and the part it spawned must follow the hand from
                        // its first frame.
                        if let partDrag { applyCircuitDrag(partDrag, hand: hand) }
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
                    defer {
                        renderer?.previewComponentID = nil
                        leadPress.cancel()
                        partPress.cancel()
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
                        model.release(id: id)
                    }
                    renderer.flashRelease()
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
                        stretch: .track(range: range, under: {
                            model.components.first { $0.id == uuid }
                                .map { SIMD3<Float>($0.position) } ?? .zero
                        }, read: { model.componentValue(id: uuid) }))
                : nil)

        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(part.position),
                     viewer: viewer, revealTarget: 1, dt: dt)
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

    /// Which branch owns this frame of the one drag gesture, as a pure
    /// static. A live carry outranks the shelf, whose `isDragging` stays
    /// true after its one-shot pull; the shelf still gets the spawn frame,
    /// when no carry exists yet.
    enum CarryPhase: Equatable {
        case leadPull, carry, rack, idle
    }

    static func carryDispatch(
        leadPullActive: Bool, partDragActive: Bool, rackDragging: Bool
    ) -> CarryPhase {
        if leadPullActive { return .leadPull }
        if partDragActive { return .carry }
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
        switch Self.resolveGrab(names: Self.nameChain(from: entity), on: model) {
        case .lead(let terminal):
            // Pressed, not pulled: it becomes a lead pull only once the hand
            // travels.
            leadPress.press(terminal, at: hand)
            return
        case .body(let id):
            partPress.press(id, at: hand)
            return
        case .wire(let id):
            // Grab the cable to move a wire, the copper to make one: the bead is
            // fatter than the cable and sits at its endpoint.
            if let end = model.nearerEnd(of: id, to: hand) {
                wirePress.press(.init(wire: id, end: end), at: hand)
            }
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

    /// A body press that travelled: start carrying it.
    private func beginCarrying(_ id: UUID, hand: SIMD3<Double>, renderer: CircuitsRenderer) {
        guard let component = model.components.first(where: { $0.id == id }) else { return }
        partDrag = RelativeDrag(name: id.uuidString, target: component.position, hand: hand)
        renderer.previewComponentID = id
        model.select(id: id)
        renderer.flashPickup(id: id)
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
        switch Self.resolveGrab(names: Self.nameChain(from: entity), on: model) {
        case .lead(let terminal):
            // An armed meter is a question and the terminal is the answer.
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
            // Select only: the toggle lives on the drag path's settled press, since
            // both gestures complete on a clean tap. VoiceOver toggles through
            // `onLeverAction`.
            model.select(id: id)
            return
        case .body(let id):
            model.clearNetHighlight()
            if ring.openID == id {
                ring.openID = nil
                SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
            } else {
                // The ring, the halo and the readout name one part.
                model.select(id: id)
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


}

