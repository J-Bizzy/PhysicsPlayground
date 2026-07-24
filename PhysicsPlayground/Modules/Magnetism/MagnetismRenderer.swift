//
//  MagnetismRenderer.swift
//  Physics Playground — Magnetism module
//
//  Renders the magnetic sandbox, fully volumetric:
//
//  · bar magnets — a red north half and a blue south half, grabbable,
//    oriented along their live moment;
//  · the looping field lines, traced off-main on a GeometryPipeline and
//    drawn as a glowing tube (a bright core inside a soft halo);
//  · a room-filling 3-D grid of compass needles that swing to point
//    along the local field every frame.
//
//  Frame-rate contract: field lines rebuild only when the magnets move
//  (change-gated, vertex math on a worker); the per-frame path is the
//  magnets' transforms and the compass needle orientations — a few dozen
//  dipole evaluations. Ticked from SceneEvents.Update.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class MagnetismRenderer {
    let root = Entity()
    var subscriptions: [EventSubscription] = []

    static let northColor = DesignTokens.Palette.positiveUI
    static let southColor = DesignTokens.Palette.negativeUI
    static let lineColor = UIColor(red: 0.72, green: 0.6, blue: 1.0, alpha: 1)

    private var magnetEntities: [UUID: Entity] = [:]
    private var magnetHalos: [UUID: Entity] = [:]

    private let linesEntity = ModelEntity()
    private let lineGlowEntity = ModelEntity()
    private let lineMaterial = UnlitMaterial(color: MagnetismRenderer.lineColor)
    private let lineGlowMaterial: UnlitMaterial = {
        var m = UnlitMaterial(color: MagnetismRenderer.lineColor)
        m.blending = .transparent(opacity: 0.2)
        return m
    }()
    private var linesPipeline: GeometryPipeline<LinesJob, LinesResult>?
    private var lastLineInputs: [BarMagnet]?

    // Compass needle grid.
    private let compassRoot = Entity()
    private var needles: [Entity] = []
    private nonisolated static let compassColumns = (x: 5, y: 4, z: 5)

    init() {
        root.addChild(Lighting.keyLight())
        root.addChild(lineGlowEntity)
        root.addChild(linesEntity)
        root.addChild(compassRoot)
        buildCompassGrid()

        linesPipeline = GeometryPipeline(
            compute: { Self.computeLines($0) },
            apply: { [weak self] in self?.applyLines($0) }
        )
    }

    // MARK: Per-frame

    func tick(_ model: MagnetismModel) {
        syncMagnets(model)
        syncFieldLines(model)
        syncCompasses(model)
    }

    // MARK: Magnets

    private func syncMagnets(_ model: MagnetismModel) {
        let live = Set(model.magnets.map(\.id))
        for (id, entity) in magnetEntities where !live.contains(id) {
            entity.removeFromParent()
            magnetEntities[id] = nil
            magnetHalos[id] = nil
        }
        for magnet in model.magnets {
            let entity = magnetEntities[magnet.id] ?? makeMagnet(magnet)
            if magnet.id != model.heldID {
                entity.position = SIMD3<Float>(magnet.position)
            }
            // Orient the bar's +Y along the moment (S→N).
            entity.orientation = simd_quatf(
                from: [0, 1, 0], to: SIMD3<Float>(magnet.axis))
            magnetHalos[magnet.id]?.isEnabled = magnet.id == model.selectedID
        }
    }

    private func makeMagnet(_ magnet: BarMagnet) -> Entity {
        let container = Entity()
        container.name = magnet.id.uuidString
        let half = Float(MagnetismModel.magnetLength) / 2
        let w: Float = 0.05

        let north = ModelEntity(
            mesh: .generateBox(size: [w, half, w], cornerRadius: 0.006),
            materials: [Materials.energized(Self.northColor, roughness: 0.28, glow: 0.16)])
        north.position = [0, half / 2, 0]
        let south = ModelEntity(
            mesh: .generateBox(size: [w, half, w], cornerRadius: 0.006),
            materials: [Materials.energized(Self.southColor, roughness: 0.28, glow: 0.16)])
        south.position = [0, -half / 2, 0]
        container.addChild(north)
        container.addChild(south)

        // Selection halo (a soft box shell), hidden until selected.
        var haloMaterial = UnlitMaterial(color: DesignTokens.Palette.selectionHaloUI)
        haloMaterial.blending = .transparent(opacity: 0.22)
        let halo = ModelEntity(
            mesh: .generateBox(size: [w + 0.03, half * 2 + 0.03, w + 0.03], cornerRadius: 0.012),
            materials: [haloMaterial])
        halo.isEnabled = false
        container.addChild(halo)
        magnetHalos[magnet.id] = halo

        Grabbable.configureTouchTarget(container, collisionRadius: half * 1.6)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Bar magnet. Grab it and carry it — nearby magnets attract, repel, and swing to align."
        container.components.set(accessibility)

        container.position = SIMD3<Float>(magnet.position)
        root.addChild(container)
        magnetEntities[magnet.id] = container
        return container
    }

    // MARK: Field lines (background, change-gated)

    private nonisolated struct LinesJob: Sendable { var magnets: [BarMagnet] }
    private nonisolated struct LinesResult: Sendable {
        var core = TubeBuffers()
        var glow = TubeBuffers()
    }

    private nonisolated static func computeLines(_ job: LinesJob) -> LinesResult {
        var config = MagneticFieldLineTracer.Config()
        config.boundsCenter = MagnetismModel.regionCenter
        config.boundsRadius = MagnetismModel.regionHalfExtent * 1.5
        let lines = MagneticFieldLineTracer.trace(magnets: job.magnets, config: config)
            .map { $0.map(SIMD3<Float>.init) }
        var result = LinesResult()
        result.core = TubeMesh.buffers(lines: lines, radius: 0.0016)
        result.glow = TubeMesh.buffers(lines: lines, radius: 0.0044)
        return result
    }

    private func applyLines(_ result: LinesResult) {
        linesEntity.model = TubeMesh.mesh(from: result.core).map {
            ModelComponent(mesh: $0, materials: [lineMaterial])
        }
        lineGlowEntity.model = TubeMesh.mesh(from: result.glow).map {
            ModelComponent(mesh: $0, materials: [lineGlowMaterial])
        }
    }

    private func syncFieldLines(_ model: MagnetismModel) {
        linesEntity.isEnabled = model.showFieldLines
        lineGlowEntity.isEnabled = model.showFieldLines
        guard model.showFieldLines else { return }
        guard model.magnets != lastLineInputs else { return }
        lastLineInputs = model.magnets
        linesPipeline?.submit(LinesJob(magnets: model.magnets))
    }

    // MARK: Compass needle grid

    private nonisolated static let gridPoints: [SIMD3<Float>] = {
        var points: [SIMD3<Float>] = []
        let (nx, ny, nz) = compassColumns
        let span = Float(MagnetismModel.regionHalfExtent) * 1.7
        let origin = SIMD3<Float>(MagnetismModel.regionCenter) - SIMD3(repeating: span / 2)
        func step(_ n: Int) -> Float { n > 1 ? span / Float(n - 1) : 0 }
        for i in 0..<nx { for j in 0..<ny { for k in 0..<nz {
            points.append(origin + SIMD3(Float(i) * step(nx),
                                         Float(j) * step(ny),
                                         Float(k) * step(nz)))
        } } }
        return points
    }()

    private func buildCompassGrid() {
        let shaftMaterial = UnlitMaterial(color: UIColor(white: 0.75, alpha: 1))
        var headMaterial = UnlitMaterial(color: Self.lineColor)
        headMaterial.blending = .transparent(opacity: 0.95)
        let shaftMesh = MeshResource.generateCylinder(height: 0.05, radius: 0.0032)
        let headMesh = MeshResource.generateCone(height: 0.018, radius: 0.0075)
        for point in Self.gridPoints {
            let needle = Entity()
            let shaft = ModelEntity(mesh: shaftMesh, materials: [shaftMaterial])
            let head = ModelEntity(mesh: headMesh, materials: [headMaterial])
            head.position = [0, 0.034, 0]
            needle.addChild(shaft)
            needle.addChild(head)
            needle.position = point
            needle.isEnabled = false
            compassRoot.addChild(needle)
            needles.append(needle)
        }
    }

    private func syncCompasses(_ model: MagnetismModel) {
        compassRoot.isEnabled = model.showCompasses
        guard model.showCompasses else { return }
        // Hide needles too close to a magnet (inside the singular near field)
        // or where the field is too weak to read.
        let magnets = model.magnets
        for (index, needle) in needles.enumerated() {
            let point = SIMD3<Double>(Self.gridPoints[index])
            let tooClose = magnets.contains {
                simd_distance($0.position, point) < MagnetismModel.magnetLength
            }
            let b = MagneticField.vector(at: point, dueTo: magnets)
            let mag = simd_length(b)
            if tooClose || mag < 2e-6 {
                needle.isEnabled = false
                continue
            }
            needle.isEnabled = true
            needle.orientation = simd_quatf(from: [0, 1, 0], to: SIMD3<Float>(b / mag))
        }
    }
}
