//
//  CircuitsRenderer.swift
//  Physics Playground — Circuits module
//
//  Renders the circuit lab: recognizable little components (a cylinder
//  battery with a + cap, banded resistors wearing their real color
//  code, glass bulbs that glow with their true power, electrolytic
//  capacitors, flip switches), copper wires that follow their terminals
//  as you carry components around the room, and — the show — electron
//  dots drifting along every live wire, minus to plus.
//
//  Components and wires are created/destroyed on edit (rare); the
//  per-frame path is transform writes: component roots, wire cylinders
//  (position/orientation/stretch — no mesh regeneration), and pooled
//  electron dots.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class CircuitsRenderer {
    let root = Entity()
    var subscriptions: [EventSubscription] = []

    var manipulatingComponentID: UUID?

    /// Parent for the selected component's readout attachment.
    let selectedAnchor = Entity()

    private struct ComponentVisual {
        let holder: Entity
        let body: ModelEntity
        var terminals: [ModelEntity]
        let label: ModelEntity
        let halo: ModelEntity
        var glow: ModelEntity?
        var filament: ModelEntity?
        var lever: ModelEntity?
        /// Motors only: the propeller that spins with the shaft.
        var rotor: Entity?
        /// Wires only: the orange end grips ("s0-"/"s1-") pulled to
        /// change the length.
        var stretchHandles: [ModelEntity] = []
        var labelText = ""
        var glowBucket = -1
        var resistorCodeKey = ""
    }

    private var visuals: [UUID: ComponentVisual] = [:]
    private var wireEntities: [UUID: ModelEntity] = [:]
    private var wirePhases: [UUID: Double] = [:]

    // MARK: Voltage skyline (potential as terrain)
    /// The datum the towers rise from — a common floor so heights are
    /// comparable, floated above the bench.
    private static let skylineDatumY: Float = 1.62
    private static let voltsToMeters: Float = 0.028
    private let skylineRoot = Entity()
    private var towers: [ModelEntity] = []
    private var towerCaps: [ModelEntity] = []
    private var towerThreads: [ModelEntity] = []
    private var towerLabels: [ModelEntity] = []
    private var towerLabelPivots: [Entity] = []
    private var towerLabelCache: [String: MeshResource] = [:]
    private var towerLabelKeys: [String] = []

    /// The wire rod's generated mesh length; live length is a scale on top.
    private static let wireBaseLength: Float = 0.12
    /// The end grip being pulled right now (system-dragged — don't
    /// reposition it), if any.
    var stretchingHandle: CircuitsModel.Terminal?
    /// The opposite end's world position, captured when the pull began —
    /// the fixed pivot the part swings around.
    var swingPivot: SIMD3<Double>?

    /// The part's aim as the hand actually left it — the system may have
    /// twisted the holder during a carry, and the model adopts that.
    func liveAxis(of id: UUID) -> SIMD3<Double>? {
        guard let visual = visuals[id] else { return nil }
        return SIMD3<Double>(visual.holder.orientation.act([1, 0, 0]))
    }

    private static let electronBudget = 200
    private let electronPool: EntityPool<Void>
    private var electronsVisible = false

    private let audioEmitter = Entity()
    private var lastSoundID = 0
    private var appliedResistorTextureVersion = -1

    private let copperMaterial = SimpleMaterial(
        color: DesignTokens.Palette.copperUI, roughness: 0.35, isMetallic: true)
    private var glowMaterials: [UnlitMaterial] = []


    /// The bench's VIEW transform.
    ///
    /// `root` belongs to the lab placement — where in your room the
    /// workshop sits. `viewRoot` belongs to the ZOOM, and the two used
    /// to fight: Electron View wrote root.position and root.scale every
    /// frame while the lab offset wrote root.position too, so whichever
    /// ran last won and moving the lab did nothing here. Splitting them
    /// gives each one transform of its own, which is also what lets the
    /// two-handed gesture in.
    let viewRoot = Entity()

    init() {
        root.addChild(viewRoot)
        root.addChild(Lighting.keyLight())
        // Bulb glow brightness buckets (materials made once).
        glowMaterials = (0..<6).map { step in
            var material = UnlitMaterial(
                color: UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1))
            material.blending = .transparent(
                opacity: .init(floatLiteral: Float(step) / 5 * 0.55))
            return material
        }

        // Electrons you can't miss: a white-hot core inside a cyan glow.
        let coreMaterial = UnlitMaterial(color: UIColor(red: 0.8, green: 1.0, blue: 1.0, alpha: 1))
        var haloMaterial = UnlitMaterial(color: DesignTokens.Palette.electronUI)
        haloMaterial.blending = .transparent(opacity: 0.35)
        let coreMesh = MeshResource.generateSphere(radius: 0.0034)
        let haloMesh = MeshResource.generateSphere(radius: 0.0075)
        electronPool = EntityPool(budget: Self.electronBudget) { container in
            let core = ModelEntity(mesh: coreMesh, materials: [coreMaterial])
            core.addChild(ModelEntity(mesh: haloMesh, materials: [haloMaterial]))
            container.addChild(core)
        }
        viewRoot.addChild(electronPool.root)

        selectedAnchor.components.set(BillboardComponent())
        viewRoot.addChild(selectedAnchor)

        skylineRoot.isEnabled = false
        viewRoot.addChild(skylineRoot)

        audioEmitter.components.set(SpatialAudioComponent())
        viewRoot.addChild(audioEmitter)

        buildTray()
    }

    // MARK: The parts tray (grab a part and a copy lifts off it)

    /// Tray templates by entity name ("tray-<kind>"), for hiding while a
    /// copy is being pulled off.
    private var trayTemplates: [String: ModelEntity] = [:]
    /// Live tray drags: template entity name → the spawned component
    /// following the hand.
    var trayDragIDs: [String: UUID] = [:]

    func setTrayTemplateHidden(_ name: String, _ hidden: Bool) {
        trayTemplates[name]?.components.set(OpacityComponent(opacity: hidden ? 0 : 1))
    }

    private func buildTray() {
        let tray = Entity()
        // Coffee-table height just below the build volume, close enough
        // to reach without leaning.
        tray.position = [0, 1.02, -0.85]
        viewRoot.addChild(tray)

        let kinds = CircuitsModel.ComponentKind.allCases
        // Two balanced rows, however many parts there are.
        let columns = (kinds.count + 1) / 2
        let slabWidth = Float(columns - 1) * 0.15 + 0.18

        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: .white)
        glass.roughness = 0.15
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        let slab = ModelEntity(
            mesh: .generateBox(size: [slabWidth, 0.015, 0.3], cornerRadius: 0.008),
            materials: [glass]
        )
        tray.addChild(slab)

        for (index, kind) in kinds.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = Float(column) * 0.15 - Float(columns - 1) * 0.075
            let z: Float = row == 0 ? -0.06 : 0.06
            let template = makeBody(for: CircuitsModel.Component(
                id: UUID(), kind: kind, position: .zero, value: kind.defaultValue))
            template.scale = SIMD3(repeating: 0.8)
            template.position = [x, 0.05, z]
            template.name = "tray-\(kind.rawValue)"
            // A drag target: pulling it spawns a copy that follows the
            // hand's displacement; the template itself never moves.
            Grabbable.configureTouchTarget(template, collisionRadius: 0.06)
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = LocalizedStringResource(
                stringLiteral: "Grab a \(kind.displayName) from the tray")
            template.components.set(accessibility)
            tray.addChild(template)
            trayTemplates[template.name] = template

            // A small flat label on the tray surface. Near-white type at
            // 85% opacity on a pale glass tray in a pale room was simply
            // unreadable — every part name vanished. Dark, opaque and a
            // little larger: the tray is the light surface, so the type
            // on it has to be the dark one.
            let labelMesh = MeshResource.generateText(
                kind.displayName, extrusionDepth: 0.0006,
                font: .systemFont(ofSize: 0.017, weight: .semibold))
            let label = ModelEntity(
                mesh: labelMesh,
                materials: [UnlitMaterial(color: UIColor(white: 0.08, alpha: 1))])
            let bounds = labelMesh.bounds
            label.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            label.position = [x - (bounds.min.x + bounds.max.x) / 2, 0.009, z + 0.052]
            tray.addChild(label)
        }
    }

    // MARK: Render clock

    /// Per-frame entry, driven straight from SceneEvents.Update: advance
    /// the electron drift by real elapsed time, then write every
    /// transform. Direct ticking (the hub/Gravity-field pattern) rather
    /// than the observation render loop — a steady DC circuit gave
    /// withObservationTracking nothing it reliably re-fired on, which
    /// froze the flow animation whenever nothing else was changing.
    /// Drives the armed-terminal pulse.
    private var pendingPulsePhase = 0.0

    // MARK: Connection previews & drag-to-wire

    /// While this part is carried (or its end pulled), ghost wires show
    /// exactly what a release would connect.
    var previewComponentID: UUID?
    /// Terminals currently highlighted as connection targets.
    private(set) var previewTargets: Set<CircuitsModel.Terminal> = []
    /// The terminal the drag-to-wire rubber band is hovering.
    var rubberTargetTerminal: CircuitsModel.Terminal?

    private var previewWireEntities: [ModelEntity] = []
    private lazy var rubberBand: ModelEntity = {
        let band = ModelEntity(
            mesh: .generateCylinder(height: 1, radius: 0.0045),
            materials: [Self.previewMaterial])
        band.isEnabled = false
        viewRoot.addChild(band)
        return band
    }()
    private static let previewMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: UIColor(
            red: 0.35, green: 1.0, blue: 0.55, alpha: 1))
        material.blending = .transparent(opacity: 0.65)
        return material
    }()

    private func stretch(_ entity: ModelEntity, from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let direction = b - a
        let length = simd_length(direction)
        guard length > 1e-4 else { entity.isEnabled = false; return }
        entity.isEnabled = true
        entity.position = (a + b) / 2
        entity.orientation = VectorFieldArrows.rotationFromYAxis(to: direction / length)
        entity.scale = SIMD3(1, length, 1)
    }

    /// The live rubber band from a terminal to the hand (or its target).
    func showRubberBand(from a: SIMD3<Float>, to b: SIMD3<Float>) {
        stretch(rubberBand, from: a, to: b)
    }

    func hideRubberBand() {
        rubberBand.isEnabled = false
        rubberTargetTerminal = nil
    }

    private func syncConnectionPreviews(_ model: CircuitsModel) {
        var pairs: [(SIMD3<Float>, SIMD3<Float>, CircuitsModel.Terminal)] = []
        if let id = previewComponentID {
            for pair in model.autoConnectCandidates(id: id) {
                if let a = terminalWorld(pair.from, model),
                   let b = terminalWorld(pair.to, model) {
                    pairs.append((a, b, pair.to))
                }
            }
        }
        previewTargets = Set(pairs.map(\.2))
        if let rubber = rubberTargetTerminal { previewTargets.insert(rubber) }

        while previewWireEntities.count < pairs.count {
            let ghost = ModelEntity(
                mesh: .generateCylinder(height: 1, radius: 0.0045),
                materials: [Self.previewMaterial])
            ghost.isEnabled = false
            viewRoot.addChild(ghost)
            previewWireEntities.append(ghost)
        }
        for (index, ghost) in previewWireEntities.enumerated() {
            if index < pairs.count {
                stretch(ghost, from: pairs[index].0, to: pairs[index].1)
            } else {
                ghost.isEnabled = false
            }
        }
    }

    /// The zoom, as ONE number.
    ///
    /// Electron View used to be a discrete 1× / 4× flip. It is now just
    /// a floor under the same continuous zoom the two hands drive, so
    /// "get closer to the electrons" and "pull the bench open with your
    /// hands" are the same gesture rather than two competing systems —
    /// and the user can stop anywhere between.
    private var benchScale: Float = 1
    static let benchPivot = SIMD3<Float>(0, 1.25, -0.85)
    /// Set by the space view from the two-handed scale rig.
    var handZoom: Float = 1
    static let electronViewZoom: Float = 4.0

    /// Where the zoom is heading: the larger of the hands' zoom and the
    /// Electron View floor, so switching Electron View on while already
    /// zoomed in never yanks the bench smaller.
    private func targetZoom(_ model: CircuitsModel) -> Float {
        max(handZoom, model.electronView ? Self.electronViewZoom : 1)
    }

    /// The zoom the bench is actually showing, for the readout.
    var currentZoom: Float { benchScale }

    // MARK: The bench's hum

    /// A mains hum whose loudness rides the total current the bench is
    /// carrying, and whose pitch rises with the power it dissipates.
    ///
    /// A live circuit is not silent, and a circuit that has just gone
    /// dead should not sound the same as one delivering two amps. This
    /// is the module's one continuous voice: close the switch and the
    /// bench comes audibly alive, short it and the hum climbs, open it
    /// and the room goes quiet — all without looking at a readout.
    private var hum: ToneVoice?

    private func tickHum(_ model: CircuitsModel) {
        if hum == nil { hum = ToneVoice(on: audioEmitter, range: (-58)...(-26)) }
        guard hum?.start() == true else { return }
        guard !model.isPaused else { hum?.mute(); return }

        let current = model.components
            .compactMap { model.readouts[$0.id]?.amps }
            .map(abs).max() ?? 0
        let power = model.components
            .compactMap { model.readouts[$0.id]?.watts }
            .map(abs).reduce(0, +)
        // 50 Hz-ish fundamental, climbing a little as the bench works
        // harder, so a short circuit is audibly frantic.
        hum?.update(pitchHz: 52 + min(power, 12) * 7,
                    loudness: Sonification.loudness(current, full: 1.5, knee: 0.55))
    }

    func tick(dt: Double, model: CircuitsModel) {
        tickHum(model)
        pendingPulsePhase += dt * 6
        let target = targetZoom(model)
        if abs(benchScale - target) > 1e-3 {
            // Eased toward the target so a flick of Electron View glides
            // rather than snaps; a live hand gesture is already smooth,
            // and the same easing keeps it from lagging perceptibly.
            benchScale += (target - benchScale) * Float(min(dt * 8, 1))
            viewRoot.scale = SIMD3(repeating: benchScale)
            viewRoot.position = Self.benchPivot * (1 - benchScale)
        }
        render(model, dt: dt)
    }

    private func render(_ model: CircuitsModel, dt: Double) {
        if appliedResistorTextureVersion != CircuitTextures.version {
            appliedResistorTextureVersion = CircuitTextures.version
            for id in visuals.keys { visuals[id]?.resistorCodeKey = "" }
        }
        syncConnectionPreviews(model)
        if let event = model.soundEvent, event.id != lastSoundID {
            lastSoundID = event.id
            audioEmitter.position = SIMD3<Float>(event.position)
            SoundPalette.play(event.kind, on: audioEmitter, volume: event.volume)
        }

        syncComponents(model)
        spinMotors(model, dt: dt)
        syncWires(model)
        syncElectrons(model, dt: dt)
        syncVoltageSkyline(model)

        if let selected = model.selectedComponent {
            selectedAnchor.isEnabled = true
            selectedAnchor.position = SIMD3<Float>(selected.position) + SIMD3(0, 0.14, 0)
        } else {
            selectedAnchor.isEnabled = false
        }
    }

    // MARK: Voltage skyline

    /// Warm for high potential, cool for low — the same language the
    /// gradient wires speak, saturated for the towers.
    private static func potentialColor(_ volts: Double, span: Double) -> UIColor {
        let t = span > 1e-6 ? CGFloat(max(-1, min(1, volts / span))) : 0   // −1…1
        if t >= 0 {
            return UIColor(red: 1.0, green: 0.6 - 0.35 * t, blue: 0.3 - 0.25 * t, alpha: 1)
        }
        return UIColor(red: 0.35 + 0.35 * t, green: 0.65 + 0.2 * t, blue: 1.0, alpha: 1)
    }

    /// Raises a translucent glowing tower over every circuit node to a
    /// height equal to its voltage, linked to the node by a faint
    /// thread. Potential becomes terrain you can compare at a glance —
    /// the battery towers up, ground sits at the datum, each component
    /// steps the height down (Kirchhoff's loop law, made spatial).
    private func syncVoltageSkyline(_ model: CircuitsModel) {
        skylineRoot.isEnabled = model.showVoltageHeights
        guard model.showVoltageHeights else { return }

        let nodes = model.nodePotentials
        let span = max(abs(model.voltageSpan.min), abs(model.voltageSpan.max), 1.0)
        while towers.count < nodes.count { growTower() }

        for (index, tower) in towers.enumerated() {
            guard index < nodes.count else {
                tower.isEnabled = false
                towerCaps[index].isEnabled = false
                towerThreads[index].isEnabled = false
                towerLabelPivots[index].isEnabled = false
                continue
            }
            let node = nodes[index]
            let base = SIMD3<Float>(Float(node.position.x), Self.skylineDatumY,
                                    Float(node.position.z))
            let height = Float(node.voltage) * Self.voltsToMeters
            let color = Self.potentialColor(node.voltage, span: span)

            // The tower: a slim column from the datum to the potential.
            tower.isEnabled = true
            let mag = max(abs(height), 0.001)
            tower.position = base + SIMD3(0, height / 2, 0)
            tower.scale = SIMD3(1, mag / 0.1, 1)   // base mesh is 0.1 tall
            setEmissive(tower, color, intensity: 0.6)

            // A glowing cap disc at the top.
            let cap = towerCaps[index]
            cap.isEnabled = true
            cap.position = base + SIMD3(0, height, 0)
            setEmissive(cap, color, intensity: 0.9)

            // A faint thread from the node's real position up to the base.
            let thread = towerThreads[index]
            let nodeWorld = SIMD3<Float>(node.position)
            thread.isEnabled = true
            thread.position = (nodeWorld + base) / 2
            let threadLen = max(simd_distance(nodeWorld, base), 0.001)
            thread.scale = SIMD3(1, threadLen / 0.1, 1)
            thread.orientation = VectorFieldArrows.rotationFromYAxis(
                to: simd_normalize(base - nodeWorld + SIMD3(0, 1e-5, 0)))

            // The voltage, floating at the cap (the billboard pivot
            // rides the world spot; the label centers within it).
            let pivot = towerLabelPivots[index]
            pivot.isEnabled = true
            pivot.position = base + SIMD3(0, height + (height >= 0 ? 0.05 : -0.06), 0)
            let text = String(format: "%.1f V", node.voltage)
            if towerLabelKeys[index] != text {
                towerLabelKeys[index] = text
                let mesh = towerLabelMesh(text)
                towerLabels[index].model = ModelComponent(
                    mesh: mesh, materials: [UnlitMaterial(color: color)])
                let bounds = mesh.bounds
                towerLabels[index].position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
            }
        }
    }

    private func setEmissive(_ entity: ModelEntity, _ color: UIColor, intensity: Float) {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = 0.4
        material.blending = .transparent(opacity: .init(floatLiteral: 0.6))
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = intensity
        entity.model?.materials = [material]
    }

    private func growTower() {
        let column = ModelEntity(mesh: .generateBox(
            size: [0.012, 0.1, 0.012], cornerRadius: 0.003))
        skylineRoot.addChild(column)
        towers.append(column)

        let cap = ModelEntity(mesh: .generateCylinder(height: 0.006, radius: 0.02))
        skylineRoot.addChild(cap)
        towerCaps.append(cap)

        var threadMaterial = UnlitMaterial(color: .white)
        threadMaterial.blending = .transparent(opacity: 0.2)
        let thread = ModelEntity(
            mesh: .generateCylinder(height: 0.1, radius: 0.0009),
            materials: [threadMaterial])
        skylineRoot.addChild(thread)
        towerThreads.append(thread)

        let label = ModelEntity()
        let pivot = Entity()
        pivot.components.set(BillboardComponent())
        skylineRoot.addChild(pivot)
        pivot.addChild(label)
        towerLabels.append(label)
        towerLabelPivots.append(pivot)
        towerLabelKeys.append("")
    }

    private func towerLabelMesh(_ text: String) -> MeshResource {
        if let cached = towerLabelCache[text] { return cached }
        if towerLabelCache.count > 200 { towerLabelCache.removeAll() }
        let mesh = MeshResource.generateText(
            text, extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.03, weight: .semibold))
        towerLabelCache[text] = mesh
        return mesh
    }

    // MARK: Components

    /// Turn each motor's propeller at its live angular speed (rad/s),
    /// accumulating on the rotor's own orientation — direction and all,
    /// so reversing the battery reverses the spin.
    private func spinMotors(_ model: CircuitsModel, dt: Double) {
        for component in model.components where component.kind == .motor {
            guard let rotor = visuals[component.id]?.rotor else { continue }
            let delta = Float(component.motorSpeed * dt)
            guard abs(delta) > 1e-6 else { continue }
            rotor.orientation = simd_quatf(angle: delta, axis: [1, 0, 0]) * rotor.orientation
        }
    }

    private func syncComponents(_ model: CircuitsModel) {
        // Remove visuals whose components are gone.
        let liveIDs = Set(model.components.map(\.id))
        for id in visuals.keys where !liveIDs.contains(id) {
            visuals[id]?.holder.removeFromParent()
            visuals[id] = nil
            wirePhases[id] = nil  // a removed jumper's electron phase
        }

        for component in model.components {
            var visual = visuals[component.id] ?? makeVisual(for: component)

            // While the hand carries the holder the system owns its
            // transform — including any twist, which the model adopts
            // on release.
            if component.id != manipulatingComponentID {
                visual.holder.position = SIMD3<Float>(component.position)
                // Aim the whole part along its model axis — but only when
                // the axis actually moved. The hand's roll is legitimate
                // orientation; snapping it away on release reads as a
                // shake.
                let target = simd_normalize(SIMD3<Float>(component.axis))
                let current = visual.holder.orientation.act([1, 0, 0])
                if simd_dot(current, target) < 0.99995 {
                    visual.holder.orientation = simd_quatf(from: [1, 0, 0], to: target)
                }
            }
            visual.halo.isEnabled = component.id == model.selectedID

            // Terminals and end grips ride the ends of the (possibly
            // stretched) span; a grip the hand is pulling is
            // system-dragged — leave it be. Pending terminal glows larger.
            let half = Float(component.terminalHalfSpan)
            for (end, terminal) in visual.terminals.enumerated() {
                let sign: Float = end == 0 ? -1 : 1
                terminal.position = SIMD3(sign * half, 0, 0)
                let key = CircuitsModel.Terminal(componentID: component.id, end: end)
                let isPending = model.pendingTerminal == key
                // The armed terminal breathes, and preview targets swell,
                // so there's never doubt what the next action will wire.
                let isProbed = model.probeA == key || model.probeB == key
                terminal.scale = SIMD3(repeating: isPending
                    ? Float(1.6 + 0.35 * sin(pendingPulsePhase))
                    : (previewTargets.contains(key) ? 1.5 : (isProbed ? 1.35 : 1.0)))

                let beingPulled = stretchingHandle ==
                    CircuitsModel.Terminal(componentID: component.id, end: end)
                if !beingPulled, visual.stretchHandles.count == 2 {
                    visual.stretchHandles[end].position =
                        SIMD3(sign * (half + Float(CircuitsModel.endGripOffset)), 0, 0)
                }
            }

            // Live label.
            let text = labelText(for: component)
            if visual.labelText != text {
                visual.labelText = text
                setLabel(visual.label, text: text)
            }

            switch component.kind {
            case .bulb:
                let watts = model.readouts[component.id]?.watts ?? 0
                let bucket = min(Int((watts / 3.0) * 5), 5)
                if visual.glowBucket != bucket {
                    visual.glowBucket = bucket
                    visual.glow?.model?.materials = [glowMaterials[max(bucket, 0)]]
                    var filamentMaterial = UnlitMaterial(
                        color: bucket > 0 ? UIColor(red: 1, green: 0.75, blue: 0.3, alpha: 1)
                                          : UIColor(white: 0.35, alpha: 1))
                    filamentMaterial.blending = .transparent(opacity: bucket > 0 ? 1.0 : 0.8)
                    visual.filament?.model?.materials = [filamentMaterial]
                }
            case .led:
                let amps = abs(model.readouts[component.id]?.amps ?? 0)
                let bucket = component.failed ? 0 : min(Int(amps / 0.005), 5)
                if visual.glowBucket != bucket {
                    visual.glowBucket = bucket
                    visual.glow?.model?.materials = [glowMaterials[max(bucket, 0)]]
                }
            case .switcher:
                visual.lever?.orientation = simd_quatf(
                    angle: component.isClosed ? 0 : 0.6, axis: [0, 0, 1])
            case .resistor:
                let key = resistorKey(component.value)
                if visual.resistorCodeKey != key {
                    if let texture = CircuitTextures.resistorTexture(ohms: component.value) {
                        visual.resistorCodeKey = key
                        var material = PhysicallyBasedMaterial()
                        material.baseColor = .init(tint: .white, texture: .init(texture))
                        material.roughness = 0.6
                        visual.body.model?.materials = [material]
                    }
                }
            case .wire:
                // The rod stretches along its axis to the wire's live
                // length (terminal/grip placement is handled above).
                let stretch = Float(component.value) / Self.wireBaseLength
                if abs(visual.body.scale.y - stretch) > 1e-4 {
                    visual.body.scale = [1, stretch, 1]
                }
            default:
                break
            }
            visuals[component.id] = visual
        }
    }

    private func resistorKey(_ ohms: Double) -> String {
        guard let code = CircuitSolver.colorBands(ohms: ohms) else { return "?" }
        return "\(code.digit1)-\(code.digit2)-\(code.multiplier)"
    }

    /// Motor speed as coarse RPM (rounded so the label doesn't thrash
    /// while the rotor accelerates).
    private static func motorRPMLabel(_ speed: Double) -> String {
        let rpm = (abs(speed) * 60 / (2 * .pi) / 50).rounded() * 50
        return String(format: "%.0f rpm", rpm)
    }

    private func labelText(for component: CircuitsModel.Component) -> String {
        switch component.kind {
        case .battery: String(format: "%.1f V", component.value)
        case .resistor, .bulb:
            component.value >= 1000
                ? String(format: "%.1f kΩ", component.value / 1000)
                : String(format: "%.0f Ω", component.value)
        case .capacitor:
            component.value >= 1e-3
                ? String(format: "%.1f mF", component.value * 1000)
                : String(format: "%.0f µF", component.value * 1e6)
        case .switcher: component.isClosed ? "closed" : "open"
        case .acSource: String(format: "%.1f V~", component.value)
        case .inductor: String(format: "%.2f H", component.value)
        case .led: component.failed ? "burned out" : "LED"
        case .motor: Self.motorRPMLabel(component.motorSpeed)
        case .fuse: component.failed
            ? "blown"
            : String(format: "%.1f A fuse", component.value)
        case .wire:
            component.value >= 0.995
                ? String(format: "%.2f m", component.value)
                : String(format: "%.0f cm", component.value * 100)
        }
    }

    private func setLabel(_ label: ModelEntity, text: String) {
        guard !text.isEmpty else {
            label.model = nil
            return
        }
        let mesh = MeshResource.generateText(
            text, extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.02, weight: .medium))
        label.model = ModelComponent(
            mesh: mesh,
            materials: [UnlitMaterial(color: UIColor(white: 0.95, alpha: 0.9))])
        let bounds = mesh.bounds
        label.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
    }

    private func makeVisual(for component: CircuitsModel.Component) -> ComponentVisual {
        // The HOLDER is the manipulation target, so a carried part brings
        // its terminals, grips, label, and halo along — and wires stay
        // pinned to real terminal entities the whole way.
        let holder = Entity()
        holder.name = component.id.uuidString
        holder.position = SIMD3<Float>(component.position)
        Grabbable.configureTouchTarget(holder, collisionRadius: 0.075)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(component.kind.displayName). Drag to move; pinch its terminals to wire.")
        holder.components.set(accessibility)
        viewRoot.addChild(holder)

        // The visible body, shaped per kind.
        let body = makeBody(for: component)
        holder.addChild(body)

        // Terminals: copper spheres, tap targets for wiring.
        var terminals: [ModelEntity] = []
        let terminalMesh = MeshResource.generateSphere(radius: 0.013)
        for end in 0...1 {
            let terminal = ModelEntity(mesh: terminalMesh, materials: [copperMaterial])
            terminal.name = "t\(end)-\(component.id.uuidString)"
            terminal.position = SIMD3(
                Float(end == 0 ? -component.terminalHalfSpan : component.terminalHalfSpan), 0, 0)
            terminal.components.set(InputTargetComponent())
            terminal.components.set(CollisionComponent(
                shapes: [.generateSphere(radius: 0.042)]))
            terminal.components.set(HoverEffectComponent())
            var terminalAccessibility = AccessibilityComponent()
            terminalAccessibility.isAccessibilityElement = true
            terminalAccessibility.label = LocalizedStringResource(stringLiteral:
                "\(component.kind.displayName) terminal. Pinch this then another terminal to wire them.")
            terminal.components.set(terminalAccessibility)
            holder.addChild(terminal)
            terminals.append(terminal)

            // A short lead from the body toward the terminal — except on
            // wires, whose rod already spans terminal to terminal.
            if component.kind != .wire {
                let lead = ModelEntity(
                    mesh: .generateCylinder(height: 0.045, radius: 0.0028),
                    materials: [copperMaterial])
                lead.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                lead.position = SIMD3(Float(end == 0 ? -0.062 : 0.062), 0, 0)
                holder.addChild(lead)
            }
        }

        // Orange end grips just past the terminals: pull one and the part
        // swings around its other end (wires also take their length from
        // the pull). Separate from the copper terminals so quick pinches
        // there still arm tap-tap wiring.
        let gripMaterial = SimpleMaterial(
            color: UIColor(red: 0.9, green: 0.45, blue: 0.15, alpha: 1),
            roughness: 0.5, isMetallic: false)
        var stretchHandles: [ModelEntity] = []
        for end in 0...1 {
            let grip = ModelEntity(
                mesh: .generateSphere(radius: 0.012), materials: [gripMaterial])
            grip.name = "s\(end)-\(component.id.uuidString)"
            let half = Float(component.terminalHalfSpan + CircuitsModel.endGripOffset)
            grip.position = SIMD3(end == 0 ? -half : half, 0, 0)
            Grabbable.configureTouchTarget(grip, collisionRadius: 0.03)
            var gripAccessibility = AccessibilityComponent()
            gripAccessibility.isAccessibilityElement = true
            gripAccessibility.label = LocalizedStringResource(stringLiteral:
                "End grip. Pull to aim the \(component.kind.displayName) in space"
                + (component.kind == .wire ? " and change its length." : "."))
            grip.components.set(gripAccessibility)
            holder.addChild(grip)
            stretchHandles.append(grip)
        }

        // The white center knob: the part's carry handle, marking where
        // to grab when you want to move it rather than aim it.
        var knobMaterial = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        knobMaterial.blending = .transparent(opacity: 0.85)
        let knob = ModelEntity(
            mesh: .generateSphere(radius: 0.009), materials: [knobMaterial])
        holder.addChild(knob)

        // Selection halo.
        var haloMaterial = UnlitMaterial(color: .white)
        haloMaterial.blending = .transparent(opacity: 0.18)
        let halo = ModelEntity(
            mesh: .generateSphere(radius: 0.085), materials: [haloMaterial])
        halo.isEnabled = false
        holder.addChild(halo)

        // Value label beneath, billboarded.
        let label = ModelEntity()
        let labelPivot = Entity()
        labelPivot.position = [0, -0.065, 0]
        labelPivot.components.set(BillboardComponent())
        labelPivot.addChild(label)
        holder.addChild(labelPivot)

        var visual = ComponentVisual(
            holder: holder, body: body, terminals: terminals,
            label: label, halo: halo)
        visual.stretchHandles = stretchHandles

        // Kind-specific extras.
        switch component.kind {
        case .bulb:
            let filament = ModelEntity(
                mesh: .generateBox(size: [0.016, 0.004, 0.004]),
                materials: [UnlitMaterial(color: UIColor(white: 0.35, alpha: 1))])
            filament.position = [0, 0.012, 0]
            body.addChild(filament)
            visual.filament = filament

            let glow = ModelEntity(
                mesh: .generateSphere(radius: 0.055), materials: [glowMaterials[0]])
            glow.position = [0, 0.012, 0]
            holder.addChild(glow)
            visual.glow = glow
        case .led:
            let glow = ModelEntity(
                mesh: .generateSphere(radius: 0.03), materials: [glowMaterials[0]])
            glow.position = [0, 0.012, 0]
            holder.addChild(glow)
            visual.glow = glow
        case .motor:
            // A two-blade propeller on the shaft end, spun each frame by
            // the motor's live speed.
            let rotor = Entity()
            rotor.position = [0.05, 0, 0]
            let hub = ModelEntity(
                mesh: .generateSphere(radius: 0.008),
                materials: [SimpleMaterial(color: UIColor(white: 0.6, alpha: 1),
                                           roughness: 0.3, isMetallic: true)])
            rotor.addChild(hub)
            let accent = UIColor(red: 0.2, green: 0.85, blue: 0.75, alpha: 1)
            for axis: SIMD3<Float> in [[0, 1, 0], [0, 0, 1]] {
                let blade = ModelEntity(
                    mesh: .generateBox(size: [0.005, 0.05, 0.004], cornerRadius: 0.002),
                    materials: [UnlitMaterial(color: accent)])
                blade.orientation = simd_quatf(from: [0, 1, 0], to: axis)
                rotor.addChild(blade)
            }
            holder.addChild(rotor)
            visual.rotor = rotor
        case .switcher:
            // The lever pivots at the left contact; the tap target is the
            // pivot so the whole arm is pinchable.
            let pivot = ModelEntity()
            pivot.name = "k-\(component.id.uuidString)"
            pivot.position = [-0.028, 0.008, 0]
            pivot.components.set(InputTargetComponent())
            pivot.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.045)]))
            pivot.components.set(HoverEffectComponent())
            var leverAccessibility = AccessibilityComponent()
            leverAccessibility.isAccessibilityElement = true
            leverAccessibility.label = "Switch lever. Pinch to open or close the circuit."
            pivot.components.set(leverAccessibility)
            let arm = ModelEntity(
                mesh: .generateBox(size: [0.06, 0.008, 0.014], cornerRadius: 0.003),
                materials: [SimpleMaterial(color: UIColor(white: 0.75, alpha: 1),
                                           roughness: 0.3, isMetallic: true)])
            arm.position = [0.028, 0.006, 0]
            pivot.addChild(arm)
            body.addChild(pivot)
            visual.lever = pivot
        default:
            break
        }

        visuals[component.id] = visual
        return visual
    }

    // MARK: Modeled bodies (Blender-authored USDZ, procedural fallback)

    /// One loaded prototype per kind; each part gets a clone. The
    /// resistor (live color-band texture) and wire (stretching rod)
    /// deliberately stay procedural.
    private static var bodyPrototypes: [CircuitsModel.ComponentKind: Entity] = [:]
    private static let bodyAssetNames: [CircuitsModel.ComponentKind: String] = [
        .battery: "CircuitBattery", .bulb: "CircuitBulb",
        .capacitor: "CircuitCapacitor", .switcher: "CircuitSwitch",
    ]

    private static func modeledBody(for kind: CircuitsModel.ComponentKind) -> ModelEntity? {
        guard let name = bodyAssetNames[kind] else { return nil }
        if bodyPrototypes[kind] == nil, let loaded = try? Entity.load(named: name) {
            bodyPrototypes[kind] = loaded
        }
        guard let prototype = bodyPrototypes[kind] else { return nil }
        let shell = ModelEntity()
        shell.addChild(prototype.clone(recursive: true))
        return shell
    }

    private func makeBody(for component: CircuitsModel.Component) -> ModelEntity {
        if let modeled = Self.modeledBody(for: component.kind) {
            return modeled
        }
        switch component.kind {
        case .battery:
            let body = ModelEntity(
                mesh: .generateCylinder(height: 0.11, radius: 0.022),
                materials: [SimpleMaterial(color: UIColor(red: 0.35, green: 0.45, blue: 0.35, alpha: 1),
                                           roughness: 0.3, isMetallic: true)])
            body.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            // The + cap on terminal 0's side (nodeA convention).
            let cap = ModelEntity(
                mesh: .generateCylinder(height: 0.008, radius: 0.009),
                materials: [copperMaterial])
            cap.position = [0, 0.059, 0]  // local +y = world −x after rotation
            body.addChild(cap)
            return body
        case .resistor:
            let body = ModelEntity(
                mesh: .generateCylinder(height: 0.075, radius: 0.016),
                materials: [SimpleMaterial(color: UIColor(red: 0.85, green: 0.72, blue: 0.55, alpha: 1),
                                           roughness: 0.6, isMetallic: false)])
            body.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            return body
        case .bulb:
            var glass = PhysicallyBasedMaterial()
            glass.baseColor = .init(tint: .white)
            glass.roughness = 0.1
            glass.blending = .transparent(opacity: .init(floatLiteral: 0.35))
            let body = ModelEntity(
                mesh: .generateSphere(radius: 0.034), materials: [glass])
            body.position = [0, 0.012, 0]
            return body
        case .capacitor:
            let body = ModelEntity(
                mesh: .generateCylinder(height: 0.06, radius: 0.02),
                materials: [SimpleMaterial(color: UIColor(red: 0.12, green: 0.2, blue: 0.45, alpha: 1),
                                           roughness: 0.4, isMetallic: false)])
            let stripe = ModelEntity(
                mesh: .generateBox(size: [0.006, 0.06, 0.041]),
                materials: [UnlitMaterial(color: UIColor(white: 0.9, alpha: 1))])
            stripe.position = [0.017, 0, 0]  // the − stripe, terminal-1 side
            body.addChild(stripe)
            return body
        case .switcher:
            return ModelEntity(
                mesh: .generateBox(size: [0.075, 0.016, 0.032], cornerRadius: 0.004),
                materials: [SimpleMaterial(color: UIColor(white: 0.25, alpha: 1),
                                           roughness: 0.6, isMetallic: false)])
        case .acSource:
            let body = ModelEntity(
                mesh: .generateCylinder(height: 0.02, radius: 0.032),
                materials: [SimpleMaterial(color: UIColor(red: 0.1, green: 0.5, blue: 0.6, alpha: 1),
                                           roughness: 0.35, isMetallic: true)])
            body.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            let band = ModelEntity(
                mesh: .generateCylinder(height: 0.021, radius: 0.012),
                materials: [UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))])
            body.addChild(band)
            return body
        case .inductor:
            let body = ModelEntity(
                mesh: .generateCylinder(height: 0.07, radius: 0.014),
                materials: [SimpleMaterial(color: UIColor(white: 0.35, alpha: 1),
                                           roughness: 0.6, isMetallic: false)])
            body.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            for offset in stride(from: -0.024, through: 0.024, by: 0.012) {
                let coil = ModelEntity(
                    mesh: .generateCylinder(height: 0.006, radius: 0.019),
                    materials: [copperMaterial])
                coil.position = [0, Float(offset), 0]
                body.addChild(coil)
            }
            return body
        case .led:
            let base = ModelEntity(
                mesh: .generateCylinder(height: 0.016, radius: 0.012),
                materials: [SimpleMaterial(color: UIColor(white: 0.75, alpha: 1),
                                           roughness: 0.3, isMetallic: true)])
            var dome = PhysicallyBasedMaterial()
            dome.baseColor = .init(tint: UIColor(red: 0.9, green: 0.2, blue: 0.15, alpha: 1))
            dome.roughness = 0.15
            dome.blending = .transparent(opacity: .init(floatLiteral: 0.75))
            let cap = ModelEntity(mesh: .generateSphere(radius: 0.013), materials: [dome])
            cap.position = [0, 0.012, 0]
            base.addChild(cap)
            return base
        case .motor:
            // A dark can with a bright faceplate; the rotor is added in
            // makeVisual so it can be spun.
            let housing = ModelEntity(
                mesh: .generateCylinder(height: 0.07, radius: 0.022),
                materials: [SimpleMaterial(color: UIColor(white: 0.2, alpha: 1),
                                           roughness: 0.4, isMetallic: true)])
            housing.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            let plate = ModelEntity(
                mesh: .generateCylinder(height: 0.006, radius: 0.023),
                materials: [SimpleMaterial(color: UIColor(red: 0.15, green: 0.5, blue: 0.55, alpha: 1),
                                           roughness: 0.35, isMetallic: true)])
            plate.position = [0, -0.038, 0]   // local −y = +x (shaft end)
            housing.addChild(plate)
            return housing
        case .fuse:
            var glass = PhysicallyBasedMaterial()
            glass.baseColor = .init(tint: .white)
            glass.roughness = 0.1
            glass.blending = .transparent(opacity: .init(floatLiteral: 0.3))
            let body = ModelEntity(
                mesh: .generateCylinder(height: 0.06, radius: 0.012), materials: [glass])
            body.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            let filament = ModelEntity(
                mesh: .generateCylinder(height: 0.055, radius: 0.0018),
                materials: [copperMaterial])
            body.addChild(filament)
            for sign: Float in [-1, 1] {
                let cap = ModelEntity(
                    mesh: .generateCylinder(height: 0.01, radius: 0.0125),
                    materials: [SimpleMaterial(color: UIColor(white: 0.8, alpha: 1),
                                               roughness: 0.25, isMetallic: true)])
                cap.position = [0, sign * 0.03, 0]
                body.addChild(cap)
            }
            return body
        case .wire:
            // A jumper: bare copper rod in an orange insulation sleeve.
            // Generated at the base length; updateVisuals stretches the
            // rod along its axis to the component's live length.
            let body = ModelEntity(
                mesh: .generateCylinder(height: Self.wireBaseLength, radius: 0.005),
                materials: [copperMaterial])
            body.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            let sleeve = ModelEntity(
                mesh: .generateCylinder(height: 0.07, radius: 0.0095),
                materials: [SimpleMaterial(color: UIColor(red: 0.9, green: 0.45, blue: 0.15, alpha: 1),
                                           roughness: 0.7, isMetallic: false)])
            body.addChild(sleeve)
            return body
        }
    }

    // MARK: Wires

    /// The insulating jacket: a dark matte sleeve that gives every wire
    /// a silhouette against a bright room and lets the coloured core
    /// read as the conductor rather than as the whole cable.
    private static let wireJacketMaterial: PhysicallyBasedMaterial = {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(white: 0.12, alpha: 1))
        material.roughness = 0.55
        material.metallic = 0.0
        material.blending = .transparent(opacity: .init(floatLiteral: 0.82))
        return material
    }()

    /// Eight-step warm↔cool palette for the live voltage gradient.
    private static let voltageMaterials: [UnlitMaterial] = (0..<8).map { step in
        let t = Double(step) / 7
        var material = UnlitMaterial(color: UIColor(
            red: 0.35 + 0.62 * t,
            green: 0.5 + 0.18 * sin(t * .pi),
            blue: 0.95 - 0.65 * t,
            alpha: 1))
        material.blending = .transparent(opacity: 0.95)
        return material
    }
    private var wireVoltBuckets: [UUID: Int] = [:]

    private func syncWires(_ model: CircuitsModel) {
        let liveIDs = Set(model.wires.map(\.id))
        for id in wireEntities.keys where !liveIDs.contains(id) {
            wireEntities[id]?.removeFromParent()
            wireEntities[id] = nil
            wirePhases[id] = nil
        }

        for wire in model.wires {
            let entity: ModelEntity
            if let existing = wireEntities[wire.id] {
                entity = existing
            } else {
                // A wire must LOOK like a wire. The conductor alone,
                // drawn thin and mid-blue, lost the competition with the
                // bright electron beads riding on it: the bench read as
                // strings of floating beads with nothing joining them.
                // A real cable is a dark insulating jacket with the
                // conductor inside, so that is what gets built — the
                // jacket carries the silhouette, the core carries the
                // live voltage colour, and the electrons ride inside.
                entity = ModelEntity(
                    mesh: .generateCylinder(height: 1, radius: 0.0032),
                    materials: [copperMaterial])
                let jacket = ModelEntity(
                    mesh: .generateCylinder(height: 1, radius: 0.0062),
                    materials: [Self.wireJacketMaterial])
                jacket.name = "jacket"
                entity.addChild(jacket)
                entity.name = "w-\(wire.id.uuidString)"
                entity.components.set(InputTargetComponent())
                entity.components.set(CollisionComponent(
                    shapes: [.generateCapsule(height: 1, radius: 0.016)]))
                entity.components.set(HoverEffectComponent())
                var accessibility = AccessibilityComponent()
                accessibility.isAccessibilityElement = true
                accessibility.label = "Wire. Pinch to remove it."
                entity.components.set(accessibility)
                viewRoot.addChild(entity)
                wireEntities[wire.id] = entity
                wirePhases[wire.id] = 0
            }

            guard let a = terminalWorld(wire.from, model),
                  let b = terminalWorld(wire.to, model) else {
                entity.isEnabled = false
                continue
            }
            entity.isEnabled = true
            let direction = b - a
            let length = simd_length(direction)
            guard length > 1e-4 else { entity.isEnabled = false; continue }
            entity.position = (a + b) / 2
            entity.orientation = VectorFieldArrows.rotationFromYAxis(to: direction / length)
            entity.scale = SIMD3(1, length, 1)

            // The wire wears its potential: warm = high, cool = low —
            // voltage differences readable at a glance across the bench.
            let span = model.voltageSpan
            let width = max(span.max - span.min, 0.5)
            let vA = model.terminalVoltages[wire.from] ?? 0
            let vB = model.terminalVoltages[wire.to] ?? 0
            let t = ((vA + vB) / 2 - span.min) / width
            let bucket = min(max(Int(t * 7.999), 0), 7)
            if wireVoltBuckets[wire.id] != bucket {
                wireVoltBuckets[wire.id] = bucket
                entity.model?.materials = [Self.voltageMaterials[bucket]]
            }
        }
    }

    private func terminalWorld(_ terminal: CircuitsModel.Terminal, _ model: CircuitsModel) -> SIMD3<Float>? {
        guard let component = model.components.first(where: { $0.id == terminal.componentID })
        else { return nil }
        // While a component is being carried, follow its actual terminal
        // entity — it rides the hand-held holder, twist and all.
        if terminal.componentID == manipulatingComponentID,
           let visual = visuals[terminal.componentID],
           visual.terminals.count == 2 {
            return visual.terminals[terminal.end].position(relativeTo: viewRoot)
        }
        return SIMD3<Float>(component.terminalPosition(terminal.end))
    }

    // MARK: Electron flow (drift is − to +: opposite conventional current)

    private func syncElectrons(_ model: CircuitsModel, dt: Double) {
        guard model.showElectronFlow else {
            if electronsVisible {
                electronPool.hideAll()
                electronsVisible = false
            }
            return
        }
        electronsVisible = true

        var dotIndex = 0
        for wire in model.wires {
            guard let entity = wireEntities[wire.id], entity.isEnabled,
                  let a = terminalWorld(wire.from, model),
                  let b = terminalWorld(wire.to, model) else { continue }
            driftDots(key: wire.id, from: a, to: b,
                      current: model.wireFlows[wire.id] ?? 0,
                      model: model, dt: dt, dotIndex: &dotIndex)
        }
        // Wire jumper components conduct too — the same drift runs along
        // their rods (keyed by component id; ids never collide with wires).
        for component in model.components where component.kind == .wire {
            guard let a = terminalWorld(.init(componentID: component.id, end: 0), model),
                  let b = terminalWorld(.init(componentID: component.id, end: 1), model)
            else { continue }
            driftDots(key: component.id, from: a, to: b,
                      current: model.readouts[component.id]?.amps ?? 0,
                      model: model, dt: dt, dotIndex: &dotIndex)
        }
        for index in dotIndex..<electronPool.budget {
            electronPool.slots[index].entity.isEnabled = false
        }
    }

    /// Lays a run of drifting electron dots between two points, advancing
    /// their shared phase by the current's drift speed (− to +, opposite
    /// the conventional arrow) over the real elapsed time.
    private func driftDots(
        key: UUID, from a: SIMD3<Float>, to b: SIMD3<Float>,
        current: Double, model: CircuitsModel, dt: Double, dotIndex: inout Int
    ) {
        guard abs(current) > 5e-4 else { return }

        let length = Double(simd_distance(a, b))
        let dots = min(max(Int(length / 0.045), 2), 9)
        // Electrons drift against conventional current.
        let speed = min(0.03 + 0.5 * abs(current), 0.35) * (current > 0 ? -1 : 1)
        if !model.isPaused {
            wirePhases[key] = ((wirePhases[key] ?? 0)
                + speed / max(length, 0.05) * dt).truncatingRemainder(dividingBy: 1)
        }
        let phase = wirePhases[key] ?? 0

        for dot in 0..<dots where dotIndex < electronPool.budget {
            var t = (phase + Double(dot) / Double(dots)).truncatingRemainder(dividingBy: 1)
            if t < 0 { t += 1 }
            let slot = electronPool.slots[dotIndex]
            slot.entity.isEnabled = true
            slot.entity.position = a + (b - a) * Float(t)
            dotIndex += 1
        }
    }
}
