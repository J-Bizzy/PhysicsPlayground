//
//  OpticsRenderer.swift
//  Physics Playground — Ray Optics module
//
//  Renders the optics area of the studio: the bench (rail, laser,
//  glass lenses, mirror, screen, glowing ray tubes rebuilt on config
//  change, image marker) plus the DISPERSION STATION below it — white
//  light meeting a real prism, fanning into a spectrum traced by
//  Snell + Cauchy in PhysicsCore, with the entry angles annotated in
//  the room and a callout when a face goes total-internal-reflection.
//  Per-frame tick; all rebuilds dirty-flagged.
//

import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class OpticsRenderer {
    let root = Entity()
    var subscriptions: [EventSubscription] = []

    var manipulatingID: UUID?
    let infoAnchor = Entity()

    private struct ElementVisual {
        let holder: ModelEntity
        /// Four labeled markers at ±f and ±2f on the axis — the bench
        /// notation the thin-lens story is told in (object at 2F images
        /// at 2F, inside F goes virtual). Lenses only.
        var focalMarkers: [ModelEntity] = []
    }
    private var visuals: [UUID: ElementVisual] = [:]
    /// Multipliers for the marker slots, matching focalMarkers order.
    private static let focalMultipliers: [Double] = [-1, 1, -2, 2]

    private lazy var fLabelMesh = MeshResource.generateText(
        "F", extrusionDepth: 0.002, font: .systemFont(ofSize: 0.02, weight: .semibold))
    private lazy var twoFLabelMesh = MeshResource.generateText(
        "2F", extrusionDepth: 0.002, font: .systemFont(ofSize: 0.02, weight: .semibold))

    private let rayEntity = ModelEntity()
    private let rayMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: UIColor(red: 1, green: 0.32, blue: 0.26, alpha: 1))
        material.blending = .transparent(opacity: 0.85)
        return material
    }()
    private let imageMarker: ModelEntity
    private var lastSnapshot: String?

    private let aluminumMaterial = SimpleMaterial(
        color: UIColor(white: 0.7, alpha: 1), roughness: 0.35, isMetallic: true)

    // MARK: Dispersion station state

    private let stationRoot = Entity()
    private var prismEntity: ModelEntity!
    private var whiteBeam = ModelEntity()
    private var spectrumEntities: [ModelEntity] = []
    private var spectrumMaterials: [UnlitMaterial] = []
    private var normalIndicator: ModelEntity!
    private var anglePivot: Entity!
    private var angleText: ModelEntity!
    private var tirPivot: Entity!
    private var tirText: ModelEntity!
    private var stationMeshCache: [String: MeshResource] = [:]
    private var lastStationKey = ""
    private let whiteBeamMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: 0.8)
        return material
    }()
    private let angleLabelMaterial = UnlitMaterial(color: UIColor(white: 1, alpha: 0.9))
    private let tirLabelMaterial = UnlitMaterial(color: UIColor(
        red: 1, green: 0.45, blue: 0.35, alpha: 1))

    // MARK: Refraction corner state

    static let blockName = "glass-block"
    static let laserName = "laser-pointer"
    private let cornerRoot = Entity()
    private var blockEntity: ModelEntity!
    private var laserEntity: ModelEntity!
    private let beamEntity = ModelEntity()
    private let beamMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: UIColor(red: 1, green: 0.32, blue: 0.26, alpha: 1))
        material.blending = .transparent(opacity: 0.9)
        return material
    }()
    private var blockNormalIndicator: ModelEntity!
    private var blockAnglePivot: Entity!
    private var blockAngleText: ModelEntity!
    private var blockTIRPivot: Entity!
    private var blockTIRText: ModelEntity!
    private var lastCornerKey = ""

    init() {
        // Rail.
        let rail = ModelEntity(
            mesh: .generateCylinder(
                height: Float(OpticsModel.railHalf - OpticsModel.sourceX) + 0.1,
                radius: 0.006),
            materials: [aluminumMaterial])
        rail.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        rail.position = SIMD3<Float>(OpticsModel.center)
            + SIMD3(Float(OpticsModel.sourceX + OpticsModel.railHalf) / 2, -0.22, 0)
        root.addChild(rail)

        // The laser source: the Blender-authored housing (ribbed slab
        // with a recessed emitter slot) when available, else the plain
        // box. The glowing strip is the app's — it sits in the recess.
        let source = ModelEntity()
        var faceX: Float = 0.053
        if let housing = try? Entity.load(named: "OpticsLaser") {
            source.addChild(housing)
            faceX = 0.045
        } else {
            source.model = ModelComponent(
                mesh: .generateBox(size: [0.1, 0.3, 0.08], cornerRadius: 0.01),
                materials: [SimpleMaterial(color: UIColor(white: 0.15, alpha: 1),
                                           roughness: 0.5, isMetallic: true)])
        }
        source.position = SIMD3<Float>(OpticsModel.center)
            + SIMD3(Float(OpticsModel.sourceX) - 0.05, 0, 0)
        let face = ModelEntity(
            mesh: .generateBox(size: [0.006, 0.28, 0.06]),
            materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.3, blue: 0.25, alpha: 1))])
        face.position = [faceX, 0, 0]
        source.addChild(face)
        root.addChild(source)

        root.addChild(rayEntity)

        imageMarker = ModelEntity(
            mesh: .generateSphere(radius: 0.014),
            materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1))])
        imageMarker.isEnabled = false
        root.addChild(imageMarker)

        infoAnchor.components.set(BillboardComponent())
        root.addChild(infoAnchor)

        buildDispersionStation()
        buildRefractionCorner()
    }

    // MARK: Dispersion station (left wall)

    private static func wavelengthColor(_ nanometers: Double) -> UIColor {
        switch nanometers {
        case ..<430: UIColor(red: 0.55, green: 0.25, blue: 1, alpha: 1)
        case ..<465: UIColor(red: 0.25, green: 0.4, blue: 1, alpha: 1)
        case ..<500: UIColor(red: 0.1, green: 0.65, blue: 1, alpha: 1)
        case ..<540: UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1)
        case ..<585: UIColor(red: 0.75, green: 0.9, blue: 0.2, alpha: 1)
        case ..<635: UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1)
        default: UIColor(red: 1, green: 0.25, blue: 0.2, alpha: 1)
        }
    }

    /// Station-local orientation: local +x (the beam) runs along
    /// world −z — the trace plane lives on the left wall, facing the
    /// room center.
    private static let stationYaw = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])

    private func buildDispersionStation() {
        // White-light source: dark housing, glowing face down the wall.
        let housing = ModelEntity(
            mesh: .generateBox(size: [0.07, 0.07, 0.06], cornerRadius: 0.008),
            materials: [SimpleMaterial(color: UIColor(white: 0.12, alpha: 1),
                                       roughness: 0.5, isMetallic: true)])
        housing.position = SIMD3<Float>(OpticsModel.dispersionWorld(
            SIMD2(OpticsModel.prismSourceLocalX - 0.03, 0)))
        housing.orientation = Self.stationYaw
        let glow = ModelEntity(
            mesh: .generateBox(size: [0.004, 0.03, 0.03]),
            materials: [UnlitMaterial(color: .white)])
        glow.position = [0.037, 0, 0]
        housing.addChild(glow)
        stationRoot.addChild(housing)

        // The prism: cross-section in the station plane, extruded,
        // built once and rotated as an entity.
        let base = Prism.Geometry(
            apex: .zero, apexAngle: .pi / 3, rotation: 0, sideLength: 0.26)
        let v = base.vertices.map { SIMD3<Float>(Float($0.x), Float($0.y), 0) }
        let halfDepth: Float = 0.05
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
            var normal = simd_cross(b - a, c - a)
            let length = simd_length(normal)
            normal = length > 1e-9 ? normal / length : SIMD3(0, 0, 1)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [normal, normal, normal])
        }
        let front = v.map { $0 + SIMD3(0, 0, halfDepth) }
        let back = v.map { $0 - SIMD3(0, 0, halfDepth) }
        triangle(front[0], front[1], front[2])
        triangle(back[0], back[2], back[1])
        for (a, b) in [(0, 1), (1, 2), (2, 0)] {
            triangle(front[a], back[a], back[b])
            triangle(front[a], back[b], front[b])
        }
        var descriptor = MeshDescriptor(name: "prism")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(Array(0..<UInt32(positions.count)))
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: UIColor(red: 0.88, green: 0.94, blue: 1, alpha: 1))
        glass.roughness = 0.04
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.34))
        prismEntity = ModelEntity(
            mesh: (try? MeshResource.generate(from: [descriptor]))
                ?? .generateBox(size: 0.2),
            materials: [glass])
        prismEntity.position = SIMD3<Float>(OpticsModel.dispersionWorld(SIMD2(0, 0.15)))
        stationRoot.addChild(prismEntity)

        stationRoot.addChild(whiteBeam)
        spectrumMaterials = OpticsModel.prismWavelengths.map { nanometers in
            var material = UnlitMaterial(color: Self.wavelengthColor(nanometers))
            material.blending = .transparent(opacity: 0.85)
            return material
        }
        for _ in spectrumMaterials {
            let tube = ModelEntity()
            stationRoot.addChild(tube)
            spectrumEntities.append(tube)
        }

        var normalMaterial = UnlitMaterial(color: .white)
        normalMaterial.blending = .transparent(opacity: 0.35)
        normalIndicator = ModelEntity(
            mesh: .generateCylinder(height: 0.15, radius: 0.0012),
            materials: [normalMaterial])
        stationRoot.addChild(normalIndicator)
        anglePivot = Entity()
        anglePivot.components.set(BillboardComponent())
        angleText = ModelEntity()
        anglePivot.addChild(angleText)
        stationRoot.addChild(anglePivot)
        tirPivot = Entity()
        tirPivot.components.set(BillboardComponent())
        tirText = ModelEntity()
        tirPivot.addChild(tirText)
        tirPivot.isEnabled = false
        stationRoot.addChild(tirPivot)

        root.addChild(stationRoot)
    }

    private func stationLabelMesh(_ string: String) -> MeshResource {
        if let cached = stationMeshCache[string] { return cached }
        if stationMeshCache.count > 200 { stationMeshCache.removeAll() }
        let mesh = MeshResource.generateText(
            string, extrusionDepth: 0.002,
            font: .systemFont(ofSize: 0.022, weight: .semibold))
        stationMeshCache[string] = mesh
        return mesh
    }

    private func setStationLabel(_ entity: ModelEntity, _ string: String,
                                 material: UnlitMaterial) {
        let mesh = stationLabelMesh(string)
        entity.model = ModelComponent(mesh: mesh, materials: [material])
        let bounds = mesh.bounds
        entity.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
    }

    private func syncDispersionStation(_ model: OpticsModel) {
        let key = String(format: "%.2f", model.prismRotationDegrees)
        guard key != lastStationKey else { return }
        lastStationKey = key

        prismEntity.orientation = Self.stationYaw * simd_quatf(
            angle: Float(model.prismRotationDegrees) * .pi / 180, axis: [0, 0, 1])

        func world(_ local: SIMD2<Double>) -> SIMD3<Float> {
            SIMD3<Float>(OpticsModel.dispersionWorld(local))
        }

        let traces = model.prismTraces
        let middle = traces[traces.count / 2].line
        if middle.count >= 2 {
            let white = [world(middle[0]), world(middle[1])]
            if let mesh = TubeMesh.tube(lines: [white], radius: 0.0035, sides: 6) {
                whiteBeam.model = ModelComponent(mesh: mesh, materials: [whiteBeamMaterial])
            }
        }
        for (index, trace) in traces.enumerated() where index < spectrumEntities.count {
            let points = trace.line.dropFirst().map { world($0) }
            if points.count >= 2,
               let mesh = TubeMesh.tube(lines: [Array(points)], radius: 0.0018, sides: 4) {
                spectrumEntities[index].model = ModelComponent(
                    mesh: mesh, materials: [spectrumMaterials[index]])
            } else {
                spectrumEntities[index].model = nil
            }
        }

        if middle.count >= 2 {
            let entryLocal = middle[1]
            let rotation = model.prismRotationDegrees * .pi / 180
            let half = Double.pi / 6
            let baseNormal = SIMD2(-cos(half), sin(half))
            let localNormal = SIMD2(
                baseNormal.x * cos(rotation) - baseNormal.y * sin(rotation),
                baseNormal.x * sin(rotation) + baseNormal.y * cos(rotation))
            // Station-local (x, y) → world (−z, y).
            let worldNormal = SIMD3<Float>(0, Float(localNormal.y), Float(-localNormal.x))
            normalIndicator.position = world(entryLocal)
            normalIndicator.orientation = VectorFieldArrows.rotationFromYAxis(to: worldNormal)
            let angles = model.prismEntryAngles
            setStationLabel(angleText, String(
                format: "θ₁ %.0f°  →  θ₂ %.0f°",
                angles.incidence * 180 / .pi, angles.refraction * 180 / .pi),
                material: angleLabelMaterial)
            anglePivot.position = world(entryLocal) + worldNormal * 0.17

            let tir = model.prismShowsTIR
            tirPivot.isEnabled = tir
            if tir {
                setStationLabel(tirText, "total internal reflection",
                                material: tirLabelMaterial)
                tirPivot.position = world(SIMD2(0.3, 0.0))
            }
        }
    }

    // MARK: Refraction corner (right side)

    private func buildRefractionCorner() {
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: UIColor(red: 0.85, green: 0.93, blue: 1, alpha: 1))
        glass.roughness = 0.05
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.3))
        let h = OpticsModel.blockHalfExtents
        blockEntity = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(SIMD3(h.x * 2, h.y * 2, h.z * 2)),
                               cornerRadius: 0.004),
            materials: [glass])
        blockEntity.name = Self.blockName
        Grabbable.configureTouchTarget(blockEntity, collisionRadius: 0.3)
        var blockAccessibility = AccessibilityComponent()
        blockAccessibility.isAccessibilityElement = true
        blockAccessibility.label = "Glass block. Carry it anywhere — the laser follows."
        blockEntity.components.set(blockAccessibility)
        cornerRoot.addChild(blockEntity)

        // The hand laser: a pocket pointer with a bright nose.
        let body = ModelEntity(
            mesh: .generateCylinder(height: 0.11, radius: 0.016),
            materials: [SimpleMaterial(color: UIColor(white: 0.15, alpha: 1),
                                       roughness: 0.4, isMetallic: true)])
        let nose = ModelEntity(
            mesh: .generateCylinder(height: 0.012, radius: 0.017),
            materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.32, blue: 0.26, alpha: 1))])
        nose.position = [0, 0.06, 0]
        laserEntity = ModelEntity()
        laserEntity.addChild(body)
        laserEntity.addChild(nose)
        laserEntity.name = Self.laserName
        Grabbable.configureTouchTarget(laserEntity, collisionRadius: 0.07)
        var laserAccessibility = AccessibilityComponent()
        laserAccessibility.isAccessibilityElement = true
        laserAccessibility.label = "Laser pointer. It always aims at the glass block — where you hold it IS the angle of incidence."
        laserEntity.components.set(laserAccessibility)
        cornerRoot.addChild(laserEntity)

        cornerRoot.addChild(beamEntity)

        var normalMaterial = UnlitMaterial(color: .white)
        normalMaterial.blending = .transparent(opacity: 0.35)
        blockNormalIndicator = ModelEntity(
            mesh: .generateCylinder(height: 0.16, radius: 0.0012),
            materials: [normalMaterial])
        cornerRoot.addChild(blockNormalIndicator)
        blockAnglePivot = Entity()
        blockAnglePivot.components.set(BillboardComponent())
        blockAngleText = ModelEntity()
        blockAnglePivot.addChild(blockAngleText)
        cornerRoot.addChild(blockAnglePivot)
        blockTIRPivot = Entity()
        blockTIRPivot.components.set(BillboardComponent())
        blockTIRText = ModelEntity()
        blockTIRPivot.addChild(blockTIRText)
        blockTIRPivot.isEnabled = false
        cornerRoot.addChild(blockTIRPivot)

        root.addChild(cornerRoot)
    }

    private func syncRefractionCorner(_ model: OpticsModel) {
        blockEntity.position = SIMD3<Float>(model.blockCenter)
        laserEntity.position = SIMD3<Float>(model.laserPosition)
        laserEntity.orientation = VectorFieldArrows.rotationFromYAxis(
            to: SIMD3<Float>(model.laserAim))

        let key = String(
            format: "%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.2f",
            model.laserPosition.x, model.laserPosition.y, model.laserPosition.z,
            model.blockCenter.x, model.blockCenter.y, model.blockCenter.z,
            model.blockIndex)
        guard key != lastCornerKey else { return }
        lastCornerKey = key

        let points = model.blockTrace.map { SIMD3<Float>($0) }
        if let mesh = TubeMesh.tube(lines: [points], radius: 0.0028, sides: 5) {
            beamEntity.model = ModelComponent(mesh: mesh, materials: [beamMaterial])
        }

        if let entry = model.blockEntry {
            blockNormalIndicator.isEnabled = true
            blockAnglePivot.isEnabled = true
            blockNormalIndicator.position = SIMD3<Float>(entry.point)
            blockNormalIndicator.orientation = VectorFieldArrows.rotationFromYAxis(
                to: SIMD3<Float>(entry.normal))
            setStationLabel(blockAngleText, String(
                format: "θ₁ %.0f°  →  θ₂ %.0f°",
                entry.incidence * 180 / .pi, entry.refraction * 180 / .pi),
                material: angleLabelMaterial)
            blockAnglePivot.position = SIMD3<Float>(entry.point + entry.normal * 0.16)
        } else {
            blockNormalIndicator.isEnabled = false
            blockAnglePivot.isEnabled = false
        }

        let tir = model.blockShowsTIR
        blockTIRPivot.isEnabled = tir
        if tir {
            setStationLabel(blockTIRText, "total internal reflection — a light pipe",
                            material: tirLabelMaterial)
            blockTIRPivot.position = SIMD3<Float>(model.blockCenter)
                + SIMD3(0, Float(OpticsModel.blockHalfExtents.y) + 0.07, 0)
        }
    }

    /// The pool for the screen's blur disc: bright and tiny in focus,
    /// broad and dim out of it.
    private lazy var screenSpotEntity: ModelEntity = {
        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.004, radius: 0.01),
            materials: [UnlitMaterial(color: .white)])
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        disc.isEnabled = false
        root.addChild(disc)
        return disc
    }()

    private func syncScreenSpot(_ model: OpticsModel) {
        guard let spot = model.screenSpot else {
            screenSpotEntity.isEnabled = false
            return
        }
        screenSpotEntity.isEnabled = true
        // Nudge off the screen face so the disc never z-fights it.
        screenSpotEntity.position = SIMD3<Float>(spot.center) - SIMD3(0.006, 0, 0)
        let scale = Float(spot.radius / 0.01)
        screenSpotEntity.scale = SIMD3(scale, 1, scale)
        let focusGlow = max(0.25, min(0.95, 0.95 - spot.radius * 5))
        // Bucketed materials: the glow sweeps continuously while a lens
        // is dragged, but eight steps read identically.
        let bucket = Int(focusGlow * 8)
        if bucket != appliedSpotBucket {
            appliedSpotBucket = bucket
            if screenSpotMaterials[bucket] == nil {
                var material = UnlitMaterial(color: UIColor(
                    red: 1.0, green: 0.55, blue: 0.4, alpha: 1))
                material.blending = .transparent(
                    opacity: .init(floatLiteral: Float(bucket) / 8))
                screenSpotMaterials[bucket] = material
            }
            screenSpotEntity.model?.materials = [screenSpotMaterials[bucket]!]
        }
    }

    private var screenSpotMaterials: [Int: UnlitMaterial] = [:]
    private var appliedSpotBucket = -1

    func tick(model: OpticsModel) {
        syncElements(model)
        syncRays(model)
        syncDispersionStation(model)
        syncRefractionCorner(model)

        if let selected = model.selected {
            infoAnchor.isEnabled = true
            infoAnchor.position = SIMD3<Float>(OpticsModel.center)
                + SIMD3(Float(selected.x), 0.28, 0)
        } else {
            infoAnchor.isEnabled = false
        }
    }

    private func syncElements(_ model: OpticsModel) {
        let liveIDs = Set(model.elements.map(\.id))
        for id in visuals.keys where !liveIDs.contains(id) {
            visuals[id]?.holder.removeFromParent()
            visuals[id]?.focalMarkers.forEach { $0.removeFromParent() }
            visuals[id] = nil
        }
        for element in model.elements {
            let visual = visuals[element.id] ?? makeVisual(for: element)
            if element.id != manipulatingID {
                visual.holder.position = SIMD3<Float>(OpticsModel.center)
                    + SIMD3(Float(element.x), 0, 0)
            }
            for (multiplier, marker) in zip(Self.focalMultipliers, visual.focalMarkers) {
                let x = element.x + multiplier * element.focal
                // Markers past the bench ends would float in space.
                marker.isEnabled = abs(x) < OpticsModel.railHalf + 0.05
                marker.position = SIMD3<Float>(OpticsModel.center)
                    + SIMD3(Float(x), 0, 0)
            }
            visuals[element.id] = visual
        }
    }

    private func makeVisual(for element: OpticsModel.Element) -> ElementVisual {
        let holder: ModelEntity
        switch element.kind {
        case .convergingLens, .divergingLens:
            let assetName = element.kind == .convergingLens
                ? "OpticsLensConvex" : "OpticsLensConcave"
            holder = ModelEntity()
            if let lens = try? Entity.load(named: assetName) {
                // Blender glass: biconvex bulge or biconcave waist —
                // the SHAPE says converging or diverging.
                holder.addChild(lens)
            } else {
                var glass = PhysicallyBasedMaterial()
                glass.baseColor = .init(tint: UIColor(red: 0.85, green: 0.93, blue: 1, alpha: 1))
                glass.roughness = 0.05
                glass.blending = .transparent(opacity: .init(floatLiteral: 0.32))
                holder.model = ModelComponent(
                    mesh: .generateCylinder(height: 0.02, radius: 0.17),
                    materials: [glass])
                holder.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            }
            // The accent dot ties the glass to its focal markers' color.
            let rimColor: UIColor = element.kind == .convergingLens
                ? UIColor(red: 0.3, green: 0.75, blue: 1, alpha: 1)
                : UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1)
            let rim = ModelEntity(
                mesh: .generateCylinder(height: 0.021, radius: 0.012),
                materials: [UnlitMaterial(color: rimColor)])
            rim.position = [0, 0, 0.172]
            holder.addChild(rim)
        case .mirror:
            holder = ModelEntity()
            if let mirror = try? Entity.load(named: "OpticsMirror") {
                holder.addChild(mirror)
            } else {
                holder.model = ModelComponent(
                    mesh: .generateBox(size: [0.015, 0.34, 0.22], cornerRadius: 0.004),
                    materials: [SimpleMaterial(color: UIColor(white: 0.9, alpha: 1),
                                               roughness: 0.05, isMetallic: true)])
            }
        case .screen:
            holder = ModelEntity()
            if let screen = try? Entity.load(named: "OpticsScreen") {
                holder.addChild(screen)
            } else {
                var canvas = PhysicallyBasedMaterial()
                canvas.baseColor = .init(tint: .white)
                canvas.roughness = 0.9
                canvas.blending = .transparent(opacity: .init(floatLiteral: 0.85))
                holder.model = ModelComponent(
                    mesh: .generateBox(size: [0.008, 0.36, 0.26], cornerRadius: 0.004),
                    materials: [canvas])
            }
        }
        var focalMarkers: [ModelEntity] = []
        if element.kind == .convergingLens || element.kind == .divergingLens {
            let markerColor: UIColor = element.kind == .convergingLens
                ? UIColor(red: 0.3, green: 0.75, blue: 1, alpha: 1)
                : UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1)
            var labelMaterial = UnlitMaterial(color: markerColor)
            labelMaterial.blending = .transparent(opacity: 0.85)
            for slot in 0..<Self.focalMultipliers.count {
                let isTwoF = slot >= 2
                let marker = ModelEntity(
                    mesh: .generateSphere(radius: isTwoF ? 0.0058 : 0.0075),
                    materials: [UnlitMaterial(color: markerColor)])
                // The bench letter riding just above each dot.
                let pivot = Entity()
                pivot.components.set(BillboardComponent())
                pivot.position = [0, 0.02, 0]
                let labelMesh = isTwoF ? twoFLabelMesh : fLabelMesh
                let label = ModelEntity(mesh: labelMesh, materials: [labelMaterial])
                let bounds = labelMesh.bounds
                label.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
                pivot.addChild(label)
                marker.addChild(pivot)
                root.addChild(marker)
                focalMarkers.append(marker)
            }
        }
        holder.name = element.id.uuidString
        Grabbable.configureTouchTarget(holder, collisionRadius: 0.2)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(element.kind.displayName). Slide it along the bench.")
        holder.components.set(accessibility)
        root.addChild(holder)
        return ElementVisual(holder: holder, focalMarkers: focalMarkers)
    }

    private func syncRays(_ model: OpticsModel) {
        // Rebuild only when the optical configuration changes.
        let snapshot = model.sourceMode.rawValue + model.elements.map {
            "\($0.kind.rawValue):\(String(format: "%.4f", $0.x)):\(String(format: "%.4f", $0.focal))"
        }.joined()
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot

        var lines: [[SIMD3<Float>]] = []
        for ray in model.tracedRays3D where ray.count > 1 {
            lines.append(ray.map { SIMD3<Float>($0) })
        }
        syncScreenSpot(model)
        if let mesh = TubeMesh.tube(lines: lines, radius: 0.0018, sides: 3) {
            rayEntity.model = ModelComponent(mesh: mesh, materials: [rayMaterial])
        } else {
            rayEntity.model = nil
        }

        if let prediction = model.imagePrediction,
           prediction.x < OpticsModel.railHalf, prediction.imageDistance > 0 {
            imageMarker.isEnabled = true
            imageMarker.position = SIMD3<Float>(
                OpticsModel.center + SIMD3(prediction.x, 0, 0))
        } else {
            imageMarker.isEnabled = false
        }
    }
}
