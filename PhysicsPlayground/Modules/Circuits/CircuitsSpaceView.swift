//
//  CircuitsSpaceView.swift
//  Physics Playground — Circuits module
//
//  The circuit lab immersive scene. Component bodies route through
//  RenderKit's ManipulationRouter (grab to carry anywhere); terminals,
//  wires, and switch levers are tap targets — pinch a terminal, then
//  another, and they're wired; pinch a wire to remove it; pinch a
//  lever to flip it. The solver clock is SceneEvents.Update.
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
    @State private var wireDragFrom: CircuitsModel.Terminal?
    @State private var partDrag: RelativeDrag?
    @State private var trayDragID: UUID?
    @State private var gripDrag: (grip: CircuitsModel.Terminal, pivot: SIMD3<Double>)?
    @Environment(AppModel.self) private var appModel
    /// Two-handed zoom on the bench. Electron View is now a FLOOR under
    /// this same number rather than a competing 1x/4x flip, so "get in
    /// among the electrons" and "pull the bench open with both hands"
    /// are one continuous control.
    @State private var scaleRig = SpatialScaleRig(
        pivot: CircuitsRenderer.benchPivot, range: 0.6...8.0, allowsTurn: false)
    /// The layers bank: which views of the current are switched on.
    ///
    /// It also finally gives ELECTRON VIEW a door. `model.electronView`
    /// has existed since the bench was written — it raises the zoom floor
    /// to 4x so the wires swell around you and the drifting electrons
    /// become things you stand among — and NOTHING in the app ever set it.
    /// It was reachable only by happening to pinch the bench open with two
    /// hands past 4x. The one view that kills the misconception this module
    /// exists to kill was hidden behind an accident.
    @State private var layers: SpatialLayerBank?

    var body: some View {
        RealityView { content in
            let renderer = CircuitsRenderer()
            content.add(renderer.root)
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

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                    // (No counter-translation here: this module's pods
                    // hang off the scene content rather than the renderer
                    // root, so they never inherited the offset.)
                    model.step(dt: event.deltaTime)
                    // The bank stands beside the bench, at the bench's own
                    // depth so it sits in the same ~15 deg band as the
                    // apparatus rather than dropping out of view.
                    layers?.update(
                        anchor: CircuitsRenderer.benchPivot + SIMD3(0.62, -0.06, 0.16),
                        viewer: appModel.room.headPosition.map { SIMD3<Float>($0) },
                        dt: event.deltaTime)
                    // Rendered here every frame (not via the observation
                    // loop): a steady DC circuit mutates nothing that
                    // observation reliably re-fires on, but its electrons
                    // must keep drifting.
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
            #endif
            self.renderer = renderer
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // Ring petals first; then the bench's own tap
                    // grammar (terminals wire, wires delete, levers
                    // flip, bodies toggle their control ring).
                    if layers?.handleTap(value.entity) == true { return }
                    if bloom.handleTap(value.entity) { return }
                    handleTap(on: value.entity)
                }
        )
        // One drag gesture, four grabs — all relative, nothing lurches
        // toward the hand: a terminal pulls a live wire; an end grip
        // aims/stretches its part; a tray template spawns a copy that
        // follows the hand's displacement; a part body carries the
        // part. Tap-tap wiring still works too.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    // Into the BENCH's own frame, not the room's. The
                    // bench can be zoomed (Electron View, two hands) and
                    // moved (lab placement); converting through viewRoot
                    // inverts both exactly, so a part follows the hand
                    // 1:1 on screen at any zoom instead of flying four
                    // times as far.
                    let handF = renderer.viewRoot.convert(
                        position: SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene)),
                        from: nil)
                    let hand = SIMD3<Double>(handF)
                    if bloom.updateGrip(hand: handF) { return }
                    if wireDragFrom == nil, partDrag == nil {
                        if bloom.beginGrip(value.entity, hand: handF) { return }
                        beginCircuitDrag(entity: value.entity, hand: hand, renderer: renderer)
                    }
                    if let source = wireDragFrom,
                       let sourceComponent = model.components.first(
                         where: { $0.id == source.componentID }) {
                        let target = nearestTerminal(to: handF, excluding: source)
                        renderer.rubberTargetTerminal = target?.terminal
                        renderer.showRubberBand(
                            from: SIMD3<Float>(sourceComponent.terminalPosition(source.end)),
                            to: target.map { SIMD3<Float>($0.position) } ?? handF)
                    } else if let partDrag {
                        applyCircuitDrag(partDrag, hand: hand)
                    }
                }
                .onEnded { value in
                    bloom.endGrip()
                    defer {
                        renderer?.hideRubberBand()
                        renderer?.previewComponentID = nil
                        wireDragFrom = nil
                        partDrag = nil
                        trayDragID = nil
                        gripDrag = nil
                        model.endCarry()
                    }
                    guard let renderer else { return }
                    // Into the BENCH's own frame, not the room's. The
                    // bench can be zoomed (Electron View, two hands) and
                    // moved (lab placement); converting through viewRoot
                    // inverts both exactly, so a part follows the hand
                    // 1:1 on screen at any zoom instead of flying four
                    // times as far.
                    let handF = renderer.viewRoot.convert(
                        position: SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene)),
                        from: nil)
                    let hand = SIMD3<Double>(handF)
                    if let source = wireDragFrom {
                        if let target = nearestTerminal(to: handF, excluding: source) {
                            model.connectTerminals(source, target.terminal)
                        }
                        return
                    }
                    guard let partDrag else { return }
                    applyCircuitDrag(partDrag, hand: hand)
                    if let gripDrag {
                        model.autoConnect(id: gripDrag.grip.componentID)
                    } else if let id = trayDragID ?? UUID(uuidString: partDrag.name) {
                        model.autoConnect(id: id)
                    }
                    if trayDragID != nil {
                        renderer.setTrayTemplateHidden(partDrag.name, false)
                    }
                }
        )
        .spatialScale(scaleRig)
    }

    /// Resolves what the pinch landed on and opens the right session:
    /// wire (terminal), aim/stretch (grip), spawn (tray), carry (body).

    /// A part's own controls. Its value has no size of its own, so the
    /// grip's honesty is the CONSEQUENCE — pull a bulb's resistance up
    /// and it visibly dims, pull the battery's volts and the electron
    /// drift quickens while your hand is still moving. Switches get a
    /// petal instead, because open and closed is not a continuum.
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
                                tint: UIColor(white: 0.45, alpha: 1)) {
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
                                tint: UIColor(white: 0.45, alpha: 1)) {
                model.detachComponent(id: uuid)
            })
        }
        petals.append(.init(name: "Delete", symbol: "trash",
                            tint: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)) {
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

    private func beginCircuitDrag(
        entity: Entity, hand: SIMD3<Double>, renderer: CircuitsRenderer
    ) {
        var current: Entity? = entity
        while let candidate = current {
            let name = candidate.name
            if name.hasPrefix("t0-") || name.hasPrefix("t1-") {
                wireDragFrom = terminal(on: candidate)
                return
            }
            if let grip = stretchTerminal(from: name),
               let component = model.components.first(
                where: { $0.id == grip.componentID }) {
                let sign = grip.end == 0 ? -1.0 : 1.0
                let gripWorld = component.position + sign
                    * (component.terminalHalfSpan + CircuitsModel.endGripOffset)
                    * component.axis
                gripDrag = (grip, component.terminalPosition(1 - grip.end))
                partDrag = RelativeDrag(name: name, target: gripWorld, hand: hand)
                renderer.previewComponentID = grip.componentID
                model.select(id: grip.componentID)
                model.beginCarry(id: grip.componentID)
                return
            }
            if name.hasPrefix("tray-") {
                guard let kind = CircuitsModel.ComponentKind(
                        rawValue: String(name.dropFirst(5))) else { return }
                let templateWorld = SIMD3<Double>(candidate.position(relativeTo: renderer.viewRoot))
                guard let id = model.add(kind, at: templateWorld) else { return }
                trayDragID = id
                partDrag = RelativeDrag(name: name, target: templateWorld, hand: hand)
                renderer.previewComponentID = id
                renderer.setTrayTemplateHidden(name, true)
                return
            }
            if let id = UUID(uuidString: name),
               let component = model.components.first(where: { $0.id == id }) {
                partDrag = RelativeDrag(name: name, target: component.position, hand: hand)
                renderer.previewComponentID = id
                model.select(id: id)
                model.beginCarry(id: id)
                return
            }
            current = candidate.parent
        }
    }

    private func applyCircuitDrag(_ drag: RelativeDrag, hand: SIMD3<Double>) {
        let position = drag.position(forHand: hand)
        if let gripDrag {
            model.dragEnd(id: gripDrag.grip.componentID,
                          grabbedEnd: gripDrag.grip.end,
                          pivot: gripDrag.pivot, hand: position)
            model.breakOverstretchedWires(id: gripDrag.grip.componentID)
        } else if let id = trayDragID ?? UUID(uuidString: drag.name) {
            model.move(id: id, to: position)
            model.breakOverstretchedWires(id: id)
        }
    }

    /// The terminal an entity (or any ancestor) represents, if any.
    private func terminal(on entity: Entity) -> CircuitsModel.Terminal? {
        var current: Entity? = entity
        while let candidate = current {
            let name = candidate.name
            if name.hasPrefix("t0-") || name.hasPrefix("t1-"),
               let id = UUID(uuidString: String(name.dropFirst(3))) {
                return CircuitsModel.Terminal(
                    componentID: id, end: name.hasPrefix("t0-") ? 0 : 1)
            }
            current = candidate.parent
        }
        return nil
    }

    /// The closest connectable terminal within reach of the hand.
    private func nearestTerminal(
        to hand: SIMD3<Float>, excluding source: CircuitsModel.Terminal
    ) -> (terminal: CircuitsModel.Terminal, position: SIMD3<Double>)? {
        var best: (CircuitsModel.Terminal, SIMD3<Double>, Float)?
        for component in model.components {
            for end in 0...1 {
                let terminal = CircuitsModel.Terminal(componentID: component.id, end: end)
                guard terminal != source else { continue }
                let position = component.terminalPosition(end)
                let distance = simd_distance(SIMD3<Float>(position), hand)
                guard distance < 0.09 else { continue }
                if best == nil || distance < best!.2 {
                    best = (terminal, position, distance)
                }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Terminals ("t0-"/"t1-"), wires ("w-"), and levers ("k-") are tap
    /// targets; walk up the hierarchy to find whichever was hit.
    private func handleTap(on entity: Entity) {
        var current: Entity? = entity
        while let candidate = current {
            let name = candidate.name
            if name.hasPrefix("t0-") || name.hasPrefix("t1-") {
                let end = name.hasPrefix("t0-") ? 0 : 1
                if let id = UUID(uuidString: String(name.dropFirst(3))) {
                    let terminal = CircuitsModel.Terminal(componentID: id, end: end)
                    if model.multimeterArmed {
                        model.probeTap(terminal)
                    } else {
                        model.tapTerminal(terminal)
                    }
                }
                return
            }
            if name.hasPrefix("w-"), let id = UUID(uuidString: String(name.dropFirst(2))) {
                model.deleteWire(id: id)
                return
            }
            if name.hasPrefix("k-"), let id = UUID(uuidString: String(name.dropFirst(2))) {
                model.toggleSwitch(id: id)
                return
            }
            // A tap on a component body toggles its control ring.
            if let id = UUID(uuidString: name),
               model.components.contains(where: { $0.id == id }) {
                if ring.openID == id {
                    ring.openID = nil
                } else {
                    ring.openID = id
                    SoundPalette.play(.pop, on: entity, volume: 0.35)
                }
                return
            }
            current = candidate.parent
        }
        ring.openID = nil
    }

    /// The end-grip being pulled, parsed from "s0-"/"s1-" entity names.
    private func stretchTerminal(from name: String) -> CircuitsModel.Terminal? {
        guard name.hasPrefix("s0-") || name.hasPrefix("s1-"),
              let id = UUID(uuidString: String(name.dropFirst(3))) else { return nil }
        return CircuitsModel.Terminal(componentID: id, end: name.hasPrefix("s0-") ? 0 : 1)
    }

    /// Component bodies (named by UUID, marked by the white center knob)
    /// are carried directly. Tray templates ("tray-<kind>") spawn a copy
    /// on grab-begin; the copy follows the hand while the hidden template
    /// glides back to its slot on release. End grips ("s0-"/"s1-") swing
    /// the part around its opposite end — pinned where it was when the
    /// pull began — and set a wire's length from the hand's reach.
}

// CircuitsSelectedReadout lives in CircuitsControlsPanel.swift —
// it was rescued there when this view was briefly a station of the
// merged E&M world, and the panel is its right home anyway.

