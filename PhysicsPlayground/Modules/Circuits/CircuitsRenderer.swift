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
    /// cannot pull. It is the terminal's activate; the pinch path never calls it.
    var onTerminalAction: ((CircuitsModel.Terminal) -> Void)?
    /// VoiceOver's switch toggle, its own callback because the physical tap
    /// path only selects a lever.
    var onLeverAction: ((UUID) -> Void)?
    /// VoiceOver's wire removal: the pinch path deletes a wire by pulling
    /// it into open air, so its activate deletes directly.
    var onWireAction: ((UUID) -> Void)?
    /// VoiceOver's turn of the stage: a hand turns it by its rim, which
    /// VoiceOver cannot, so activating the rim turns the circuit 45°.
    var onStageAction: (() -> Void)?

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

    /// The lead's touch target — the bead and the carry target are both sized
    /// against it. The collider rule allows (0.017 + 0.030) / 2 round a dot.
    static let terminalTargetRadius: Float = 0.023

    private struct ComponentVisual {
        let holder: Entity
        let body: ModelEntity
        /// The resistor's procedural ceramic, which wears the live bands.
        var ceramic: ModelEntity?
        /// The terminals: each a holder for its brass dot.
        var terminals: [Entity]
        /// Each lead's line, coloured by its terminal's net like a wire.
        var leads: [Entity] = []
        var leadBuckets: [Int] = [Int.min, Int.min]
        /// Each lead's current accessibility value — unchanged state costs no write.
        var terminalValues: [String] = ["", ""]
        /// Whether each lead is in a joint: its dot hidden for the junction
        /// dot and its target withdrawn — changed only when it moves.
        var terminalJoined: [Bool] = [false, false]
        let label: BackedLabel
        /// Selection is told by the part's own outline (`outlineSlots`),
        /// lit toward white as `selectionLevel` rises; written only when its
        /// step moves.
        var outline: [OutlineSlots] = []
        var selectionLevel: Float = 0
        var selectionStep = 0
        var glow: ModelEntity?
        var filament: Entity?
        /// The bulb's own light on the parts round it.
        var light: Entity?
        var lever: Entity?
        /// The drawn blade, rad: thrown open on the house spring, falling on
        /// the model's own clock when it closes (`closingIn`), bouncing in
        /// its contact once it lands.
        var blade = Motion.Spring(0)
        var bladeFalling = false
        /// Motors only: the flywheel that turns with the shaft, its blur
        /// at speed, and the rotor's own materials to put back.
        var rotor: Entity?
        var rotorBlur: Entity?
        var rotorDress: Dress?
        var blurred = false
        /// The fuse's middle filament segment, gone when it blows, and its
        /// glass, scorched with it.
        var fuseBridge: Entity?
        var fuseGlass: Entity?
        var fuseGlassDress: Dress?
        /// The capacitor's plates, tinted by the charge on them.
        var plates: [Entity] = []
        var plateDresses: [Dress] = []
        var chargeBucket = Int.min
        /// The AC source's bead, riding the sine at the source's phase.
        var bead: Entity?
        /// The LED's epoxy cone, lit red when it conducts and dark once
        /// burned out, and its own materials to put back.
        var ledCore: Entity?
        var ledDress: Dress?
        let labelPivot: Entity
        /// The axis and stage yaw the orientation was last built for, the
        /// frame built, and whether the drawn frame is still easing to it.
        var orientedFor: (axis: SIMD3<Float>, yaw: Double)?
        var targetOrientation: simd_quatf?
        var easingOrientation = false
        var fuseIntact: Bool?
        var ledState = Int.min
        var labelText = ""
        /// What VoiceOver last heard the part say about itself.
        var spokenState = ""
        var glowBucket = -1
        var resistorCodeKey = ""
        /// Resistors: how hot, 0…4 by dissipation against the rating,
        /// −2 once scorched — the material is rebuilt only when it moves.
        var heatBucket = -1
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
    /// Towers whose label the rate limit held back; offered again next frame.
    private var towerLabelsPending: Set<Int> = []
    private var towerLabelPivots: [Entity] = []
    /// The colour step each tower wears — unchanged potential costs no material write.
    private var towerBuckets: [Int] = []

    /// The bench's own magnetic field. Deliberately modest budget: what teaches
    /// is arrows circling a wire, not a room-filling fog.
    private let fieldArrows = VectorFieldArrows(count: 260)
    /// How many runs get rings, longest first.
    private static let fieldRunBudget = 10
    /// Rings per run, and arrows per ring.
    private static let fieldStations = 3
    private static let fieldSpokes = 8
    /// Ring offset: far enough that the 1/d field is not a spike, close enough
    /// that the circulation reads as belonging to this wire.
    private static let fieldRingRadius: Double = 0.055

    /// The dots a bench may show at once (contract D5's fallback): one
    /// draw each, shared out among the wires when a bench wants more.
    static let electronBudget = 120
    let electronDots = ElectronDots(capacity: electronBudget)
    private var electronsVisible = false
    private var fieldArrowsVisible = false
    /// The segments the field arrows were last drawn from — nil when the layer
    /// is off, so re-enabling always redraws.
    private var lastFieldSegments: [WireField.Segment]?
    private var lastCoils: [BarMagnet]?

    private let audioEmitter = Entity()
    private var lastSoundID = 0
    private var appliedResistorTextureVersion = -1

    /// The wire core. Static so `makeBody` can be too: the palette's previews
    /// are built before any renderer exists to own a copper.
    private static let copperMaterial = Materials.machined(
        DesignTokens.Palette.copperUI, roughness: 0.35)


    /// The bench's view transform: `root` belongs to the lab placement,
    /// `viewRoot` to the zoom — one transform each, so they cannot fight.
    let viewRoot = Entity()

    /// The turntable under the floating circuit (2026-10-18): deck and rim,
    /// inside the zoom with the bench, taking the parts' shadows. Its height
    /// eases to the model's (`CircuitsModel.settleStage`), and it fades out as
    /// a two-hand zoom passes 1.25×, so a dive into the copper never stands a
    /// metres-wide disc below the floor.
    private let stageRoot = Entity()
    private var stageTop: Float?
    private var appliedStageOpacity: Float = -1

    init() {
        root.addChild(viewRoot)
        stageRoot.name = "circuit-stage"
        if let deck = PropCache.instance(named: "CircuitStageDeck") {
            deck.name = Self.stageDeckName
            deck.components.set(CollisionComponent(shapes: Self.deckBandShapes()))
            deck.components.set(InputTargetComponent())
            stageRoot.addChild(deck)
        }
        if let rim = PropCache.instance(named: "CircuitStageRim") {
            rim.name = Self.stageRimName
            rim.components.set(CollisionComponent(shapes: Self.rimShapes()))
            rim.components.set(InputTargetComponent())
            rim.components.set(HoverEffectComponent())
            stageRoot.addChild(rim)
        }
        GroundingShadows.receive(on: stageRoot)
        viewRoot.addChild(stageRoot)
        root.addChild(Lighting.keyLight())

        viewRoot.addChild(electronDots.root)
        viewRoot.addChild(fieldArrows.root)
        fieldArrows.hideAll()

        selectedAnchor.components.set(BillboardComponent())
        viewRoot.addChild(selectedAnchor)

        skylineRoot.isEnabled = false
        viewRoot.addChild(skylineRoot)

        audioEmitter.components.set(SpatialAudioComponent())
        viewRoot.addChild(audioEmitter)

        if let rim = stageRoot.findEntity(named: Self.stageRimName) {
            SpatialActions.attach(
                to: rim, label: "Turntable. Activate to turn the circuit 45 degrees.",
                activate: { [weak self] in self?.onStageAction?() })
        }

    }

    /// The electron's core and halo: the milled low-poly pair (400
    /// triangles, contract D5) — `generateSphere` is 8,064 each, whatever
    /// the radius — or, missing, those spheres.
    static func electronMeshes() -> (core: MeshResource, halo: MeshResource) {
        func mesh(_ name: String) -> MeshResource? {
            PropCache.prototype(named: electronAssetName)?.findEntity(named: name)
                .flatMap { entity in
                    entity.components[ModelComponent.self]?.mesh
                        ?? entity.children.lazy.compactMap { $0.components[ModelComponent.self]?.mesh }.first
                }
        }
        return (mesh("core") ?? Primitives.sphere(radius: 0.0026),
                mesh("halo") ?? Primitives.sphere(radius: 0.0045))
    }

    // MARK: The bench's magnetic field

    /// Places arrows on rings around each current-carrying run, never a
    /// volume grid. Each vector is the total field from every segment, so
    /// nearby wires visibly reinforce or cancel.
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

        // Change-gated: a static bench costs one array compare; a carried part
        // changes the segments every frame.
        let segments = model.currentSegments
        let coils = model.coilMagnets
        guard segments != lastFieldSegments || coils != lastCoils else { return }
        lastFieldSegments = segments
        lastCoils = coils

        guard !segments.isEmpty || !coils.isEmpty else {
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
            // The world axis the run is least aligned with keeps the cross
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
                    // The total field — every segment and every coil.
                    vectors.append(model.magneticField(at: point))
                }
            }
        }

        // The coil is a magnet: rings around each carrying inductor's axis, out
        // past its ends where a bar field closes, plus the axis itself.
        for coil in coils {
            let axis = simd_normalize(coil.moment)
            let reference: SIMD3<Double> = abs(axis.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
            let u = simd_normalize(simd_cross(axis, reference))
            let v = simd_cross(axis, u)
            for station in stride(from: -0.12, through: 0.12, by: 0.06) {
                let centre = coil.position + axis * station
                for spokeIndex in 0..<Self.fieldSpokes {
                    let angle = 2 * Double.pi * Double(spokeIndex) / Double(Self.fieldSpokes)
                    let point = centre + (u * cos(angle) + v * sin(angle)) * Self.coilRingRadius
                    points.append(point)
                    vectors.append(model.magneticField(at: point))
                }
            }
            for end in [-0.16, 0.16] {
                let point = coil.position + axis * end
                points.append(point)
                vectors.append(model.magneticField(at: point))
            }
        }
        fieldArrows.update(points: points, vectors: vectors,
                           hidden: Array(repeating: false, count: points.count))
    }
    /// Wider than a wire's ring: the windings are 0.019 m and the arrows
    /// must stand clear of the part they describe.
    private static let coilRingRadius: Double = 0.07

    /// Distance from a point to a segment — clamped to the ends, not the
    /// infinite line.
    private static func distance(from point: SIMD3<Double>,
                                 to segment: WireField.Segment) -> Double {
        let along = segment.b - segment.a
        let lengthSquared = simd_length_squared(along)
        guard lengthSquared > 1e-12 else { return simd_distance(point, segment.a) }
        let t = min(max(simd_dot(point - segment.a, along) / lengthSquared, 0), 1)
        return simd_distance(point, segment.a + along * t)
    }

    // MARK: The Solid Schematic (2026-10-30)

    /// The numbers the assets and this renderer share, as `Tools/circuitparts.py`
    /// mills them — `CircuitPropTests` holds each to its literal there.
    /// A terminal's brass dot (`CircuitDot.usdz`).
    nonisolated static let contactRadius: Float = 0.0085
    /// A joint's two dots drawn as one junction dot, this much larger.
    nonisolated static let junctionScale: Float = 1.25
    /// A wire's core and its dark jacket — and a lead's: leads and wires are
    /// one line (contract D1).
    nonisolated static let wireCoreRadius: Float = 0.0022
    nonisolated static let wireJacketRadius: Float = 0.0037
    /// Every element stays inside |x| < this; the leads are drawn here.
    nonisolated static let elementClamp: Float = 0.060
    /// The switch's blade turns about +z through this point, and opens to
    /// the symbol's own angle.
    nonisolated static let switchPivot = SIMD3<Float>(-0.032, 0, 0)
    nonisolated static let switchOpenAngle: Float = 30 * .pi / 180
    /// The AC source's wave: half-width, amplitude, and the plane it lies
    /// in; the bead rides it this far in front.
    nonisolated static let acWaveHalfWidth: Float = 0.018
    nonisolated static let acWaveAmplitude: Float = 0.0075
    nonisolated static let acBeadZ: Float = 0.0069
    /// Where each part's leads stop, −X end then +X end: the element's own
    /// surface (`LEAD_INNER`).
    nonisolated static let leadInner: [CircuitsModel.ComponentKind: SIMD2<Float>] = [
        .battery: [-0.012, 0.014], .acSource: [-0.035, 0.035],
        .resistor: [-0.0255, 0.0255], .capacitor: [-0.007, 0.0075],
        .inductor: [-0.027, 0.027], .bulb: [-0.0345, 0.0345],
        .led: [-0.012, 0.007], .motor: [-0.014, 0.014],
        .fuse: [-0.028, 0.028], .switcher: [-0.040, 0.040],
    ]
    static let dotAssetName = "CircuitDot"
    static let electronAssetName = "CircuitElectron"
    /// The shelf shows each module at this fraction of its size, so a whole
    /// module — dots and all — fits a slot.
    nonisolated static let shelfPreviewScale: Float = 0.60
    /// The capacitor's charge, full at the bench's tallest source, V.
    nonisolated static let gaugeFullScale = 24.0

    private static let contactMaterial = Materials.machined(
        DesignTokens.Palette.contactBrassUI, roughness: 0.28)

    /// One part as built: its milled element and the pieces that move or
    /// light in it, its two dots and two leads, for `makeVisual`, the shelf
    /// and the home's diorama to share.
    struct Module {
        let root: Entity
        let body: ModelEntity
        var ceramic: ModelEntity?
        var contacts: [Entity] = []
        var leads: [Entity] = []
        var filament: Entity?
        var glow: ModelEntity?
        var light: Entity?
        var rotor: Entity?
        var rotorBlur: Entity?
        var lever: Entity?
        var fuseBridge: Entity?
        var fuseGlass: Entity?
        var plates: [Entity] = []
        var bead: Entity?
        var ledCore: Entity?
    }

    static func makeModule(kind: CircuitsModel.ComponentKind) -> Module {
        let root = Entity()
        let (body, ceramic) = makeBody(kind: kind)
        root.addChild(body)
        var module = Module(root: root, body: body, ceramic: ceramic)
        let span = Float(CircuitsModel.terminalOffset)
        let inner = leadInner[kind] ?? [-0.03, 0.03]
        for end in 0...1 {
            let sign: Float = end == 0 ? -1 : 1
            let contact = makeDot()
            contact.position = [sign * span, 0, 0]
            root.addChild(contact)
            module.contacts.append(contact)
            let lead = makeLine(from: [sign * span, 0, 0], to: [end == 0 ? inner.x : inner.y, 0, 0])
            lead.name = "lead\(end)"
            root.addChild(lead)
            module.leads.append(lead)
        }
        // The live pieces are the asset's own named children; renamed here
        // to the names the bench has always looked them up by.
        func child(_ name: String, as renamed: String) -> Entity? {
            let found = body.findEntity(named: name)
            found?.name = renamed
            return found
        }
        switch kind {
        case .bulb:
            module.filament = child("filament", as: "bulb-filament")
            let glow = GlowSprite.make(size: 0.10)
            glow.isEnabled = false
            root.addChild(glow)
            module.glow = glow
            let light = Entity()
            root.addChild(light)
            module.light = light
        case .led:
            module.ledCore = child("core", as: "led-core")
            let glow = GlowSprite.make(size: 0.06)
            glow.isEnabled = false
            root.addChild(glow)
            module.glow = glow
            let light = Entity()
            light.position = [0, 0.010, 0]
            root.addChild(light)
            module.light = light
        case .motor:
            module.rotor = child("rotor", as: "motor-rotor")
            module.rotorBlur = child("rotor_blur", as: "motor-rotor-blur")
            module.rotorBlur?.isEnabled = false
        case .switcher:
            module.lever = child("blade", as: "switch-blade")
        case .fuse:
            module.fuseBridge = child("fuse_bridge", as: "fuse-bridge")
            module.fuseGlass = child("fuse_glass", as: "fuse-glass")
        case .capacitor:
            module.plates = [child("plate0", as: "capacitor-plate-0"),
                             child("plate1", as: "capacitor-plate-1")].compactMap { $0 }
        case .acSource:
            module.bead = child("bead", as: "ac-bead")
        default:
            break
        }
        return module
    }

    /// A terminal's brass dot, the milled one or, missing, a sphere.
    static func makeDot() -> Entity {
        let holder = Entity()
        if let dot = PropCache.instance(named: dotAssetName) {
            holder.addChild(dot)
        } else {
            holder.addChild(ModelEntity(mesh: Primitives.sphere(radius: contactRadius),
                                        materials: [contactMaterial]))
        }
        return holder
    }

    /// The line the bench draws for a lead or a wire: a voltage-coloured
    /// core in a dark jacket, a unit segment stretched by its transform.
    static func makeLine(from a: SIMD3<Float>, to b: SIMD3<Float>) -> Entity {
        let line = Entity()
        let core = ModelEntity(mesh: Primitives.cylinder(height: 1, radius: wireCoreRadius),
                               materials: [voltageMaterials[3]])
        core.name = "cable"
        let jacket = ModelEntity(mesh: Primitives.cylinder(height: 1, radius: wireJacketRadius),
                                 materials: [wireJacketMaterial])
        jacket.name = "jacket"
        core.addChild(jacket)
        line.addChild(core)
        let direction = b - a
        let length = simd_length(direction)
        if length > 1e-6 {
            core.position = (a + b) / 2
            core.orientation = VectorFieldArrows.rotationFromYAxis(to: direction / length)
            core.scale = SIMD3(1, length, 1)
        } else {
            core.isEnabled = false
        }
        return line
    }

    /// Every material a piece wears, to put back after a state has dressed it.
    struct Dress {
        private var saved: [(entity: Entity, materials: [RealityKit.Material])] = []

        init(_ entity: Entity?) {
            guard let entity else { return }
            var stack = [entity]
            while let next = stack.popLast() {
                if let model = next.components[ModelComponent.self] {
                    saved.append((next, model.materials))
                }
                stack.append(contentsOf: next.children)
            }
        }

        func restore() {
            for (entity, materials) in saved {
                guard var model = entity.components[ModelComponent.self] else { continue }
                model.materials = materials
                entity.components.set(model)
            }
        }
    }

    /// Dresses every mesh under `entity` in one material.
    static func dress(_ entity: Entity?, _ material: RealityKit.Material) {
        guard let entity else { return }
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { _ in material }
            entity.components.set(model)
        }
        for child in entity.children { dress(child, material) }
    }

    // MARK: Selection is the part's own outline (2026-11-02)
    //
    // A selected part used to stand in a rounded white box at 22 %, which the
    // owner read as a hitbox. Now the symbol says it: its champagne keyline
    // lights toward white, as a schematic draws a selected symbol in another
    // ink. Nothing is added round the part.

    /// The material slots of one mesh that a selection lights, and what they
    /// wear unselected.
    struct OutlineSlots {
        let entity: ModelEntity
        let slots: [Int]
        let rest: [RealityKit.Material]
    }

    /// The material every symbol is keylined in (`Tools/circuitparts.py`).
    nonisolated static let keylineMaterialName = "CircuitChampagne"
    /// The steps the outline lights through on its way to white over the
    /// house fade: a handful of material writes per selection change, none
    /// while it rests.
    nonisolated static let selectionSteps = 4
    /// How bright a fully lit outline glows. No part's own material glows,
    /// so this is also how a test tells a lit outline from a resting one.
    nonisolated static let selectionGlow: Float = 0.9
    private static var litMaterials: [String: RealityKit.Material] = [:]

    /// Where a part shows its selection: the keyline, wherever it is drawn.
    /// The coil and the fuse have none, so theirs is the element itself (the
    /// copper helix, the brass caps), the mesh named for the asset; a
    /// stand-in body for a missing asset lights whole.
    static func outlineSlots(of body: ModelEntity,
                             kind: CircuitsModel.ComponentKind) -> [OutlineSlots] {
        let elementName = bodyAssetNames[kind] ?? resistorCapsAssetName
        var keyline: [OutlineSlots] = []
        var element: [OutlineSlots] = []
        func walk(_ entity: Entity, inElement: Bool) {
            let inElement = inElement || entity.name == elementName
            if let model = entity as? ModelEntity, let materials = model.model?.materials,
               !materials.isEmpty {
                let named = materials.indices.filter {
                    (materials[$0] as? PhysicallyBasedMaterial)?.name == keylineMaterialName
                }
                if !named.isEmpty {
                    keyline.append(.init(entity: model, slots: named,
                                         rest: named.map { materials[$0] }))
                } else if inElement {
                    element.append(.init(entity: model, slots: Array(materials.indices),
                                         rest: materials))
                }
            }
            for child in entity.children { walk(child, inElement: inElement) }
        }
        walk(body, inElement: false)
        if !keyline.isEmpty { return keyline }
        if !element.isEmpty { return element }
        guard let materials = body.model?.materials, !materials.isEmpty else { return [] }
        return [.init(entity: body, slots: Array(materials.indices), rest: materials)]
    }

    /// `rest`, lit `step` of `selectionSteps` of the way to white.
    static func lit(_ rest: RealityKit.Material, step: Int) -> RealityKit.Material {
        guard step > 0, var pbr = rest as? PhysicallyBasedMaterial else { return rest }
        let key = pbr.name.map { "\($0)#\(step)" }
        if let key, let cached = litMaterials[key] { return cached }
        let t = CGFloat(step) / CGFloat(selectionSteps)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        pbr.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        pbr.baseColor.tint = UIColor(red: r + (1 - r) * t, green: g + (1 - g) * t,
                                     blue: b + (1 - b) * t, alpha: a)
        pbr.emissiveColor = .init(color: .white)
        pbr.emissiveIntensity = selectionGlow * Float(t)
        if let key { litMaterials[key] = pbr }
        return pbr
    }

    /// Eases a part's outline toward lit or rest over the house fade, and
    /// writes its materials only when the step moves.
    private static func tickSelection(_ visual: inout ComponentVisual, selected: Bool,
                                      dt: Double) {
        let target: Float = selected ? 1 : 0
        if Motion.isReduced {
            visual.selectionLevel = target
        } else {
            let step = Float(dt / Fade.duration)
            visual.selectionLevel = target > visual.selectionLevel
                ? min(visual.selectionLevel + step, target)
                : max(visual.selectionLevel - step, target)
        }
        let step = Int((visual.selectionLevel * Float(selectionSteps)).rounded())
        guard step != visual.selectionStep else { return }
        visual.selectionStep = step
        for outline in visual.outline {
            guard var model = outline.entity.model else { continue }
            for (slot, rest) in zip(outline.slots, outline.rest)
            where model.materials.indices.contains(slot) {
                model.materials[slot] = lit(rest, step: step)
            }
            outline.entity.model = model
        }
    }

    /// The steepest a wearer looks down onto a part's rail, as a slope: tan
    /// 40°. A target's front face hangs this much lower in the eye than it
    /// stands, for every metre it stands toward the viewer. Leaning in to
    /// look 35° down at a part puts the rail under it nearer 41°, which is
    /// what the lying battery found at tan 35°.
    nonisolated static let lookDownSlope: Float = 0.84

    /// How far a part's own pinch targets (its carry box, its dots, a
    /// switch's blade) reach below its centre as the wearer sees them, in
    /// the bench's frame: each target's lowest corner, lowered by how far it
    /// stands toward the viewer × `lookDownSlope`. Its value track hangs
    /// below this (`Bloom.Grip.Track.clearsBelow`), so the part never takes
    /// a pinch meant for the rail. Nil for a part not drawn yet.
    func targetReachBelow(of id: UUID, towardViewer: SIMD3<Float>) -> Float? {
        guard let holder = visuals[id]?.holder else { return nil }
        let flat = SIMD3<Float>(towardViewer.x, 0, towardViewer.z)
        let toward = simd_length(flat) > 1e-4 ? simd_normalize(flat) : SIMD3<Float>(0, 0, 1)
        let centre = holder.position(relativeTo: viewRoot)
        var reach: Float = 0
        func walk(_ entity: Entity) {
            guard entity.isEnabled else { return }
            if let collision = entity.components[CollisionComponent.self] {
                for shape in collision.shapes {
                    let box = shape.bounds
                    for corner in 0..<8 {
                        let local = SIMD3<Float>(corner & 1 == 0 ? box.min.x : box.max.x,
                                                 corner & 2 == 0 ? box.min.y : box.max.y,
                                                 corner & 4 == 0 ? box.min.z : box.max.z)
                        let p = entity.convert(position: local, to: viewRoot) - centre
                        reach = max(reach, -p.y + max(simd_dot(p, toward), 0) * Self.lookDownSlope)
                    }
                }
            }
            entity.children.forEach(walk)
        }
        walk(holder)
        return reach
    }

    /// How far from the stage's front a part's axis must lie (the sine of
    /// the angle between them) before "its face toward the front" means
    /// anything.
    nonisolated static let faceThreshold: Float = 0.26

    /// The angle of a part's frame (contract D7): x along its axis and, so
    /// that a symbol drawn in the part's face plane reads from where the
    /// wearer stands, its face (+z) toward the stage's front — lying or
    /// standing. A part lying along x keeps its +y to the sky; one standing
    /// on end turns its face to the front and its +y to the side. (Until
    /// 2026-10-30 the rule turned a lab-kit carrier's TOP to the sky, which
    /// put a standing part's face plane edge-on to the wearer.)
    ///
    /// Within 15° of pointing at the front a face can no longer face it — it
    /// would wheel round the axis as a hand wobbled — so there the frame is
    /// the `previous` one carried onto the new axis by the shortest arc,
    /// keeping its roll; with none, its face turns to the sky. Turns rigidly
    /// with the stage.
    nonisolated static func moduleOrientation(axis: SIMD3<Float>, front: SIMD3<Float>,
                                              previous: simd_quatf? = nil) -> simd_quatf {
        let x = simd_normalize(axis)
        let facing = front - simd_dot(front, x) * x
        if simd_length(facing) >= faceThreshold {
            return frame(x: x, face: facing)
        }
        if let previous {
            let carried = rotation(from: previous.act([1, 0, 0]), to: x) * previous
            return frame(x: x, face: carried.act([0, 0, 1]))
        }
        let up = SIMD3<Float>(0, 1, 0)
        var face = up - simd_dot(up, x) * x
        if simd_length(face) < 1e-4 {
            face = SIMD3<Float>(1, 0, 0) - simd_dot(SIMD3<Float>(1, 0, 0), x) * x
        }
        return frame(x: x, face: face)
    }

    private nonisolated static func frame(x: SIMD3<Float>, face: SIMD3<Float>) -> simd_quatf {
        let z = simd_normalize(face - simd_dot(face, x) * x)
        return simd_quatf(simd_float3x3(columns: (x, simd_cross(z, x), z)))
    }

    /// A frame change bigger than this eases rather than snaps: a swing
    /// across the threshold, a part flipped end-for-end. A hand's own motion
    /// moves a part a few degrees a frame.
    nonisolated static let orientationEaseThreshold: Float = 10 * .pi / 180

    /// Where a part's value hangs, in the room, from its centre: below it,
    /// clear of the largest element (the motor's 40 mm flywheel), or beside
    /// it once it stands nearly on end and below is its own lower dot — on
    /// the side away from a switch's knob.
    nonisolated static func labelOffset(for orientation: simd_quatf) -> SIMD3<Float> {
        let x = orientation.act([1, 0, 0])
        let side = orientation.act([0, -1, 0])
        let t = min(max((abs(x.y) - 0.70) / 0.25, 0), 1)
        let w = t * t * (3 - 2 * t)
        return (1 - w) * SIMD3(0, -0.056, 0) + w * side * 0.060
    }

    /// The direction the stage faces you from, turned with the stage.
    nonisolated static func stageFront(yaw: Double) -> SIMD3<Float> {
        SIMD3(Float(sin(yaw)), 0, Float(cos(yaw)))
    }

    /// A resistor's ceramic in its live bands.
    static func paintResistor(_ ceramic: ModelEntity, ohms: Double) -> Bool {
        guard let texture = CircuitTextures.resistorTexture(ohms: ohms) else { return false }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.roughness = 0.6
        ceramic.model?.materials = [material]
        return true
    }

    // MARK: The parts palette

    /// One part for a `Well` preview: the whole module, carrier and contacts,
    /// at `shelfPreviewScale`, so the preview and the object it makes are one
    /// thing that fits its slot.
    static func partPreview(for kind: CircuitsModel.ComponentKind,
                            scale: Float = shelfPreviewScale) -> Entity {
        let module = makeModule(kind: kind)
        if let ceramic = module.ceramic {
            // The bands are drawn off the main thread, so the first shelf
            // may be built before they exist; it is banded when they land.
            CircuitTextures.withResistorTexture(ohms: kind.defaultValue) { [weak ceramic] _ in
                if let ceramic { _ = paintResistor(ceramic, ohms: kind.defaultValue) }
            }
        }
        module.root.scale = SIMD3(repeating: scale)
        let holder = Entity()
        holder.addChild(module.root)
        return holder
    }

    // MARK: Render clock
    // Ticked from SceneEvents.Update, not the observation loop: a steady
    // DC circuit gives it nothing to re-fire on.

    /// Drives the armed-terminal pulse.
    private var pendingPulsePhase = 0.0

    // MARK: Connection previews & drag-to-wire

    /// While this part is carried, ghost wires show what a release would connect.
    var previewComponentID: UUID?
    /// Where the selected part's card stands while its ring is open, in
    /// the billboarded anchor's frame: 15 cm to the viewer's left and 5 cm
    /// lower, clear of the petals at any distance the ring is read from.
    nonisolated static let readoutAside = SIMD3<Float>(-0.15, -0.05, 0)

    /// The part whose ring is open. Its bead's callout carries its number
    /// there, so where the part's own label says the same thing it stands
    /// down: the track runs under the part, through where the label hangs.
    var ringPartID: UUID?
    /// Terminals currently highlighted as connection targets.
    private(set) var previewTargets: Set<CircuitsModel.Terminal> = []
    private var previewWireEntities: [ModelEntity] = []

    /// The terminals a carried part would be refused against, found while
    /// drawing its previews: their nets light, so the "no" shows the
    /// connection that is already there.
    private var refusedPreviewTargets: [CircuitsModel.Terminal] = []
    /// A refused join's net stays lit this long after the release.
    nonisolated static let refusalLinger = 0.8
    private var lingeringRefusal: (terminal: CircuitsModel.Terminal, remaining: Double)?
    private var lastNetRefusalSerial = 0

    /// The lead in flight. Fatter than a wire's jacket, or a lead lying
    /// along an existing wire is swallowed by it — the refusal case.
    private static let flyingLeadRadius: Float = 0.008

    private lazy var flyingLead: ModelEntity = {
        let lead = ModelEntity(
            mesh: Primitives.cylinder(height: 1, radius: Self.flyingLeadRadius),
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
    /// Refusing: a release right now would be declined. No text — the refusal
    /// is the recoil, red and shortened.
    private static let refusalMaterial: UnlitMaterial = {
        let material = Materials.unlit(DesignTokens.Palette.destructiveUI, opacity: 0.8)
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
        var pairs: [(a: SIMD3<Float>, b: SIMD3<Float>,
                     target: CircuitsModel.Terminal, refused: Bool)] = []
        if let id = previewComponentID {
            for pair in model.pendingJoins(for: id) {
                if let a = terminalWorld(pair.from, model),
                   let b = terminalWorld(pair.to, model) {
                    pairs.append((a, b, pair.to, false))
                }
            }
            // The joins a release would refuse, in the lead pull's red.
            for pair in model.refusedJoins(for: id) {
                if let a = terminalWorld(pair.from, model),
                   let b = terminalWorld(pair.to, model) {
                    pairs.append((a, b, pair.to, true))
                }
            }
        }
        // Only the joinable targets swell — never one that would refuse.
        previewTargets = Set(pairs.filter { !$0.refused }.map(\.target))
        refusedPreviewTargets = pairs.filter(\.refused).map(\.target)
        // A lead in flight swells its landing target on the same terms.
        if let pull = model.leadPull, pull.refusal == nil, let target = pull.target {
            previewTargets.insert(target)
        }

        while previewWireEntities.count < pairs.count {
            let ghost = ModelEntity(
                mesh: Primitives.cylinder(height: 1, radius: 0.0045),
                materials: [Self.previewMaterial])
            ghost.isEnabled = false
            viewRoot.addChild(ghost)
            previewWireEntities.append(ghost)
        }
        for (index, ghost) in previewWireEntities.enumerated() {
            if index < pairs.count {
                stretch(ghost, from: pairs[index].a, to: pairs[index].b)
                ghost.model?.materials = [pairs[index].refused
                    ? Self.refusalMaterial : Self.previewMaterial]
            } else {
                ghost.isEnabled = false
            }
        }
    }

    /// The zoom, as one number: Electron View is a floor under the same
    /// continuous two-hand zoom, not a competing 1×/4× flip.
    private var benchScale: Float = 1
    nonisolated static let benchPivot = SIMD3<Float>(0, 1.25, -0.85)

    /// A bench-space point in the room, through the zoom rig, for an
    /// instrument that hangs under a part without scaling with the bench.
    func worldPosition(ofBenchPoint point: SIMD3<Double>) -> SIMD3<Float> {
        viewRoot.position + SIMD3<Float>(point) * benchScale
    }
    /// Set by the space view from the two-handed scale rig.
    var handZoom: Float = 1

    /// Where the zoom is heading: the hands' own. Into the copper is a
    /// two-handed spread; the 4× Electron View switch that duplicated it
    /// went in the subtraction pass.
    private func targetZoom(_ model: CircuitsModel) -> Float {
        handZoom
    }

    // MARK: The bench's hum

    /// A mains hum whose loudness rides total current and whose pitch
    /// rises with dissipated power.
    private var hum: ToneVoice?

    private func tickHum(_ model: CircuitsModel) {
        if hum == nil { hum = ToneVoice(on: audioEmitter, tone: .hum, range: (-58)...(-26)) }
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
        if abs(benchScale - 1) < 1e-3, abs(target - 1) < 1e-3 {
            zoomPivot = Self.zoomPivot(for: model.stage)
        }
        if abs(benchScale - target) > 1e-3 {
            // Eased toward the target so an Electron View flick glides.
            benchScale += (target - benchScale) * Float(min(dt * 8, 1))
            viewRoot.scale = SIMD3(repeating: benchScale)
            viewRoot.position = zoomPivot * (1 - benchScale)
        }
        render(model, dt: dt)
    }

    /// Acknowledge a grab: the live glow and a tick on the part just taken.
    /// The glow stays until `flashRelease`. `tick` false for a part the
    /// shelf has just handed over, whose pop already spoke; a part born
    /// this frame has no visual yet, and takes its glow when it gets one.
    func flashPickup(id: UUID, tick: Bool = true) {
        landings[id] = nil
        carriedID = id
        guard let holder = visuals[id]?.holder else {
            pendingGlowID = id
            return
        }
        pendingGlowID = nil
        if let previous = pulsedGrabEntity, previous !== holder {
            LiveGlow.set(false, on: previous)
        }
        pulsedGrabEntity = holder
        LiveGlow.set(true, on: holder)
        if tick { SoundPalette.play(.grabTick, on: holder, volume: 0.2) }
    }

    /// A part taken before its visual existed (pulled off the shelf).
    private var pendingGlowID: UUID?

    /// Answer a release, on whatever was last picked up.
    func flashRelease() {
        carriedID = nil
        pendingGlowID = nil
        guard let entity = pulsedGrabEntity else { return }
        LiveGlow.set(false, on: entity)
        SoundPalette.play(.releaseTick, on: entity, volume: 0.18)
        pulsedGrabEntity = nil
    }

    // MARK: Taking hold of the stage (2026-10-18)

    nonisolated static let stageRimName = "circuit-stage-rim"
    nonisolated static let stageDeckName = "circuit-stage-deck"
    /// The rim's grab ring: capsules along the knurled band's centre line,
    /// as thick as the collider rule allows a 12 mm disc.
    nonisolated static let rimGrabRadius: Float = 0.020
    nonisolated static let rimGrabSegments = 48
    /// The deck takes a hand only on a band inside the rim — the middle,
    /// under the parts, takes nothing, so a pinch that misses a part never
    /// carries the whole circuit.
    nonisolated static let deckBand: ClosedRange<Float> =
        Float(CircuitsModel.stageRadius) - 0.12 ... Float(CircuitsModel.stageRadius) - 0.035
    nonisolated static let deckBandSegments = 24

    private static func rimShapes() -> [ShapeResource] {
        let radius = Float(CircuitsModel.stageRadius) - 0.009
        let step = 2 * Float.pi / Float(rimGrabSegments)
        let chord = 2 * radius * sin(step / 2)
        return (0..<rimGrabSegments).map { index in
            let angle = (Float(index) + 0.5) * step
            let centre = SIMD3(radius * cos(angle) * cos(step / 2), -0.006,
                               -radius * sin(angle) * cos(step / 2))
            let tangent = SIMD3(-sin(angle), 0, -cos(angle))
            return Primitives.collisionCapsule(height: chord + 2 * rimGrabRadius,
                                               radius: rimGrabRadius)
                .offsetBy(rotation: VectorFieldArrows.rotationFromYAxis(to: tangent),
                          translation: centre)
        }
    }

    private static func deckBandShapes() -> [ShapeResource] {
        let inner = deckBand.lowerBound, outer = deckBand.upperBound
        let step = 2 * Float.pi / Float(deckBandSegments)
        let width = 2 * outer * sin(step / 2)
        return (0..<deckBandSegments).map { index in
            let angle = Float(index) * step
            let middle = (inner + outer) / 2
            return Primitives.collisionBox(size: [outer - inner, 0.030, width])
                .offsetBy(rotation: simd_quatf(angle: angle, axis: [0, 1, 0]),
                          translation: SIMD3(middle * cos(angle), -0.006, -middle * sin(angle)))
        }
    }

    /// The zoom grows the bench about this point, which rides the stage
    /// while the bench is at 1× and holds still once a zoom is under way —
    /// a circuit carried a metre away still zooms about itself.
    nonisolated static func zoomPivot(for stage: CircuitsModel.Stage) -> SIMD3<Float> {
        let home = CircuitsModel.homeStage
        return benchPivot + SIMD3<Float>(Float(stage.center.x - home.center.x),
                                         Float(stage.top - home.top),
                                         Float(stage.center.y - home.center.y))
    }
    private var zoomPivot = CircuitsRenderer.benchPivot

    /// How opaque the stage is at a zoom: whole to 1.25×, gone by 2×.
    nonisolated static func stageOpacity(atZoom zoom: Float) -> Float {
        min(max((2 - zoom) / 0.75, 0), 1)
    }

    private func syncStage(_ model: CircuitsModel, dt: Double) {
        let stage = model.stage
        let target = Float(stage.top)
        // The house ease, so a 0.9 m disc does not glide under Reduce Motion.
        let top = Motion.ease(stageTop ?? target, toward: target, dt: dt, rate: 6)
        stageTop = top
        stageRoot.position = SIMD3(Float(stage.center.x), top, Float(stage.center.y))
        stageRoot.orientation = simd_quatf(angle: Float(stage.yaw), axis: [0, 1, 0])
        let opacity = Self.stageOpacity(atZoom: benchScale)
        if abs(opacity - appliedStageOpacity) > 0.002 {
            appliedStageOpacity = opacity
            stageRoot.isEnabled = opacity > 0.002
            if opacity < 0.998 {
                stageRoot.components.set(OpacityComponent(opacity: opacity))
            } else {
                stageRoot.components.remove(OpacityComponent.self)
            }
        }
    }

    private func render(_ model: CircuitsModel, dt: Double) {
        advanceLandings(dt: dt)
        advanceFeel(model, dt: dt)
        advanceRefusal(model, dt: dt)
        syncStage(model, dt: dt)
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

        syncComponents(model, dt: dt)
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
            // With the part's ring open the card stands aside, up and to the
            // viewer's left (the anchor billboards, so its x is the viewer's):
            // the petals arc where it hung, and the track runs under the part
            // to the right (2026-11-02).
            let aside = ringPartID == selected.id ? Self.readoutAside : .zero
            for card in selectedAnchor.children {
                card.position = Motion.isReduced ? aside
                    : card.position + (aside - card.position) * Float(min(dt * 12, 1))
            }
        } else {
            selectedAnchor.isEnabled = false
        }
    }

    // MARK: Voltage skyline

    /// The skyline's warm↔cool ramp over a normalised −1…1 axis, saturated
    /// for the towers.
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
        // Faded, not switched (2026-11-02), as every layer from More is.
        Fade.tick(skylineRoot, visible: model.showVoltageHeights)
        guard model.showVoltageHeights else { return }

        // One tower per net, in node order, so a tower keeps its identity
        // between frames.
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
            // `setText` compares colour too, so a held-back tint retries.
            if towerReadings[index] != reading || colorMoved
                || towerLabelsPending.contains(index) {
                if towerLabels[index].setText(
                    PhysicsFormat.measurement(node.voltage, "V", decimals: 1),
                    color: Self.skylineTint(bucket)) {
                    towerReadings[index] = reading
                    towerLabelsPending.remove(index)
                } else {
                    towerLabelsPending.insert(index)
                }
            }
        }
    }

    private func growTower() {
        // Square-cornered: a rounded `generateBox` is 13k triangles whatever
        // its size, so three towers out-cost the circuit they stand over
        // (CircuitBudgetTests).
        let column = ModelEntity(mesh: Primitives.box(size: [0.012, 0.1, 0.012]))
        skylineRoot.addChild(column)
        towers.append(column)

        let cap = ModelEntity(mesh: Primitives.cylinder(height: 0.006, radius: 0.02))
        skylineRoot.addChild(cap)
        towerCaps.append(cap)

        let threadMaterial = Materials.unlit(.white, opacity: 0.2)
        let thread = ModelEntity(
            mesh: Primitives.cylinder(height: 0.1, radius: 0.0009),
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

    /// Turn each motor's flywheel at its live angular speed (rad/s) about
    /// its face normal, accumulating on the rotor's own orientation —
    /// direction and all, so reversing the battery reverses the spin. Above
    /// `rotorBlurTurnsPerSecond` the marker becomes the smeared band the eye
    /// would see, and the rotor goes plain steel under it.
    private func spinMotors(_ model: CircuitsModel, dt: Double) {
        for component in model.components where component.kind == .motor {
            guard var visual = visuals[component.id], let rotor = visual.rotor else { continue }
            let blurred = Self.rotorBlurred(motorSpeed: component.motorSpeed)
            if visual.blurred != blurred {
                visual.blurred = blurred
                visual.rotorBlur?.isEnabled = blurred
                if blurred { Self.dress(rotor, Self.plainSteel) } else { visual.rotorDress?.restore() }
                visuals[component.id] = visual
            }
            let delta = Float(component.motorSpeed * dt)
            guard abs(delta) > 1e-6 else { continue }
            rotor.orientation = simd_quatf(angle: delta, axis: [0, 0, 1]) * rotor.orientation
        }
    }

    /// The lit terminals, recomputed once a frame rather than once per lead
    /// — a net walks the topology: the tapped net, and while a join is
    /// refused because its ends are already one point, that point's net.
    private(set) var litTerminals: Set<CircuitsModel.Terminal> = []

    static func litTerminals(_ model: CircuitsModel,
                             refused: [CircuitsModel.Terminal]) -> Set<CircuitsModel.Terminal> {
        var lit = Set(model.highlightedTerminals)
        for terminal in refused where !lit.contains(terminal) {
            lit.formUnion(model.netTerminals(containing: terminal))
        }
        return lit
    }

    /// The terminals whose nets a refusal lights this frame: a lead held on
    /// its own net, a carried part over one, and a refused release's for
    /// `refusalLinger` after. A full wire budget lights nothing — that "no"
    /// is the recoil alone.
    private func refusalSources(_ model: CircuitsModel) -> [CircuitsModel.Terminal] {
        var sources = refusedPreviewTargets
        if let pull = model.leadPull, pull.refusal == .sameNet, let target = pull.target {
            sources.append(target)
        }
        if let lingering = lingeringRefusal { sources.append(lingering.terminal) }
        return sources
    }

    private func advanceRefusal(_ model: CircuitsModel, dt: Double) {
        if let event = model.lastNetRefusal, event.serial != lastNetRefusalSerial {
            lastNetRefusalSerial = event.serial
            lingeringRefusal = (event.terminal, Self.refusalLinger)
        } else if var lingering = lingeringRefusal {
            lingering.remaining -= dt
            lingeringRefusal = lingering.remaining > 0 ? lingering : nil
        }
    }

    /// Every lead in a joint, where the renderer draws it — through a
    /// landing's ease, so a joint forms as the part arrives.
    private func jointTerminals(_ model: CircuitsModel) -> Set<CircuitsModel.Terminal> {
        var joined: Set<CircuitsModel.Terminal> = []
        for wire in model.wires {
            guard let a = terminalWorld(wire.from, model), let b = terminalWorld(wire.to, model),
                  simd_distance(a, b) < Float(CircuitsModel.jointLength) else { continue }
            joined.insert(wire.from)
            joined.insert(wire.to)
        }
        return joined
    }

    // MARK: The feel (2026-10-30)

    /// How high a held part rides above where the hand holds it — the small
    /// lift of taking an object up — and how near one of its leads must
    /// come to a joinable terminal before the part leans in to seat. All of
    /// it is drawn only: the model's part is where the hand is.
    nonisolated static let liftHeight: Float = 0.006
    nonisolated static let pullInDistance = 0.010

    /// How far a held part leans toward the pose `alignment(for:)` would
    /// give it: nothing beyond `pullInDistance`, everything at contact,
    /// smoothstepped between.
    nonisolated static func pullInWeight(distance: Double) -> Double {
        let t = 1 - min(max(distance / pullInDistance, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The part a hand holds; each part's lift, 0…1, easing up while held
    /// and back down after; the pose a held part leans toward this frame.
    private var carriedID: UUID?
    private var lifts: [UUID: Float] = [:]
    private var leans: [UUID: (position: SIMD3<Double>, axis: SIMD3<Double>, weight: Double)] = [:]

    /// A joint pulled at whose press has not yet given: its wire and how
    /// far the hand has carried it. Its junction strains toward the hand.
    var jointStrain: (wire: UUID, travel: SIMD3<Float>)?
    private var strainedJunction: UUID?

    private func advanceFeel(_ model: CircuitsModel, dt: Double) {
        if let pending = pendingGlowID, visuals[pending] != nil, carriedID == pending {
            flashPickup(id: pending, tick: false)
        }
        for id in Set(lifts.keys).union(carriedID.map { [$0] } ?? []) {
            let target: Float = id == carriedID && !Motion.isReduced ? 1 : 0
            let next = Motion.ease(lifts[id] ?? 0, toward: target, dt: dt, rate: 14)
            lifts[id] = next == 0 ? nil : next
        }
        leans = [:]
        guard let id = carriedID, !Motion.isReduced, model.leadPull == nil,
              let component = model.components.first(where: { $0.id == id }),
              let alignment = model.alignment(for: id),
              let target = model.components.first(where: { $0.id == alignment.target.componentID })?
                .terminalPosition(alignment.target.end) else { return }
        let distance = min(simd_distance(component.terminalPosition(0), target),
                           simd_distance(component.terminalPosition(1), target))
        let weight = Self.pullInWeight(distance: distance)
        if weight > 0 { leans[id] = (alignment.position, alignment.axis, weight) }
    }

    /// A joint's junction stretched toward the hand pulling it apart, up to
    /// 1.6× when the press gives at `PressLatch.tapTravel` — volume kept, so
    /// it reads as a pull against the seat rather than a swelling.
    private func strain(_ junction: Entity, wire: UUID, at centre: SIMD3<Float>) {
        let travel = jointStrain?.wire == wire ? jointStrain!.travel : .zero
        let length = simd_length(travel)
        let reach = min(length / Float(PressLatch<Int>.tapTravel), 1)
        guard reach > 0, !Motion.isReduced else {
            if strainedJunction == wire {
                strainedJunction = nil
                junction.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
                junction.scale = SIMD3(repeating: Self.junctionScale)
                junction.position = centre
            }
            return
        }
        strainedJunction = wire
        let direction = travel / length
        let stretch = 1 + 0.6 * reach
        junction.orientation = VectorFieldArrows.rotationFromYAxis(to: direction)
        junction.scale = SIMD3(1 / stretch.squareRoot(), stretch, 1 / stretch.squareRoot())
            * Self.junctionScale
        junction.position = centre + direction * (stretch - 1) * Self.contactRadius * Self.junctionScale
    }

    // MARK: The landing

    /// A released part snapped onto a neighbour's lead glides the last few
    /// centimetres instead of jumping (2026-10-18), over this long. Only a
    /// release starts one — never a restore, a preset or a spin.
    nonisolated static let landingDuration = 0.12

    private struct Landing {
        let position: SIMD3<Double>
        let axis: SIMD3<Double>
        var elapsed: Double
    }
    private var landings: [UUID: Landing] = [:]
    /// `-circSnapAt <s>`: every landing held that many seconds in, for a
    /// still of a part mid-snap — the glide is over in 0.12 s, which no
    /// screenshot can catch.
    var pinnedLandingTime: Double?

    /// Called around `CircuitsModel.release(id:)` with the pose the part
    /// had before it: what is drawn eases from there to where the model put
    /// it — the holder, and through `terminalWorld` its wires and electrons.
    func easeLanding(id: UUID, from position: SIMD3<Double>, axis: SIMD3<Double>) {
        guard !Motion.isReduced else { return }
        landings[id] = Landing(position: position, axis: axis, elapsed: 0)
    }

    private func advanceLandings(dt: Double) {
        for id in Array(landings.keys) {
            if let pinned = pinnedLandingTime {
                landings[id]?.elapsed = min(pinned, Self.landingDuration * 0.999)
                continue
            }
            landings[id]?.elapsed += dt
            if let landing = landings[id], landing.elapsed >= Self.landingDuration {
                landings[id] = nil
            }
        }
    }

    /// Where a part is drawn: the model's pose, partway through a landing,
    /// leaning in to seat, and lifted while held.
    func displayPose(of component: CircuitsModel.Component)
    -> (position: SIMD3<Double>, axis: SIMD3<Double>) {
        var position = component.position, axis = component.axis
        if let landing = landings[component.id] {
            let t = min(max(landing.elapsed / Self.landingDuration, 0), 1)
            let e = t * t * (3 - 2 * t)
            position = landing.position + (component.position - landing.position) * e
            let from = simd_normalize(landing.axis), to = simd_normalize(component.axis)
            let turn = simd_slerp(simd_quatd(angle: 0, axis: [0, 1, 0]), simd_quatd(from: from, to: to), e)
            axis = turn.act(from)
        }
        if let lean = leans[component.id] {
            position += (lean.position - position) * lean.weight
            let from = simd_normalize(axis), to = simd_normalize(lean.axis)
            axis = simd_slerp(simd_quatd(angle: 0, axis: [0, 1, 0]), simd_quatd(from: from, to: to),
                              lean.weight).act(from)
        }
        if let lift = lifts[component.id] {
            position.y += Double(lift * Self.liftHeight)
        }
        return (position, axis)
    }

    private func syncComponents(_ model: CircuitsModel, dt: Double) {
        litTerminals = Self.litTerminals(model, refused: refusalSources(model))
        let joined = jointTerminals(model)
        // Remove visuals whose components are gone.
        let liveIDs = Set(model.components.map(\.id))
        for id in visuals.keys where !liveIDs.contains(id) {
            visuals[id].map { Retire.entity($0.holder) }
            visuals[id] = nil
            wirePhases[id] = nil  // a removed jumper's electron phase
        }

        for component in model.components {
            var visual = visuals[component.id] ?? makeVisual(for: component)

            // The model owns motion; the renderer follows it, through a
            // released part's eased landing.
            let pose = displayPose(of: component)
            visual.holder.position = SIMD3<Float>(pose.position)
            orient(&visual, along: SIMD3<Float>(pose.axis), yaw: model.stage.yaw, dt: dt)
            Self.tickSelection(&visual, selected: component.id == model.selectedID, dt: dt)

            // One contact at each end, and nothing else to hit there.
            for (end, terminal) in visual.terminals.enumerated() {
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
                let isLit = litTerminals.contains(key)
                // A lead in a joint gives its target and its dot to the
                // joint's one junction dot: two coincident leads' targets
                // overlapped, and which one a pinch took was hit order.
                let inJoint = joined.contains(key)
                if visual.terminalJoined[end] != inJoint {
                    visual.terminalJoined[end] = inJoint
                    terminal.children.forEach { $0.isEnabled = !inJoint }
                    if inJoint {
                        terminal.components.remove(CollisionComponent.self)
                    } else {
                        terminal.components.set(CollisionComponent(
                            shapes: [Primitives.collisionSphere(radius: Self.terminalTargetRadius)]))
                    }
                }
                terminal.scale = SIMD3(repeating: isSource
                    // Breathes to say "wiring from here"; held at its mean
                    // size under Reduce Motion.
                    ? Float(1.6 + (Motion.isReduced ? 0 : 0.35 * sin(pendingPulsePhase)))
                    : (previewTargets.contains(key) ? 1.5
                        : ((isProbed || isLit) ? 1.35 : 1.0)))
            }

            // Each lead wears its terminal's potential, as a wire does — the
            // lead and the wires on that terminal are one net, one line — and
            // a lit net lights it too.
            let span = model.voltageSpan
            let width = max(span.max - span.min, 0.5)
            for end in 0..<min(visual.leads.count, 2) {
                let key = CircuitsModel.Terminal(componentID: component.id, end: end)
                let t = ((model.terminalVoltages[key] ?? 0) - span.min) / width
                let bucket = litTerminals.contains(key) ? -1 : min(max(Int(t * 7.999), 0), 7)
                if visual.leadBuckets[end] != bucket {
                    visual.leadBuckets[end] = bucket
                    let material: RealityKit.Material = bucket < 0
                        ? Self.netHighlightMaterial : Self.voltageMaterials[bucket]
                    (visual.leads[end].findEntity(named: "cable") as? ModelEntity)?
                        .model?.materials = [material]
                }
            }

            // Live label. `BackedLabel` self-gates on unchanged text.
            let text = Self.labelText(for: component)
            if visual.labelText != text,
               visual.label.setText(text, color: UIColor(white: 0.95, alpha: 1)) {
                visual.labelText = text
            }
            let echoed = component.id == ringPartID
                && text == CircuitsModel.formatValue(component.value, for: component.kind)
            visual.labelPivot.isEnabled = !text.isEmpty && !echoed
            // Its value and its state, spoken — a switch's open or closed
            // and a blown fuse are otherwise only seen.
            let spoken = Self.spokenState(for: component)
            if visual.spokenState != spoken {
                visual.spokenState = spoken
                SpatialActions.republish(value: spoken, on: visual.holder)
                if let lever = visual.lever {
                    SpatialActions.republish(value: component.isClosed ? "closed" : "open", on: lever)
                }
            }

            switch component.kind {
            case .bulb:
                let watts = model.readouts[component.id]?.watts ?? 0
                let step = Self.filamentStep(watts: watts)
                if visual.glowBucket != step {
                    visual.glowBucket = step
                    Self.paintBulb(filament: visual.filament, glow: visual.glow,
                                   light: visual.light, watts: watts)
                }
            case .led:
                let amps = abs(model.readouts[component.id]?.amps ?? 0)
                let state = component.failed ? -1 : min(Int(amps / 0.004), 5)
                if visual.ledState != state {
                    visual.ledState = state
                    Self.paintLED(core: visual.ledCore, rest: visual.ledDress, glow: visual.glow,
                                  light: visual.light, state: state)
                }
            case .switcher:
                let before = visual.blade.value
                Self.throwBlade(&visual, component: component, dt: dt)
                if visual.blade.value != before {
                    visual.lever?.orientation = simd_quatf(angle: visual.blade.value, axis: [0, 0, 1])
                }
            case .fuse:
                let intact = !component.failed
                if visual.fuseIntact != intact {
                    visual.fuseIntact = intact
                    visual.fuseBridge?.isEnabled = intact
                    if intact { visual.fuseGlassDress?.restore() } else {
                        Self.dress(visual.fuseGlass, Self.scorchedGlass)
                    }
                }
            case .capacitor:
                let bucket = Self.chargeBucket(volts: model.readouts[component.id]?.volts ?? 0)
                if visual.chargeBucket != bucket {
                    visual.chargeBucket = bucket
                    Self.tintPlates(visual.plates, rests: visual.plateDresses, bucket: bucket)
                }
            case .acSource:
                visual.bead?.position = Self.beadPosition(phase: model.acPhase(of: component))
            case .resistor:
                // Heat: the ceramic glows by I²R against its rating, in four
                // steps, and goes black when it scorches.
                let key = resistorKey(component.value)
                let rating = CircuitsModel.powerRating(for: .resistor) ?? 1
                let load = (model.readouts[component.id]?.watts ?? 0) / rating
                let bucket = component.failed ? -2 : min(Int(max(0, load) * 4), 4)
                if visual.resistorCodeKey != key || visual.heatBucket != bucket,
                   let ceramic = visual.ceramic {
                    if component.failed {
                        visual.resistorCodeKey = key
                        visual.heatBucket = bucket
                        var scorched = PhysicallyBasedMaterial()
                        scorched.baseColor = .init(tint: UIColor(white: 0.08, alpha: 1))
                        scorched.roughness = 0.9
                        ceramic.model?.materials = [scorched]
                    } else if let texture = CircuitTextures.resistorTexture(ohms: component.value) {
                        visual.resistorCodeKey = key
                        visual.heatBucket = bucket
                        var material = PhysicallyBasedMaterial()
                        material.baseColor = .init(tint: .white, texture: .init(texture))
                        material.roughness = 0.6
                        if bucket > 0 {
                            material.emissiveColor = .init(
                                color: UIColor(red: 1, green: 0.42, blue: 0.08, alpha: 1))
                            material.emissiveIntensity = Float(bucket) * 0.55
                        }
                        ceramic.model?.materials = [material]
                    }
                }
            default:
                break
            }
            visuals[component.id] = visual
        }
    }

    /// Turns a part to `moduleOrientation`, easing a large change, and hangs
    /// its label below it in the room.
    private func orient(_ visual: inout ComponentVisual, along axis: SIMD3<Float>,
                        yaw: Double, dt: Double) {
        let axis = simd_normalize(axis)
        let moved = visual.orientedFor.map {
            simd_dot($0.axis, axis) < 0.99999 || abs($0.yaw - yaw) > 1e-5
        } ?? true
        if moved {
            visual.orientedFor = (axis, yaw)
            let target = Self.moduleOrientation(axis: axis, front: Self.stageFront(yaw: yaw),
                                                previous: visual.targetOrientation)
            let first = visual.targetOrientation == nil
            visual.targetOrientation = target
            if first || Motion.isReduced
                || Self.angle(between: visual.holder.orientation, and: target)
                    < Self.orientationEaseThreshold {
                visual.holder.orientation = target
                visual.easingOrientation = false
            } else {
                visual.easingOrientation = true
            }
        }
        if visual.easingOrientation, let target = visual.targetOrientation {
            let next = simd_slerp(visual.holder.orientation, target, Float(min(dt * 14, 1)))
            if Self.angle(between: next, and: target) < 0.01 {
                visual.holder.orientation = target
                visual.easingOrientation = false
            } else {
                visual.holder.orientation = next
            }
        }
        if moved || visual.easingOrientation {
            let orientation = visual.holder.orientation
            visual.labelPivot.position = orientation.inverse.act(Self.labelOffset(for: orientation))
        }
    }

    nonisolated static func angle(between a: simd_quatf, and b: simd_quatf) -> Float {
        2 * acos(min(abs(simd_dot(a.vector, b.vector)), 1))
    }

    // MARK: Live states

    /// The most a landed blade bounces, rad: 2°, which at the contact ring
    /// (64 mm from the pivot) is 2.2 mm — inside its 6 mm, so the blade
    /// never leaves the contact the circuit closed through.
    nonisolated static let bladeBounceLimit: Float = 2 * .pi / 180

    /// How the drawn blade moves (contract D3). Opening: the house spring,
    /// past 30° and back. Closing: a fall timed by the model's own
    /// `closingIn`, accelerating as a dropped blade does, so it reaches the
    /// contact on the frame the model closes the circuit — then a small
    /// bounce. Under Reduce Motion the blade is where the switch is.
    private static func throwBlade(_ visual: inout ComponentVisual,
                                   component: CircuitsModel.Component, dt: Double) {
        let open = switchOpenAngle
        let delay = Float(CircuitsModel.switchCloseDelay)
        if component.closingIn > 0, !Motion.isReduced {
            let fallen = 1 - Float(component.closingIn) / delay
            visual.blade = Motion.Spring(open * (1 - fallen * fallen),
                                         velocity: -2 * open * fallen / delay)
            visual.bladeFalling = true
        } else if component.isClosed {
            if visual.bladeFalling {
                // Landed at 2·open/delay; it comes back up a little.
                visual.bladeFalling = false
                visual.blade = Motion.Spring(0, velocity: 0.3 * 2 * open / delay)
            }
            visual.blade.step(toward: 0, dt: dt, frequency: 12, damping: 0.35)
            if visual.blade.value < 0 {
                // The contact stops it: it bounces rather than passing through.
                visual.blade = Motion.Spring(0, velocity: abs(visual.blade.velocity) * 0.3)
            }
            visual.blade.value = min(visual.blade.value, bladeBounceLimit)
        } else {
            visual.bladeFalling = false
            visual.blade.step(toward: open, dt: dt)
        }
    }

    /// How full the capacitor's charge reads, 0…1: |V| (so |Q| = C|V|)
    /// against the bench's tallest source.
    nonisolated static func gaugeFill(volts: Double) -> Double {
        min(abs(volts) / gaugeFullScale, 1)
    }

    /// The capacitor's charge as a tint step: the sign of the charge on
    /// plate 0 (terminal 0's side) times 0…7 by |V|. Plate 0 wears red when
    /// it holds +Q, plate 1 the blue of the −Q facing it — the physics
    /// colours, on the physics.
    nonisolated static func chargeBucket(volts: Double) -> Int {
        let level = min(Int(gaugeFill(volts: volts) * 7.999), 7)
        return volts < 0 ? -level : level
    }

    /// Where the AC source's bead rides its sine for a phase of the cycle:
    /// its height is the EMF's, so it crests when the source does.
    nonisolated static func beadPosition(phase: Double) -> SIMD3<Float> {
        var u = (phase / (2 * .pi)).truncatingRemainder(dividingBy: 1)
        if u < 0 { u += 1 }
        return [-acWaveHalfWidth + 2 * acWaveHalfWidth * Float(u),
                acWaveAmplitude * Float(sin(2 * .pi * u)), acBeadZ]
    }

    /// A filament's temperature at a power: radiation carries a lamp's
    /// power away, so P ∝ T⁴ and T = T_ref·(P / P_ref)^¼, 2700 K at 3 W (the
    /// bench's bulb at full brightness), capped at tungsten's 3200 K.
    nonisolated static let filamentReference = (watts: 3.0, kelvin: 2700.0)
    nonisolated static func filamentTemperature(watts: Double) -> Double {
        guard watts > 0 else { return 0 }
        return min(filamentReference.kelvin * pow(watts / filamentReference.watts, 0.25), 3200)
    }

    /// The filament's state in one of 16 steps between first visible glow
    /// (900 K) and 3200 K, so its material changes only when the step does.
    /// −1 is dark.
    nonisolated static let filamentSteps = 16
    nonisolated static func filamentStep(watts: Double) -> Int {
        let t = filamentTemperature(watts: watts)
        guard t >= 900 else { return -1 }
        return min(Int((t - 900) / (3200 - 900) * Double(filamentSteps)), filamentSteps - 1)
    }

    /// A step's colour and brightness: the blackbody at the step's middle
    /// temperature through `StellarColour` (Planck against the CIE 1931
    /// observer, at full chroma — a filament is not a star seen by
    /// starlight), and its luminance against the reference filament's.
    nonisolated static let filamentLooks: [(colour: SIMD3<Double>, brightness: Double)] = {
        func luminance(_ t: Double) -> Double {
            stride(from: 380.0, through: 780.0, by: 5).reduce(0) {
                $0 + StellarColour.planck(wavelength: $1 * 1e-9, temperature: t)
                    * StellarColour.colourMatching(nanometres: $1).y
            }
        }
        let reference = luminance(filamentReference.kelvin)
        return (0..<filamentSteps).map { step in
            let t = 900 + (Double(step) + 0.5) / Double(filamentSteps) * (3200 - 900)
            return (StellarColour.displayColour(temperature: t, chroma: 1), luminance(t) / reference)
        }
    }()

    private static let darkFilament = Materials.unlit(UIColor(white: 0.30, alpha: 1))

    /// A bulb at a power: its filament in the colour of its temperature, the
    /// glow round its glass and its light on the parts beside it, both as
    /// bright as the filament's luminance against the reference.
    static func paintBulb(filament: Entity?, glow: ModelEntity?, light: Entity?, watts: Double) {
        let step = filamentStep(watts: watts)
        guard step >= 0 else {
            dress(filament, darkFilament)
            glow?.isEnabled = false
            light?.components.remove(PointLightComponent.self)
            return
        }
        let look = filamentLooks[step]
        // Dim steps are drawn darker as well as redder; the glow and the
        // light carry the rest of the brightness.
        let level = min(look.brightness, 1)
        let shade = 0.35 + 0.65 * pow(level, 1 / 2.2)
        let colour = UIColor(red: look.colour.x * shade, green: look.colour.y * shade,
                             blue: look.colour.z * shade, alpha: 1)
        dress(filament, Materials.unlit(colour))
        let strength = Float(level)
        let tint = UIColor(red: look.colour.x, green: look.colour.y, blue: look.colour.z, alpha: 1)
        if let glow {
            glow.isEnabled = strength > 0.02
            GlowSprite.paint(glow, tint, strength: max(strength, 0.125))
        }
        if strength > 0.02 {
            light?.components.set(PointLightComponent(
                color: tint, intensity: 1100 * strength, attenuationRadius: 0.25))
        } else {
            light?.components.remove(PointLightComponent.self)
        }
    }

    private static let ledOff = Materials.unlit(UIColor(white: 0.06, alpha: 1))

    /// An LED in a state: −1 burned out (a dark die), 0 its own red epoxy
    /// at rest, 1…5 lit at 625 nm, the colour a red LED emits.
    static func paintLED(core: Entity?, rest: Dress?, glow: ModelEntity?, light: Entity?, state: Int) {
        guard state > 0 else {
            if state < 0 { dress(core, ledOff) } else { rest?.restore() }
            glow?.isEnabled = false
            light?.components.remove(PointLightComponent.self)
            return
        }
        let strength = Float(state) / 5
        let red = MagnetismRenderer.ledRed
        // Brighter is whiter at the core, as a real LED's lens saturates.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        red.getRed(&r, green: &g, blue: &b, alpha: &a)
        let w = CGFloat(0.35 * strength)
        dress(core, Materials.unlit(UIColor(red: r + (1 - r) * w, green: g + (1 - g) * w,
                                            blue: b + (1 - b) * w, alpha: 1)))
        if let glow {
            glow.isEnabled = true
            GlowSprite.paint(glow, red, strength: strength)
        }
        light?.components.set(PointLightComponent(
            color: red, intensity: 700 * strength, attenuationRadius: 0.18))
    }

    /// A charge step on the capacitor's two plates (`chargeBucket`).
    private static func tintPlates(_ plates: [Entity], rests: [Dress], bucket: Int) {
        guard bucket != 0 else {
            rests.forEach { $0.restore() }
            return
        }
        let f = CGFloat(abs(bucket)) / 7
        let grey = UIColor(white: 0.36, alpha: 1)
        func mix(_ to: UIColor) -> UIColor {
            var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            grey.getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
            to.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            return UIColor(red: r0 + (r1 - r0) * f, green: g0 + (g1 - g0) * f,
                           blue: b0 + (b1 - b0) * f, alpha: 1)
        }
        let positive = Materials.machined(mix(DesignTokens.Palette.positiveUI), roughness: 0.45)
        let negative = Materials.machined(mix(DesignTokens.Palette.negativeUI), roughness: 0.45)
        for (index, plate) in plates.enumerated() {
            // Plate 0 holds +Q when the charge is positive, plate 1 the −Q.
            let holdsPositive = (index == 0) == (bucket > 0)
            dress(plate, holdsPositive ? positive : negative)
        }
    }

    /// A motor's flywheel above this many turns a second is drawn as the eye
    /// sees one: its marker smeared into a band (`rotor_blur`). Its one
    /// marker passes at most 20 times a second there, under half of 90 Hz,
    /// so below it the turn the wearer sees is the true one.
    nonisolated static let rotorBlurTurnsPerSecond = 20.0

    nonisolated static func rotorBlurred(motorSpeed: Double) -> Bool {
        abs(motorSpeed) / (2 * .pi) > rotorBlurTurnsPerSecond
    }

    private static let plainSteel = Materials.machined(UIColor(white: 0.6, alpha: 1), roughness: 0.22)

    /// A blown fuse's glass, smoked by the filament that went.
    private static let scorchedGlass: PhysicallyBasedMaterial = {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(white: 0.10, alpha: 1))
        material.roughness = 0.5
        material.blending = .transparent(opacity: .init(floatLiteral: 0.7))
        return material
    }()

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

    /// The bench label: the part's number and nothing else (2026-10-18). Its
    /// state is the part's own to show — a lever up, a dark bulb, a broken
    /// filament, a scorched ceramic — so no word repeats it, and a part with
    /// no number (a switch, an LED) carries no label. Value formatting goes
    /// through the one authority, `CircuitsModel.formatValue`, so label and
    /// readout cannot disagree.
    static func labelText(for component: CircuitsModel.Component) -> String {
        switch component.kind {
        case .battery, .acSource, .bulb, .capacitor, .inductor, .resistor, .fuse:
            CircuitsModel.formatValue(component.value, for: component.kind)
        case .switcher, .led: ""
        case .motor: motorRPMLabel(component.motorSpeed)
        }
    }

    /// A part's value and state as VoiceOver says them.
    static func spokenState(for component: CircuitsModel.Component) -> String {
        var words: [String] = []
        let value = labelText(for: component)
        if !value.isEmpty { words.append(PhysicsFormat.spoken(value)) }
        switch component.kind {
        case .switcher: words.append(component.isClosed ? "closed" : "open")
        case .fuse where component.failed: words.append("blown")
        case .led where component.failed: words.append("burned out")
        case .resistor where component.failed: words.append("scorched")
        default: break
        }
        return words.joined(separator: ", ")
    }

    private func makeVisual(for component: CircuitsModel.Component) -> ComponentVisual {
        // The holder is the manipulation target, so a carried part brings
        // its contacts and label along.
        let holder = Entity()
        holder.name = component.id.uuidString
        holder.position = SIMD3<Float>(component.position)
        // Its name, not its id: the touch target's attach below keeps it.
        SpatialActions.describe(holder, label: component.kind.displayName)
        viewRoot.addChild(holder)

        // The module: the part's milled element and its live pieces, its two
        // brass dots and its two leads. Everything solid shadows the stage.
        let module = Self.makeModule(kind: component.kind)
        holder.addChild(module.root)
        GroundingShadows.cast(on: module.body)

        // The carry target runs the line from lead's end to lead's end — the
        // old carrier's reach — clamped inside the dots' targets, so a body
        // pinch cannot swallow a lead; across the line it is the element's
        // own size (the holder collects a bulb's glow).
        let bounds = module.body.visualBounds(relativeTo: holder)
        let clearOfLead = Float(CircuitsModel.terminalOffset) - Self.terminalTargetRadius - 0.002
        let half = SIMD3<Float>(
            clearOfLead,
            max(bounds.extents.y, 2 * Self.wireJacketRadius) / 2 + Grabbable.reach,
            max(bounds.extents.z, 2 * Self.wireJacketRadius) / 2 + Grabbable.reach)
        Grabbable.configureTouchTarget(
            holder, box: half * 2, offset: [0, bounds.center.y, bounds.center.z],
            activate: { [weak self, weak holder] in
                guard let holder else { return }
                self?.onTap?(holder)
            })

        // The dots are the terminals: the only thing at each end.
        for (end, terminal) in module.contacts.enumerated() {
            terminal.name = "t\(end)-\(component.id.uuidString)"
            // The only target at this end; the far dot is 0.17 m away.
            terminal.components.set(InputTargetComponent())
            terminal.components.set(CollisionComponent(
                shapes: [Primitives.collisionSphere(radius: Self.terminalTargetRadius)]))
            terminal.components.set(HoverEffectComponent())
            let key = CircuitsModel.Terminal(componentID: component.id, end: end)
            SpatialActions.attach(
                to: terminal, label: "Terminal. Activate to wire from here.",
                activate: { [weak self] in self?.onTerminalAction?(key) })
            // "Activate this, then another" is true for VoiceOver's tap-tap path
            // (`voiceOverWire`).
            SpatialActions.describe(terminal, label:
                "\(component.kind.displayName), \(end == 0 ? "first" : "second") terminal. "
                + "Activate this, then another terminal, to wire them.")
            GroundingShadows.cast(on: terminal)
        }

        // The value beneath, billboarded over the dark backing. Its pivot is
        // placed in the room each time the part turns, so it hangs below
        // whatever angle the part takes.
        let label = BackedLabel(size: 0.018)
        let labelPivot = Entity()
        labelPivot.components.set(BillboardComponent())
        labelPivot.addChild(label.root)
        holder.addChild(labelPivot)

        var visual = ComponentVisual(
            holder: holder, body: module.body, ceramic: module.ceramic,
            terminals: module.contacts, label: label,
            labelPivot: labelPivot)
        visual.outline = Self.outlineSlots(of: module.body, kind: component.kind)
        visual.leads = module.leads
        visual.glow = module.glow
        visual.filament = module.filament
        visual.light = module.light
        visual.rotor = module.rotor
        visual.rotorBlur = module.rotorBlur
        visual.rotorDress = Dress(module.rotor)
        visual.fuseBridge = module.fuseBridge
        visual.fuseGlass = module.fuseGlass
        visual.fuseGlassDress = Dress(module.fuseGlass)
        visual.plates = module.plates
        visual.plateDresses = module.plates.map { Dress($0) }
        visual.bead = module.bead
        visual.ledCore = module.ledCore
        visual.ledDress = Dress(module.ledCore)

        if component.kind == .switcher, let blade = module.lever {
            // The blade turns about the pivot (its own origin); it is the tap
            // target, so the whole blade and its knob are pinchable.
            blade.name = "k-\(component.id.uuidString)"
            // Measured with the blade closed, so it does not bulge below the
            // switch and take the pinches meant for the dots. Set directly:
            // the blade is not a carried object.
            let bladeBounds = blade.visualBounds(relativeTo: blade)
            blade.components.set(InputTargetComponent())
            blade.components.set(CollisionComponent(shapes: [
                Primitives.collisionBox(size: bladeBounds.extents
                             + SIMD3<Float>(repeating: 2 * Grabbable.reach), offset: bladeBounds.center),
            ]))
            blade.components.set(HoverEffectComponent())
            // A dedicated callback, not `onTap`: the physical tap path only selects
            // a lever, so VoiceOver's activate needs its own route.
            SpatialActions.attach(
                to: blade, label: "Switch",
                activate: { [weak self] in
                    self?.onLeverAction?(component.id)
                })
            visual.lever = blade
            visual.blade = Motion.Spring(component.isClosed ? 0 : Self.switchOpenAngle)
            blade.orientation = simd_quatf(angle: visual.blade.value, axis: [0, 0, 1])
        }

        visuals[component.id] = visual
        return visual
    }

    // MARK: Modeled bodies (Blender-authored USDZ, procedural fallback)

    /// Each part clones the shared `PropCache` prototype, milled by
    /// `Tools/circuitparts.py` as its own symbol on the line, live pieces and
    /// all. The resistor's ceramic stays procedural: its colour bands are a
    /// live texture painted from the value; only its steel caps and zigzag
    /// are milled. The procedural bodies below are the fallback for a missing
    /// asset, which `CircuitPropTests` fails.
    static let bodyAssetNames: [CircuitsModel.ComponentKind: String] = [
        .battery: "CircuitBattery", .acSource: "CircuitACSource",
        .capacitor: "CircuitCapacitor", .inductor: "CircuitInductor",
        .bulb: "CircuitBulb", .led: "CircuitLED", .motor: "CircuitMotor",
        .fuse: "CircuitFuse", .switcher: "CircuitSwitch",
    ]
    static let resistorCapsAssetName = "CircuitResistorCaps"
    /// The resistor's ceramic, on the line between the milled caps at ±0.0225.
    nonisolated static let ceramicRadius: Float = 0.012
    nonisolated static let ceramicLength: Float = 0.050

    private static func modeledBody(for kind: CircuitsModel.ComponentKind) -> ModelEntity? {
        guard let name = bodyAssetNames[kind] else { return nil }
        guard let prototype = PropCache.prototype(named: name) else { return nil }
        let shell = ModelEntity()
        shell.addChild(prototype.clone(recursive: true))
        return shell
    }

    /// The part's body, and for a resistor the ceramic that wears its bands.
    private static func makeBody(kind: CircuitsModel.ComponentKind) -> (ModelEntity, ModelEntity?) {
        if kind == .resistor {
            let shell = ModelEntity()
            let ceramic = ModelEntity(
                mesh: Primitives.cylinder(height: ceramicLength, radius: ceramicRadius),
                materials: [Materials.machined(UIColor(red: 0.85, green: 0.72, blue: 0.55, alpha: 1),
                                               roughness: 0.6)])
            ceramic.name = "ceramic"
            ceramic.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            shell.addChild(ceramic)
            if let caps = PropCache.prototype(named: resistorCapsAssetName) {
                shell.addChild(caps.clone(recursive: true))
            }
            return (shell, ceramic)
        }
        if let modeled = modeledBody(for: kind) {
            return (modeled, nil)
        }
        return (fallbackBody(for: kind), nil)
    }

    /// A plain stand-in on the line, in the part's own colour.
    private static func fallbackBody(for kind: CircuitsModel.ComponentKind) -> ModelEntity {
        let colour: UIColor = switch kind {
        case .battery: UIColor(red: 0.35, green: 0.45, blue: 0.35, alpha: 1)
        case .capacitor: UIColor(red: 0.12, green: 0.2, blue: 0.45, alpha: 1)
        case .acSource: UIColor(red: 0.1, green: 0.5, blue: 0.6, alpha: 1)
        case .motor, .switcher: UIColor(white: 0.2, alpha: 1)
        default: UIColor(white: 0.6, alpha: 1)
        }
        let body = ModelEntity(
            mesh: Primitives.box(size: [0.070, 0.024, 0.030], cornerRadius: 0.006),
            materials: [Materials.machined(colour, roughness: 0.4)])
        return body
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

    /// The lit net: one material in the module's accent, shown on demand,
    /// because the standing colour language on this bench already means
    /// voltage.
    private static let netHighlightMaterial: UnlitMaterial = {
        var material = Materials.unlit(UIColor(DesignTokens.Palette.circuitsAccent), opacity: 0.95)
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

    /// The endpoints each wire's segment was last laid out for: a wire is a
    /// pure function of its two endpoints, so the transform and collider
    /// are rebuilt only when an end moves.
    private var wireLaidEndpoints: [UUID: (a: SIMD3<Float>, b: SIMD3<Float>)] = [:]

    /// Where each wire's collider was last shaped, so a wire that is
    /// not moving does not rebuild shapes it already has.
    private var wireColliderAnchors: [UUID: (SIMD3<Float>, SIMD3<Float>)] = [:]

    /// How far an end must move before the grab volume is rebuilt; shapes
    /// are allocations.
    private static let colliderRebuildEpsilon: Float = 0.002

    /// A wire's grab volume (2026-10-18). It never reaches a lead's own
    /// target: a capsule along the cable that stops `wireGrabInset` short of
    /// each lead's centre — it used to run end to end, overlapping both
    /// leads' targets, so a pinch at a plug took whichever was hit first.
    /// Two leads closer than `CircuitsModel.jointLength` are a joint: one
    /// sphere where they meet, the leads' own targets withdrawn.
    enum WireGrabShape: Equatable {
        case joint(radius: Float)
        /// `height` is the capsule's whole length, caps included.
        case cable(height: Float, radius: Float)
        /// Too short to hold a target clear of both leads: grab a lead.
        case none
    }

    /// How far short of a lead's centre a cable's target stops: the lead's
    /// own target radius and 2 mm of daylight.
    nonisolated static let wireGrabInset: Float = 0.025
    nonisolated static let wireGrabRadius: Float = 0.016
    nonisolated static let jointGrabRadius: Float = 0.022

    nonisolated static func wireGrabShape(length: Float) -> WireGrabShape {
        if length < Float(CircuitsModel.jointLength) { return .joint(radius: jointGrabRadius) }
        let half = length / 2 - wireGrabInset
        guard half > 0.004 else { return .none }
        return .cable(height: 2 * half, radius: min(wireGrabRadius, half))
    }

    /// On this unscaled parent: the visual segment carries its length as a
    /// Y scale, which `ColliderCriterionTests` refuses to measure under a
    /// world scale of 0.05.
    private func reshapeCollider(_ entity: ModelEntity, id: UUID,
                                 from a: SIMD3<Float>, to b: SIMD3<Float>) {
        if let previous = wireColliderAnchors[id],
           simd_distance(previous.0, a) < Self.colliderRebuildEpsilon,
           simd_distance(previous.1, b) < Self.colliderRebuildEpsilon {
            return
        }
        wireColliderAnchors[id] = (a, b)

        let direction = b - a
        let length = simd_length(direction)
        let shape: ShapeResource
        switch Self.wireGrabShape(length: length) {
        case .joint(let radius):
            shape = Primitives.collisionSphere(radius: radius).offsetBy(translation: (a + b) / 2)
        case .cable(let height, let radius):
            shape = Primitives.collisionCapsule(height: height, radius: radius)
                .offsetBy(rotation: VectorFieldArrows.rotationFromYAxis(to: direction / length),
                          translation: (a + b) / 2)
        case .none:
            entity.components.remove(CollisionComponent.self)
            return
        }
        entity.components.set(CollisionComponent(shapes: [shape]))
        entity.components.set(InputTargetComponent())
        entity.components.set(HoverEffectComponent())
    }

    /// A joint's junction dot (2026-10-30): the two meeting dots drawn as
    /// one, a size larger, as a schematic marks a junction — what says
    /// "these are joined, and you can pull them apart here". It replaced the
    /// lab kit's champagne collar.
    private func syncJunction(_ entity: ModelEntity, at a: SIMD3<Float>, _ b: SIMD3<Float>) {
        let isJoint = simd_distance(a, b) < Float(CircuitsModel.jointLength)
        var junction = entity.children.first { $0.name == "junction" }
        guard isJoint else {
            junction?.isEnabled = false
            return
        }
        if junction == nil {
            let made = Self.makeDot()
            made.name = "junction"
            made.scale = SIMD3(repeating: Self.junctionScale)
            GroundingShadows.cast(on: made)
            entity.addChild(made)
            junction = made
        }
        junction?.isEnabled = true
        junction?.position = (a + b) / 2
    }

    /// Stretches a wire's one segment taut between its endpoints: a copper
    /// core with a dark jacket child; the electrons ride inside.
    private func layOut(segmentsOf entity: ModelEntity,
                        from a: SIMD3<Float>, to b: SIMD3<Float>) {
        if !entity.children.contains(where: { $0.name == "cable" }) {
            let core = ModelEntity(
                mesh: Primitives.cylinder(height: 1, radius: Self.wireCoreRadius),
                materials: [Self.copperMaterial])
            core.name = "cable"
            let jacket = ModelEntity(
                mesh: Primitives.cylinder(height: 1, radius: Self.wireJacketRadius),
                materials: [Self.wireJacketMaterial])
            jacket.name = "jacket"
            core.addChild(jacket)
            // The segment is pure visual, no collider: it carries its length as a
            // Y scale. The grab volume lives on the unscaled parent
            // (`reshapeCollider`).
            entity.addChild(core)
        }
        guard let child = entity.children.first(where: { $0.name == "cable" }) else { return }
        let direction = b - a
        let length = simd_length(direction)
        guard length > 1e-6 else { child.isEnabled = false; return }
        child.isEnabled = true
        // The parent is at the origin of `viewRoot`, so segment
        // transforms are bench coordinates directly.
        child.position = (a + b) / 2
        child.orientation = VectorFieldArrows.rotationFromYAxis(to: direction / length)
        child.scale = SIMD3(1, length, 1)
    }

    private func syncWires(_ model: CircuitsModel) {
        let liveIDs = Set(model.wires.map(\.id))
        for id in wireEntities.keys where !liveIDs.contains(id) {
            wireEntities[id].map(Retire.entity)
            wireEntities[id] = nil
            wirePhases[id] = nil
            wireLaidEndpoints[id] = nil
            wireColliderAnchors[id] = nil
        }

        for wire in model.wires {
            let entity: ModelEntity
            if let existing = wireEntities[wire.id] {
                entity = existing
            } else {
                // A cable is one unit-cylinder segment stretched by its transform,
                // never a regenerated `TubeMesh`: the per-frame path touches
                // transforms only.
                entity = ModelEntity()
                entity.name = "w-\(wire.id.uuidString)"
                // The activation removes the wire (a gesture VoiceOver cannot make by
                // pulling) — arming on the first, as every destructive verb does;
                // physical taps never fire this.
                let key = wire.id
                SpatialActions.attach(
                    to: entity, label: "Wire. Activate twice to remove it.",
                    activate: { [weak self] in
                        self?.onWireAction?(key)
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
            // Two leads snapped into one point need no cable between them,
            // and are drawn and grabbed as a joint.
            entity.isEnabled = true

            // Re-laid only when an end moved: on an idle bench the endpoints are
            // bit-identical frame to frame.
            if wireLaidEndpoints[wire.id].map({ $0.a != a || $0.b != b }) ?? true {
                wireLaidEndpoints[wire.id] = (a, b)
                layOut(segmentsOf: entity, from: a, to: b)
                reshapeCollider(entity, id: wire.id, from: a, to: b)
                syncJunction(entity, at: a, b)
                // A re-lay can mint the segment in bare copper, and stretching changes
                // no voltage; forget the bucket so the repaint covers it.
                wireVoltBuckets[wire.id] = nil
            }

            if let junction = entity.children.first(where: { $0.name == "junction" }),
               junction.isEnabled {
                strain(junction, wire: wire.id, at: (a + b) / 2)
            }

            // The wire wears its potential: warm = high, cool = low —
            // voltage differences readable at a glance across the bench.
            let span = model.voltageSpan
            let width = max(span.max - span.min, 0.5)
            let vA = model.terminalVoltages[wire.from] ?? 0
            let vB = model.terminalVoltages[wire.to] ?? 0
            let t = ((vA + vB) / 2 - span.min) / width
            // A lit net overrides the voltage ramp; `-1` is the highlight bucket,
            // so dropping it repaints once. Both ends are one point, so either
            // answers.
            let lit = litTerminals.contains(wire.from)
            let bucket = lit ? -1 : min(max(Int(t * 7.999), 0), 7)
            if wireVoltBuckets[wire.id] != bucket {
                wireVoltBuckets[wire.id] = bucket
                let material: RealityKit.Material = lit
                    ? Self.netHighlightMaterial
                    : Self.voltageMaterials[bucket]
                for segment in entity.children where segment.name == "cable" {
                    (segment as? ModelEntity)?.model?.materials = [material]
                }
                Self.dress(entity.children.first { $0.name == "junction" },
                           lit ? Self.netHighlightMaterial : Self.contactMaterial)
            }
        }
    }

    private func terminalWorld(_ terminal: CircuitsModel.Terminal, _ model: CircuitsModel) -> SIMD3<Float>? {
        guard let component = model.components.first(where: { $0.id == terminal.componentID })
        else { return nil }
        // The model owns where a lead is, carried or not; a landing eases
        // what is drawn, wires and electrons with it.
        guard landings[component.id] != nil || leans[component.id] != nil
                || lifts[component.id] != nil else {
            return SIMD3<Float>(component.terminalPosition(terminal.end))
        }
        let pose = displayPose(of: component)
        let half = CircuitsModel.terminalOffset
        return SIMD3<Float>(pose.position + (terminal.end == 0 ? -half : half) * pose.axis)
    }

    // MARK: Electron flow (drift is − to +: opposite conventional current)

    /// One factor for both true-speed visuals, so the ratio the eye sees is
    /// the ratio physics reports. The signal (2×10⁸ m/s) shows as 1 m/s;
    /// the electrons come out at 10⁻¹³ m/s and stop dead, which is the
    /// lesson.
    private static let trueSpeedGain = 1.0 / ChargeTransport.speedOfLight / 0.66

    /// How fast to slide electron beads along a conductor, signed against
    /// the conventional current. The default is the usual pretty lie;
    /// true-speed mode uses the real drift scaled by the same factor as the
    /// field front.
    static func electronDisplaySpeed(current: Double, model: CircuitsModel) -> Double {
        if model.trueSpeedMode {
            return model.driftSpeed * trueSpeedGain * (current > 0 ? -1 : 1)
        }
        return min(0.03 + 0.5 * abs(current), 0.35) * (current > 0 ? -1 : 1)
    }

    private let fieldFront = ModelEntity(
        mesh: Primitives.sphere(radius: 0.012),
        materials: [UnlitMaterial(color: UIColor(
            red: 1.0, green: 0.95, blue: 0.6, alpha: 1))])
    private var fieldFrontPhase = 0.0
    private var trueSpeedCallout: Callout?

    /// A bright front sprinting the loop at the signal's scaled speed while
    /// the electron dots hold still at theirs, and a readout naming both
    /// real times.
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
        // Parked at the bench, not on the field front: the number is a fact
        // about the whole circuit, and text pinned to the fastest-moving object
        // is unreadable.
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
                electronDots.show([])
                electronsVisible = false
            }
            return
        }
        electronsVisible = true

        // Each conducting wire's run and the dots it would carry, then the
        // pool shared out in proportion, so a bench that wants more dots
        // than there are thins every wire rather than starving the last.
        var runs: [(a: SIMD3<Float>, b: SIMD3<Float>, phase: Double, count: Int)] = []
        for wire in model.wires {
            guard let entity = wireEntities[wire.id], entity.isEnabled,
                  let a = terminalWorld(wire.from, model),
                  let b = terminalWorld(wire.to, model),
                  let drift = drift(key: wire.id, from: a, to: b,
                                    current: model.wireFlows[wire.id] ?? 0,
                                    model: model, dt: dt)
            else { continue }
            runs.append((a, b, drift.phase, drift.count))
        }
        let counts = Self.shareDots(runs.map(\.count), capacity: electronDots.capacity)
        var dots: [SIMD3<Float>] = []
        dots.reserveCapacity(electronDots.capacity)
        for (run, count) in zip(runs, counts) {
            for dot in 0..<count {
                var t = (run.phase + Double(dot) / Double(count)).truncatingRemainder(dividingBy: 1)
                if t < 0 { t += 1 }
                dots.append(run.a + (run.b - run.a) * Float(t))
            }
        }
        electronDots.show(dots)
    }

    /// Advances a taut wire's drift phase by the drift speed (− to +) over
    /// real elapsed time, and says how many dots it would carry; nil for a
    /// wire carrying no current worth drawing.
    private func drift(
        key: UUID, from a: SIMD3<Float>, to b: SIMD3<Float>,
        current: Double, model: CircuitsModel, dt: Double
    ) -> (phase: Double, count: Int)? {
        guard abs(current) > 5e-4 else { return nil }
        let total = simd_distance(a, b)
        guard total > 1e-6 else { return nil }
        let length = Double(total)
        // Bead count grows with zoom sublinearly: the beads scale with the
        // wire, so flat spacing is right and only the cap starves Electron
        // View; the square root splits the difference.
        let zoom = Double(max(benchScale, 1))
        let spacing = 0.045 / zoom.squareRoot()
        let cap = Int((9 * zoom).rounded())
        let count = min(max(Int(length / spacing), 2), cap)
        let speed = Self.electronDisplaySpeed(current: current, model: model)
        if !model.isPaused {
            wirePhases[key] = ((wirePhases[key] ?? 0)
                + speed / max(length, 0.05) * dt).truncatingRemainder(dividingBy: 1)
        }
        return (wirePhases[key] ?? 0, count)
    }

    /// Shares `capacity` dots among wires that want `wanted` each: all of
    /// them when they fit, otherwise each in proportion, never fewer than
    /// two on a wire that carries current (one dot cannot show a drift).
    nonisolated static func shareDots(_ wanted: [Int], capacity: Int) -> [Int] {
        let total = wanted.reduce(0, +)
        guard total > capacity else { return wanted }
        let floor = min(2, capacity / max(wanted.count, 1))
        let share = Double(capacity - floor * wanted.count) / Double(total - floor * wanted.count)
        return wanted.map { floor + Int(Double($0 - floor) * share) }
    }
}

/// The bench's electron dots: one pale bead per dot, as wide as the old
/// halo so it stands proud of the wire's dark jacket it rides inside (the
/// core alone, 2.6 mm in a 3.7 mm jacket, all but vanishes). Instancing
/// them (contract D5) was tried first and measured: a `LowLevelInstanceData`
/// written every frame waits on the renderer's in-flight limit — the main
/// thread in `freeListWait` half the time, 70 long frames in every 5 s at
/// 4× — so this is D5's fallback, a pool of plain entities that move by
/// transform alone, one draw each.
@MainActor
final class ElectronDots {
    let root = Entity()
    let capacity: Int
    private(set) var positions: [SIMD3<Float>] = []
    private let pool: EntityPool<Void>
    /// The bead's radius: the old halo's, 0.8 mm proud of the jacket.
    static let beadRadius: Float = 0.0045
    private static let coreRadius: Float = 0.0026

    init(capacity: Int) {
        self.capacity = capacity
        root.name = "electron-dots"
        let material = UnlitMaterial(color: UIColor(red: 0.8, green: 1.0, blue: 1.0, alpha: 1))
        let mesh = CircuitsRenderer.electronMeshes().core
        let scale = Self.beadRadius / Self.coreRadius
        pool = EntityPool(budget: capacity) { container in
            let bead = ModelEntity(mesh: mesh, materials: [material])
            bead.scale = SIMD3(repeating: scale)
            container.addChild(bead)
        }
        root.addChild(pool.root)
    }

    /// Draws a dot at each position (bench frame), up to `capacity`. A
    /// paused bench's unchanged dots write nothing.
    func show(_ dots: [SIMD3<Float>]) {
        let dots = Array(dots.prefix(capacity))
        guard dots != positions else { return }
        let shown = positions.count
        positions = dots
        for index in 0..<max(shown, dots.count) {
            let entity = pool.slots[index].entity
            if index < dots.count {
                if index >= shown { entity.isEnabled = true }
                entity.position = dots[index]
            } else {
                entity.isEnabled = false
            }
        }
    }
}
