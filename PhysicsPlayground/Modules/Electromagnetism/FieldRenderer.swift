//
//  FieldRenderer.swift
//  Physics Playground — Electromagnetism module
//
//  Translates electrostatics state into RealityKit entities, built on
//  RenderKit: VectorFieldArrows (pooled arrow grid), GeometryPipeline
//  (background line/shell rebuilds with coalescing), TubeMesh (field
//  lines), Grabbable (manipulation). Ticked per frame from
//  SceneEvents.Update.
//
//  Frame-rate contract (shared by all simulations): the per-frame path is
//  tiny — entity transforms only. The arrow grid recomputes just when
//  charges change, and streamline tracing + isosurface marching never run
//  on the main thread.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class FieldRenderer {
    /// Root of everything we render; added to RealityView content at identity,
    /// so this entity's coordinate space == immersive space coordinates.
    let root = Entity()

    /// Event subscriptions, owned here so they live as long as the scene.
    var subscriptions: [EventSubscription] = []

    /// While the system is driving an entity mid-drag, we must not write its
    /// position from the model, or the two would fight and jitter.
    var manipulatingChargeID: UUID?
    var isManipulatingProbe = false

    /// Entity name for the probe (charges use their UUID string).
    static let probeEntityName = "probe"

    // MARK: Visual constants — always the DesignTokens conventions, so the
    // in-space entities and the shell-rendered legend can never drift apart.
    static let positiveColor = DesignTokens.Palette.positiveUI
    static let negativeColor = DesignTokens.Palette.negativeUI
    static let probePositiveColor = DesignTokens.Palette.probePositiveUI
    static let probeNegativeColor = DesignTokens.Palette.probeNegativeUI
    static let lineColor = DesignTokens.Palette.fieldLineUI
    static let positiveShellColor = DesignTokens.Palette.positiveShellUI
    static let negativeShellColor = DesignTokens.Palette.negativeShellUI
    static let chargeRadius: Float = 0.03
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
    private let lineGlowEntity = ModelEntity()
    private let positiveShellsEntity = ModelEntity()
    private let negativeShellsEntity = ModelEntity()
    private let lineMaterial = UnlitMaterial(color: FieldRenderer.lineColor)
    private let lineGlowMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: FieldRenderer.lineColor)
        material.blending = .transparent(opacity: 0.2)
        return material
    }()
    private let positiveShellMaterial = FieldRenderer.shellMaterial(color: FieldRenderer.positiveShellColor)
    private let negativeShellMaterial = FieldRenderer.shellMaterial(color: FieldRenderer.negativeShellColor)

    // Change detection: the expensive paths only run when these differ.
    private var lastCharges: [PointCharge]?
    private var lastRegion: FieldModel.SamplingRegion?
    private var lastShowLines: Bool?
    private var lastShowShells: Bool?

    private var geometryPipeline: GeometryPipeline<GeometryJob, GeometryResult>?
    private let fieldFlowRoot = Entity()
    /// The charge layout the currently-applied geometry was traced from.
    private var appliedCharges: [PointCharge] = []

    init() {
        let headMesh = MeshResource.generateCone(height: 0.022, radius: 0.0085)
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
        root.addChild(fieldFlowRoot)
        // The glow halo sits under the arrowheads and the bright core so
        // the crisp line and heads read over the soft bloom.
        fieldFlowRoot.addChild(lineGlowEntity)
        fieldFlowRoot.addChild(arrowHeads.root)
        for entity in [linesEntity, positiveShellsEntity, negativeShellsEntity] {
            entity.isEnabled = false
            fieldFlowRoot.addChild(entity)
        }
        lineGlowEntity.isEnabled = false

        geometryPipeline = GeometryPipeline(
            compute: { Self.computeGeometry($0) },
            apply: { [weak self] in self?.applyGeometry($0) }
        )
    }

    private static func shellMaterial(color: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: 0.14)
        material.faceCulling = .none  // shells stay visible from inside them
        return material
    }

    // MARK: Render loop

    /// Per-frame sync, called from SceneEvents.Update — the observation
    /// loop starves during system manipulation, so EM ticks directly
    /// like every continuously-animating module. All expensive paths
    /// inside render() are change-gated, so the per-frame cost is tiny.
    func tick(_ model: FieldModel) {
        self.model = model
        render(
                charges: model.charges,
                region: model.samplingRegion,
                selectedID: model.selectedChargeID,
                probe: model.probe,
                probeIsPositive: model.probeIsPositive,
                showLines: model.showLines,
                showShells: model.showEquipotentials,
                shells: model.equipotentialShells,
                capacitorOn: model.capacitorOn,
                capacitorCenter: model.capacitorCenter,
                plateSeparation: model.plateSeparation,
                magneticFieldOn: model.magneticFieldOn
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
        showShells: Bool,
        shells: Int = 3,
        capacitorOn: Bool = false,
        capacitorCenter: SIMD3<Double> = .zero,
        plateSeparation: Double = 0.44,
        magneticFieldOn: Bool = false
    ) {
        // Cheap path — runs every render.
        syncChargeEntities(charges, selectedID: selectedID)
        syncProbeEntity(probe, isPositive: probeIsPositive)
        syncPlates(on: capacitorOn, center: capacitorCenter, separation: plateSeparation)
        syncBField(on: magneticFieldOn)
        syncFieldFlowWarp(charges)

        let chargesChanged = charges != lastCharges || region != lastRegion

        // Expensive path — lines (with their riding arrowheads) and shells
        // rebuild on the geometry pipeline.
        linesEntity.isEnabled = showLines && !charges.isEmpty
        lineGlowEntity.isEnabled = showLines && !charges.isEmpty
        if !showLines || charges.isEmpty {
            arrowHeads.hideAll()
        }
        positiveShellsEntity.isEnabled = showShells && !charges.isEmpty
        negativeShellsEntity.isEnabled = showShells && !charges.isEmpty
        let visibilityChanged = showLines != lastShowLines || showShells != lastShowShells
        let shellsChanged = shells != lastShells
        if (showLines || showShells) && (chargesChanged || visibilityChanged || shellsChanged)
            && !charges.isEmpty {
            geometryPipeline?.submit(GeometryJob(
                charges: charges,
                region: region,
                wantLines: showLines,
                wantShells: showShells,
                shells: shells
            ))
        }
        lastShells = shells
        lastShowLines = showLines
        lastShowShells = showShells
        lastCharges = charges
        lastRegion = region
    }

    // MARK: Background field geometry (lines + equipotential shells)

    private nonisolated struct GeometryJob: Sendable {
        var charges: [PointCharge]
        var region: FieldModel.SamplingRegion
        var wantLines: Bool
        var wantShells: Bool
        var shells: Int
    }

    private var lastShells = 3

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
    // continuous vertical lines with arrowheads riding them, pointing the
    // way B points (up). Violet, like the magnet pod. The field is
    // uniform, so the geometry is static — built once, then toggled.

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
            let coneMesh = MeshResource.generateCone(height: 0.02, radius: 0.008)
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
            root.addChild(bFieldRoot)
        }
        bFieldRoot.isEnabled = on
    }

    // MARK: Capacitor plates

    private var plateEntities: [ModelEntity] = []
    /// The plate a hand is dragging (system-owned; don't reposition it).
    var manipulatingPlateIndex: Int?

    private func syncPlates(on: Bool, center: SIMD3<Double>, separation: Double) {
        if plateEntities.isEmpty {
            let mesh = MeshResource.generateBox(
                size: [0.012, Float(FieldModel.plateSize), Float(FieldModel.plateSize)],
                cornerRadius: 0.004)
            for isPositive in [true, false] {
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: isPositive
                    ? DesignTokens.Palette.positiveUI : DesignTokens.Palette.negativeUI)
                material.roughness = 0.4
                material.blending = .transparent(opacity: .init(floatLiteral: 0.35))
                let plate = ModelEntity(mesh: mesh, materials: [material])
                plate.name = isPositive ? "plate-0" : "plate-1"
                // The plates wear the same sign glyphs as the charges.
                let signPivot = Entity()
                signPivot.components.set(BillboardComponent())
                signPivot.position = [0, Float(FieldModel.plateSize) * 0.28, 0]
                let strokeMaterial = UnlitMaterial(color: UIColor(white: 1, alpha: 0.9))
                let horizontal = ModelEntity(
                    mesh: .generateBox(size: [0.05, 0.011, 0.004], cornerRadius: 0.002),
                    materials: [strokeMaterial])
                signPivot.addChild(horizontal)
                if isPositive {
                    let vertical = ModelEntity(
                        mesh: .generateBox(size: [0.011, 0.05, 0.004], cornerRadius: 0.002),
                        materials: [strokeMaterial])
                    signPivot.addChild(vertical)
                }
                plate.addChild(signPivot)
                Grabbable.configureTouchTarget(plate, collisionRadius: 0.26)
                var accessibility = AccessibilityComponent()
                accessibility.isAccessibilityElement = true
                accessibility.label = "Capacitor plate. Drag along the field axis to change the gap; carry it to move the capacitor."
                plate.components.set(accessibility)
                plate.isEnabled = false
                plateEntities.append(plate)
                root.addChild(plate)
            }
        }
        let mid = SIMD3<Float>(center)
        let half = Float(separation / 2)
        if manipulatingPlateIndex != 0 {
            plateEntities[0].position = mid + SIMD3(-half, 0, 0)  // + plate
        }
        if manipulatingPlateIndex != 1 {
            plateEntities[1].position = mid + SIMD3(half, 0, 0)   // − plate
        }
        for plate in plateEntities { plate.isEnabled = on }
    }

    private nonisolated struct ShellMeshData: Sendable {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
    }

    private nonisolated struct GeometryResult: Sendable {
        var sourceCharges: [PointCharge] = []
        var tube = TubeBuffers()
        /// A fatter, fainter tube along the same lines — the soft glow
        /// halo that makes the field read as light, not wire.
        var tubeGlow = TubeBuffers()
        /// Sample points along the lines where arrowheads ride, with the
        /// true field vector there (direction AND strength for the pool's
        /// log-brightness ramp).
        var arrowPoints: [SIMD3<Double>] = []
        var arrowVectors: [SIMD3<Double>] = []
        var positiveShells = ShellMeshData()
        var negativeShells = ShellMeshData()
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
            let lines = FieldLineTracer.trace(charges: job.charges, config: config)
                .map { $0.map(SIMD3<Float>.init) }
            result.tube = TubeMesh.buffers(lines: lines)
            result.tubeGlow = TubeMesh.buffers(lines: lines, radius: 0.0044)

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

        if job.wantShells {
            for level in EquipotentialSurface.defaultLevels(for: job.charges, shells: job.shells) {
                let triangles = EquipotentialSurface.triangles(
                    level: level,
                    charges: job.charges,
                    center: job.region.center,
                    extents: job.region.extents,
                    resolution: 24
                )
                guard !triangles.isEmpty else { continue }
                var data = level >= 0 ? result.positiveShells : result.negativeShells
                data.positions.reserveCapacity(data.positions.count + triangles.count)
                for vertex in triangles {
                    data.positions.append(SIMD3<Float>(vertex))
                    data.normals.append(SIMD3<Float>(
                        EquipotentialSurface.outwardNormal(at: vertex, level: level, charges: job.charges)
                    ))
                }
                if level >= 0 { result.positiveShells = data } else { result.negativeShells = data }
            }
        }
        return result
    }

    private func applyGeometry(_ result: GeometryResult) {
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
        applyShellMesh(result.positiveShells, to: positiveShellsEntity, material: positiveShellMaterial)
        applyShellMesh(result.negativeShells, to: negativeShellsEntity, material: negativeShellMaterial)
    }

    private func applyShellMesh(_ data: ShellMeshData, to entity: ModelEntity, material: UnlitMaterial) {
        guard !data.positions.isEmpty else {
            entity.model = nil
            return
        }
        var descriptor = MeshDescriptor(name: "equipotential")
        descriptor.positions = MeshBuffer(data.positions)
        descriptor.normals = MeshBuffer(data.normals)
        descriptor.primitives = .triangles(Array(0..<UInt32(data.positions.count)))
        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            entity.model = ModelComponent(mesh: mesh, materials: [material])
        }
    }

    // MARK: Charges

    private func syncChargeEntities(_ charges: [PointCharge], selectedID: UUID?) {
        var seen = Set<UUID>()
        for charge in charges {
            seen.insert(charge.id)
            let entity = chargeEntities[charge.id] ?? makeChargeEntity(for: charge)
            // Hands off while the manipulation system is dragging this one.
            if charge.id != manipulatingChargeID {
                entity.position = SIMD3<Float>(charge.position)
            }
            if appliedPolarity[charge.id] != charge.isPositive {
                entity.model?.materials = [Self.chargeMaterial(isPositive: charge.isPositive)]
                appliedPolarity[charge.id] = charge.isPositive
                chargeSignVerticals[charge.id]?.isEnabled = charge.isPositive
                setAccessibilityLabel(on: entity, for: charge)
            }
            chargeHalos[charge.id]?.isEnabled = (charge.id == selectedID)
        }
        for (id, entity) in chargeEntities where !seen.contains(id) {
            entity.removeFromParent()
            chargeEntities.removeValue(forKey: id)
            chargeHalos.removeValue(forKey: id)
            chargeSignVerticals.removeValue(forKey: id)
            appliedPolarity.removeValue(forKey: id)
        }
    }

    private func makeChargeEntity(for charge: PointCharge) -> ModelEntity {
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: Self.chargeRadius),
            materials: [Self.chargeMaterial(isPositive: charge.isPositive)]
        )
        // Name carries the charge's identity so manipulation event handlers
        // can map the grabbed entity back to a model object.
        sphere.name = charge.id.uuidString
        Grabbable.configureTouchTarget(sphere, collisionRadius: Self.chargeRadius * 1.8)
        setAccessibilityLabel(on: sphere, for: charge)

        // Translucent halo shown on the selected charge (the one the sliders edit).
        var haloMaterial = UnlitMaterial(color: DesignTokens.Palette.selectionHaloUI)
        haloMaterial.blending = .transparent(opacity: 0.25)
        let halo = ModelEntity(
            mesh: .generateSphere(radius: Self.chargeRadius * 1.35),
            materials: [haloMaterial]
        )
        halo.isEnabled = false
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
            mesh: .generateBox(size: [0.024, 0.0062, 0.005], cornerRadius: 0.0022),
            materials: [strokeMaterial])
        horizontal.position = [0, 0, Self.chargeRadius * 1.15]
        let vertical = ModelEntity(
            mesh: .generateBox(size: [0.0062, 0.024, 0.005], cornerRadius: 0.0022),
            materials: [strokeMaterial])
        vertical.position = [0, 0, Self.chargeRadius * 1.15]
        vertical.isEnabled = charge.isPositive
        signPivot.addChild(horizontal)
        signPivot.addChild(vertical)
        sphere.addChild(signPivot)

        root.addChild(sphere)
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
        let magnitude = String(format: "%.1f", charge.magnitudeMicroCoulombs)
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(polarity) charge, \(magnitude) microcoulombs. Drag to move."
        )
        entity.components.set(accessibility)
    }

    // MARK: Probe

    /// Same-frame probe sync, called from the per-frame simulation tick so
    /// the probe's motion never waits for the observation round-trip.
    func syncProbeNow(_ probe: TestChargeDynamics.ProbeState?, isPositive: Bool) {
        syncProbeEntity(probe, isPositive: isPositive)
    }

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
        if !isManipulatingProbe {
            entity.position = SIMD3<Float>(probe.position)
        }
    }

    private func makeProbeEntity() -> ModelEntity {
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: Self.probeRadius),
            materials: [Materials.energized(Self.probePositiveColor)]
        )
        sphere.name = Self.probeEntityName
        Grabbable.configureTouchTarget(sphere, collisionRadius: max(Self.probeRadius * 2.4, 0.06))

        // Same sign glyph the source charges wear, scaled to probe size.
        let signPivot = Entity()
        signPivot.components.set(BillboardComponent())
        let strokeMaterial = UnlitMaterial(color: UIColor(white: 1.0, alpha: 1))
        let horizontal = ModelEntity(
            mesh: .generateBox(size: [0.015, 0.004, 0.002], cornerRadius: 0.001),
            materials: [strokeMaterial])
        horizontal.position = [0, 0, Self.probeRadius * 1.2]
        let vertical = ModelEntity(
            mesh: .generateBox(size: [0.004, 0.015, 0.002], cornerRadius: 0.001),
            materials: [strokeMaterial])
        vertical.position = [0, 0, Self.probeRadius * 1.2]
        signPivot.addChild(horizontal)
        signPivot.addChild(vertical)
        sphere.addChild(signPivot)
        probeSignVertical = vertical

        root.addChild(sphere)
        probeEntity = sphere
        return sphere
    }

}
