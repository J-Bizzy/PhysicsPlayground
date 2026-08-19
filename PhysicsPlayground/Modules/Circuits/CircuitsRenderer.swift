//
//  CircuitsRenderer.swift
//  Physics Playground — Circuits module
//
//  Renders the circuit lab. Entities are created/destroyed on edit (rare);
//  the per-frame path is transform writes only — no mesh regeneration.
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

    /// The SpaceView's tap router. A callback, not a model reference — the
    /// renderer deliberately holds no model.
    var onTap: ((Entity) -> Void)?
    /// The accessibility door, and the only one: tap-tap wiring for users who
    /// cannot pull. It IS the terminal's activate; the pinch path never calls it.
    var onTerminalAction: ((CircuitsModel.Terminal) -> Void)?

    /// Called from the SpaceView's `onDisappear` — an `EventSubscription`
    /// outlives the view that made it and would hold the entity graph alive.
    func teardown() {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
    }

    /// Where the release tick plays from when the grab ends.
    private weak var pulsedGrabEntity: Entity?

    /// Parent for the selected component's readout attachment.
    let selectedAnchor = Entity()

    /// The lead's touch target — the bead and the carry target are both sized against it.
    static let terminalTargetRadius: Float = 0.026

    private struct ComponentVisual {
        let holder: Entity
        let body: ModelEntity
        var terminals: [ModelEntity]
        /// Each lead's current accessibility value — unchanged state costs no write.
        var terminalValues: [String] = ["", ""]
        let label: BackedLabel
        let halo: ModelEntity
        var glow: ModelEntity?
        var filament: ModelEntity?
        var lever: ModelEntity?
        /// Motors only: the propeller that spins with the shaft.
        var rotor: Entity?
        var labelText = ""
        var glowBucket = -1
        var resistorCodeKey = ""
    }

    private var visuals: [UUID: ComponentVisual] = [:]
    private var wireEntities: [UUID: ModelEntity] = [:]
    private var wirePhases: [UUID: Double] = [:]

    // MARK: Voltage skyline (potential as terrain)
    /// The datum the towers rise from — a common floor so heights are comparable.
    private static let skylineDatumY: Float = 1.62
    private static let voltsToMeters: Float = 0.028
    private let skylineRoot = Entity()
    private var towers: [ModelEntity] = []
    private var towerCaps: [ModelEntity] = []
    private var towerThreads: [ModelEntity] = []
    private var towerLabels: [BackedLabel] = []
    /// Each tower's last-formatted reading, at the decimal it displays —
    /// NaN until first write. See the gate in `syncVoltageSkyline`.
    private var towerReadings: [Double] = []
    private var towerLabelPivots: [Entity] = []
    /// The colour step each tower wears — unchanged potential costs no material write.
    private var towerBuckets: [Int] = []

    /// The bench's own magnetic field. Deliberately modest budget: what teaches
    /// is arrows CIRCLING a wire, not a room-filling fog.
    private let fieldArrows = VectorFieldArrows(count: 260)
    /// How many runs get rings, longest first.
    private static let fieldRunBudget = 10
    /// Rings per run, and arrows per ring.
    private static let fieldStations = 3
    private static let fieldSpokes = 8
    /// Ring offset: far enough that the 1/d field is not a spike, close enough
    /// that the circulation reads as belonging to THIS wire.
    private static let fieldRingRadius: Double = 0.055

    private static let electronBudget = 200
    private let electronPool: EntityPool<Void>
    private var electronsVisible = false
    private var fieldArrowsVisible = false
    /// The segments the field arrows were last drawn from — nil when the layer
    /// is off, so re-enabling always redraws.
    private var lastFieldSegments: [WireField.Segment]?

    private let audioEmitter = Entity()
    private var lastSoundID = 0
    private var appliedResistorTextureVersion = -1

    /// The wire core. STATIC so `makeBody` can be too: the palette's previews
    /// are built before any renderer exists to own a copper.
    private static let copperMaterial = Materials.machined(
        DesignTokens.Palette.copperUI, roughness: 0.35)
    private var glowMaterials: [UnlitMaterial] = []


    /// The bench's VIEW transform: `root` belongs to the lab placement,
    /// `viewRoot` to the ZOOM — one transform each, so they cannot fight.
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
        viewRoot.addChild(fieldArrows.root)
        fieldArrows.hideAll()

        selectedAnchor.components.set(BillboardComponent())
        viewRoot.addChild(selectedAnchor)

        skylineRoot.isEnabled = false
        viewRoot.addChild(skylineRoot)

        audioEmitter.components.set(SpatialAudioComponent())
        viewRoot.addChild(audioEmitter)

    }

    // MARK: The bench's magnetic field

    /// Places arrows on RINGS around each current-carrying run — never a volume
    /// grid (`VectorFieldArrows` takes the first points given, so a grid dumps
    /// the whole budget into one slab). Each vector is still the TOTAL field
    /// from every segment, so nearby wires visibly reinforce or cancel.
    private func syncMagneticField(_ model: CircuitsModel) {
        guard model.showMagneticField else {
            if fieldArrowsVisible {
                fieldArrows.hideAll()
                fieldArrowsVisible = false
            }
            // Invalidated, not remembered: re-enabling must redraw.
            lastFieldSegments = nil
            return
        }
        fieldArrowsVisible = true

        // CHANGE-GATED: everything below is a pure function of the segments,
        // so a static bench costs one array compare; a carried part still
        // updates every frame because it changes the segments.
        let segments = model.currentSegments
        guard segments != lastFieldSegments else { return }
        lastFieldSegments = segments

        guard !segments.isEmpty else {
            fieldArrows.hideAll()
            return
        }

        // Longest runs first: a 2 cm stub has no room to read a circulation from.
        let ranked = segments
            .sorted { simd_length($0.b - $0.a) > simd_length($1.b - $1.a) }
            .prefix(Self.fieldRunBudget)

        var points: [SIMD3<Double>] = []
        var vectors: [SIMD3<Double>] = []

        for segment in ranked {
            let along = segment.b - segment.a
            let length = simd_length(along)
            guard length > 1e-4 else { continue }
            let axis = along / length
            // The world axis the run is LEAST aligned with keeps the cross
            // product well conditioned.
            let reference: SIMD3<Double> = abs(axis.y) < 0.9
                ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
            let u = simd_normalize(simd_cross(axis, reference))
            let v = simd_cross(axis, u)

            for stationIndex in 0..<Self.fieldStations {
                let t = (Double(stationIndex) + 0.5) / Double(Self.fieldStations)
                let centre = segment.a + along * t
                for spokeIndex in 0..<Self.fieldSpokes {
                    let angle = 2 * Double.pi * Double(spokeIndex)
                        / Double(Self.fieldSpokes)
                    let offset = (u * cos(angle) + v * sin(angle)) * Self.fieldRingRadius
                    let point = centre + offset
                    points.append(point)
                    vectors.append(WireField.field(at: point, segments: segments))
                }
            }
        }
        fieldArrows.update(points: points, vectors: vectors,
                           hidden: Array(repeating: false, count: points.count))
    }

    /// Distance from a point to a SEGMENT — clamped to the ends, not the
    /// infinite line.
    private static func distance(from point: SIMD3<Double>,
                                 to segment: WireField.Segment) -> Double {
        let along = segment.b - segment.a
        let lengthSquared = simd_length_squared(along)
        guard lengthSquared > 1e-12 else { return simd_distance(point, segment.a) }
        let t = min(max(simd_dot(point - segment.a, along) / lengthSquared, 0), 1)
        return simd_distance(point, segment.a + along * t)
    }

    // MARK: The parts palette

    /// One part for a `Well` preview — `makeBody` itself, at final size, so the
    /// preview and the object it makes are one thing.
    static func partPreview(for kind: CircuitsModel.ComponentKind) -> ModelEntity {
        makeBody(for: CircuitsModel.Component(
            id: UUID(), kind: kind, position: .zero, value: kind.defaultValue))
    }

    // MARK: Render clock
    // Ticked directly from SceneEvents.Update, not the observation render loop —
    // a steady DC circuit gives withObservationTracking nothing to re-fire on.

    /// Drives the armed-terminal pulse.
    private var pendingPulsePhase = 0.0

    // MARK: Connection previews & drag-to-wire

    /// While this part is carried, ghost wires show what a release would connect.
    var previewComponentID: UUID?
    /// Terminals currently highlighted as connection targets.
    private(set) var previewTargets: Set<CircuitsModel.Terminal> = []
    private var previewWireEntities: [ModelEntity] = []

    /// The lead in flight, in one of three states. FATTER THAN A WIRE'S 0.0062
    /// jacket, load-bearing: a thinner lead lying along an existing wire is
    /// swallowed by it — which is exactly the refusal case.
    private static let flyingLeadRadius: Float = 0.008

    private lazy var flyingLead: ModelEntity = {
        let lead = ModelEntity(
            mesh: .generateCylinder(height: 1, radius: Self.flyingLeadRadius),
            materials: [Self.leadMaterial])
        lead.isEnabled = false
        viewRoot.addChild(lead)
        return lead
    }()

    /// Neutral: reaching, nothing under it yet.
    private static let leadMaterial = Materials.machined(
        DesignTokens.Palette.copperUI, roughness: 0.35)
    /// Armed: a release right now lands a wire. Same green as the ghost wires —
    /// "this will connect" is one colour on this bench.
    private static let previewMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: UIColor(
            red: 0.35, green: 1.0, blue: 0.55, alpha: 1))
        material.blending = .transparent(opacity: 0.65)
        return material
    }()
    /// Refusing: a release right now would be declined. NO TEXT — the refusal
    /// is the recoil, red and shortened.
    private static let refusalMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: DesignTokens.Palette.destructiveUI)
        material.blending = .transparent(opacity: 0.8)
        return material
    }()
    /// How far back a refused lead pulls — unmistakable without vanishing.
    private static let refusalRecoil: Float = 0.65

    private func stretch(_ entity: ModelEntity, from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let direction = b - a
        let length = simd_length(direction)
        guard length > 1e-4 else { entity.isEnabled = false; return }
        entity.isEnabled = true
        entity.position = (a + b) / 2
        entity.orientation = VectorFieldArrows.rotationFromYAxis(to: direction / length)
        entity.scale = SIMD3(1, length, 1)
    }

    /// Draw the lead a hand is pulling, in whichever state the model says.
    private func syncFlyingLead(_ model: CircuitsModel) {
        guard let pull = model.leadPull,
              let source = terminalWorld(pull.source, model) else {
            flyingLead.isEnabled = false
            return
        }
        let hand = SIMD3<Float>(pull.hand)
        // Armed leads snap to their target, so picture and outcome cannot disagree.
        let landing: SIMD3<Float>
        let material: RealityKit.Material
        // A refused lead also thickens, so the red stub cannot hide inside the
        // wire it lies along.
        var girth: Float = 1
        if pull.refusal != nil {
            landing = source + (hand - source) * (1 - Self.refusalRecoil)
            material = Self.refusalMaterial
            girth = 1.5
        } else if let target = pull.target,
                  let targetPoint = terminalWorld(target, model) {
            landing = targetPoint
            material = Self.previewMaterial
        } else {
            landing = hand
            material = Self.leadMaterial
        }
        stretch(flyingLead, from: source, to: landing)
        flyingLead.scale = SIMD3(girth, flyingLead.scale.y, girth)
        flyingLead.model?.materials = [material]
    }

    private func syncConnectionPreviews(_ model: CircuitsModel) {
        var pairs: [(SIMD3<Float>, SIMD3<Float>, CircuitsModel.Terminal)] = []
        if let id = previewComponentID {
            for pair in model.pendingJoins(for: id) {
                if let a = terminalWorld(pair.from, model),
                   let b = terminalWorld(pair.to, model) {
                    pairs.append((a, b, pair.to))
                }
            }
        }
        previewTargets = Set(pairs.map(\.2))
        // A lead in flight swells its landing target — never one that would
        // REFUSE it.
        if let pull = model.leadPull, pull.refusal == nil, let target = pull.target {
            previewTargets.insert(target)
        }

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

    /// The zoom, as ONE number: Electron View is a floor under the same
    /// continuous two-hand zoom, not a competing 1×/4× flip.
    private var benchScale: Float = 1
    static let benchPivot = SIMD3<Float>(0, 1.25, -0.85)
    /// Set by the space view from the two-handed scale rig.
    var handZoom: Float = 1
    static let electronViewZoom: Float = 4.0

    /// Where the zoom is heading: the larger of the hands' zoom and the
    /// Electron View floor, so enabling it while zoomed never shrinks the bench.
    private func targetZoom(_ model: CircuitsModel) -> Float {
        max(handZoom, model.electronView ? Self.electronViewZoom : 1)
    }

    // MARK: The bench's hum

    /// A mains hum whose loudness rides total current and whose pitch
    /// rises with dissipated power.
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
        // 50 Hz-ish fundamental, climbing as the bench works harder.
        hum?.update(pitchHz: 52 + min(power, 12) * 7,
                    loudness: Sonification.loudness(current, full: 1.5, knee: 0.55))
    }

    func tick(dt: Double, model: CircuitsModel) {
        tickHum(model)
        pendingPulsePhase += dt * 6
        let target = targetZoom(model)
        if abs(benchScale - target) > 1e-3 {
            // Eased toward the target so an Electron View flick glides.
            benchScale += (target - benchScale) * Float(min(dt * 8, 1))
            viewRoot.scale = SIMD3(repeating: benchScale)
            viewRoot.position = Self.benchPivot * (1 - benchScale)
        }
        render(model, dt: dt)
    }

    /// Acknowledge a grab: a light pulse and a tick on the part just taken.
    func flashPickup(id: UUID) {
        guard let holder = visuals[id]?.holder else { return }
        pulsedGrabEntity = holder
        PickupPulse.flash(on: holder)
        SoundPalette.play(.grabTick, on: holder, volume: 0.2)
    }

    /// Answer a release, on whatever was last picked up.
    func flashRelease() {
        guard let entity = pulsedGrabEntity else { return }
        SoundPalette.play(.releaseTick, on: entity, volume: 0.18)
        pulsedGrabEntity = nil
    }

    private func render(_ model: CircuitsModel, dt: Double) {
        if appliedResistorTextureVersion != CircuitTextures.version {
            appliedResistorTextureVersion = CircuitTextures.version
            for id in visuals.keys { visuals[id]?.resistorCodeKey = "" }
        }
        syncConnectionPreviews(model)
        syncFlyingLead(model)
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
        syncMagneticField(model)

        if let selected = model.selectedComponent {
            selectedAnchor.isEnabled = true
            selectedAnchor.position = SIMD3<Float>(selected.position) + SIMD3(0, 0.14, 0)
            // Counter-scaled: the anchor hangs under `viewRoot` (the zoom
            // rig), so its position rides the zoom but its size must not.
            selectedAnchor.scale = SIMD3(repeating: 1 / max(benchScale, 0.001))
        } else {
            selectedAnchor.isEnabled = false
        }
    }

    // MARK: Voltage skyline

    /// Warm for high potential, cool for low — the same language the
    /// gradient wires speak, saturated for the towers.
    /// The skyline's warm↔cool ramp, over a normalised −1…1 axis.
    private static func potentialTint(_ t: CGFloat) -> UIColor {
        if t >= 0 {
            return UIColor(red: 1.0, green: 0.6 - 0.35 * t, blue: 0.3 - 0.25 * t, alpha: 1)
        }
        return UIColor(red: 0.35 + 0.35 * t, green: 0.65 + 0.2 * t, blue: 1.0, alpha: 1)
    }

    // The skyline's materials, resolved once: the axis is quantised into
    // 33 steps so a tower whose bucket has not moved writes no material.
    private static let skylineSteps = 33

    private static func skylineBucket(_ volts: Double, span: Double) -> Int {
        let t = span > 1e-6 ? max(-1, min(1, volts / span)) : 0
        return min(max(Int(((t + 1) / 2) * Double(skylineSteps - 1) + 0.5), 0),
                   skylineSteps - 1)
    }

    private static func skylineTint(_ bucket: Int) -> UIColor {
        potentialTint(CGFloat(bucket) / CGFloat(skylineSteps - 1) * 2 - 1)
    }

    private static func skylineMaterial(_ bucket: Int, intensity: Float)
    -> PhysicallyBasedMaterial {
        let color = skylineTint(bucket)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = 0.4
        material.blending = .transparent(opacity: .init(floatLiteral: 0.6))
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = intensity
        return material
    }

    private static let towerMaterials: [PhysicallyBasedMaterial] =
        (0..<skylineSteps).map { skylineMaterial($0, intensity: 0.6) }
    private static let capMaterials: [PhysicallyBasedMaterial] =
        (0..<skylineSteps).map { skylineMaterial($0, intensity: 0.9) }

    /// Raises a glowing tower over every node to a height equal to its
    /// voltage — potential as terrain (Kirchhoff's loop law made spatial).
    private func syncVoltageSkyline(_ model: CircuitsModel) {
        skylineRoot.isEnabled = model.showVoltageHeights
        guard model.showVoltageHeights else { return }

        // One tower per net, in node order — so a tower keeps its
        // identity between frames instead of being whichever entry a
        // dictionary happened to hand back.
        let nodes = model.nets
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
            let bucket = Self.skylineBucket(node.voltage, span: span)
            let colorMoved = towerBuckets[index] != bucket
            if colorMoved { towerBuckets[index] = bucket }

            // The tower: a slim column from the datum to the potential.
            tower.isEnabled = true
            let mag = max(abs(height), 0.001)
            tower.position = base + SIMD3(0, height / 2, 0)
            tower.scale = SIMD3(1, mag / 0.1, 1)   // base mesh is 0.1 tall

            // A glowing cap disc at the top.
            let cap = towerCaps[index]
            cap.isEnabled = true
            cap.position = base + SIMD3(0, height, 0)

            if colorMoved {
                tower.model?.materials = [Self.towerMaterials[bucket]]
                cap.model?.materials = [Self.capMaterials[bucket]]
            }

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
            // Formatted only when the displayed decimal or tint bucket moves.
            let reading = (node.voltage * 10).rounded()
            if towerReadings[index] != reading || colorMoved {
                towerReadings[index] = reading
                towerLabels[index].setText(
                    PhysicsFormat.measurement(node.voltage, "V", decimals: 1),
                    color: Self.skylineTint(bucket))
            }
        }
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

        let label = BackedLabel(size: PlateStyle.exhibitLabelSize)
        let pivot = Entity()
        pivot.components.set(BillboardComponent())
        skylineRoot.addChild(pivot)
        pivot.addChild(label.root)
        towerLabels.append(label)
        towerReadings.append(.nan)
        towerLabelPivots.append(pivot)
        towerBuckets.append(-1)
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

    /// The lit net's terminals, recomputed once a frame rather than
    /// once per lead — `highlightedTerminals` walks the topology.
    private var highlightedTerminals: Set<CircuitsModel.Terminal> = []

    private func syncComponents(_ model: CircuitsModel) {
        highlightedTerminals = Set(model.highlightedTerminals)
        // Remove visuals whose components are gone.
        let liveIDs = Set(model.components.map(\.id))
        for id in visuals.keys where !liveIDs.contains(id) {
            visuals[id]?.holder.removeFromParent()
            visuals[id] = nil
            wirePhases[id] = nil  // a removed jumper's electron phase
        }

        for component in model.components {
            var visual = visuals[component.id] ?? makeVisual(for: component)

            // The model owns motion; the renderer follows it.
            visual.holder.position = SIMD3<Float>(component.position)
            // Aim the whole part along its model axis — but only when
            // the axis actually moved.
            let target = simd_normalize(SIMD3<Float>(component.axis))
            let current = visual.holder.orientation.act([1, 0, 0])
            if simd_dot(current, target) < 0.99995 {
                // A part dragged end-for-end has axis exactly
                // [-1,0,0]; the flip has to keep it the right way up.
                visual.holder.orientation = rotation(from: [1, 0, 0], to: target)
            }
            Fade.tick(visual.halo, visible: component.id == model.selectedID)

            // One lead at each end, and nothing else to hit there.
            let half = Float(CircuitsModel.terminalOffset)
            for (end, terminal) in visual.terminals.enumerated() {
                let sign: Float = end == 0 ? -1 : 1
                terminal.position = SIMD3(sign * half, 0, 0)
                let key = CircuitsModel.Terminal(componentID: component.id, end: end)
                let isSource = model.leadPull?.source == key
                    || model.voiceWireSource == key
                // The armed terminal breathes, and preview targets swell,
                // so there's never doubt what the next action will wire.
                let isProbed = model.probeA == key || model.probeB == key
                // The armed state is audible too — VoiceOver cannot see a bead breathe.
                let spokenValue = isSource ? "armed" : ""
                if visual.terminalValues[end] != spokenValue {
                    visual.terminalValues[end] = spokenValue
                    SpatialActions.republish(value: spokenValue, on: terminal)
                }
                let isLit = highlightedTerminals.contains(key)
                terminal.scale = SIMD3(repeating: isSource
                    ? Float(1.6 + 0.35 * sin(pendingPulsePhase))
                    : (previewTargets.contains(key) ? 1.5
                        : ((isProbed || isLit) ? 1.35 : 1.0)))
            }

            // Live label. `BackedLabel` self-gates on unchanged text.
            let text = labelText(for: component)
            if visual.labelText != text {
                visual.labelText = text
                visual.label.setText(text, color: UIColor(white: 0.95, alpha: 1))
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
        return PhysicsFormat.measurement(rpm, "rpm", decimals: 0)
    }

    /// The bench label. Value formatting goes through the ONE authority,
    /// `CircuitsModel.formatValue`, so label and readout cannot disagree;
    /// only bench-specific wording stays here (motor rpm, switch
    /// open/closed, the AC tilde).
    private func labelText(for component: CircuitsModel.Component) -> String {
        switch component.kind {
        case .battery, .resistor, .bulb, .capacitor, .inductor:
            CircuitsModel.formatValue(component.value, for: component.kind)
        case .switcher: component.isClosed ? "closed" : "open"
        case .acSource:
            CircuitsModel.formatValue(component.value, for: component.kind) + "~"
        case .led: component.failed ? "burned out" : "LED"
        case .motor: Self.motorRPMLabel(component.motorSpeed)
        case .fuse: component.failed
            ? "blown"
            : PhysicsFormat.measurement(component.value, "A fuse", decimals: 1)
        }
    }

    private func makeVisual(for component: CircuitsModel.Component) -> ComponentVisual {
        // The HOLDER is the manipulation target, so a carried part brings
        // its terminals, label and halo along.
        let holder = Entity()
        holder.name = component.id.uuidString
        holder.position = SIMD3<Float>(component.position)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(component.kind.displayName). Drag to move; pinch its terminals to wire.")
        holder.components.set(accessibility)
        viewRoot.addChild(holder)

        // The visible body, shaped per kind.
        let body = Self.makeBody(for: component)
        holder.addChild(body)

        // The carry target is the BODY, measured from `body` not `holder`
        // (which collects a bulb's glow and a selection halo). Its x
        // half-extent is clamped just inside the terminal target's inner
        // edge (0.085 − 0.026 = 0.059) so a body pinch cannot swallow a lead.
        let bodyExtents = body.visualBounds(relativeTo: holder).extents
        let clearOfLead = Float(CircuitsModel.terminalOffset) - Self.terminalTargetRadius - 0.002
        let half = SIMD3<Float>(
            min(bodyExtents.x / 2 + Grabbable.reach, clearOfLead),
            bodyExtents.y / 2 + Grabbable.reach,
            bodyExtents.z / 2 + Grabbable.reach)
        Grabbable.configureTouchTarget(
            holder, box: half * 2,
            activate: { [weak self, weak holder] in
                guard let holder else { return }
                self?.onTap?(holder)
            })

        // Terminals: copper spheres, tap targets for wiring.
        var terminals: [ModelEntity] = []
        let terminalMesh = MeshResource.generateSphere(radius: 0.013)
        for end in 0...1 {
            let terminal = ModelEntity(mesh: terminalMesh, materials: [Self.copperMaterial])
            terminal.name = "t\(end)-\(component.id.uuidString)"
            terminal.position = SIMD3(
                Float(end == 0 ? -CircuitsModel.terminalOffset : CircuitsModel.terminalOffset), 0, 0)
            // The only target at this end; the far lead is 0.17 m away.
            terminal.components.set(InputTargetComponent())
            terminal.components.set(CollisionComponent(
                shapes: [.generateSphere(radius: Self.terminalTargetRadius)]))
            terminal.components.set(HoverEffectComponent())
            let key = CircuitsModel.Terminal(componentID: component.id, end: end)
            SpatialActions.attach(
                to: terminal, label: "Terminal. Activate to wire from here.",
                activate: { [weak self] in self?.onTerminalAction?(key) })
            var terminalAccessibility = AccessibilityComponent()
            terminalAccessibility.isAccessibilityElement = true
            terminalAccessibility.label = LocalizedStringResource(stringLiteral:
                "\(component.kind.displayName) terminal. Pinch this then another terminal to wire them.")
            terminal.components.set(terminalAccessibility)
            holder.addChild(terminal)
            terminals.append(terminal)

            // A short lead from the body toward the terminal.
            let lead = ModelEntity(
                mesh: .generateCylinder(height: 0.045, radius: 0.0028),
                materials: [Self.copperMaterial])
            lead.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            lead.position = SIMD3(Float(end == 0 ? -0.062 : 0.062), 0, 0)
            holder.addChild(lead)
        }

        // The white center knob: the part's carry handle.
        var knobMaterial = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        knobMaterial.blending = .transparent(opacity: 0.85)
        let knob = ModelEntity(
            mesh: .generateSphere(radius: 0.009), materials: [knobMaterial])
        holder.addChild(knob)

        // Selection halo.
        let halo = SelectionHalo.make(mesh: .generateSphere(radius: 0.085))
        holder.addChild(halo)

        // Value label beneath, billboarded over the dark backing.
        let label = BackedLabel(size: 0.02)
        let labelPivot = Entity()
        labelPivot.position = [0, -0.065, 0]
        labelPivot.components.set(BillboardComponent())
        labelPivot.addChild(label.root)
        holder.addChild(labelPivot)

        var visual = ComponentVisual(
            holder: holder, body: body, terminals: terminals,
            label: label, halo: halo)

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
                materials: [Materials.machined(UIColor(white: 0.6, alpha: 1), roughness: 0.3)])
            rotor.addChild(hub)
            // The motor's own accent, from the tokens. This was a
            // hand-typed teal that belonged to no palette entry — an
            // unowned hue on a physics object.
            let accent = DesignTokens.Palette.motorAccentUI
            for axis: SIMD3<Float> in [[0, 1, 0], [0, 0, 1]] {
                let blade = ModelEntity(
                    mesh: .generateBox(size: [0.005, 0.05, 0.004], cornerRadius: 0.002),
                    materials: [UnlitMaterial(color: accent)])
                blade.orientation = rotation(from: [0, 1, 0], to: axis)
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
            var leverAccessibility = AccessibilityComponent()
            leverAccessibility.isAccessibilityElement = true
            leverAccessibility.label = "Switch lever. Pinch to open or close the circuit."
            pivot.components.set(leverAccessibility)
            let arm = ModelEntity(
                mesh: .generateBox(size: [0.06, 0.008, 0.014], cornerRadius: 0.003),
                materials: [Materials.machined(UIColor(white: 0.75, alpha: 1), roughness: 0.3)])
            arm.position = [0.028, 0.006, 0]
            pivot.addChild(arm)
            // THE ARM IS A BLADE. A 0.045 m sphere on a lever 8 mm
            // thick bulged 4 cm below the switch body and took the
            // pinches meant for the terminals underneath it. Measured
            // after the arm exists, so the target is the lever — and
            // set directly rather than through `Grabbable`, because
            // this pivot is not a carried object and wants no
            // grounding shadow of its own.
            let leverBounds = pivot.visualBounds(relativeTo: pivot)
            pivot.components.set(InputTargetComponent())
            pivot.components.set(CollisionComponent(shapes: [
                .generateBox(size: leverBounds.extents
                             + SIMD3<Float>(repeating: 2 * Grabbable.reach))
                    .offsetBy(translation: leverBounds.center),
            ]))
            pivot.components.set(HoverEffectComponent())
            SpatialActions.attach(
                to: pivot, label: "Switch",
                activate: { [weak self, weak pivot] in
                    guard let pivot else { return }
                    self?.onTap?(pivot)
                })
            body.addChild(pivot)
            visual.lever = pivot
        default:
            break
        }

        visuals[component.id] = visual
        return visual
    }

    // MARK: Modeled bodies (Blender-authored USDZ, procedural fallback)

    /// Each part clones the shared `PropCache` prototype. The resistor
    /// (live color-band texture) and wire (stretching rod) deliberately
    /// stay procedural.
    private static let bodyAssetNames: [CircuitsModel.ComponentKind: String] = [
        .battery: "CircuitBattery", .bulb: "CircuitBulb",
        .capacitor: "CircuitCapacitor", .switcher: "CircuitSwitch",
    ]

    private static func modeledBody(for kind: CircuitsModel.ComponentKind) -> ModelEntity? {
        guard let name = bodyAssetNames[kind] else { return nil }
        guard let prototype = PropCache.prototype(named: name) else { return nil }
        let shell = ModelEntity()
        shell.addChild(prototype.clone(recursive: true))
        return shell
    }

    private static func makeBody(for component: CircuitsModel.Component) -> ModelEntity {
        if let modeled = Self.modeledBody(for: component.kind) {
            return modeled
        }
        switch component.kind {
        case .battery:
            let body = ModelEntity(
                mesh: .generateCylinder(height: 0.11, radius: 0.022),
                materials: [Materials.machined(UIColor(red: 0.35, green: 0.45, blue: 0.35, alpha: 1), roughness: 0.3)])
            body.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            // The + cap on terminal 0's side (nodeA convention).
            let cap = ModelEntity(
                mesh: .generateCylinder(height: 0.008, radius: 0.009),
                materials: [Self.copperMaterial])
            cap.position = [0, 0.059, 0]  // local +y = world −x after rotation
            body.addChild(cap)
            return body
        case .resistor:
            let body = ModelEntity(
                mesh: .generateCylinder(height: 0.075, radius: 0.016),
                materials: [Materials.machined(UIColor(red: 0.85, green: 0.72, blue: 0.55, alpha: 1),
                                               roughness: 0.6)])
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
                materials: [Materials.machined(UIColor(red: 0.12, green: 0.2, blue: 0.45, alpha: 1),
                                               roughness: 0.4)])
            let stripe = ModelEntity(
                mesh: .generateBox(size: [0.006, 0.06, 0.041]),
                materials: [UnlitMaterial(color: UIColor(white: 0.9, alpha: 1))])
            stripe.position = [0.017, 0, 0]  // the − stripe, terminal-1 side
            body.addChild(stripe)
            return body
        case .switcher:
            return ModelEntity(
                mesh: .generateBox(size: [0.075, 0.016, 0.032], cornerRadius: 0.004),
                materials: [Materials.graphite(UIColor(white: 0.25, alpha: 1))])
        case .acSource:
            let body = ModelEntity(
                mesh: .generateCylinder(height: 0.02, radius: 0.032),
                materials: [Materials.machined(UIColor(red: 0.1, green: 0.5, blue: 0.6, alpha: 1), roughness: 0.35)])
            body.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            let band = ModelEntity(
                mesh: .generateCylinder(height: 0.021, radius: 0.012),
                materials: [UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))])
            body.addChild(band)
            return body
        case .inductor:
            let body = ModelEntity(
                mesh: .generateCylinder(height: 0.07, radius: 0.014),
                materials: [Materials.machined(UIColor(white: 0.35, alpha: 1),
                                               roughness: 0.6)])
            body.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            for offset in stride(from: -0.024, through: 0.024, by: 0.012) {
                let coil = ModelEntity(
                    mesh: .generateCylinder(height: 0.006, radius: 0.019),
                    materials: [Self.copperMaterial])
                coil.position = [0, Float(offset), 0]
                body.addChild(coil)
            }
            return body
        case .led:
            let base = ModelEntity(
                mesh: .generateCylinder(height: 0.016, radius: 0.012),
                materials: [Materials.machined(UIColor(white: 0.75, alpha: 1), roughness: 0.3)])
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
                materials: [Materials.machined(UIColor(white: 0.2, alpha: 1), roughness: 0.4)])
            housing.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            let plate = ModelEntity(
                mesh: .generateCylinder(height: 0.006, radius: 0.023),
                materials: [Materials.machined(UIColor(red: 0.15, green: 0.5, blue: 0.55, alpha: 1), roughness: 0.35)])
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
                materials: [Self.copperMaterial])
            body.addChild(filament)
            for sign: Float in [-1, 1] {
                let cap = ModelEntity(
                    mesh: .generateCylinder(height: 0.01, radius: 0.0125),
                    materials: [Materials.machined(UIColor(white: 0.8, alpha: 1), roughness: 0.25)])
                cap.position = [0, sign * 0.03, 0]
                body.addChild(cap)
            }
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
    /// THE LIT NET. One material, the module's own accent — no new
    /// hue, and no permanent tint on anything: a net's identity is
    /// shown ON DEMAND, because the standing colour language on this
    /// bench already means voltage (warm high, cool low) and a second
    /// permanent colour would be arguing with it.
    private static let netHighlightMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: UIColor(DesignTokens.Palette.circuitsAccent))
        material.blending = .transparent(opacity: 0.95)
        return material
    }()

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

    /// The polyline each wire is currently drawn along, so the
    /// electrons can ride the same path rather than the chord.
    private var wireCurves: [UUID: [SIMD3<Float>]] = [:]
    /// The endpoints each wire's segments were last laid out for, and
    /// the cumulative arc table the drift dots walk. Both are pure
    /// functions of the endpoints, so both are rebuilt only when an end
    /// actually moves — an idle bench used to re-solve every catenary
    /// and rewrite every segment transform every frame for nothing.
    private var wireLaidEndpoints: [UUID: (a: SIMD3<Float>, b: SIMD3<Float>)] = [:]
    private var wireArcs: [UUID: [Float]] = [:]

    /// How many segments a hanging cable is drawn from.
    ///
    /// A STRAIGHT WIRE IS ONE SEGMENT, which matters more than it
    /// sounds: after a snap-align most joints are coincident and most
    /// remaining wires are short and taut, so a tidy bench costs
    /// exactly what it cost before sag existed. Only a genuine span
    /// pays for its own curve.
    private static let sagSegments = 7

    /// The path a wire hangs along, in bench coordinates.
    private func wireCurve(from a: SIMD3<Float>, to b: SIMD3<Float>,
                           span: Double) -> [SIMD3<Float>] {
        var slack = CircuitsModel.slack(span: span)
        #if DEBUG
        // `-circSag <ratio>` overrides the policy so a still frame can
        // show the curve at a chosen depth — and `-circSag 0` proves
        // the straight fallback, which is otherwise only reachable by
        // building a bench with every joint snapped.
        // `as? NSNumber`, not `as? Double`: `-circSag 0` is stored as
        // an integer, so a Double cast silently fails and the override
        // does nothing — which is exactly how the first attempt at
        // photographing the straight fallback produced two identical
        // pictures of a sagging one.
        if let forced = UserDefaults.standard.object(forKey: "circSag") as? NSNumber {
            slack = forced.doubleValue * span
        }
        #endif
        guard slack > 1e-5 else { return [a, b] }
        return Catenary.points(from: SIMD3<Double>(a), to: SIMD3<Double>(b),
                               slack: slack, samples: Self.sagSegments + 1)
            .map { SIMD3<Float>($0) }
    }

    /// Where each wire's collider was last shaped, so a wire that is
    /// not moving does not rebuild shapes it already has.
    private var wireColliderAnchors: [UUID: (SIMD3<Float>, SIMD3<Float>)] = [:]

    /// How far an end must move before the grab volume is rebuilt.
    /// Shapes are allocations, and a bench of stationary wires should
    /// cost none — only the one or two on a carried part pay.
    private static let colliderRebuildEpsilon: Float = 0.002

    /// Give the wire a grab volume that FOLLOWS THE CURVE, in three
    /// capsules rather than one along the chord.
    ///
    /// On a long hanging span the chord passes through open air a
    /// hand's width above the cable, so a single straight capsule
    /// would put the grab volume where the wire visibly is not.
    private func reshapeCollider(_ entity: ModelEntity, id: UUID,
                                 along curve: [SIMD3<Float>]) {
        guard let first = curve.first, let last = curve.last else { return }
        if let previous = wireColliderAnchors[id],
           simd_distance(previous.0, first) < Self.colliderRebuildEpsilon,
           simd_distance(previous.1, last) < Self.colliderRebuildEpsilon {
            return
        }
        wireColliderAnchors[id] = (first, last)

        // Three, whatever the curve was sampled at: enough to follow a
        // sag, few enough that a moving wire is cheap.
        var shapes: [ShapeResource] = []
        let pieces = 3
        for piece in 0..<pieces {
            let a = curve[piece * (curve.count - 1) / pieces]
            let b = curve[(piece + 1) * (curve.count - 1) / pieces]
            let direction = b - a
            let length = simd_length(direction)
            guard length > 1e-4 else { continue }
            shapes.append(ShapeResource
                .generateCapsule(height: length, radius: 0.016)
                .offsetBy(rotation: VectorFieldArrows.rotationFromYAxis(to: direction / length),
                          translation: (a + b) / 2))
        }
        guard !shapes.isEmpty else { return }
        entity.components.set(CollisionComponent(shapes: shapes))
        entity.components.set(InputTargetComponent())
        entity.components.set(HoverEffectComponent())
    }

    /// Point a wire's segment children along a polyline, growing the
    /// pool of segments if the curve needs more than it has.
    ///
    /// Each segment is a copper core with a dark jacket child, the
    /// same two-layer cable the straight version drew — the jacket
    /// carries the silhouette, the core carries the live voltage
    /// colour, and the electrons ride inside.
    private func layOut(segmentsOf entity: ModelEntity, along curve: [SIMD3<Float>]) {
        let needed = max(curve.count - 1, 1)
        while entity.children.count < needed {
            let core = ModelEntity(
                mesh: .generateCylinder(height: 1, radius: 0.0032),
                materials: [Self.copperMaterial])
            let jacket = ModelEntity(
                mesh: .generateCylinder(height: 1, radius: 0.0062),
                materials: [Self.wireJacketMaterial])
            jacket.name = "jacket"
            core.addChild(jacket)
            // SEGMENTS ARE PURE VISUALS — no collider, deliberately.
            // A segment carries its own length as a Y scale, and a
            // 45 mm piece of a curve therefore has a world scale of
            // 0.045; `ColliderCriterionTests` reads any collider under
            // a scale below 0.05 as a FOLDED instrument it cannot
            // honestly measure, and says so rather than passing. It is
            // right to. The grab volume lives on the parent instead,
            // which is unscaled — see `reshapeCollider`.
            entity.addChild(core)
        }
        for (index, child) in entity.children.enumerated() {
            guard index < needed else { child.isEnabled = false; continue }
            let a = curve[index], b = curve[index + 1]
            let direction = b - a
            let length = simd_length(direction)
            guard length > 1e-6 else { child.isEnabled = false; continue }
            child.isEnabled = true
            // The parent is at the origin of `viewRoot`, so segment
            // transforms are bench coordinates directly.
            child.position = (a + b) / 2
            child.orientation = VectorFieldArrows.rotationFromYAxis(to: direction / length)
            child.scale = SIMD3(1, length, 1)
        }
    }

    private func syncWires(_ model: CircuitsModel) {
        let liveIDs = Set(model.wires.map(\.id))
        for id in wireEntities.keys where !liveIDs.contains(id) {
            wireEntities[id]?.removeFromParent()
            wireEntities[id] = nil
            wirePhases[id] = nil
            wireCurves[id] = nil
            wireLaidEndpoints[id] = nil
            wireArcs[id] = nil
            wireColliderAnchors[id] = nil
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
                // A CABLE THAT HANGS IS BUILT FROM SEGMENTS, not
                // from a regenerated mesh. The house rule is that the
                // per-frame path touches only entity transforms and
                // that mesh generation goes through
                // `GeometryPipeline`'s worker — and a sagging wire
                // moves every frame while its part is carried, so a
                // `TubeMesh` rebuilt inline would break exactly that
                // rule. Segments share one unit-cylinder mesh and
                // move by transform alone.
                entity = ModelEntity()
                entity.name = "w-\(wire.id.uuidString)"
                var accessibility = AccessibilityComponent()
                accessibility.isAccessibilityElement = true
                accessibility.label = "Wire. Pinch an end and pull to move it."
                entity.components.set(accessibility)
                SpatialActions.attach(
                    to: entity, label: "Wire. Activate to remove it.",
                    activate: { [weak self, weak entity] in
                        guard let entity else { return }
                        self?.onTap?(entity)
                    })
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
            let length = simd_distance(a, b)
            // Two leads snapped into one point need no cable between
            // them, which is what keeps a tidy chained bench from
            // sprouting droops at every joint.
            guard length > 1e-4 else { entity.isEnabled = false; continue }

            // Re-laid ONLY when an end moved. The curve, the segment
            // transforms, the collider and the arc table are all pure
            // functions of the two endpoints; on an idle bench the
            // endpoints are bit-identical frame to frame, and a carried
            // part changes them every frame — so this gate costs the
            // moving case nothing and saves the still case everything.
            if wireLaidEndpoints[wire.id].map({ $0.a != a || $0.b != b }) ?? true {
                wireLaidEndpoints[wire.id] = (a, b)
                let curve = wireCurve(from: a, to: b, span: Double(length))
                wireCurves[wire.id] = curve
                layOut(segmentsOf: entity, along: curve)
                reshapeCollider(entity, id: wire.id, along: curve)
                // The arc table the drift dots walk, built beside the
                // curve it measures rather than once per frame in
                // `driftDots`.
                var arc: [Float] = [0]
                arc.reserveCapacity(curve.count)
                for index in 1..<curve.count {
                    arc.append(arc[index - 1]
                        + simd_distance(curve[index - 1], curve[index]))
                }
                wireArcs[wire.id] = arc
                // A re-lay can GROW the segment pool, and `layOut`
                // mints new cores in bare copper. The repaint below
                // only fires on a bucket change, and stretching a wire
                // changes no voltage — so without this the six fresh
                // segments of a newly hanging cable stay copper beside
                // one painted one. Forgetting the bucket forces the
                // repaint to cover them on this same pass.
                wireVoltBuckets[wire.id] = nil
            }

            // The wire wears its potential: warm = high, cool = low —
            // voltage differences readable at a glance across the bench.
            let span = model.voltageSpan
            let width = max(span.max - span.min, 0.5)
            let vA = model.terminalVoltages[wire.from] ?? 0
            let vB = model.terminalVoltages[wire.to] ?? 0
            let t = ((vA + vB) / 2 - span.min) / width
            // A lit net overrides the voltage ramp for as long as it
            // is lit. `-1` is the "currently wearing the highlight"
            // bucket, so dropping the highlight repaints exactly once.
            let lit = model.isHighlighted(wire: wire)
            let bucket = lit ? -1 : min(max(Int(t * 7.999), 0), 7)
            if wireVoltBuckets[wire.id] != bucket {
                wireVoltBuckets[wire.id] = bucket
                let material: RealityKit.Material = lit
                    ? Self.netHighlightMaterial
                    : Self.voltageMaterials[bucket]
                for segment in entity.children {
                    (segment as? ModelEntity)?.model?.materials = [material]
                }
            }
        }
    }

    private func terminalWorld(_ terminal: CircuitsModel.Terminal, _ model: CircuitsModel) -> SIMD3<Float>? {
        guard let component = model.components.first(where: { $0.id == terminal.componentID })
        else { return nil }
        // The model owns where a lead is, carried or not. (A branch
        // here followed the live entity instead, for the case where
        // the system held the transform — it had no writer and never
        // ran.)
        return SIMD3<Float>(component.terminalPosition(terminal.end))
    }

    // MARK: Electron flow (drift is − to +: opposite conventional current)

    /// ONE factor, applied to both true-speed visuals, so the ratio the
    /// eye sees is the ratio physics reports: display metres per second
    /// per real metre per second. Set so the signal — 2×10⁸ m/s — shows
    /// as 1 m/s, a front you can follow with your eyes. The electrons,
    /// multiplied by the very same number, come out at 10⁻¹³ m/s and
    /// stop dead. That is the lesson, not a bug.
    private static let trueSpeedGain = 1.0 / ChargeTransport.speedOfLight / 0.66

    /// How fast to slide electron beads along a conductor, in display
    /// metres per second, signed so they run AGAINST the conventional
    /// current.
    ///
    /// TWO SPEEDS, and only one of them is true. The default is the
    /// usual pretty lie every circuit animation tells: a rate picked to
    /// look like flow. True-speed mode replaces it with the real drift
    /// scaled by the SAME factor the field front is scaled by, so the
    /// ratio you see is the ratio that exists — which means the
    /// electrons stop dead. That is the lesson, not a bug.
    static func electronDisplaySpeed(current: Double, model: CircuitsModel) -> Double {
        if model.trueSpeedMode {
            return model.driftSpeed * trueSpeedGain * (current > 0 ? -1 : 1)
        }
        return min(0.03 + 0.5 * abs(current), 0.35) * (current > 0 ? -1 : 1)
    }

    private let fieldFront = ModelEntity(
        mesh: .generateSphere(radius: 0.012),
        materials: [UnlitMaterial(color: UIColor(
            red: 1.0, green: 0.95, blue: 0.6, alpha: 1))])
    private var fieldFrontPhase = 0.0
    private var trueSpeedCallout: Callout?

    /// The race, made watchable: a bright front sprinting the loop at
    /// the signal's scaled speed while the electron dots hold still at
    /// theirs, and a readout naming both real times. The bulb lights
    /// because of the sprinter, not the crawlers.
    private func syncTrueSpeed(_ model: CircuitsModel, dt: Double) {
        guard model.trueSpeedMode, model.showElectronFlow,
              model.conductingPathLength > 1e-4, model.peakCurrent > 5e-4 else {
            fieldFront.isEnabled = false
            trueSpeedCallout?.isEnabled = false
            return
        }
        if fieldFront.parent == nil { viewRoot.addChild(fieldFront) }

        // Walk the carrying wires as one path and place the front on it.
        var runs: [(a: SIMD3<Float>, b: SIMD3<Float>, length: Float)] = []
        for wire in model.wires where abs(model.wireFlows[wire.id] ?? 0) > 5e-4 {
            guard let a = terminalWorld(wire.from, model),
                  let b = terminalWorld(wire.to, model) else { continue }
            runs.append((a, b, simd_distance(a, b)))
        }
        let total = runs.reduce(0) { $0 + $1.length }
        guard total > 1e-4, !runs.isEmpty else {
            fieldFront.isEnabled = false
            return
        }
        if !model.isPaused {
            // Same gain the electrons get — the front just happens to be
            // carrying a speed thirteen orders of magnitude larger.
            let displaySpeed = ChargeTransport.signalSpeed() * Self.trueSpeedGain
            fieldFrontPhase = (fieldFrontPhase + displaySpeed / Double(total) * dt)
                .truncatingRemainder(dividingBy: 1)
        }
        var walk = Float(fieldFrontPhase) * total
        var placed = false
        for run in runs {
            if walk <= run.length {
                fieldFront.position = run.a + (run.b - run.a) * (walk / max(run.length, 1e-5))
                placed = true
                break
            }
            walk -= run.length
        }
        fieldFront.isEnabled = placed

        if trueSpeedCallout == nil {
            let callout = Callout(color: UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1),
                                  textSize: 0.02, offset: SIMD3(0, 0.11, 0))
            callout.setAccessibilityName("Electron drift speed")
            viewRoot.addChild(callout.root)
            trueSpeedCallout = callout
        }
        trueSpeedCallout?.isEnabled = true
        // Parked at the bench, NOT on the field front.
        //
        // It rode the front for a long time, which meant the most
        // quotable text in the app was pinned to the fastest-moving
        // object in it: unreadable while it swept the loop, and
        // impossible to catch in a still frame. The number is a fact
        // about the whole circuit, not about a position on it.
        trueSpeedCallout?.anchor(at: Self.benchPivot + SIMD3(0, 0.26, 0))
        trueSpeedCallout?.setText(
            "electron: \(Self.humanTime(model.driftLapTime)) per lap\n"
            + "field: \(Self.humanTime(model.signalLapTime))")
    }

    /// Nanoseconds to years, in whatever unit makes the number speak.
    private static func humanTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        switch seconds {
        case ..<1e-6: return PhysicsFormat.measurement(seconds * 1e9, "ns", decimals: 1)
        case ..<1e-3: return PhysicsFormat.measurement(seconds * 1e6, "µs", decimals: 1)
        case ..<1: return PhysicsFormat.measurement(seconds * 1e3, "ms", decimals: 1)
        case ..<60: return PhysicsFormat.measurement(seconds, "s", decimals: 1)
        case ..<3600: return PhysicsFormat.measurement(seconds / 60, "min", decimals: 1)
        case ..<86_400: return PhysicsFormat.measurement(seconds / 3600, "h", decimals: 1)
        default: return PhysicsFormat.measurement(seconds / 86_400, "days", decimals: 1)
        }
    }

    private func syncElectrons(_ model: CircuitsModel, dt: Double) {
        syncTrueSpeed(model, dt: dt)
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
            driftDots(key: wire.id, along: wireCurves[wire.id] ?? [a, b],
                      current: model.wireFlows[wire.id] ?? 0,
                      model: model, dt: dt, dotIndex: &dotIndex)
        }
        for index in dotIndex..<electronPool.budget {
            electronPool.slots[index].entity.isEnabled = false
        }
    }

    /// Lays a run of drifting electron dots between two points, advancing
    /// their shared phase by the current's drift speed (− to +, opposite
    /// the conventional arrow) over the real elapsed time.
    /// Where a given distance along the polyline lands.
    private func point(onCurve curve: [SIMD3<Float>], arc: [Float],
                       at distance: Float) -> SIMD3<Float> {
        var index = 1
        while index < arc.count - 1 && arc[index] < distance { index += 1 }
        let spanStart = arc[index - 1]
        let spanLength = max(arc[index] - spanStart, 1e-6)
        let t = min(max((distance - spanStart) / spanLength, 0), 1)
        return curve[index - 1] + (curve[index] - curve[index - 1]) * t
    }

    /// Beads riding a wire, spaced along its ARC — so on a hanging
    /// cable they follow the droop rather than cutting through the
    /// air beneath it.
    private func driftDots(
        key: UUID, along curve: [SIMD3<Float>],
        current: Double, model: CircuitsModel, dt: Double, dotIndex: inout Int
    ) {
        guard abs(current) > 5e-4, curve.count >= 2 else { return }

        // Cumulative arc length, so `t` is a fraction of the distance
        // TRAVELLED and the beads stay evenly spaced around the curve
        // instead of bunching where it bends. Cached beside the curve in
        // `syncWires` and rebuilt only when an end moves; built here
        // only for a run with no cache entry (or a stale one — the
        // count check catches the `?? [a, b]` fallback curve).
        let arc: [Float]
        if let cached = wireArcs[key], cached.count == curve.count {
            arc = cached
        } else {
            var built: [Float] = [0]
            built.reserveCapacity(curve.count)
            for index in 1..<curve.count {
                built.append(built[index - 1]
                    + simd_distance(curve[index - 1], curve[index]))
            }
            arc = built
        }
        let total = arc[arc.count - 1]
        guard total > 1e-6 else { return }
        let length = Double(total)
        // Bead count grows with the zoom, but SUBLINEARLY, and the
        // exponent is the whole subtlety here.
        //
        // The pool hangs under `viewRoot`, so the beads are scaled by
        // the zoom exactly like the wire they ride: at 4x a bead is 4x
        // fatter and a gap 4x wider, and the picture is unchanged. A
        // flat model-space spacing is therefore already correct — it is
        // the CAP of 9 that starves the moment, because Electron View
        // puts you inside one long wire and nine beads on a barrel that
        // fills your view reads as a dotted line, not a current.
        //
        // Dividing the spacing by the full zoom (the obvious fix) packs
        // them until they overlap into a striped tube, because the
        // beads grew too. The square root splits the difference: denser
        // when you are inside the wire, still visibly separate beads.
        //
        // The pool remains the ceiling — EntityPool's contract is to
        // show what the budget affords rather than drop frames — so the
        // loop below stops at the budget regardless.
        let zoom = Double(max(benchScale, 1))
        let spacing = 0.045 / zoom.squareRoot()
        let cap = Int((9 * zoom).rounded())
        let dots = min(max(Int(length / spacing), 2), cap)
        let speed = Self.electronDisplaySpeed(current: current, model: model)
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
            slot.entity.position = point(onCurve: curve, arc: arc, at: Float(t) * total)
            dotIndex += 1
        }
    }
}
