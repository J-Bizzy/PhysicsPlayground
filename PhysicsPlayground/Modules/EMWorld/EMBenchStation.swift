//
//  EMBenchStation.swift
//  Physics Playground — Electricity & Magnetism
//
//  The circuit bench, as one station of the E&M world.
//
//  This is CircuitsSpaceView's body turned inside out. It was a View
//  because it was a whole module; now two apparatus share one
//  RealityView, and a scene can only have one set of gestures — so the
//  bench becomes an object that owns its renderer, its zoom rig, and
//  its drag state, and answers the world's questions: is this entity
//  mine, and if so, what does a pinch on it mean?
//
//  Nothing about the bench's own coordinates changed. It still believes
//  it stands at CircuitsRenderer.benchPivot; the world translates its
//  root to the left-hand seat on the arc. The one thing that DID move
//  is the layers bank, which used to hang off the bench's right flank —
//  the side that now faces the magnets across the middle of the world.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

@MainActor
final class EMBenchStation: Station {
    let model: CircuitsModel
    let renderer = CircuitsRenderer()

    /// Two-handed zoom on the bench. Electron View is a FLOOR under
    /// this same number rather than a competing 1x/4x flip, so "get in
    /// among the electrons" and "pull the bench open with both hands"
    /// are one continuous control.
    private let rig = SpatialScaleRig(
        pivot: CircuitsRenderer.benchPivot, range: 0.6...8.0, allowsTurn: false)

    /// `Station`'s accessor. Optional in the protocol because an
    /// apparatus may refuse to be scaled at all; the bench has one.
    var scaleRig: SpatialScaleRig? { rig }

    private let bloom = Bloom()
    /// Which component's ring is open — shared by the tap gesture and
    /// the render loop (see RingState's header).
    private let ring = RingState()
    private var layers: SpatialLayerBank?

    private var wireDragFrom: CircuitsModel.Terminal?
    private var partDrag: RelativeDrag?
    private var trayDragID: UUID?
    private var gripDrag: (grip: CircuitsModel.Terminal, pivot: SIMD3<Double>)?

    /// The world routes a gesture here when the entity it hit lives
    /// under this root.
    var root: Entity { renderer.root }

    init(model: CircuitsModel) {
        self.model = model
    }

    // MARK: Installation

    func install(into content: RealityViewContent) {
        content.add(renderer.root)
        renderer.viewRoot.addChild(bloom.root)

        let bank = SpatialLayerBank(
            accent: UIColor(DesignTokens.Palette.circuitsAccent),
            layers: [
                .init(id: "flow", label: "Electron flow", symbol: "circle.dotted",
                      isOn: { [model] in model.showElectronFlow },
                      toggle: { [model] in model.showElectronFlow.toggle() }),
                .init(id: "truespeed", label: "True speed", symbol: "tortoise",
                      isOn: { [model] in model.trueSpeedMode },
                      toggle: { [model] in model.trueSpeedMode.toggle() }),
                .init(id: "skyline", label: "Voltage skyline", symbol: "building.2",
                      isOn: { [model] in model.showVoltageHeights },
                      toggle: { [model] in model.showVoltageHeights.toggle() }),
                .init(id: "electron", label: "Electron view",
                      symbol: "arrow.down.left.and.arrow.up.right",
                      isOn: { [model] in model.electronView },
                      toggle: { [model] in model.electronView.toggle() }),
            ])
        // Under `root`, NOT `viewRoot`: the zoom reaches 8x, and a
        // control that grew with the bench would be a metre wide — and
        // Electron View's own switch would swell out of reach the
        // moment you used it.
        renderer.root.addChild(bank.root)
        layers = bank

        #if DEBUG
        if UserDefaults.standard.double(forKey: "trueSpeed") > 0 {
            model.trueSpeedMode = true
        }
        // `-viewScale.bench 2.5` bakes a committed scale in at launch,
        // so the scaled view can be screenshot-verified from the CLI —
        // the simulator has no second hand to pinch with. Addressed,
        // because the field station reads the same key (StationDebug).
        if let forcedScale = StationDebug.forcedScale(EMStation.bench.rawValue) {
            rig.updateMagnification(forcedScale)
            rig.endGesture()
        }
        // `-circRing 1` opens the first component's control ring at
        // launch, for CLI screenshots.
        if UserDefaults.standard.bool(forKey: "circRing"),
           let first = model.components.first {
            ring.openID = first.id
        }
        #endif
    }

    // MARK: Per-frame

    func tick(dt: Double, appModel: AppModel) {
        // The lab's placement in the user's room, plus this station's
        // seat on the arc. Both are pure display offsets, safe because
        // every grab here moves a body by hand DISPLACEMENT, which a
        // constant translation leaves untouched.
        renderer.root.position =
            appModel.labPlacement.offset + EMStationLayout.offset(.bench)
        model.step(dt: dt)
        // The bank stands beside the bench, at the bench's own depth so
        // it sits in the same ~15 deg band as the apparatus rather than
        // dropping out of view — and on the bench's OUTBOARD flank, so
        // it doesn't reach across the world toward the magnets.
        layers?.update(
            anchor: CircuitsRenderer.benchPivot
                + SIMD3(0.62 * Float(EMStationLayout.outboard(.bench)), -0.06, 0.16),
            viewer: appModel.room.headPosition.map { SIMD3<Float>($0) },
            dt: dt)
        // Ticked here every frame (not via the observation loop): a
        // steady DC circuit mutates nothing that observation reliably
        // re-fires on, but its electrons must keep drifting.
        renderer.handZoom = rig.liveScale
        renderer.tick(dt: dt, model: model)
        syncBloom(dt: dt, appModel: appModel)
    }

    // MARK: The far end of the circuit

    /// Where the feed line to the electromagnet leaves the bench, in
    /// SCENE space — the two terminals of the first inductor.
    ///
    /// Nil when the bench has no inductor, which is the same condition
    /// under which `inductorCurrent` is zero and the coil is dead. The
    /// cable and the current appear together or not at all.
    var inductorLeads: (SIMD3<Float>, SIMD3<Float>)? {
        guard let inductor = model.components.first(where: { $0.kind == .inductor })
        else { return nil }
        // Out of the bench's own zoomed, offset frame: at 4x the
        // terminals are somewhere quite different from where the model
        // put them, and the cable has to meet them where they look.
        return (renderer.viewRoot.convert(
                    position: SIMD3<Float>(inductor.terminalPosition(0)), to: nil),
                renderer.viewRoot.convert(
                    position: SIMD3<Float>(inductor.terminalPosition(1)), to: nil))
    }

    // MARK: Gestures

    /// Ring petals first; then the bench's own tap grammar (terminals
    /// wire, wires delete, levers flip, bodies toggle their ring).
    func handleTap(_ entity: Entity) -> Bool {
        if layers?.handleTap(entity) == true { return true }
        if bloom.handleTap(entity) { return true }
        handleBenchTap(on: entity)
        return true
    }

    func dragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        // Into the BENCH's own frame, not the room's. The bench can be
        // zoomed (Electron View, two hands) and moved (lab placement and
        // its seat on the arc); converting through viewRoot inverts all
        // of it exactly, so a part follows the hand 1:1 on screen at any
        // zoom instead of flying four times as far.
        let handF = renderer.viewRoot.convert(
            position: SIMD3<Float>(value.convert(
                value.location3D, from: .local, to: .scene)),
            from: nil)
        let hand = SIMD3<Double>(handF)
        if bloom.updateGrip(hand: handF) { return }
        if wireDragFrom == nil, partDrag == nil {
            if bloom.beginGrip(value.entity, hand: handF) { return }
            beginCircuitDrag(entity: value.entity, hand: hand)
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

    func dragEnded(_ value: EntityTargetValue<DragGesture.Value>) {
        bloom.endGrip()
        defer {
            renderer.hideRubberBand()
            renderer.previewComponentID = nil
            wireDragFrom = nil
            partDrag = nil
            trayDragID = nil
            gripDrag = nil
            model.endCarry()
        }
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

    // MARK: The part ring

    /// A part's own controls. Its value has no size of its own, so the
    /// grip's honesty is the CONSEQUENCE — pull a bulb's resistance up
    /// and it visibly dims, pull the battery's volts and the electron
    /// drift quickens while your hand is still moving. Switches get a
    /// petal instead, because open and closed is not a continuum.
    private func syncBloom(dt: Double, appModel: AppModel) {
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
                                tint: UIColor(white: 0.45, alpha: 1)) { [model] in
                model.toggleSwitch(id: uuid)
            })
        }
        if part.failed {
            // A blown bulb's most-wanted action, finally reachable.
            petals.append(.init(name: "Replace", symbol: "arrow.triangle.2.circlepath",
                                tint: UIColor(red: 0.95, green: 0.60,
                                              blue: 0.15, alpha: 1)) { [model] in
                model.replaceFailed(id: uuid)
            })
        } else if model.isWired(id: uuid) {
            petals.append(.init(name: "Detach", symbol: "scissors",
                                tint: UIColor(white: 0.45, alpha: 1)) { [model] in
                model.detachComponent(id: uuid)
            })
        }
        petals.append(.init(name: "Delete", symbol: "trash",
                            tint: UIColor(red: 0.85, green: 0.25,
                                          blue: 0.25, alpha: 1)) { [model] in
            model.removeComponent(id: uuid)
        })

        let range = CircuitsModel.valueRange(for: part.kind)
        bloom.retarget(
            uuid,
            petals: petals,
            grip: range.upperBound > range.lowerBound
                ? .init(name: "Value",
                        range: range,
                        read: { [model] in model.componentValue(id: uuid) },
                        write: { [model] in model.setComponentValue(id: uuid, $0) },
                        format: { CircuitsModel.formatValue($0, for: part.kind) },
                        radius: { 0.05 })
                : nil)

        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(part.position),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }

    // MARK: Hit resolution

    /// Component bodies (named by UUID, marked by the white center knob)
    /// are carried directly. Tray templates ("tray-<kind>") spawn a copy
    /// on grab-begin; the copy follows the hand while the hidden template
    /// glides back to its slot on release. End grips ("s0-"/"s1-") swing
    /// the part around its opposite end — pinned where it was when the
    /// pull began — and set a wire's length from the hand's reach.
    private func beginCircuitDrag(entity: Entity, hand: SIMD3<Double>) {
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
                let templateWorld = SIMD3<Double>(
                    candidate.position(relativeTo: renderer.viewRoot))
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
    private func handleBenchTap(on entity: Entity) {
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
}
