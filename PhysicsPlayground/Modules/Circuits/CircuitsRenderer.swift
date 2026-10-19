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

    /// The lead's touch target — the bead and the carry target are both sized against it.
    static let terminalTargetRadius: Float = 0.026

    private struct ComponentVisual {
        let holder: Entity
        let body: ModelEntity
        /// The resistor's procedural ceramic, which wears the live bands.
        var ceramic: ModelEntity?
        var terminals: [ModelEntity]
        /// Each lead's current accessibility value — unchanged state costs no write.
        var terminalValues: [String] = ["", ""]
        /// Whether each lead is in a joint, its target withdrawn for the
        /// joint's collar — changed only when it moves.
        var terminalJoined: [Bool] = [false, false]
        let label: BackedLabel
        let halo: ModelEntity
        var glow: ModelEntity?
        var filament: ModelEntity?
        /// The bulb's own light on the parts round it.
        var light: Entity?
        var lever: ModelEntity?
        /// Motors only: the propeller that spins with the shaft.
        var rotor: Entity?
        /// The fuse's middle filament segment, gone when it blows.
        var fuseBridge: ModelEntity?
        /// The capacitor's charge gauge, scaled along x by |V|/24.
        var gaugeFill: ModelEntity?
        /// The AC source's needle, swung by the EMF.
        var needle: Entity?
        /// The LED's lit die, red when it conducts and dark once burned out.
        var ledCore: Entity?
        let labelPivot: Entity
        /// The axis and stage yaw the orientation was last built for, the
        /// frame built, and whether the drawn frame is still easing to it.
        var orientedFor: (axis: SIMD3<Float>, yaw: Double)?
        var targetOrientation: simd_quatf?
        var easingOrientation = false
        var appliedGauge: Float = -1
        var fuseIntact: Bool?
        var ledState = Int.min
        var labelText = ""
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

    private static let electronBudget = 200
    private let electronPool: EntityPool<Void>
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

        // Electrons you can't miss: a white-hot core inside a cyan glow.
        let coreMaterial = UnlitMaterial(color: UIColor(red: 0.8, green: 1.0, blue: 1.0, alpha: 1))
        let haloMaterial = Materials.unlit(DesignTokens.Palette.electronUI, opacity: 0.35)
        let coreMesh = Primitives.sphere(radius: 0.0034)
        let haloMesh = Primitives.sphere(radius: 0.0075)
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

        if let rim = stageRoot.findEntity(named: Self.stageRimName) {
            SpatialActions.attach(
                to: rim, label: "Turntable. Activate to turn the circuit 45 degrees.",
                activate: { [weak self] in self?.onStageAction?() })
        }

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

    // MARK: Lab-kit modules (2026-10-18)

    /// Where `Tools/circuitparts.py` stands each part's live pieces — keep in
    /// step with its constants of the same names.
    nonisolated static let carrierTop: Float = -0.012
    nonisolated static let carrierBottom: Float = -0.026
    nonisolated static let bulbCentre: Float = 0.024
    nonisolated static let ledGlowHeight: Float = 0.013
    nonisolated static let motorAxis: Float = 0.008
    nonisolated static let switchPivot = SIMD3<Float>(-0.028, 0.004, 0)
    nonisolated static let resistorAxis: Float = 0.006
    nonisolated static let fuseAxis: Float = 0
    nonisolated static let acFace: Float = -0.0018
    /// The brass ball at each end: the terminal, as a lab kit's contact.
    nonisolated static let contactRadius: Float = 0.012
    static let carrierAssetName = "CircuitCarrier"
    /// The shelf shows each module at this fraction of its size, so a whole
    /// module — carrier, contacts and all — fits a slot.
    nonisolated static let shelfPreviewScale: Float = 0.60
    /// The capacitor gauge's full scale, V: the bench's tallest source.
    nonisolated static let gaugeFullScale = 24.0

    private static let contactMaterial = Materials.machined(
        DesignTokens.Palette.contactBrassUI, roughness: 0.28)

    /// One lab-kit module as built: its carrier, its body and contacts, and
    /// the pieces that move or light, for `makeVisual`, the shelf and the
    /// home's diorama to share.
    struct Module {
        let root: Entity
        var carrier: Entity?
        let body: ModelEntity
        var ceramic: ModelEntity?
        var contacts: [ModelEntity] = []
        var filament: ModelEntity?
        var glow: ModelEntity?
        var light: Entity?
        var rotor: Entity?
        var lever: ModelEntity?
        var fuseBridge: ModelEntity?
        var gaugeFill: ModelEntity?
        var needle: Entity?
        var ledCore: Entity?
    }

    static func makeModule(kind: CircuitsModel.ComponentKind) -> Module {
        let root = Entity()
        var carrier: Entity?
        if let prototype = PropCache.prototype(named: carrierAssetName) {
            let mounted = prototype.clone(recursive: true)
            mounted.name = "carrier"
            root.addChild(mounted)
            carrier = mounted
        }
        let (body, ceramic) = makeBody(kind: kind)
        root.addChild(body)
        var module = Module(root: root, carrier: carrier, body: body, ceramic: ceramic)
        let contactMesh = Primitives.sphere(radius: contactRadius)
        for end in 0...1 {
            let contact = ModelEntity(mesh: contactMesh, materials: [contactMaterial])
            contact.position = [Float(end == 0 ? -1 : 1) * Float(CircuitsModel.terminalOffset), 0, 0]
            root.addChild(contact)
            module.contacts.append(contact)
        }
        switch kind {
        case .bulb:
            // Between the milled supports' tips at ±0.005.
            let filament = ModelEntity(
                mesh: Primitives.cylinder(height: 0.010, radius: 0.0009),
                materials: [Materials.unlit(UIColor(white: 0.35, alpha: 1))])
            filament.name = "bulb-filament"
            filament.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            filament.position = [0, bulbCentre, 0]
            root.addChild(filament)
            module.filament = filament
            let glow = GlowSprite.make(size: 0.10)
            glow.position = [0, bulbCentre, 0]
            glow.isEnabled = false
            root.addChild(glow)
            module.glow = glow
            let light = Entity()
            light.position = [0, bulbCentre, 0]
            root.addChild(light)
            module.light = light
        case .led:
            let glow = GlowSprite.make(size: 0.06)
            glow.position = [0, ledGlowHeight, 0]
            glow.isEnabled = false
            root.addChild(glow)
            module.glow = glow
            let light = Entity()
            light.position = [0, ledGlowHeight + 0.006, 0]
            root.addChild(light)
            module.light = light
            // A skin just over the milled lens and its barrel: the lit die
            // when it conducts, the dark one once it has burned out.
            let core = Entity()
            core.name = "led-core"
            core.isEnabled = false
            let dome = ModelEntity(mesh: Primitives.sphere(radius: 0.0060), materials: [])
            dome.position = [0, 0.014, 0]
            core.addChild(dome)
            let barrel = ModelEntity(mesh: Primitives.cylinder(height: 0.008, radius: 0.0060),
                                     materials: [])
            barrel.position = [0, 0.010, 0]
            core.addChild(barrel)
            root.addChild(core)
            module.ledCore = core
        case .motor:
            // A two-blade propeller on the shaft end, spun each frame by the
            // motor's live speed; its tips clear the carrier's top by 2 mm.
            let rotor = Entity()
            rotor.position = [0.050, motorAxis, 0]
            rotor.addChild(ModelEntity(
                mesh: Primitives.sphere(radius: 0.006),
                materials: [Materials.machined(UIColor(white: 0.6, alpha: 1), roughness: 0.3)]))
            for axis: SIMD3<Float> in [[0, 1, 0], [0, 0, 1]] {
                let blade = ModelEntity(
                    mesh: Primitives.box(size: [0.004, 0.036, 0.003], cornerRadius: 0.0015),
                    materials: [Materials.unlit(DesignTokens.Palette.motorAccentUI)])
                blade.orientation = rotation(from: [0, 1, 0], to: axis)
                rotor.addChild(blade)
            }
            root.addChild(rotor)
            module.rotor = rotor
        case .switcher:
            // The knife switch's blade, pivoting between the brass cheeks.
            let pivot = ModelEntity()
            pivot.position = switchPivot
            // Long enough to pass through the spring contact at +0.028, so
            // its grip stands clear of the springs.
            let blade = ModelEntity(
                mesh: Primitives.box(size: [0.066, 0.005, 0.0045], cornerRadius: 0.0015),
                materials: [Materials.machined(DesignTokens.Palette.contactBrassUI, roughness: 0.3)])
            blade.position = [0.033, 0.0005, 0]
            pivot.addChild(blade)
            let grip = ModelEntity(
                mesh: Primitives.box(size: [0.008, 0.010, 0.008], cornerRadius: 0.003),
                materials: [Materials.graphite()])
            grip.position = [0.064, 0.003, 0]
            pivot.addChild(grip)
            root.addChild(pivot)
            module.lever = pivot
        case .fuse:
            // The filament in three segments, so a blown fuse loses its middle.
            for (index, x) in [Float(-0.0105), 0, 0.0105].enumerated() {
                let segment = ModelEntity(
                    mesh: Primitives.cylinder(height: index == 1 ? 0.009 : 0.012, radius: 0.0006),
                    materials: [copperMaterial])
                segment.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                segment.position = [x, fuseAxis, 0]
                root.addChild(segment)
                if index == 1 {
                    segment.name = "fuse-bridge"
                    module.fuseBridge = segment
                }
            }
        case .capacitor:
            // The charge gauge, a champagne bar on the carrier's top in front
            // of the can, filling from the left.
            let track = ModelEntity(
                mesh: Primitives.box(size: [0.026, 0.0010, 0.0032]),
                materials: [Materials.unlit(UIColor(white: 0.18, alpha: 1))])
            track.position = [0, carrierTop + 0.0005, 0.0175]
            root.addChild(track)
            let fill = ModelEntity(
                mesh: Primitives.box(size: [1, 0.0014, 0.0034]),
                materials: [Materials.machined(DesignTokens.Palette.contactBrassUI, roughness: 0.25)])
            fill.name = "capacitor-gauge"
            fill.position = [-0.013, carrierTop + 0.0007, 0.0175]
            fill.scale = [0.0001, 1, 1]
            root.addChild(fill)
            module.gaugeFill = fill
        case .acSource:
            // The dial's needle, pointing away at zero, swung ±60° by the EMF.
            let needle = Entity()
            needle.name = "ac-needle"
            needle.position = [0, acFace + 0.0010, 0]
            let pointer = ModelEntity(
                mesh: Primitives.box(size: [0.0012, 0.0008, 0.0150], cornerRadius: 0.0003),
                materials: [Materials.unlit(UIColor(white: 0.10, alpha: 1))])
            pointer.position = [0, 0, -0.0068]
            needle.addChild(pointer)
            let hub = ModelEntity(mesh: Primitives.cylinder(height: 0.0012, radius: 0.0018),
                                  materials: [Materials.machined(DesignTokens.Palette.contactBrassUI)])
            needle.addChild(hub)
            root.addChild(needle)
            module.needle = needle
        default:
            break
        }
        return module
    }

    /// How far from vertical a part's axis must lie (the sine of its angle
    /// from the vertical) before "its top toward the sky" means anything.
    nonisolated static let uprightThreshold: Float = 0.26

    /// The angle of a module's frame: x along its axis and, wherever the axis
    /// lies far enough from vertical, its carrier's top toward the sky — as a
    /// real part sits on a turning table, so a part laid end-for-end shows its
    /// back chamfer (whose symbol reads the right way from behind) rather than
    /// hanging upside down, which the shortest-arc rotation this replaces
    /// (2026-10-18) did to every part swung near −X.
    ///
    /// Within 15° of vertical "up" can no longer be its top — the top would
    /// wheel round the axis as a hand wobbled it — so there the frame is the
    /// `previous` one carried onto the new axis by the shortest arc, keeping
    /// whatever roll it had. With no previous frame (a part made standing),
    /// its top turns to the stage's `front`. Turns rigidly with the stage.
    nonisolated static func moduleOrientation(axis: SIMD3<Float>, front: SIMD3<Float>,
                                              previous: simd_quatf? = nil) -> simd_quatf {
        let x = simd_normalize(axis)
        let up = SIMD3<Float>(0, 1, 0)
        let upPerpendicular = up - simd_dot(up, x) * x
        if simd_length(upPerpendicular) >= uprightThreshold {
            return frame(x: x, top: upPerpendicular)
        }
        if let previous {
            let carried = rotation(from: previous.act([1, 0, 0]), to: x) * previous
            return frame(x: x, top: carried.act([0, 1, 0]))
        }
        var top = front - simd_dot(front, x) * x
        if simd_length(top) < 1e-4 {
            let fallback = SIMD3<Float>(0, 0, 1)
            top = fallback - simd_dot(fallback, x) * x
        }
        return frame(x: x, top: top)
    }

    private nonisolated static func frame(x: SIMD3<Float>, top: SIMD3<Float>) -> simd_quatf {
        let y = simd_normalize(top - simd_dot(top, x) * x)
        return simd_quatf(simd_float3x3(columns: (x, y, simd_cross(x, y))))
    }

    /// A frame change bigger than this eases rather than snaps: a swing
    /// across the upright threshold, a part flipped end-for-end. A hand's
    /// own motion moves a part a few degrees a frame.
    nonisolated static let orientationEaseThreshold: Float = 10 * .pi / 180

    /// Where a part's value hangs, in the room, from its centre: below it,
    /// or beside it once it stands nearly on end and below is its own lower
    /// contact.
    nonisolated static func labelOffset(for orientation: simd_quatf) -> SIMD3<Float> {
        let x = orientation.act([1, 0, 0])
        let side = orientation.act([0, 0, 1])
        let t = min(max((abs(x.y) - 0.70) / 0.25, 0), 1)
        let w = t * t * (3 - 2 * t)
        return (1 - w) * SIMD3(0, -0.050, 0) + w * side * 0.060
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
    /// The glow stays until `flashRelease`.
    func flashPickup(id: UUID) {
        landings[id] = nil
        guard let holder = visuals[id]?.holder else { return }
        if let previous = pulsedGrabEntity, previous !== holder {
            LiveGlow.set(false, on: previous)
        }
        pulsedGrabEntity = holder
        LiveGlow.set(true, on: holder)
        SoundPalette.play(.grabTick, on: holder, volume: 0.2)
    }

    /// Answer a release, on whatever was last picked up.
    func flashRelease() {
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
        var top = stageTop ?? target
        top += (target - top) * Float(min(dt * 6, 1))
        if abs(target - top) < 0.0005 { top = target }
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
        skylineRoot.isEnabled = model.showVoltageHeights
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
        let column = ModelEntity(mesh: Primitives.box(
            size: [0.012, 0.1, 0.012], cornerRadius: 0.003))
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

    /// Called around `CircuitsModel.release(id:)` with the pose the part
    /// had before it: what is drawn eases from there to where the model put
    /// it — the holder, and through `terminalWorld` its wires and electrons.
    func easeLanding(id: UUID, from position: SIMD3<Double>, axis: SIMD3<Double>) {
        guard !Motion.isReduced else { return }
        landings[id] = Landing(position: position, axis: axis, elapsed: 0)
    }

    private func advanceLandings(dt: Double) {
        for id in Array(landings.keys) {
            landings[id]?.elapsed += dt
            if let landing = landings[id], landing.elapsed >= Self.landingDuration {
                landings[id] = nil
            }
        }
    }

    /// Where a part is drawn: the model's pose, or partway through a landing.
    func displayPose(of component: CircuitsModel.Component)
    -> (position: SIMD3<Double>, axis: SIMD3<Double>) {
        guard let landing = landings[component.id] else {
            return (component.position, component.axis)
        }
        let t = min(max(landing.elapsed / Self.landingDuration, 0), 1)
        let e = t * t * (3 - 2 * t)
        let position = landing.position + (component.position - landing.position) * e
        let from = simd_normalize(landing.axis), to = simd_normalize(component.axis)
        let turn = simd_slerp(simd_quatd(angle: 0, axis: [0, 1, 0]), simd_quatd(from: from, to: to), e)
        return (position, turn.act(from))
    }

    private func syncComponents(_ model: CircuitsModel, dt: Double) {
        litTerminals = Self.litTerminals(model, refused: refusalSources(model))
        let joined = jointTerminals(model)
        // Remove visuals whose components are gone.
        let liveIDs = Set(model.components.map(\.id))
        for id in visuals.keys where !liveIDs.contains(id) {
            visuals[id]?.holder.removeFromParent()
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
            Fade.tick(visual.halo, visible: component.id == model.selectedID)

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
                // A lead in a joint gives its target to the joint's collar:
                // two coincident leads' targets overlapped, and which one a
                // pinch took was hit order.
                let inJoint = joined.contains(key)
                if visual.terminalJoined[end] != inJoint {
                    visual.terminalJoined[end] = inJoint
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

            // Live label. `BackedLabel` self-gates on unchanged text.
            let text = Self.labelText(for: component)
            if visual.labelText != text,
               visual.label.setText(text, color: UIColor(white: 0.95, alpha: 1)) {
                visual.labelText = text
            }
            visual.labelPivot.isEnabled = !text.isEmpty

            switch component.kind {
            case .bulb:
                let watts = model.readouts[component.id]?.watts ?? 0
                let bucket = min(max(Int((watts / 3.0) * 5), 0), 5)
                if visual.glowBucket != bucket {
                    visual.glowBucket = bucket
                    Self.paintBulb(filament: visual.filament, glow: visual.glow,
                                   light: visual.light, level: bucket)
                }
            case .led:
                let amps = abs(model.readouts[component.id]?.amps ?? 0)
                let state = component.failed ? -1 : min(Int(amps / 0.004), 5)
                if visual.ledState != state {
                    visual.ledState = state
                    Self.paintLED(core: visual.ledCore, glow: visual.glow,
                                  light: visual.light, state: state)
                }
            case .switcher:
                visual.lever?.orientation = simd_quatf(
                    angle: component.isClosed ? 0 : 0.6, axis: [0, 0, 1])
            case .fuse:
                let intact = !component.failed
                if visual.fuseIntact != intact {
                    visual.fuseIntact = intact
                    visual.fuseBridge?.isEnabled = intact
                }
            case .capacitor:
                let charge = Float(Self.gaugeFill(volts: model.readouts[component.id]?.volts ?? 0))
                if abs(charge - visual.appliedGauge) > 0.004 {
                    visual.appliedGauge = charge
                    visual.gaugeFill?.isEnabled = charge > 0.004
                    visual.gaugeFill?.scale = [max(charge, 0.0001) * Self.gaugeLength, 1, 1]
                    visual.gaugeFill?.position.x = -Self.gaugeLength / 2 + charge * Self.gaugeLength / 2
                }
            case .acSource:
                visual.needle?.orientation = simd_quatf(
                    angle: Self.needleAngle(phase: model.acPhase(of: component)), axis: [0, 1, 0])
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

    /// The capacitor gauge's bar, m, at full charge.
    nonisolated static let gaugeLength: Float = 0.026

    /// How full the capacitor's gauge reads, 0…1: |V| against the bench's
    /// tallest source.
    nonisolated static func gaugeFill(volts: Double) -> Double {
        min(abs(volts) / gaugeFullScale, 1)
    }

    /// The AC dial's needle for a phase of the source's cycle: ±60° at the
    /// crests, straight up the dial at zero.
    nonisolated static func needleAngle(phase: Double) -> Float {
        Float(.pi / 3 * sin(phase))
    }

    private static let warmLight = UIColor(red: 1, green: 0.82, blue: 0.5, alpha: 1)
    private static let litFilament = Materials.unlit(UIColor(red: 1, green: 0.78, blue: 0.36, alpha: 1))
    private static let darkFilament = Materials.unlit(UIColor(white: 0.35, alpha: 1))

    /// A bulb at a brightness, 0…5: its filament, the glow round its glass
    /// and its light on the parts beside it.
    static func paintBulb(filament: ModelEntity?, glow: ModelEntity?, light: Entity?, level: Int) {
        filament?.model?.materials = [level > 0 ? litFilament : darkFilament]
        guard level > 0 else {
            glow?.isEnabled = false
            light?.components.remove(PointLightComponent.self)
            return
        }
        let strength = Float(level) / 5
        if let glow {
            glow.isEnabled = true
            GlowSprite.paint(glow, warmLight, strength: strength)
        }
        light?.components.set(PointLightComponent(
            color: warmLight, intensity: 1100 * strength, attenuationRadius: 0.25))
    }

    private static let ledOff = Materials.unlit(UIColor(white: 0.06, alpha: 1))

    /// An LED in a state: −1 burned out (a dark die), 0 dark, 1…5 lit red at
    /// 625 nm, the colour a red LED emits.
    static func paintLED(core: Entity?, glow: ModelEntity?, light: Entity?, state: Int) {
        let skins = core?.children.compactMap { $0 as? ModelEntity } ?? []
        guard state > 0 else {
            core?.isEnabled = state < 0
            skins.forEach { $0.model?.materials = [ledOff] }
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
        let lit = Materials.unlit(UIColor(red: r + (1 - r) * w, green: g + (1 - g) * w,
                                          blue: b + (1 - b) * w, alpha: 1))
        core?.isEnabled = true
        skins.forEach { $0.model?.materials = [lit] }
        if let glow {
            glow.isEnabled = true
            GlowSprite.paint(glow, red, strength: strength)
        }
        light?.components.set(PointLightComponent(
            color: red, intensity: 700 * strength, attenuationRadius: 0.18))
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

    /// The bench label: the part's number and nothing else (2026-10-18). Its
    /// state is the part's own to show — a lever up, a dark bulb, a broken
    /// filament, a scorched ceramic — so no word repeats it, and a part with
    /// no number (a switch, an LED) carries no label. Value formatting goes
    /// through the one authority, `CircuitsModel.formatValue`, so label and
    /// readout cannot disagree.
    static func labelText(for component: CircuitsModel.Component) -> String {
        switch component.kind {
        case .battery, .acSource, .bulb, .capacitor, .inductor, .resistor:
            CircuitsModel.formatValue(component.value, for: component.kind)
        case .switcher, .led: ""
        case .motor: motorRPMLabel(component.motorSpeed)
        case .fuse: PhysicsFormat.measurement(component.value, "A", decimals: 1)
        }
    }

    private func makeVisual(for component: CircuitsModel.Component) -> ComponentVisual {
        // The holder is the manipulation target, so a carried part brings
        // its contacts, label and halo along.
        let holder = Entity()
        holder.name = component.id.uuidString
        holder.position = SIMD3<Float>(component.position)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(component.kind.displayName). Drag to move; pull from its terminals to wire.")
        holder.components.set(accessibility)
        viewRoot.addChild(holder)

        // The module: the part on its carrier, its two brass contacts and its
        // live pieces. Everything solid shadows the stage below.
        let module = Self.makeModule(kind: component.kind)
        holder.addChild(module.root)
        GroundingShadows.cast(on: module.body)
        if let carrier = module.carrier { GroundingShadows.cast(on: carrier) }

        // The carry target is the body and its carrier, measured from them
        // (the holder collects a bulb's glow and a halo), with its x
        // half-extent clamped inside the contact target's inner edge so a
        // body pinch cannot swallow a lead.
        var bounds = module.body.visualBounds(relativeTo: holder)
        if let carrier = module.carrier {
            bounds = bounds.union(carrier.visualBounds(relativeTo: holder))
        }
        let clearOfLead = Float(CircuitsModel.terminalOffset) - Self.terminalTargetRadius - 0.002
        let half = SIMD3<Float>(
            min(bounds.extents.x / 2 + Grabbable.reach, clearOfLead),
            bounds.extents.y / 2 + Grabbable.reach,
            bounds.extents.z / 2 + Grabbable.reach)
        Grabbable.configureTouchTarget(
            holder, box: half * 2, offset: [0, bounds.center.y, bounds.center.z],
            activate: { [weak self, weak holder] in
                guard let holder else { return }
                self?.onTap?(holder)
            })

        // The contacts are the terminals: the only thing at each end.
        for (end, terminal) in module.contacts.enumerated() {
            terminal.name = "t\(end)-\(component.id.uuidString)"
            // The only target at this end; the far contact is 0.17 m away.
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
            var terminalAccessibility = AccessibilityComponent()
            terminalAccessibility.isAccessibilityElement = true
            terminalAccessibility.label = LocalizedStringResource(stringLiteral:
                "\(component.kind.displayName) terminal. Activate this, then another terminal, to wire them.")
            terminal.components.set(terminalAccessibility)
            GroundingShadows.cast(on: terminal)
        }

        // Selection halo: a rounded slab the module's own shape.
        let halo = SelectionHalo.make(mesh: Primitives.box(
            size: [0.215, 0.085, 0.090], cornerRadius: 0.030))
        halo.position = [0, 0.008, 0]
        holder.addChild(halo)

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
            terminals: module.contacts, label: label, halo: halo,
            labelPivot: labelPivot)
        visual.glow = module.glow
        visual.filament = module.filament
        visual.light = module.light
        visual.rotor = module.rotor
        visual.fuseBridge = module.fuseBridge
        visual.gaugeFill = module.gaugeFill
        visual.needle = module.needle
        visual.ledCore = module.ledCore

        if component.kind == .switcher, let pivot = module.lever {
            // The blade pivots between the cheeks; the tap target is the
            // pivot, so the whole blade is pinchable.
            pivot.name = "k-\(component.id.uuidString)"
            var leverAccessibility = AccessibilityComponent()
            leverAccessibility.isAccessibilityElement = true
            leverAccessibility.label = "Switch lever. Pinch to open or close the circuit."
            pivot.components.set(leverAccessibility)
            // Measured after the blade exists, so it does not bulge below the
            // switch and take the pinches meant for the contacts. Set
            // directly: the pivot is not a carried object.
            let leverBounds = pivot.visualBounds(relativeTo: pivot)
            pivot.components.set(InputTargetComponent())
            pivot.components.set(CollisionComponent(shapes: [
                Primitives.collisionBox(size: leverBounds.extents
                             + SIMD3<Float>(repeating: 2 * Grabbable.reach), offset: leverBounds.center),
            ]))
            pivot.components.set(HoverEffectComponent())
            // A dedicated callback, not `onTap`: the physical tap path only selects
            // a lever, so VoiceOver's activate needs its own route.
            SpatialActions.attach(
                to: pivot, label: "Switch",
                activate: { [weak self] in
                    self?.onLeverAction?(component.id)
                })
            GroundingShadows.cast(on: pivot)
            visual.lever = pivot
        }

        visuals[component.id] = visual
        return visual
    }

    // MARK: Modeled bodies (Blender-authored USDZ, procedural fallback)

    /// Each part clones the shared `PropCache` prototype, milled by
    /// `Tools/circuitparts.py` to stand on the carrier. The resistor's ceramic
    /// stays procedural: its colour bands are a live texture painted from the
    /// value; only its steel caps and legs are milled. The procedural bodies
    /// below are the fallback for a missing asset, which `CircuitPropTests`
    /// fails.
    static let bodyAssetNames: [CircuitsModel.ComponentKind: String] = [
        .battery: "CircuitBattery", .acSource: "CircuitACSource",
        .capacitor: "CircuitCapacitor", .inductor: "CircuitInductor",
        .bulb: "CircuitBulb", .led: "CircuitLED", .motor: "CircuitMotor",
        .fuse: "CircuitFuse", .switcher: "CircuitSwitch",
    ]
    static let resistorCapsAssetName = "CircuitResistorCaps"
    /// The resistor's ceramic, between the milled caps at ±0.0225.
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
            ceramic.position = [0, resistorAxis, 0]
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

    /// A plain stand-in on the carrier, in the part's own colour.
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
        body.position = [0, carrierTop + 0.012, 0]
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
    nonisolated static let wireGrabInset: Float = 0.028
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

    /// A joint's collar: a champagne sleeve round the two meeting contacts,
    /// what says "these are joined, and you can pull them apart here".
    private static let collarMaterial = Materials.machined(
        UIColor(red: 0.83, green: 0.70, blue: 0.45, alpha: 1), roughness: 0.30)
    nonisolated static let collarRadius: Float = 0.015
    nonisolated static let collarLength: Float = 0.016

    /// Shows or hides a wire's collar, sleeved along the line between its two
    /// parts — the joint's own axis when they lie end to end.
    private func syncCollar(_ entity: ModelEntity, _ wire: CircuitsModel.Wire,
                            model: CircuitsModel, at a: SIMD3<Float>, _ b: SIMD3<Float>) {
        let isJoint = simd_distance(a, b) < Float(CircuitsModel.jointLength)
        var collar = entity.children.first { $0.name == "collar" } as? ModelEntity
        guard isJoint else {
            collar?.isEnabled = false
            return
        }
        if collar == nil {
            let made = ModelEntity(
                mesh: Primitives.cylinder(height: Self.collarLength, radius: Self.collarRadius),
                materials: [Self.collarMaterial])
            made.name = "collar"
            GroundingShadows.cast(on: made)
            entity.addChild(made)
            collar = made
        }
        guard let collar else { return }
        collar.isEnabled = true
        collar.position = (a + b) / 2
        let centres = [wire.from, wire.to].compactMap { terminal in
            model.components.first { $0.id == terminal.componentID }
                .map { SIMD3<Float>(displayPose(of: $0).position) }
        }
        if centres.count == 2, simd_distance(centres[0], centres[1]) > 1e-4 {
            collar.orientation = VectorFieldArrows.rotationFromYAxis(
                to: simd_normalize(centres[1] - centres[0]))
        }
    }

    /// Stretches a wire's one segment taut between its endpoints: a copper
    /// core with a dark jacket child; the electrons ride inside.
    private func layOut(segmentsOf entity: ModelEntity,
                        from a: SIMD3<Float>, to b: SIMD3<Float>) {
        if !entity.children.contains(where: { $0.name == "cable" }) {
            let core = ModelEntity(
                mesh: Primitives.cylinder(height: 1, radius: 0.0032),
                materials: [Self.copperMaterial])
            core.name = "cable"
            let jacket = ModelEntity(
                mesh: Primitives.cylinder(height: 1, radius: 0.0062),
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
            wireEntities[id]?.removeFromParent()
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
                var accessibility = AccessibilityComponent()
                accessibility.isAccessibilityElement = true
                accessibility.label = "Wire. Pinch an end and pull to move it."
                entity.components.set(accessibility)
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
                syncCollar(entity, wire, model: model, at: a, b)
                // A re-lay can mint the segment in bare copper, and stretching changes
                // no voltage; forget the bucket so the repaint covers it.
                wireVoltBuckets[wire.id] = nil
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
                (entity.children.first { $0.name == "collar" } as? ModelEntity)?
                    .model?.materials = [lit ? Self.netHighlightMaterial : Self.collarMaterial]
            }
        }
    }

    private func terminalWorld(_ terminal: CircuitsModel.Terminal, _ model: CircuitsModel) -> SIMD3<Float>? {
        guard let component = model.components.first(where: { $0.id == terminal.componentID })
        else { return nil }
        // The model owns where a lead is, carried or not; a landing eases
        // what is drawn, wires and electrons with it.
        guard landings[component.id] != nil else {
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
        for index in dotIndex..<electronPool.budget {
            electronPool.slots[index].entity.isEnabled = false
        }
    }

    /// Lays drifting electron dots along a taut wire, advancing their
    /// shared phase by the drift speed (− to +) over real elapsed time.
    private func driftDots(
        key: UUID, from a: SIMD3<Float>, to b: SIMD3<Float>,
        current: Double, model: CircuitsModel, dt: Double, dotIndex: inout Int
    ) {
        guard abs(current) > 5e-4 else { return }
        let total = simd_distance(a, b)
        guard total > 1e-6 else { return }
        let length = Double(total)
        // Bead count grows with zoom sublinearly: the beads scale with the
        // wire, so flat spacing is right and only the cap starves Electron
        // View; the square root splits the difference.
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
            slot.entity.position = a + (b - a) * Float(t)
            dotIndex += 1
        }
    }
}
