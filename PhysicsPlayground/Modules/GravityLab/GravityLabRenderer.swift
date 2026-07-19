//
//  GravityLabRenderer.swift
//  Physics Playground — Gravity Lab module
//
//  Renders the solar system diorama: a glowing Sun that actually lights
//  nearby bodies (PointLight), pooled planets (grabbable, hover-lit by
//  the system), per-body orbit trails, the held-body orbit prediction,
//  velocity/acceleration/force arrows on the selected body, and a soft
//  flash when bodies merge.
//
//  Frame-rate contract: pools built once; per-frame work is transform
//  writes. Every tube — orbit trails, the held-body prediction (a
//  1200-step n-body integration), and the spacetime grid — is computed
//  on a GeometryPipeline worker; the main thread only uploads finished
//  buffers. Materials are created once and cached. Ticked per frame
//  from SceneEvents.Update (observation loops starve during grabs —
//  house rule since the EM module's device findings).
//

import Foundation
import PhysicsCore
import QuartzCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class GravityLabRenderer {
    let root = Entity()
    var subscriptions: [EventSubscription] = []

    /// Set by the space view's router while the hand owns a body.
    var manipulatingBodyID: UUID?

    /// Where the system center sits in the room.
    static let systemPosition = SIMD3<Float>(0, 1.25, -1.2)

    /// Parent for the selected body's floating data panel (the space view
    /// attaches the SwiftUI attachment here; we move it each render).
    let selectedAnchor = Entity()

    private let systemRoot = Entity()
    /// Mode-dependent (AU scale vs. Earth–Moon scale); refreshed per render.
    private var scale: Float = 1

    private let bodyPool: EntityPool<ModelEntity>
    private var bodyMaterialKeys: [String]
    private var bodyNames: [String]
    private static let baseBodyRadius: Float = 0.05

    private let trailPool: EntityPool<Void>
    private var trailEntities: [ModelEntity] = []
    private var trailBuiltCounts: [Int]
    private var trailMaterialCache: [String: UnlitMaterial] = [:]
    private var activeTrailSlots = 0
    private var trailPipeline: GeometryPipeline<TrailJob, TrailResult>?
    private var predictionPipeline: GeometryPipeline<PredictionJob, TubeBuffers>?
    private var predictionActive = false
    private var gridPipeline: GeometryPipeline<GridJob, TubeBuffers>?
    private let gridMaterial: UnlitMaterial

    private let sunLight = Entity()
    private var sunGlow: ModelEntity!
    private let audioEmitter = Entity()
    private var lastSoundID = 0
    private var appliedTextureVersion = -1
    private let predictionEntity = ModelEntity()
    private let predictionMaterial: UnlitMaterial
    private let flashEntity: ModelEntity
    private var platform: ModelEntity!

    // Field particles (display-space positions, relative to systemRoot).
    private static let particleBudget = 450
    private static let particleLife = 7.0
    private let particlePool: EntityPool<Void>
    private var particlePositions: [SIMD3<Float>] = []
    private var particleAges: [Double] = []
    private var particlesVisible = false

    // Spacetime grid. Constants live in a plain enum so the background
    // grid computation can read them without actor hops.
    private nonisolated enum GridSpec {
        static let floorHeight: Float = -0.42
        static let extent: Float = 1.4
        static let lineCount = 11
        static let samples = 25
    }
    private let gridEntity = ModelEntity()

    private struct Arrow {
        let container: Entity
        let shaft: ModelEntity
        let head: ModelEntity
    }
    private var velocityArrow: Arrow!
    private var accelerationArrow: Arrow!
    private var forceArrow: Arrow!

    private var frameCounter = 0
    private var lastMergeNonce = 0

    init() {
        var grid = UnlitMaterial(color: .white)
        grid.blending = .transparent(opacity: 0.3)
        gridMaterial = grid

        systemRoot.position = Self.systemPosition
        root.addChild(systemRoot)

        // The floating platform under the system — a quiet glass disc.
        // Hidden while the spacetime grid takes over as the floor.
        var platformMaterial = UnlitMaterial(color: .black)
        platformMaterial.blending = .transparent(opacity: 0.35)
        platform = ModelEntity(
            mesh: .generateCylinder(height: 0.006, radius: 0.9),
            materials: [platformMaterial]
        )
        platform.position = [0, GridSpec.floorHeight, 0]
        systemRoot.addChild(platform)

        // The spacetime grid (rubber-sheet picture), rebuilt as bodies move.
        systemRoot.addChild(gridEntity)

        // Field particles: a fixed pool of faint dots that drift along the
        // local gravitational field. Density near masses emerges from the
        // flow itself — strong fields pull the streamlines together.
        var particleMaterial = UnlitMaterial(color: .white)
        particleMaterial.blending = .transparent(opacity: 0.32)
        let particleMesh = MeshResource.generateSphere(radius: 0.0028)
        particlePool = EntityPool(budget: Self.particleBudget) { container in
            container.addChild(ModelEntity(mesh: particleMesh, materials: [particleMaterial]))
        }
        particlePositions = (0..<Self.particleBudget).map { _ in Self.randomParticleHome() }
        particleAges = (0..<Self.particleBudget).map { _ in Double.random(in: 0..<Self.particleLife) }
        systemRoot.addChild(particlePool.root)

        // Bodies.
        let bodyMesh = MeshResource.generateSphere(radius: Self.baseBodyRadius)
        bodyPool = EntityPool(budget: GravityLabModel.bodyBudget) { container in
            let sphere = ModelEntity(
                mesh: bodyMesh,
                materials: [SimpleMaterial(color: .white, roughness: 0.6, isMetallic: false)]
            )
            Grabbable.configureTouchTarget(sphere, collisionRadius: Self.baseBodyRadius * 1.5)
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = "Celestial body. Grab to move it; throw it to set a new orbit."
            sphere.components.set(accessibility)
            container.addChild(sphere)
            return sphere
        }
        bodyMaterialKeys = Array(repeating: "", count: bodyPool.budget)
        bodyNames = Array(repeating: "", count: bodyPool.budget)
        systemRoot.addChild(bodyPool.root)

        // The Sun's light: warm, following the heaviest body — plus a
        // soft corona shell so it reads as incandescent, not painted.
        sunLight.components.set(PointLightComponent(
            color: UIColor(red: 1.0, green: 0.9, blue: 0.75, alpha: 1),
            intensity: 12_000,
            attenuationRadius: 5
        ))
        systemRoot.addChild(sunLight)

        var glowMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 0.82, blue: 0.5, alpha: 1))
        glowMaterial.blending = .transparent(opacity: 0.16)
        sunGlow = ModelEntity(mesh: .generateSphere(radius: 0.105), materials: [glowMaterial])
        systemRoot.addChild(sunGlow)

        audioEmitter.components.set(SpatialAudioComponent())
        systemRoot.addChild(audioEmitter)
        CelestialTextures.warmUp()

        // Trails: one tube entity per body slot.
        trailPool = EntityPool(budget: GravityLabModel.bodyBudget) { _ in }
        for slot in trailPool.slots {
            let tube = ModelEntity()
            slot.entity.addChild(tube)
            slot.entity.isEnabled = true
            trailEntities.append(tube)
        }
        trailBuiltCounts = Array(repeating: -1, count: trailPool.budget)
        systemRoot.addChild(trailPool.root)

        // Held-body orbit prediction.
        var predictionMaterial = UnlitMaterial(color: DesignTokens.Palette.predictedArcUI)
        predictionMaterial.blending = .transparent(opacity: 0.55)
        self.predictionMaterial = predictionMaterial
        systemRoot.addChild(predictionEntity)

        // Merge flash.
        var flashMaterial = UnlitMaterial(color: .white)
        flashMaterial.blending = .transparent(opacity: 0.7)
        flashEntity = ModelEntity(mesh: .generateSphere(radius: 0.03), materials: [flashMaterial])
        flashEntity.isEnabled = false
        systemRoot.addChild(flashEntity)

        // Vector arrows on the selected body.
        velocityArrow = Self.makeArrow(color: DesignTokens.Palette.velocityVectorUI)
        accelerationArrow = Self.makeArrow(color: DesignTokens.Palette.accelerationVectorUI)
        forceArrow = Self.makeArrow(color: DesignTokens.Palette.forceVectorUI)
        for arrow in [velocityArrow!, accelerationArrow!, forceArrow!] {
            systemRoot.addChild(arrow.container)
        }

        selectedAnchor.components.set(BillboardComponent())
        systemRoot.addChild(selectedAnchor)

        // Lagrange point markers: five small diamonds with labels,
        // co-rotating with the Moon (positions written every render).
        let markerMesh = MeshResource.generateSphere(radius: 0.009)
        var markerMaterial = UnlitMaterial(color: DesignTokens.Palette.targetUI)
        markerMaterial.blending = .transparent(opacity: 0.85)
        for name in ["L1", "L2", "L3", "L4", "L5"] {
            let marker = ModelEntity(mesh: markerMesh, materials: [markerMaterial])
            let labelMesh = MeshResource.generateText(
                name, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.02, weight: .semibold))
            let label = ModelEntity(
                mesh: labelMesh,
                materials: [UnlitMaterial(color: DesignTokens.Palette.targetUI)])
            let bounds = labelMesh.bounds
            label.position = [-(bounds.min.x + bounds.max.x) / 2, 0.016, 0]
            let labelPivot = Entity()
            labelPivot.components.set(BillboardComponent())
            labelPivot.addChild(label)
            marker.addChild(labelPivot)
            marker.isEnabled = false
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = "Lagrange point \(name)"
            marker.components.set(accessibility)
            lagrangeMarkers.append(marker)
            systemRoot.addChild(marker)
        }

        trailPipeline = GeometryPipeline(
            compute: { Self.computeTrails($0) },
            apply: { [weak self] in self?.applyTrails($0) }
        )
        predictionPipeline = GeometryPipeline(
            compute: { Self.computePrediction($0) },
            apply: { [weak self] in self?.applyPrediction($0) }
        )
        gridPipeline = GeometryPipeline(
            compute: { Self.computeGrid($0) },
            apply: { [weak self] in self?.applyGrid($0) }
        )
    }

    private var lagrangeMarkers: [ModelEntity] = []


    private static func makeArrow(color: UIColor) -> Arrow {
        let material = UnlitMaterial(color: color)
        let shaft = ModelEntity(
            mesh: .generateCylinder(height: 0.1, radius: 0.0035), materials: [material])
        let head = ModelEntity(
            mesh: .generateCone(height: 0.028, radius: 0.010), materials: [material])
        let container = Entity()
        container.addChild(shaft)
        container.addChild(head)
        container.isEnabled = false
        return Arrow(container: container, shaft: shaft, head: head)
    }

    // MARK: Per-frame tick (from SceneEvents.Update)

    /// Room coordinates → display coordinates relative to the system center.
    func displayPoint(fromWorld world: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3<Double>(world - Self.systemPosition)
    }

    func tick(_ model: GravityLabModel) {
        frameCounter &+= 1
        scale = Float(model.simToDisplay)

        // Fresh procedural textures arrived: reapply body materials.
        if appliedTextureVersion != CelestialTextures.version {
            appliedTextureVersion = CelestialTextures.version
            bodyMaterialKeys = Array(repeating: "", count: bodyPool.budget)
        }

        // Spatial sounds requested by the model.
        if let event = model.soundEvent, event.id != lastSoundID {
            lastSoundID = event.id
            audioEmitter.position = SIMD3<Float>(event.position) * scale
            SoundPalette.play(event.kind, on: audioEmitter, volume: event.volume)
        }

        syncBodies(model)
        syncTrails(model)
        syncPrediction(model)
        syncVectors(model)
        syncMergeFlash(model)
        syncLagrangeMarkers(model)
        syncSpacetimeGrid(model)
    }

    // MARK: Field particles (ticked every frame by the space view, so the
    // flow keeps moving even while the simulation itself is paused)

    func tickFieldParticles(dt: Double, model: GravityLabModel) {
        // Pause freezes EVERYTHING in time — spins and field flow included.
        guard !model.isPaused else { return }

        // Every body turns slowly on its axis — pure presentation, but it
        // makes the textures live.
        for (index, slot) in bodyPool.slots.enumerated()
        where index < model.bodies.count {
            let rate: Float = model.bodies[index].body.name.hasPrefix("Sun") ? 0.06 : 0.22
            slot.payload.orientation = simd_quatf(angle: rate * Float(dt), axis: [0, 1, 0])
                * slot.payload.orientation
        }

        guard model.showFieldParticles else {
            if particlesVisible {
                particlePool.hideAll()
                particlesVisible = false
            }
            return
        }
        particlesVisible = true

        let bodies = model.bodies
        guard !bodies.isEmpty else { return }
        let G = model.effectiveG
        let toSim = model.displayToSim
        // Field strength at the scene's natural distance from the primary —
        // the yardstick that maps acceleration to a visible drift speed.
        let primaryMass = model.primaryBody?.body.mass ?? 1
        let referenceAcceleration = G * primaryMass
            / (model.characteristicLength * model.characteristicLength)

        for index in 0..<Self.particleBudget {
            var position = particlePositions[index]
            particleAges[index] += dt

            // True local field: a = Σ G·m·r̂/r², same math the planets feel.
            let simPoint = SIMD3<Double>(position) * toSim
            var acceleration = SIMD3<Double>.zero
            var nearBody = false
            for orbiting in bodies {
                let offset = orbiting.body.position - simPoint
                let distanceSquared = simd_length_squared(offset)
                acceleration += (G * orbiting.body.mass
                    / (distanceSquared * distanceSquared.squareRoot())) * offset
                let displayDistance = distanceSquared.squareRoot() / toSim
                if displayDistance < orbiting.displayRadius * 1.7 { nearBody = true }
            }
            let magnitude = simd_length(acceleration)

            if magnitude > 0 {
                // Drift along the field; speed grows sub-linearly with
                // strength so the far field still visibly creeps.
                let speed = 0.05 + 0.22 * min(1, pow(magnitude / referenceAcceleration, 0.35))
                position += SIMD3<Float>(acceleration / magnitude) * Float(speed * dt)
            }

            // Absorbed, expired, or wandered off: respawn somewhere fresh.
            if nearBody || particleAges[index] > Self.particleLife
                || simd_length(position) > 1.6 {
                position = Self.randomParticleHome()
                particleAges[index] = 0
            }
            particlePositions[index] = position

            // Fade in at birth and out near death by scaling.
            let age = particleAges[index]
            let fade = max(0.02, min(age / 0.6, (Self.particleLife - age) / 0.8, 1))
            let slot = particlePool.slots[index]
            slot.entity.isEnabled = true
            slot.entity.position = position
            slot.entity.scale = SIMD3(repeating: Float(fade))
        }
    }

    private static func randomParticleHome() -> SIMD3<Float> {
        // A point in a spherical shell around the system, biased outward
        // so particles enter from the quiet far field.
        var direction = SIMD3<Float>(
            Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1))
        let length = simd_length(direction)
        direction = length > 1e-5 ? direction / length : SIMD3(0, 1, 0)
        return direction * Float.random(in: 0.45...1.5)
    }

    // MARK: Spacetime grid (the rubber-sheet picture — conceptual only)

    private nonisolated struct GridWell: Sendable {
        var center: SIMD2<Float>
        var weight: Float
    }

    private nonisolated struct GridJob: Sendable {
        var wells: [GridWell]
    }

    private nonisolated static func computeGrid(_ job: GridJob) -> TubeBuffers {
        func height(_ x: Float, _ z: Float) -> Float {
            var dip: Float = 0
            for well in job.wells {
                let d = simd_length(SIMD2(x, z) - well.center)
                dip += well.weight / (1 + (d * d) / (0.22 * 0.22))
            }
            return GridSpec.floorHeight - min(dip * 0.14, 0.2)
        }

        let extent = GridSpec.extent
        var lines: [[SIMD3<Float>]] = []
        lines.reserveCapacity(GridSpec.lineCount * 2)
        for lineIndex in 0..<GridSpec.lineCount {
            let offset = -extent + 2 * extent * Float(lineIndex) / Float(GridSpec.lineCount - 1)
            var alongX: [SIMD3<Float>] = []
            var alongZ: [SIMD3<Float>] = []
            for sample in 0..<GridSpec.samples {
                let t = -extent + 2 * extent * Float(sample) / Float(GridSpec.samples - 1)
                alongX.append(SIMD3(t, height(t, offset), offset))
                alongZ.append(SIMD3(offset, height(offset, t), t))
            }
            lines.append(alongX)
            lines.append(alongZ)
        }
        return TubeMesh.buffers(lines: lines, radius: 0.0011, sides: 3)
    }

    private func applyGrid(_ buffers: TubeBuffers) {
        guard gridEntity.isEnabled, let mesh = TubeMesh.mesh(from: buffers) else { return }
        gridEntity.model = ModelComponent(mesh: mesh, materials: [gridMaterial])
    }

    private func syncSpacetimeGrid(_ model: GravityLabModel) {
        let show = model.showSpacetimeGrid
        platform.isEnabled = !show
        gridEntity.isEnabled = show
        // Resubmit at a third of the render rate; bodies barely move per
        // frame, and the sheet itself is sampled on the worker.
        guard show, frameCounter % 3 == 0 else { return }

        // Well weight ∝ m^¼ — deliberately compressed so planets still dent
        // the sheet visibly beside the Sun. Conceptual, and labeled so.
        let maxMass = model.bodies.map(\.body.mass).max() ?? 1
        let wells = model.bodies.map { orbiting in
            let display = SIMD3<Float>(orbiting.body.position) * scale
            return GridWell(center: SIMD2(display.x, display.z),
                            weight: Float(pow(orbiting.body.mass / maxMass, 0.25)))
        }
        gridPipeline?.submit(GridJob(wells: wells))
    }

    private func syncLagrangeMarkers(_ model: GravityLabModel) {
        let points = model.mode == .lagrange ? model.lagrangePoints : []
        for (index, marker) in lagrangeMarkers.enumerated() {
            guard index < points.count else {
                marker.isEnabled = false
                continue
            }
            marker.isEnabled = true
            marker.position = SIMD3<Float>(points[index].position) * scale
        }
    }

    /// Billboarded name tags riding above the bodies — you should never
    /// have to guess which dot is Mars.
    private var bodyLabels: [Entity] = []
    private var bodyLabelTexts: [ModelEntity] = []
    private var labelMeshCache: [String: MeshResource] = [:]

    private func labelMesh(for name: String) -> MeshResource {
        if let cached = labelMeshCache[name] { return cached }
        let mesh = MeshResource.generateText(
            name, extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.022, weight: .semibold))
        labelMeshCache[name] = mesh
        return mesh
    }

    private func ensureLabel(_ index: Int) {
        while bodyLabels.count <= index {
            let holder = Entity()
            let pivot = Entity()
            pivot.components.set(BillboardComponent())
            holder.addChild(pivot)
            let text = ModelEntity()
            var material = UnlitMaterial(color: UIColor(white: 1, alpha: 0.75))
            material.blending = .transparent(opacity: 0.75)
            text.model = ModelComponent(mesh: labelMesh(for: " "), materials: [material])
            pivot.addChild(text)
            holder.isEnabled = false
            systemRoot.addChild(holder)
            bodyLabels.append(holder)
            bodyLabelTexts.append(text)
        }
    }

    private func syncBodies(_ model: GravityLabModel) {
        for (index, slot) in bodyPool.slots.enumerated() {
            guard index < model.bodies.count else {
                slot.entity.isEnabled = false
                continue
            }
            let orbiting = model.bodies[index]
            slot.entity.isEnabled = true
            if slot.payload.name != orbiting.id.uuidString {
                slot.payload.name = orbiting.id.uuidString
            }
            ensureLabel(index)
            if bodyMaterialKeys[index] != orbiting.body.name {
                bodyMaterialKeys[index] = orbiting.body.name
                slot.payload.model?.materials = [material(for: orbiting.body.name)]
                let mesh = labelMesh(for: orbiting.body.name)
                bodyLabelTexts[index].model?.mesh = mesh
                let bounds = mesh.bounds
                bodyLabelTexts[index].position = [
                    -(bounds.min.x + bounds.max.x) / 2, 0, 0]
            }
            bodyLabels[index].isEnabled = true
            bodyLabels[index].position = SIMD3<Float>(orbiting.body.position) * scale
                + SIMD3(0, Float(orbiting.displayRadius) + 0.028, 0)
            slot.entity.scale = SIMD3<Float>(
                repeating: Float(orbiting.displayRadius) / Self.baseBodyRadius)

            if orbiting.id == manipulatingBodyID {
                // Hand owns the sphere: leave transforms alone.
            } else {
                slot.entity.position = SIMD3<Float>(orbiting.body.position) * scale
                slot.payload.position = .zero
            }
        }
        for index in model.bodies.count..<bodyPool.budget {
            bodyPool.slots[index].entity.isEnabled = false
            if index < bodyLabels.count { bodyLabels[index].isEnabled = false }
        }

        if let primary = model.primaryBody {
            sunLight.position = SIMD3<Float>(primary.body.position) * scale
            let isSun = primary.body.name.hasPrefix("Sun")
            sunGlow.isEnabled = isSun
            if isSun {
                sunGlow.position = sunLight.position
                sunGlow.scale = SIMD3(repeating: Float(primary.displayRadius / 0.075))
            }
        }

        // Data-panel anchor floats above the selected body.
        if let selected = model.selectedBody {
            selectedAnchor.isEnabled = true
            selectedAnchor.position = SIMD3<Float>(selected.body.position) * scale
                + SIMD3(0, Float(selected.displayRadius) + 0.12, 0)
        } else {
            selectedAnchor.isEnabled = false
        }
    }

    private func material(for name: String) -> RealityKit.Material {
        let texture = CelestialTextures.texture(for: name)
        if name.hasPrefix("Sun") {
            // Unlit = self-luminous against the room.
            var material = UnlitMaterial(color: DesignTokens.Palette.celestialUI(name))
            if let texture {
                material.color = .init(tint: .white, texture: .init(texture))
            }
            return material
        }
        if let texture {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.roughness = 0.7
            material.metallic = 0.0
            return material
        }
        return SimpleMaterial(
            color: DesignTokens.Palette.celestialUI(name), roughness: 0.55, isMetallic: false)
    }

    // MARK: Trails (vertex math on the pipeline worker)

    private nonisolated struct TrailJob: Sendable {
        var names: [String]
        var lines: [[SIMD3<Float>]]
    }

    private nonisolated struct TrailResult: Sendable {
        var names: [String]
        var buffers: [TubeBuffers]
    }

    private nonisolated static func computeTrails(_ job: TrailJob) -> TrailResult {
        TrailResult(
            names: job.names,
            buffers: job.lines.map { line in
                line.count >= 2
                    ? TubeMesh.buffers(lines: [line], radius: 0.0012)
                    : TubeBuffers()
            }
        )
    }

    private func applyTrails(_ result: TrailResult) {
        for (index, buffers) in result.buffers.enumerated()
        where index < trailEntities.count {
            // A body removed after submission: don't repaint its slot.
            guard index < activeTrailSlots else { continue }
            if let mesh = TubeMesh.mesh(from: buffers) {
                trailEntities[index].model = ModelComponent(
                    mesh: mesh, materials: [trailMaterial(for: result.names[index])])
            } else {
                trailEntities[index].model = nil
            }
        }
    }

    private func trailMaterial(for name: String) -> UnlitMaterial {
        if let cached = trailMaterialCache[name] { return cached }
        var material = UnlitMaterial(color: DesignTokens.Palette.celestialUI(name))
        material.blending = .transparent(opacity: 0.5)
        trailMaterialCache[name] = material
        return material
    }

    private func syncTrails(_ model: GravityLabModel) {
        activeTrailSlots = min(model.bodies.count, trailPool.budget)
        for index in activeTrailSlots..<trailPool.budget
        where trailBuiltCounts[index] != -1 {
            trailEntities[index].model = nil
            trailBuiltCounts[index] = -1
        }

        // One coalescing job covers every body; resubmitted at a quarter
        // of the render rate when any trail actually grew.
        guard frameCounter % 4 == 0 else { return }
        var changed = false
        for index in 0..<activeTrailSlots
        where model.bodies[index].trail.count != trailBuiltCounts[index] {
            changed = true
            break
        }
        guard changed else { return }

        let scale = self.scale
        var names: [String] = []
        var lines: [[SIMD3<Float>]] = []
        for index in 0..<activeTrailSlots {
            let orbiting = model.bodies[index]
            names.append(orbiting.body.name)
            lines.append(orbiting.trail.map { SIMD3<Float>($0) * scale })
            trailBuiltCounts[index] = orbiting.trail.count
        }
        trailPipeline?.submit(TrailJob(names: names, lines: lines))
    }

    // MARK: Held-body prediction (n-body integration on the worker)

    private nonisolated struct PredictionJob: Sendable {
        var inputs: GravityLabModel.PredictionInputs
        var scale: Float
    }

    private nonisolated static func computePrediction(_ job: PredictionJob) -> TubeBuffers {
        let path = NBody.predictedPath(
            bodies: job.inputs.bodies, of: job.inputs.index,
            dt: job.inputs.dt, steps: job.inputs.steps,
            pointStride: job.inputs.pointStride,
            gravitationalConstant: job.inputs.gravitationalConstant
        )
        let points = path.map { SIMD3<Float>($0) * job.scale }
        guard points.count >= 2 else { return TubeBuffers() }
        return TubeMesh.buffers(lines: [points], radius: 0.002)
    }

    private func applyPrediction(_ buffers: TubeBuffers) {
        guard predictionActive else { return }
        if let mesh = TubeMesh.mesh(from: buffers) {
            predictionEntity.model = ModelComponent(mesh: mesh, materials: [predictionMaterial])
        } else {
            predictionEntity.model = nil
        }
    }

    private func syncPrediction(_ model: GravityLabModel) {
        guard let inputs = model.heldPredictionInputs() else {
            if predictionActive {
                predictionActive = false
                predictionEntity.model = nil
            }
            return
        }
        predictionActive = true
        // Submit freely: the pipeline coalesces, so the preview refreshes
        // at whatever rate the worker can integrate — never blocking a
        // frame, always tracking the newest hand state.
        predictionPipeline?.submit(PredictionJob(inputs: inputs, scale: scale))
    }

    // MARK: Vectors (lengths are log-scaled; the legend says so)

    private func syncVectors(_ model: GravityLabModel) {
        guard let selected = model.selectedBody,
              let readout = model.readout(for: selected),
              selected.id != manipulatingBodyID else {
            velocityArrow.container.isEnabled = false
            accelerationArrow.container.isEnabled = false
            forceArrow.container.isEnabled = false
            return
        }
        let origin = SIMD3<Float>(selected.body.position) * scale
        let primary = model.primaryBody

        let velocityDirection = selected.body.velocity - (primary?.body.velocity ?? .zero)
        update(arrow: velocityArrow,
               visible: model.showVelocityVector,
               origin: origin,
               direction: velocityDirection,
               length: 0.04 + 0.05 * log10(1 + readout.speedKmPerS))

        let towardPrimary = (primary?.body.position ?? .zero) - selected.body.position
        update(arrow: accelerationArrow,
               visible: model.showAccelerationVector,
               origin: origin,
               direction: towardPrimary,
               length: 0.03 + 0.04 * log10(1 + readout.accelerationMS2 * 1e3))
        update(arrow: forceArrow,
               visible: model.showForceVector,
               origin: origin,
               direction: towardPrimary,
               length: 0.03 + 0.03 * log10(1 + readout.forceNewtons / 1e20))
    }

    private func update(
        arrow: Arrow, visible: Bool,
        origin: SIMD3<Float>, direction: SIMD3<Double>, length: Double
    ) {
        let magnitude = simd_length(direction)
        guard visible, magnitude > 1e-12, length.isFinite else {
            arrow.container.isEnabled = false
            return
        }
        let l = Float(min(max(length, 0.02), 0.3))
        arrow.container.isEnabled = true
        arrow.container.position = origin
        arrow.container.orientation = VectorFieldArrows.rotationFromYAxis(
            to: SIMD3<Float>(direction / magnitude))
        arrow.shaft.scale = [1, l / 0.1, 1]
        arrow.shaft.position = [0, l / 2, 0]
        arrow.head.position = [0, l + 0.014, 0]
    }

    // MARK: Merge flash

    private func syncMergeFlash(_ model: GravityLabModel) {
        guard model.mergeNonce != lastMergeNonce else { return }
        lastMergeNonce = model.mergeNonce
        flashEntity.position = SIMD3<Float>(model.lastMergePosition) * scale
        flashEntity.scale = SIMD3(repeating: 0.4)
        flashEntity.isEnabled = true
        flashEntity.move(
            to: Transform(scale: SIMD3(repeating: 3.0),
                          translation: flashEntity.position),
            relativeTo: systemRoot,
            duration: 0.3,
            timingFunction: .easeOut
        )
        Task { [weak flashEntity] in
            try? await Task.sleep(for: .milliseconds(320))
            flashEntity?.isEnabled = false
        }
    }
}
