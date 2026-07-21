//
//  OpticsRenderer.swift
//  Physics Playground — Ray Optics module
//
//  Renders the optical bench: a rail, a laser source box, glass lens
//  discs / mirror / screen the user drags along the rail, glowing ray
//  tubes rebuilt whenever the configuration changes, and a bright
//  marker where the image forms. Per-frame tick; tube rebuilds are
//  dirty-flagged like the wind tunnel's streamlines.
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
