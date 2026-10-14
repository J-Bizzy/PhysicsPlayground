//
//  FieldRenderer.swift
//  Physics Playground — Electromagnetism module
//
//  Translates electrostatics state into RealityKit entities on
//  RenderKit: VectorFieldArrows, GeometryPipeline (background line
//  rebuilds), TubeMesh, Grabbable. Ticked per frame from
//  SceneEvents.Update; the per-frame path is transforms only, and
//  tracing never runs on the main thread.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class FieldRenderer {
    /// The SpaceView's tap router, so a carried object can be operated
    /// without hands; only the module knows a tap opens a ring.
    var onObjectTap: ((Entity) -> Void)?

    /// Root of everything we render; added to RealityView content at identity,
    /// so this entity's coordinate space == immersive space coordinates.
    let root = Entity()
    /// The two-hand-scalable display root: physics only. Pods and
    /// lighting stay on `root`, unscaled; hands convert through here.
    let viewRoot = Entity()

    /// Event subscriptions, owned here so they live as long as the scene.
    var subscriptions: [EventSubscription] = []

    /// Called from the SpaceView's `onDisappear`: an `EventSubscription`
    /// outlives the view and holds the entity graph alive, and a
    /// `GeometryPipeline` job in flight would upload into a scene being
    /// torn down.
    func teardown() {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        geometryPipeline?.cancel()
    }

    /// The charge in a hand, copied from the model every tick, so a grab is
    /// acknowledged with a flash and a tick like every other lab's. Until
    /// 2026-10-14 nothing set it (it was named for a manipulation system the
    /// lab no longer uses), so no charge ever answered a grab. The model moves
    /// a held charge, so its transform is written like any other.
    var heldChargeID: UUID?
    /// The charge already acknowledged with a pickup pulse — one flash
    /// per grab, not one per frame.
    private var pulsedGrabID: UUID?
    /// Where the release tick plays from when the grab ends.
    private weak var pulsedGrabEntity: Entity?

    /// Entity name for the probe (charges use their UUID string).
    static let probeEntityName = "probe"

    // MARK: Visual constants — always the DesignTokens conventions, so the
    // in-space entities and the window UI can never drift apart.
    static let positiveColor = DesignTokens.Palette.positiveUI
    static let negativeColor = DesignTokens.Palette.negativeUI
    static let probePositiveColor = DesignTokens.Palette.probePositiveUI
    static let probeNegativeColor = DesignTokens.Palette.probeNegativeUI
    static let lineColor = DesignTokens.Palette.fieldLineUI
    static let chargeRadius: Float = 0.03

    /// How big a charge is actually drawn right now — the Bloom's grip
    /// rides this so the handle sits on the sphere's own surface and
    /// travels outward as the charge grows.
    func displayRadius(forChargeID id: UUID) -> Float {
        guard let entity = chargeEntities[id] else { return Self.chargeRadius }
        return Self.chargeRadius * entity.scale.x
    }
    static let probeRadius: Float = 0.018
    /// Arrowheads are hidden inside this distance of a charge, where the
    /// 1/r² field diverges and a finite arrow is meaningless.
    static let arrowExclusionRadius = 0.09
    /// Arc-length spacing of the arrowheads riding each field line.
    static let arrowSpacing: Float = 0.17

    private var model: FieldModel?
    /// Bare arrowhead cones riding the field lines. The line itself is
    /// the shaft — consecutive heads follow the curve, so the arrows bend
    /// with the line instead of laying straight chords over it.
    private let arrowHeads: EntityPool<ModelEntity>
    private var chargeEntities: [UUID: ModelEntity] = [:]
    private var chargeHalos: [UUID: ModelEntity] = [:]
    /// The vertical stroke of each charge's sign glyph — hidden on a
    /// negative charge, turning the + into a −.
    private var chargeSignVerticals: [UUID: ModelEntity] = [:]
    private var appliedPolarity: [UUID: Bool] = [:]
    private var probeEntity: ModelEntity?
    /// Vertical stroke of the probe's sign glyph (hidden makes it a −).
    private var probeSignVertical: ModelEntity?
    private var appliedProbePolarity: Bool?
    private let linesEntity = ModelEntity()
    private let lineCasingEntity = ModelEntity()
    private let lineGlowEntity = ModelEntity()
    /// Core radius of a field line; the casing is swept from it.
    static let lineRadius: Float = 0.0016
    private let lineMaterial = UnlitMaterial(color: FieldRenderer.lineColor)
    private let lineCasingMaterial =
        Materials.contrastLine(FieldRenderer.lineColor).casing
    private let lineGlowMaterial: UnlitMaterial = {
        let material = Materials.unlit(FieldRenderer.lineColor, opacity: 0.2)
        return material
    }()
    // Change detection: the expensive paths only run when these differ.
    private var lastCharges: [PointCharge]?
    /// The calibrated capacitor the lines and dressing were last drawn
    /// for — Equatable, so a static bench is one compare and a carried
    /// plate re-draws live, the same contract `lastCharges` has.
    private var lastCapacitor: PlateField.Capacitor?
    private var lastRegion: FieldModel.SamplingRegion?
    private var lastShowLines: Bool?

    private var geometryPipeline: GeometryPipeline<GeometryJob, GeometryResult>?
    private let fieldFlowRoot = Entity()

    /// The charge layout the currently-applied geometry was traced from.
    private var appliedCharges: [PointCharge] = []

    init() {
        let headMesh = Primitives.cone(height: 0.022, radius: 0.0085)
        let headMaterial = UnlitMaterial(color: FieldRenderer.lineColor)
        arrowHeads = EntityPool(budget: 400) { container in
            let head = ModelEntity(mesh: headMesh, materials: [headMaterial])
            container.addChild(head)
            return head
        }

        // Everything derived from the traced field lives under one root:
        // while a single charge is dragged, the whole pattern translates
        // rigidly with it (exact for one charge — the field just moves),
        // so the lines stick to the hand while the re-trace catches up.
        root.addChild(Lighting.keyLight())
        root.addChild(viewRoot)
        viewRoot.addChild(fieldFlowRoot)
        // The glow halo sits under the arrowheads and the bright core so
        // the crisp line and heads read over the soft bloom.
        fieldFlowRoot.addChild(lineGlowEntity)
        // Casing under the bright core: darkness first, light on top.
        fieldFlowRoot.addChild(lineCasingEntity)
        fieldFlowRoot.addChild(arrowHeads.root)
        linesEntity.isEnabled = false
        fieldFlowRoot.addChild(linesEntity)
        lineGlowEntity.isEnabled = false
        lineCasingEntity.isEnabled = false

        geometryPipeline = GeometryPipeline(
            compute: { Self.computeGeometry($0) },
            apply: { [weak self] in self?.applyGeometry($0) }
        )
    }

    // MARK: Render loop

    /// World → model coordinates, through the scaled view.
    func displayPoint(fromWorld world: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3<Double>(viewRoot.convert(position: world, from: nil))
    }

    func tick(_ model: FieldModel, room: RoomBox = .unscanned) {
        self.model = model
        heldChargeID = model.heldChargeID
        syncProbeTrail(model)
        render(
                charges: model.charges,
                region: model.samplingRegion,
                selectedID: model.selectedChargeID,
                probe: model.probe,
                probeIsPositive: model.probeIsPositive,
                showLines: model.showLines,
                capacitorOn: model.capacitorOn,
                capacitorCenter: model.capacitorCenter,
                plateSeparation: model.plateSeparation,
                capacitor: model.capacitor,
                slabCenter: model.dielectricSlabCenter,
                magneticFieldOn: model.magneticFieldOn,
                room: room
        )
    }

    /// Re-syncs all visuals to the given state.
    func render(
        charges: [PointCharge],
        region: FieldModel.SamplingRegion,
        selectedID: UUID?,
        probe: TestChargeDynamics.ProbeState?,
        probeIsPositive: Bool,
        showLines: Bool,
        capacitorOn: Bool = false,
        capacitorCenter: SIMD3<Double> = .zero,
        plateSeparation: Double = 0.44,
        capacitor: PlateField.Capacitor? = nil,
        slabCenter: SIMD3<Double> = .zero,
        magneticFieldOn: Bool = false,
        room: RoomBox = .unscanned
    ) {
        // Cheap path — runs every render.
        if let id = heldChargeID {
            if pulsedGrabID != id, let entity = chargeEntities[id] {
                pulsedGrabID = id
                // Live while held: the glow stays until the hand lets go.
                if let previous = pulsedGrabEntity, previous !== entity {
                    LiveGlow.set(false, on: previous)
                }
                pulsedGrabEntity = entity
                LiveGlow.set(true, on: entity)
                SoundPalette.play(.grabTick, on: entity, volume: 0.2)
            }
        } else {
            if pulsedGrabID != nil, let entity = pulsedGrabEntity {
                LiveGlow.set(false, on: entity)
                SoundPalette.play(.releaseTick, on: entity, volume: 0.18)
            }
            pulsedGrabID = nil
            pulsedGrabEntity = nil
        }
        syncChargeEntities(charges, selectedID: selectedID)
        syncProbeEntity(probe, isPositive: probeIsPositive)
        syncPlates(on: capacitorOn, center: capacitorCenter, separation: plateSeparation)
        let capacitorChanged = capacitor != lastCapacitor
        syncCapacitorDressing(capacitor, slabCenter: slabCenter,
                              changed: capacitorChanged)
        syncBField(on: magneticFieldOn)
        syncFieldFlowWarp(charges)

        let chargesChanged = charges != lastCharges || region != lastRegion

        // Expensive path — lines (with their riding arrowheads)
        // rebuild on the geometry pipeline.
        // A bare capacitor is a field source in its own right now —
        // the gap draws its bundle with no point charges in the room.
        let hasSources = !charges.isEmpty || capacitor != nil
        linesEntity.isEnabled = showLines && hasSources
        lineCasingEntity.isEnabled = showLines && hasSources
        lineGlowEntity.isEnabled = showLines && hasSources
        if !showLines || !hasSources {
            arrowHeads.hideAll()
        }
        let visibilityChanged = showLines != lastShowLines
        let roomChanged = room != lastRoom
        if showLines
            && (chargesChanged || capacitorChanged || visibilityChanged
                || roomChanged)
            && hasSources {
            geometryPipeline?.submit(GeometryJob(
                charges: charges,
                region: region,
                wantLines: showLines,
                room: room,
                capacitor: capacitor
            ))
        }
        lastRoom = room
        lastShowLines = showLines
        lastCharges = charges
        lastCapacitor = capacitor
        lastRegion = region
    }

    // MARK: Background field geometry (the traced lines)

    private nonisolated struct GeometryJob: Sendable {
        var charges: [PointCharge]
        var region: FieldModel.SamplingRegion
        var wantLines: Bool
        /// The user's real room. Lines are clipped to it: a wall is a
        /// conductor's boundary as far as this picture is concerned.
        var room: RoomBox
        /// The calibrated plates, joining the same trace as the charges.
        var capacitor: PlateField.Capacitor?
    }

    private var lastRoom: RoomBox?

    /// Re-aims the arrowhead pool at the given points, each cone rotated
    /// from its rest +y onto the line's local direction there.
    private func syncArrowHeads(points: [SIMD3<Double>], directions: [SIMD3<Double>]) {
        for (index, slot) in arrowHeads.slots.enumerated() {
            guard index < points.count, index < directions.count else {
                slot.entity.isEnabled = false
                continue
            }
            let direction = directions[index]
            let length = simd_length(direction)
            guard length > 1e-12 else {
                slot.entity.isEnabled = false
                continue
            }
            slot.entity.isEnabled = true
            slot.entity.position = SIMD3<Float>(points[index])
            slot.entity.orientation = simd_quatf(
                from: [0, 1, 0], to: SIMD3<Float>(direction / length))
        }
    }

    /// While a lone charge moves, translate the whole traced pattern with
    /// it — exact physics (one charge's field is the same everywhere, just
    /// centered on the charge), and it makes the lines stick to the hand
    /// instead of trailing the background re-trace.
    private func syncFieldFlowWarp(_ charges: [PointCharge]) {
        if charges.count == 1, appliedCharges.count == 1,
           charges[0].id == appliedCharges[0].id {
            fieldFlowRoot.position = SIMD3<Float>(charges[0].position - appliedCharges[0].position)
        } else {
            fieldFlowRoot.position = .zero
        }
    }

    // MARK: Uniform B field — the same visual language as the E lines:
    // Uniform B: continuous vertical lines with arrowheads riding them,
    // pointing up. Static geometry, built once and toggled.

    private let bFieldRoot = Entity()
    private var bFieldBuilt = false

    private func syncBField(on: Bool) {
        if on && !bFieldBuilt {
            bFieldBuilt = true
            let material = UnlitMaterial(color: DesignTokens.Palette.probeNegativeUI)
            let center = SIMD3<Float>(FieldModel.regionCenter)
            let lattice: [Float] = [-0.54, -0.18, 0.18, 0.54]
            let yBottom = center.y - 0.6
            let yTop = center.y + 0.6

            var lines: [[SIMD3<Float>]] = []
            for x in lattice {
                for z in lattice {
                    lines.append([SIMD3(center.x + x, yBottom, center.z + z),
                                  SIMD3(center.x + x, yTop, center.z + z)])
                }
            }
            if let mesh = TubeMesh.tube(lines: lines) {
                bFieldRoot.addChild(ModelEntity(mesh: mesh, materials: [material]))
            }
            // Arrowheads chained up each line (cones point +y already).
            let coneMesh = Primitives.cone(height: 0.02, radius: 0.008)
            for x in lattice {
                for z in lattice {
                    var y = yBottom + 0.12
                    while y < yTop - 0.06 {
                        let head = ModelEntity(mesh: coneMesh, materials: [material])
                        head.position = [center.x + x, y, center.z + z]
                        bFieldRoot.addChild(head)
                        y += FieldRenderer.arrowSpacing
                    }
                }
            }
            viewRoot.addChild(bFieldRoot)
        }
        bFieldRoot.isEnabled = on
    }

    // MARK: Capacitor plates

    private var plateEntities: [ModelEntity] = []
    /// The surface-charge dots on the plates' inner faces — density per
    /// band follows σ·A, so raising ΔV, closing the gap or sliding the slab
    /// in visibly packs more charge. Rebuilt only when the calibrated
    /// capacitor changes.
    private var chargeDots: [ModelEntity] = []
    private var dielectricSlab: ModelEntity?
    private var slabHandle: Entity?
    /// Which sign each dot last wore, so a rebuild repaints only the
    /// dots that actually flipped plates.
    private var chargeDotSigns: [Bool] = []
    /// C, Q, U and the measured E, floating over the + plate.
    private var capacitorCallout: Callout?
    /// Set when the capacitor changes, cleared once its callout shows it.
    private var capacitorTextPending = false

    private func syncPlates(on: Bool, center: SIMD3<Double>, separation: Double) {
        if plateEntities.isEmpty {
            // The machined plate from `Tools/fieldprops.py`, painted in anodised
            // accent metal here so the palette stays the authority on +/−. The
            // translucent box is the fallback.
            let prototype = PropCache.prototype(named: "CapacitorPlate")
            let mesh = Primitives.box(
                size: [0.012, Float(FieldModel.plateSize), Float(FieldModel.plateSize)],
                cornerRadius: 0.004)
            for isPositive in [true, false] {
                let accent = isPositive
                    ? DesignTokens.Palette.positiveUI
                    : DesignTokens.Palette.negativeUI
                let plate: ModelEntity
                if let prototype {
                    let holder = ModelEntity()
                    let body = prototype.clone(recursive: true)
                    let metal = Materials.machined(accent, roughness: 0.34)
                    func paint(_ entity: Entity) {
                        if var model = entity.components[ModelComponent.self] {
                            model.materials = [metal]
                            entity.components.set(model)
                        }
                        for child in entity.children { paint(child) }
                    }
                    paint(body)
                    // The furniture is authored on the −x face; the −
                    // plate turns about Y so its terminal faces outward.
                    if !isPositive {
                        body.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
                    }
                    holder.addChild(body)
                    plate = holder
                } else {
                    var material = PhysicallyBasedMaterial()
                    material.baseColor = .init(tint: accent)
                    material.roughness = 0.4
                    material.blending = .transparent(opacity: .init(floatLiteral: 0.35))
                    plate = ModelEntity(mesh: mesh, materials: [material])
                }
                plate.name = isPositive ? "plate-0" : "plate-1"
                // The plates wear the same sign glyphs as the charges —
                // the shared builder, with the bar length the plate's
                // own scale asks for rather than a sphere's.
                let signPivot = Self.signGlyph(isPositive: isPositive,
                                               radius: 0, barLength: 0.05)
                signPivot.position = [0, Float(FieldModel.plateSize) * 0.28, 0]
                plate.addChild(signPivot)
                // The plate is a slab, not a ball: a sphere collider overlapped through
                // the whole interior of the capacitor and made every charge inside it
                // unpinchable.
                Grabbable.configureTouchTarget(
                    plate, matchingVisualBoundsOf: plate,
                    activate: { [weak self, weak plate] in
                        guard let plate else { return }
                        self?.onObjectTap?(plate)
                    })
                var accessibility = AccessibilityComponent()
                accessibility.isAccessibilityElement = true
                accessibility.label = "Capacitor plate. Drag along the field axis to change the gap; carry it to move the capacitor."
                plate.components.set(accessibility)
                plate.isEnabled = false
                plateEntities.append(plate)
                viewRoot.addChild(plate)
            }
        }
        let mid = SIMD3<Float>(center)
        let half = Float(separation / 2)
        plateEntities[0].position = mid + SIMD3(-half, 0, 0)  // + plate
        plateEntities[1].position = mid + SIMD3(half, 0, 0)   // − plate
        for plate in plateEntities { plate.isEnabled = on }
    }

    /// Everything the real capacitor wears beyond the plates: the
    /// dielectric slab, the surface-charge dots and the callout. Transforms
    /// every frame; dot layout and callout text gated on the calibrated
    /// capacitor changing.
    private func syncCapacitorDressing(_ capacitor: PlateField.Capacitor?,
                                       slabCenter: SIMD3<Double>,
                                       changed: Bool) {
        if dielectricSlab == nil {
            // Frosted glass built as a unit cube, so the per-frame path is
            // transforms only while the gap stretches around it.
            var glass = PhysicallyBasedMaterial()
            glass.baseColor = .init(tint: UIColor(red: 0.72, green: 0.84,
                                                  blue: 0.88, alpha: 1))
            glass.roughness = .init(floatLiteral: 0.65)
            glass.blending = .transparent(opacity: .init(floatLiteral: 0.3))
            let slab = ModelEntity(
                mesh: Primitives.box(size: [1, 1, 1], cornerRadius: 0.015),
                materials: [glass])
            slab.name = "dielectric-slab"
            Grabbable.configureTouchTarget(slab, box: [1, 1, 1])
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = LocalizedStringResource(
                stringLiteral: "Dielectric slab. Slide it into the gap "
                + "to raise the capacitance.")
            slab.components.set(accessibility)
            viewRoot.addChild(slab)
            dielectricSlab = slab

            // The brass T-handle the slab is slid by (`fieldprops.py`): fixed size,
            // so a sibling rather than a child the slab's stretch would distort. It
            // shares the slab's name so a pinch on either routes to the same drag.
            if let handle = PropCache.instance(named: "SlabHandle") {
                let holder = Entity()
                holder.name = "dielectric-slab"
                holder.addChild(handle)
                Grabbable.configureTouchTarget(
                    holder, box: [0.11, 0.05, 0.09],
                    offset: [0, 0, -0.05])
                viewRoot.addChild(holder)
                slabHandle = holder
            }
        }
        guard let capacitor else {
            dielectricSlab?.isEnabled = false
            slabHandle?.isEnabled = false
            capacitorCallout?.isEnabled = false
            for dot in chargeDots { dot.isEnabled = false }
            return
        }

        if let slab = dielectricSlab {
            slab.isEnabled = true
            slab.position = SIMD3<Float>(slabCenter)
            slab.scale = SIMD3(Float(capacitor.separation) * 0.94,
                               Float(capacitor.plateSize) * 0.96,
                               Float(capacitor.plateSize) * 0.99)
        }
        if let handle = slabHandle {
            handle.isEnabled = true
            handle.position = SIMD3<Float>(slabCenter)
                + SIMD3(0, 0, -Float(capacitor.plateSize) * 0.99 / 2)
        }

        if capacitorCallout == nil {
            let callout = Callout(color: UIColor(white: 0.95, alpha: 1),
                                  textSize: 0.020, offset: SIMD3(0, 0.09, 0))
            callout.setAccessibilityName("Capacitor readout")
            viewRoot.addChild(callout.root)
            capacitorCallout = callout
        }
        capacitorCallout?.isEnabled = true
        capacitorCallout?.anchor(at: SIMD3<Float>(
            capacitor.center + SIMD3(-capacitor.separation / 2,
                                     capacitor.plateSize / 2 + 0.06, 0)))
        if changed {
            syncChargeDots(capacitor)
            capacitorTextPending = true
        }
        // Offered until the callout takes it: a change the rate limit held
        // back used to leave the last value up until the plates moved again.
        if capacitorTextPending {
            // Real units off the calibrated model: honest C (above ε₀A/d — the
            // plates are open), the charge, the energy, and the same centre field
            // the ΔV rail shows.
            let text = "C " + PhysicsFormat.measurement(capacitor.capacitance * 1e12, "pF", decimals: 1)
                + " · Q " + PhysicsFormat.measurement(capacitor.chargeOnPositivePlate * 1e6, "µC", decimals: 2)
                + "\nU " + PhysicsFormat.measurement(capacitor.storedEnergy * 1e3, "mJ", decimals: 2)
                + " · E " + PhysicsFormat.measurement(capacitor.field(at: capacitor.center).x / 1000,
                                                      "kV/m", decimals: 1)
            if capacitorCallout?.setText(text) == true {
                capacitorTextPending = false
            }
        }
    }

    /// Surface charge, drawn: dots on each plate's inner face, budgeted per
    /// band by σ·A exactly as the tracer seeds are — Gauss's law twice over.
    private func syncChargeDots(_ capacitor: PlateField.Capacitor) {
        let budgetPerPlate = 30
        var wanted: [(position: SIMD3<Float>, positive: Bool)] = []
        for positive in [true, false] {
            let bands = capacitor.rectangles.filter {
                positive ? $0.sigma > 0 : $0.sigma < 0
            }
            let weights = bands.map { abs($0.sigma) * $0.area }
            let total = weights.reduce(0, +)
            guard total > 0 else { continue }
            for (band, weight) in zip(bands, weights) {
                let share = max(Int((Double(budgetPerPlate) * weight / total)
                                    .rounded()), 1)
                let ySpan = band.yRange.upperBound - band.yRange.lowerBound
                let zSpan = band.zRange.upperBound - band.zRange.lowerBound
                let columns = max(Int((Double(share) * zSpan
                                       / max(ySpan, 1e-6)).squareRoot()
                                        .rounded()), 1)
                let rows = max((share + columns - 1) / columns, 1)
                // The inner face: the + plate's is its +x side.
                let face = band.x + (positive ? 0.008 : -0.008)
                for row in 0..<rows {
                    for column in 0..<columns {
                        let y = band.yRange.lowerBound
                            + ySpan * (Double(row) + 0.5) / Double(rows)
                        let z = band.zRange.lowerBound
                            + zSpan * (Double(column) + 0.5) / Double(columns)
                        wanted.append((SIMD3<Float>(SIMD3(face, y, z)),
                                       positive))
                    }
                }
            }
        }

        while chargeDots.count < wanted.count && chargeDots.count < 96 {
            let dot = ModelEntity(
                mesh: Primitives.sphere(radius: 0.007),
                materials: [Materials.energized(
                    DesignTokens.Palette.positiveUI, glow: 0.5)])
            dot.scale = [0.4, 1, 1]   // a bead flattened against the face
            viewRoot.addChild(dot)
            chargeDots.append(dot)
        }
        // Freshly made dots wear the positive material, so their cached
        // sign starts true.
        if chargeDotSigns.count < chargeDots.count {
            chargeDotSigns.append(contentsOf: Array(
                repeating: true, count: chargeDots.count - chargeDotSigns.count))
        }
        for (index, dot) in chargeDots.enumerated() {
            guard index < wanted.count else { dot.isEnabled = false; continue }
            dot.isEnabled = true
            dot.position = wanted[index].position
            // One material write per dot per rebuild, not per frame —
            // and only for the dots whose sign actually flipped.
            if chargeDotSigns[index] != wanted[index].positive {
                chargeDotSigns[index] = wanted[index].positive
                dot.model?.materials = [Materials.energized(
                    wanted[index].positive
                        ? DesignTokens.Palette.positiveUI
                        : DesignTokens.Palette.negativeUI, glow: 0.5)]
            }
        }
    }

    private nonisolated struct GeometryResult: Sendable {
        var sourceCharges: [PointCharge] = []
        var tube = TubeBuffers()
        /// A near-black tube swept fatter than the core, drawn underneath it:
        /// passthrough is a bright medium and a pale filament over a cream wall
        /// disappears.
        var tubeCasing = TubeBuffers()
        /// A fatter, fainter tube along the same lines — the soft glow
        /// halo that makes the field read as light, not wire.
        var tubeGlow = TubeBuffers()
        /// Sample points along the lines where arrowheads ride, with the
        /// true field vector there (direction and strength for the pool's
        /// log-brightness ramp).
        var arrowPoints: [SIMD3<Double>] = []
        var arrowVectors: [SIMD3<Double>] = []
    }

    private nonisolated static func computeGeometry(_ job: GeometryJob) -> GeometryResult {
        var result = GeometryResult()
        result.sourceCharges = job.charges

        if job.wantLines {
            var config = FieldLineTracer.Config()
            config.boundsCenter = job.region.center
            config.boundsRadius = max(simd_reduce_max(job.region.extents), FieldModel.regionExtent) * 0.95
            // 1.2 cm steps: invisible on a 1.6 mm tube, ~40% cheaper than
            // the tracer's default, so drags re-trace at a higher rate.
            config.stepSize = 0.012
            config.maxSteps = 220
            let traced = FieldLineTracer.trace(charges: job.charges,
                                               capacitor: job.capacitor,
                                               config: config)
            // Clip to the room, then drop the crumbs: a two-point stub
            // left over from a clip carries no shape and only adds
            // overdraw.
            let lines = job.room.clip(polylines: traced)
                .filter { $0.count > 2 }
                .map { $0.map(SIMD3<Float>.init) }
            result.tube = TubeMesh.buffers(lines: lines, radius: FieldRenderer.lineRadius)
            result.tubeCasing = TubeMesh.buffers(
                lines: lines,
                radius: Materials.casingRadius(forCore: FieldRenderer.lineRadius))
            result.tubeGlow = TubeMesh.buffers(
                lines: lines,
                radius: Materials.glowRadius(forCore: FieldRenderer.lineRadius))

            // Arrowheads at regular arc length along every line — the line
            // carries the path, the arrows carry the direction.
            for line in lines {
                var nextAt = FieldRenderer.arrowSpacing * 0.6
                var walked: Float = 0
                for (a, b) in zip(line, line.dropFirst()) {
                    let step = simd_distance(a, b)
                    while walked + step >= nextAt {
                        let t = (nextAt - walked) / max(step, 1e-6)
                        let point = SIMD3<Double>(a + (b - a) * t)
                        let nearCharge = job.charges.contains {
                            simd_distance($0.position, point) < FieldRenderer.arrowExclusionRadius
                        }
                        if !nearCharge {
                            result.arrowPoints.append(point)
                            result.arrowVectors.append(
                                ElectricField.vector(at: point, dueTo: job.charges))
                        }
                        nextAt += FieldRenderer.arrowSpacing
                    }
                    walked += step
                }
            }
        }

        return result
    }

    private func applyGeometry(_ result: GeometryResult) {
        if let casingMesh = TubeMesh.mesh(from: result.tubeCasing) {
            lineCasingEntity.model = ModelComponent(mesh: casingMesh,
                                                    materials: [lineCasingMaterial])
        } else {
            lineCasingEntity.model = nil
        }
        if let mesh = TubeMesh.mesh(from: result.tube) {
            linesEntity.model = ModelComponent(mesh: mesh, materials: [lineMaterial])
        } else {
            linesEntity.model = nil
        }
        if let glowMesh = TubeMesh.mesh(from: result.tubeGlow) {
            lineGlowEntity.model = ModelComponent(mesh: glowMesh, materials: [lineGlowMaterial])
        } else {
            lineGlowEntity.model = nil
        }
        syncArrowHeads(points: result.arrowPoints, directions: result.arrowVectors)
        // Fresh geometry is anchored to its own charge layout; re-derive
        // the warp so there's no pop when it lands mid-drag.
        appliedCharges = result.sourceCharges
        if let model { syncFieldFlowWarp(model.charges) }
    }

    // MARK: Charges

    private func syncChargeEntities(_ charges: [PointCharge], selectedID: UUID?) {
        var seen = Set<UUID>()
        for charge in charges {
            seen.insert(charge.id)
            let entity = chargeEntities[charge.id] ?? makeChargeEntity(for: charge)
            entity.position = SIMD3<Float>(charge.position)
            if appliedPolarity[charge.id] != charge.isPositive {
                entity.model?.materials = [Self.chargeMaterial(isPositive: charge.isPositive)]
                appliedPolarity[charge.id] = charge.isPositive
                chargeSignVerticals[charge.id]?.isEnabled = charge.isPositive
                setAccessibilityLabel(on: entity, for: charge)
            }
            if let halo = chargeHalos[charge.id] {
                Fade.tick(halo, visible: charge.id == selectedID)
            }
        }
        for (id, entity) in chargeEntities where !seen.contains(id) {
            entity.removeFromParent()
            chargeEntities.removeValue(forKey: id)
            chargeHalos.removeValue(forKey: id)
            chargeSignVerticals.removeValue(forKey: id)
            appliedPolarity.removeValue(forKey: id)
        }
    }

    /// The + or − glyph a charge wears: two white strokes on a billboarded
    /// pivot, the vertical one hidden to make a minus. Shared with the well
    /// mouths, so the sign is legible before you pull one out.
    static func signGlyph(isPositive: Bool, radius: Float,
                          barLength: Float? = nil) -> Entity {
        let (pivot, vertical) = signGlyphParts(radius: radius, barLength: barLength)
        vertical.isEnabled = isPositive
        return pivot
    }

    /// The same glyph with the vertical stroke handed back, for a sign
    /// whose polarity changes live (the probe). `barLength` overrides the
    /// radius-derived stroke for a glyph on a plate.
    static func signGlyphParts(radius: Float, barLength: Float? = nil)
    -> (pivot: Entity, vertical: ModelEntity) {
        let pivot = Entity()
        pivot.components.set(BillboardComponent())
        let stroke = UnlitMaterial(color: UIColor(white: 1.0, alpha: 1))
        let bar = barLength ?? min(radius * 0.9, 0.015)
        let thickness = max(bar * 0.27, 0.0025)
        let horizontal = ModelEntity(
            mesh: Primitives.box(size: [bar, thickness, 0.002], cornerRadius: 0.001),
            materials: [stroke])
        horizontal.position = [0, 0, radius * 1.2]
        pivot.addChild(horizontal)
        let vertical = ModelEntity(
            mesh: Primitives.box(size: [thickness, bar, 0.002], cornerRadius: 0.001),
            materials: [stroke])
        vertical.position = [0, 0, radius * 1.2]
        pivot.addChild(vertical)
        return (pivot, vertical)
    }

    /// A mouth's preview radius, deliberately not `chargeRadius`: a `Well`
    /// hangs its nameplate 0.034 below the preview, so at the 0.095 m pitch
    /// r must stay under 0.0255 or every label lands on the sphere beneath.
    static let wellPreviewRadius: Float = 0.024

    static func chargePreview(isPositive: Bool) -> Entity {
        let sphere = ModelEntity(mesh: Primitives.sphere(radius: wellPreviewRadius),
                                 materials: [chargeMaterial(isPositive: isPositive)])
        sphere.addChild(signGlyph(isPositive: isPositive, radius: wellPreviewRadius))
        return sphere
    }

    /// The test probe as the well shows it — one mouth per polarity, so
    /// the preview has to carry the sign as well as the tint.
    static func probePreview(isPositive: Bool) -> Entity {
        let radius = wellPreviewRadius * 0.8
        let sphere = ModelEntity(
            mesh: Primitives.sphere(radius: radius),
            materials: [Materials.energized(
                isPositive ? DesignTokens.Palette.probePositiveUI
                           : DesignTokens.Palette.probeNegativeUI, glow: 0.4)])
        sphere.addChild(signGlyph(isPositive: isPositive, radius: radius))
        return sphere
    }

    private func makeChargeEntity(for charge: PointCharge) -> ModelEntity {
        let sphere = ModelEntity(
            mesh: Primitives.sphere(radius: Self.chargeRadius),
            materials: [Self.chargeMaterial(isPositive: charge.isPositive)]
        )
        // Name carries the charge's identity so manipulation event handlers
        // can map the grabbed entity back to a model object.
        sphere.name = charge.id.uuidString
        Grabbable.configureTouchTarget(
            sphere, collisionRadius: Self.chargeRadius * 1.8,
            activate: { [weak self, weak sphere] in
                guard let sphere else { return }
                self?.onObjectTap?(sphere)
            })
        setAccessibilityLabel(on: sphere, for: charge)

        // Translucent halo shown on the selected charge.
        let halo = SelectionHalo.make(
            mesh: Primitives.sphere(radius: Self.chargeRadius * 1.35))
        sphere.addChild(halo)

        // The sign glyph: a billboarded + (or −, with the vertical stroke
        // hidden) floating just proud of the sphere, always facing the user.
        let signPivot = Entity()
        signPivot.components.set(BillboardComponent())
        // Chrome strokes with real depth, not flat unlit bars — the glyph
        // catches the key light like stamped metal.
        let strokeMaterial = Materials.energized(
            UIColor(white: 0.97, alpha: 1), roughness: 0.22, glow: 0.2)
        let horizontal = ModelEntity(
            mesh: Primitives.box(size: [0.024, 0.0062, 0.005], cornerRadius: 0.0022),
            materials: [strokeMaterial])
        horizontal.position = [0, 0, Self.chargeRadius * 1.15]
        let vertical = ModelEntity(
            mesh: Primitives.box(size: [0.0062, 0.024, 0.005], cornerRadius: 0.0022),
            materials: [strokeMaterial])
        vertical.position = [0, 0, Self.chargeRadius * 1.15]
        vertical.isEnabled = charge.isPositive
        signPivot.addChild(horizontal)
        signPivot.addChild(vertical)
        sphere.addChild(signPivot)

        viewRoot.addChild(sphere)
        chargeEntities[charge.id] = sphere
        chargeHalos[charge.id] = halo
        chargeSignVerticals[charge.id] = vertical
        appliedPolarity[charge.id] = charge.isPositive
        return sphere
    }

    private static func chargeMaterial(isPositive: Bool) -> PhysicallyBasedMaterial {
        Materials.energized(isPositive ? positiveColor : negativeColor)
    }

    private func setAccessibilityLabel(on entity: ModelEntity, for charge: PointCharge) {
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        let polarity = charge.isPositive ? "Positive" : "Negative"
        let magnitude = PhysicsFormat.fixed(charge.magnitudeMicroCoulombs, decimals: 1)
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(polarity) charge, \(magnitude) microcoulombs. Drag to move."
        )
        entity.components.set(accessibility)
    }

    // MARK: Probe

    private func syncProbeEntity(_ probe: TestChargeDynamics.ProbeState?, isPositive: Bool) {
        guard let probe else {
            probeEntity?.removeFromParent()
            probeEntity = nil
            probeSignVertical = nil
            appliedProbePolarity = nil
            return
        }
        let entity = probeEntity ?? makeProbeEntity()
        if appliedProbePolarity != isPositive {
            entity.model?.materials = [Materials.energized(
                isPositive ? Self.probePositiveColor : Self.probeNegativeColor)]
            appliedProbePolarity = isPositive
            probeSignVertical?.isEnabled = isPositive

            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            let polarity = isPositive ? "Positive" : "Negative"
            accessibility.label = LocalizedStringResource(stringLiteral:
                "\(polarity) test charge. Drag to reposition; it accelerates along the field when released."
            )
            entity.components.set(accessibility)
        }
        entity.position = SIMD3<Float>(probe.position)
    }

    // MARK: The probe's trail

    /// The probe's path as pooled beads fading toward the tail — transform
    /// writes on entities built once, where a swept tube would regenerate a
    /// mesh per point. Under `viewRoot`, so the path scales with the field.
    private lazy var probeTrailPool: EntityPool<ModelEntity> = {
        let mesh = Primitives.sphere(radius: 0.0042)
        let pool = EntityPool<ModelEntity>(budget: FieldModel.probeTrailLength) { container in
            let bead = ModelEntity(mesh: mesh,
                                   materials: [UnlitMaterial(color: Self.probePositiveColor)])
            container.addChild(bead)
            return bead
        }
        viewRoot.addChild(pool.root)
        return pool
    }()
    private var appliedTrailPolarity: Bool?
    /// How many trail beads the taper was last computed for: fade and scale
    /// are functions of index and trail length, so once the trail is full
    /// they are the same numbers every frame.
    private var appliedTrailCount: Int?

    private func syncProbeTrail(_ model: FieldModel) {
        let trail = model.probeTrail
        guard trail.count > 1 else {
            probeTrailPool.hideAll()
            return
        }
        // Recolour only when the polarity actually flips — the sign can
        // be changed mid-flight, and the trail behind the probe should
        // say which particle drew it.
        let positive = model.probeIsPositive
        if appliedTrailPolarity != positive {
            let color = positive ? Self.probePositiveColor : Self.probeNegativeColor
            let material = Materials.unlit(color, opacity: 0.9)
            for slot in probeTrailPool.slots {
                slot.payload.model?.materials = [material]
            }
            appliedTrailPolarity = positive
        }

        let count = min(trail.count, probeTrailPool.budget)
        // The newest points are the ones worth keeping when the path is
        // longer than the pool.
        let visible = trail.suffix(count)
        let taperChanged = appliedTrailCount != count
        appliedTrailCount = count
        for (index, point) in visible.enumerated() {
            let slot = probeTrailPool.slots[index]
            slot.entity.isEnabled = true
            slot.entity.position = SIMD3<Float>(point)
            // Fade and taper toward the tail, so the curve reads with a direction.
            // Index-derived, rewritten only when the trail's length changes.
            guard taperChanged else { continue }
            let age = Float(index) / Float(max(count - 1, 1))
            slot.entity.scale = SIMD3(repeating: 0.35 + 0.65 * age)
            slot.entity.components.set(
                OpacityComponent(opacity: 0.12 + 0.68 * age))
        }
        for index in count..<probeTrailPool.slots.count {
            probeTrailPool.slots[index].entity.isEnabled = false
        }
    }

    private func makeProbeEntity() -> ModelEntity {
        let sphere = ModelEntity(
            mesh: Primitives.sphere(radius: Self.probeRadius),
            materials: [Materials.energized(Self.probePositiveColor)]
        )
        sphere.name = Self.probeEntityName
        Grabbable.configureTouchTarget(
            sphere, collisionRadius: max(Self.probeRadius * 2.4, 0.06),
            activate: { [weak self, weak sphere] in
                guard let sphere else { return }
                self?.onObjectTap?(sphere)
            })

        // Same sign glyph the source charges wear, scaled to probe size —
        // the shared parts builder, so the vertical stroke can be hidden
        // live when the probe's polarity flips.
        let (signPivot, vertical) = Self.signGlyphParts(radius: Self.probeRadius)
        sphere.addChild(signPivot)
        probeSignVertical = vertical

        viewRoot.addChild(sphere)
        probeEntity = sphere
        return sphere
    }

}
