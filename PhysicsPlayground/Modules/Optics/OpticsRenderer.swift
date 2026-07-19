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
        /// Two dots at ±f on the axis — the focal points, marked where
        /// the thin-lens story actually happens. Lenses only.
        var focalMarkers: [ModelEntity] = []
    }
    private var visuals: [UUID: ElementVisual] = [:]

    private let rayEntity = ModelEntity()
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

        // The laser source: a dark box with a glowing emitter face.
        let source = ModelEntity(
            mesh: .generateBox(size: [0.1, 0.3, 0.08], cornerRadius: 0.01),
            materials: [SimpleMaterial(color: UIColor(white: 0.15, alpha: 1),
                                       roughness: 0.5, isMetallic: true)])
        source.position = SIMD3<Float>(OpticsModel.center)
            + SIMD3(Float(OpticsModel.sourceX) - 0.05, 0, 0)
        let face = ModelEntity(
            mesh: .generateBox(size: [0.006, 0.28, 0.06]),
            materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.3, blue: 0.25, alpha: 1))])
        face.position = [0.053, 0, 0]
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
        var material = UnlitMaterial(color: UIColor(
            red: 1.0, green: 0.55, blue: 0.4, alpha: 1))
        material.blending = .transparent(opacity: .init(floatLiteral: Float(focusGlow)))
        screenSpotEntity.model?.materials = [material]
    }

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
            for (side, marker) in zip([-1.0, 1.0], visual.focalMarkers) {
                marker.position = SIMD3<Float>(OpticsModel.center)
                    + SIMD3(Float(element.x + side * element.focal), 0, 0)
            }
            visuals[element.id] = visual
        }
    }

    private func makeVisual(for element: OpticsModel.Element) -> ElementVisual {
        let holder: ModelEntity
        switch element.kind {
        case .convergingLens, .divergingLens:
            var glass = PhysicallyBasedMaterial()
            glass.baseColor = .init(tint: UIColor(red: 0.85, green: 0.93, blue: 1, alpha: 1))
            glass.roughness = 0.05
            glass.blending = .transparent(opacity: .init(floatLiteral: 0.32))
            holder = ModelEntity(
                mesh: .generateCylinder(height: 0.02, radius: 0.17),
                materials: [glass])
            holder.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            // A slim rim so the glass reads at a glance.
            let rimColor: UIColor = element.kind == .convergingLens
                ? UIColor(red: 0.3, green: 0.75, blue: 1, alpha: 1)
                : UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1)
            let rim = ModelEntity(
                mesh: .generateCylinder(height: 0.021, radius: 0.012),
                materials: [UnlitMaterial(color: rimColor)])
            rim.position = [0, 0, 0.172]
            holder.addChild(rim)
        case .mirror:
            holder = ModelEntity(
                mesh: .generateBox(size: [0.015, 0.34, 0.22], cornerRadius: 0.004),
                materials: [SimpleMaterial(color: UIColor(white: 0.9, alpha: 1),
                                           roughness: 0.05, isMetallic: true)])
        case .screen:
            var screen = PhysicallyBasedMaterial()
            screen.baseColor = .init(tint: .white)
            screen.roughness = 0.9
            screen.blending = .transparent(opacity: .init(floatLiteral: 0.85))
            holder = ModelEntity(
                mesh: .generateBox(size: [0.008, 0.36, 0.26], cornerRadius: 0.004),
                materials: [screen])
        }
        var focalMarkers: [ModelEntity] = []
        if element.kind == .convergingLens || element.kind == .divergingLens {
            let markerColor: UIColor = element.kind == .convergingLens
                ? UIColor(red: 0.3, green: 0.75, blue: 1, alpha: 1)
                : UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1)
            for _ in 0..<2 {
                let marker = ModelEntity(
                    mesh: .generateSphere(radius: 0.0075),
                    materials: [UnlitMaterial(color: markerColor)])
                root.addChild(marker)
                focalMarkers.append(marker)
            }
        }
        holder.name = element.id.uuidString
        Grabbable.configure(holder, collisionRadius: 0.2)
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
            var material = UnlitMaterial(color: UIColor(red: 1, green: 0.32, blue: 0.26, alpha: 1))
            material.blending = .transparent(opacity: 0.85)
            rayEntity.model = ModelComponent(mesh: mesh, materials: [material])
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
