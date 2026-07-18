//
//  FieldRenderer.swift
//  Physics Playground — Electromagnetism module
//
//  Translates electrostatics state into RealityKit entities, built on
//  RenderKit: RenderLoop (observation-driven re-render), VectorFieldArrows
//  (pooled arrow grid), GeometryPipeline (background line/shell rebuilds
//  with coalescing), TubeMesh (field lines), Grabbable (manipulation).
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
    /// Arrows are hidden inside this distance of a charge, where the 1/r²
    /// field diverges and a finite arrow is meaningless.
    static let arrowExclusionRadius = 0.09

    private var model: FieldModel?
    private let renderLoop = RenderLoop()
    private let arrows: VectorFieldArrows
    private var chargeEntities: [UUID: ModelEntity] = [:]
    private var chargeHalos: [UUID: ModelEntity] = [:]
    private var appliedPolarity: [UUID: Bool] = [:]
    private var probeEntity: ModelEntity?
    private var appliedProbePolarity: Bool?
    private let linesEntity = ModelEntity()
    private let positiveShellsEntity = ModelEntity()
    private let negativeShellsEntity = ModelEntity()
    private let lineMaterial = UnlitMaterial(color: FieldRenderer.lineColor)
    private let positiveShellMaterial = FieldRenderer.shellMaterial(color: FieldRenderer.positiveShellColor)
    private let negativeShellMaterial = FieldRenderer.shellMaterial(color: FieldRenderer.negativeShellColor)

    // Change detection: the expensive paths only run when these differ.
    private var lastCharges: [PointCharge]?
    private var lastRegion: FieldModel.SamplingRegion?
    private var lastShowArrows: Bool?
    private var lastShowLines: Bool?
    private var lastShowShells: Bool?

    private var geometryPipeline: GeometryPipeline<GeometryJob, GeometryResult>?

    init() {
        arrows = VectorFieldArrows(
            count: FieldModel.pointsPerAxis * FieldModel.pointsPerAxis * FieldModel.pointsPerAxis
        )
        root.addChild(arrows.root)

        for entity in [linesEntity, positiveShellsEntity, negativeShellsEntity] {
            entity.isEnabled = false
            root.addChild(entity)
        }

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

    /// Starts rendering: draw now, then redraw whenever any observed model
    /// property changes.
    func startObserving(_ model: FieldModel) {
        self.model = model
        renderLoop.start { [weak self, weak model] in
            guard let self, let model else { return }
            self.render(
                charges: model.charges,
                region: model.samplingRegion,
                samplePoints: model.samplePoints,
                selectedID: model.selectedChargeID,
                probe: model.probe,
                probeIsPositive: model.probeIsPositive,
                showArrows: model.showArrows,
                showLines: model.showLines,
                showShells: model.showEquipotentials,
                shells: model.equipotentialShells,
                capacitorOn: model.capacitorOn
            )
        }
    }

    /// Re-syncs all visuals to the given state.
    func render(
        charges: [PointCharge],
        region: FieldModel.SamplingRegion,
        samplePoints: [SIMD3<Double>],
        selectedID: UUID?,
        probe: TestChargeDynamics.ProbeState?,
        probeIsPositive: Bool,
        showArrows: Bool,
        showLines: Bool,
        showShells: Bool,
        shells: Int = 3,
        capacitorOn: Bool = false
    ) {
        // Cheap path — runs every render.
        syncChargeEntities(charges, selectedID: selectedID)
        syncProbeEntity(probe, isPositive: probeIsPositive)
        syncPlates(on: capacitorOn, region: region)

        let chargesChanged = charges != lastCharges || region != lastRegion

        // Medium path — the arrow grid, only when the field actually moved.
        if chargesChanged || showArrows != lastShowArrows {
            updateArrows(charges: charges, points: samplePoints, visible: showArrows)
            lastShowArrows = showArrows
        }

        // Expensive path — lines and shells rebuild on the geometry pipeline.
        linesEntity.isEnabled = showLines && !charges.isEmpty
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

    // MARK: Capacitor plates

    private var plateEntities: [ModelEntity] = []

    private func syncPlates(on: Bool, region: FieldModel.SamplingRegion) {
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
                plate.isEnabled = false
                plateEntities.append(plate)
                root.addChild(plate)
            }
        }
        let center = SIMD3<Float>(region.center)
        let half = Float(FieldModel.plateSeparation / 2)
        plateEntities[0].position = center + SIMD3(-half, 0, 0)  // + plate
        plateEntities[1].position = center + SIMD3(half, 0, 0)   // − plate
        for plate in plateEntities { plate.isEnabled = on }
    }

    private nonisolated struct ShellMeshData: Sendable {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
    }

    private nonisolated struct GeometryResult: Sendable {
        var lines: [[SIMD3<Float>]] = []
        var positiveShells = ShellMeshData()
        var negativeShells = ShellMeshData()
    }

    private nonisolated static func computeGeometry(_ job: GeometryJob) -> GeometryResult {
        var result = GeometryResult()

        if job.wantLines {
            var config = FieldLineTracer.Config()
            config.boundsCenter = job.region.center
            config.boundsRadius = max(simd_reduce_max(job.region.extents), FieldModel.regionExtent) * 0.95
            result.lines = FieldLineTracer.trace(charges: job.charges, config: config)
                .map { $0.map(SIMD3<Float>.init) }
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
        if let mesh = TubeMesh.tube(lines: result.lines) {
            linesEntity.model = ModelComponent(mesh: mesh, materials: [lineMaterial])
        } else {
            linesEntity.model = nil
        }
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
                setAccessibilityLabel(on: entity, for: charge)
            }
            chargeHalos[charge.id]?.isEnabled = (charge.id == selectedID)
        }
        for (id, entity) in chargeEntities where !seen.contains(id) {
            entity.removeFromParent()
            chargeEntities.removeValue(forKey: id)
            chargeHalos.removeValue(forKey: id)
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
        Grabbable.configure(sphere, collisionRadius: Self.chargeRadius * 1.8)
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

        root.addChild(sphere)
        chargeEntities[charge.id] = sphere
        chargeHalos[charge.id] = halo
        appliedPolarity[charge.id] = charge.isPositive
        return sphere
    }

    private static func chargeMaterial(isPositive: Bool) -> SimpleMaterial {
        SimpleMaterial(
            color: isPositive ? positiveColor : negativeColor,
            roughness: 0.35,
            isMetallic: false
        )
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
            appliedProbePolarity = nil
            return
        }
        let entity = probeEntity ?? makeProbeEntity()
        if appliedProbePolarity != isPositive {
            entity.model?.materials = [SimpleMaterial(
                color: isPositive ? Self.probePositiveColor : Self.probeNegativeColor,
                roughness: 0.3,
                isMetallic: false
            )]
            appliedProbePolarity = isPositive

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
            materials: [SimpleMaterial(color: Self.probePositiveColor, roughness: 0.3, isMetallic: false)]
        )
        sphere.name = Self.probeEntityName
        Grabbable.configure(sphere, collisionRadius: Self.probeRadius * 2.4)
        root.addChild(sphere)
        probeEntity = sphere
        return sphere
    }

    // MARK: Arrows

    private func updateArrows(charges: [PointCharge], points: [SIMD3<Double>], visible: Bool) {
        guard visible, !charges.isEmpty else {
            arrows.hideAll()
            return
        }
        let vectors = points.map { ElectricField.vector(at: $0, dueTo: charges) }
        let hidden = points.map { point in
            charges.contains { simd_distance($0.position, point) < Self.arrowExclusionRadius }
        }
        arrows.update(points: points, vectors: vectors, hidden: hidden)
    }
}
