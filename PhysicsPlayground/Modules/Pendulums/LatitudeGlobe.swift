//
//  LatitudeGlobe.swift
//  Physics Playground — Pendulums module
//
//  Where on Earth this bench is standing, as a globe you turn.
//
//  The interaction law says a quantity with physical extent is changed by
//  changing that extent, and a latitude is the one quantity in this app
//  that has extent of an unusual kind: it is a POSITION ON A SPHERE. So
//  it does not get a rail. You take hold of the globe and slide your
//  finger up or down its face, and the marker ring on it goes where your
//  finger is — the reading is the place you are touching.
//
//  A rail would have been the cheap answer and would have been wrong in a
//  way worth naming: latitude is not a number that happens to lie between
//  two bounds, it is somewhere you can stand, and the sine of it is the
//  entire law the module is here to show. A globe makes "the poles are
//  the extremes and the equator is the zero" a fact about the shape in
//  your hand rather than a fact about the ends of a line.
//

import PhysicsCore
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class LatitudeGlobe {
    let root = Entity()

    private let accent: UIColor
    private let band = ModelEntity()
    private let readout = ModelEntity()
    private let readoutMaterial: UnlitMaterial
    private var textCache: [String: MeshResource] = [:]
    private var lastText = ""

    static let radius: Float = 0.085

    init(accent: UIColor) {
        self.accent = accent
        self.readoutMaterial = UnlitMaterial(color: accent)

        // The sphere. Machined rather than energized: this is an
        // instrument, not a piece of physics, and the material canon
        // keeps built things and energy apart.
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: Self.radius),
            materials: [Materials.machined(UIColor(white: 0.30, alpha: 1))])
        sphere.name = "latitude-globe"
        root.addChild(sphere)

        // The equator, so the zero of the sine law is a visible line on
        // the object rather than a number you have to hunt for. A single
        // pale pass is enough here: it is read against the globe's own
        // dark casing, which is what `contrastLine`'s two-pass recipe
        // exists to supply when there is no such backing.
        var equatorMaterial = UnlitMaterial(color: UIColor(white: 0.88, alpha: 1))
        equatorMaterial.blending = .transparent(opacity: 0.75)
        let equator = ModelEntity(
            mesh: .generateBox(size: [Self.radius * 2.02, 0.0022,
                                      Self.radius * 2.02],
                               cornerRadius: Self.radius),
            materials: [equatorMaterial])
        root.addChild(equator)

        // The band you have set: a bright ring at the current latitude.
        var lit = UnlitMaterial(color: accent)
        lit.blending = .transparent(opacity: 0.95)
        band.model = ModelComponent(
            mesh: .generateBox(size: [1, 0.004, 1], cornerRadius: 0.5),
            materials: [lit])
        root.addChild(band)

        let textPivot = Entity()
        textPivot.components.set(BillboardComponent())
        textPivot.position = [0, -Self.radius - 0.045, 0]
        textPivot.addChild(readout)
        root.addChild(textPivot)

        let plate = HubScene.namePlate("Latitude", accent: accent, size: 0.0108)
        plate.position = [0, Self.radius + 0.036, 0]
        root.addChild(plate)

        root.components.set(InputTargetComponent())
        // Matched to the sphere, per the collider-≤-visual rule.
        root.components.set(CollisionComponent(shapes: [
            .generateSphere(radius: Self.radius * 1.06)
        ]))
        root.components.set(HoverEffectComponent())
        root.components.set(GroundingShadowComponent(castsShadow: true))

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Latitude. Slide up or down the globe to move north or south."
        root.components.set(accessibility)
    }

    func owns(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === root { return true }
            current = candidate.parent
        }
        return false
    }

    /// Latitude from a hand position in the globe's PARENT space.
    ///
    /// Absolute, like every other instrument the app kept: the latitude
    /// is wherever on the globe your finger is, not an accumulated drag.
    /// Height above the globe's centre maps through `asin`, which is the
    /// sphere's own geometry doing the work — touch the top and you are
    /// at the pole because the top IS the pole.
    func latitude(forHand hand: SIMD3<Double>) -> Double {
        let local = SIMD3<Float>(hand) - root.position
        let sine = max(-1, min(1, local.y / Self.radius))
        return Double(asin(sine)) * 180 / .pi
    }

    /// Per frame: park at `anchor`, and show the latitude the model holds.
    func update(anchor: SIMD3<Float>, latitudeDegrees: Double,
                trueDegreesPerHour: Double, truePeriodHours: Double?) {
        root.position = anchor

        let phi = Float(latitudeDegrees * .pi / 180)
        // The band sits at the latitude's height, and its radius is the
        // circle of latitude there — cos φ, which is why it shrinks to
        // nothing at the poles. Same cosine that is missing from the
        // precession law, and seeing one go as the other arrives is the
        // clearest statement of the sine the module can make.
        band.position = [0, Self.radius * sin(phi), 0]
        let ringRadius = Self.radius * cos(phi)
        band.scale = [max(ringRadius * 2.04, 0.004), 1,
                      max(ringRadius * 2.04, 0.004)]

        setText(Self.caption(latitudeDegrees: latitudeDegrees,
                             degreesPerHour: trueDegreesPerHour,
                             periodHours: truePeriodHours))
    }

    /// The place, and THE TRUE RATE THERE — never the exaggerated one.
    /// The room turns fast so you can watch it; this line is what is
    /// actually so, and it is the disclosure that makes the exaggeration
    /// honest rather than a lie.
    static func caption(latitudeDegrees: Double, degreesPerHour: Double,
                        periodHours: Double?) -> String {
        let hemisphere = latitudeDegrees >= 0 ? "N" : "S"
        let place = String(format: "%.1f°%@", abs(latitudeDegrees), hemisphere)
        guard let periodHours else {
            return place + " — the plane never turns here"
        }
        return place + String(format: " — really %.2f°/h, one turn in %.1f h",
                              abs(degreesPerHour), periodHours)
    }

    private func setText(_ string: String) {
        guard string != lastText else { return }
        lastText = string
        if var accessibility = root.components[AccessibilityComponent.self] {
            accessibility.value = LocalizedStringResource(stringLiteral: string)
            root.components.set(accessibility)
        }
        let mesh: MeshResource
        if let cached = textCache[string] {
            mesh = cached
        } else {
            if textCache.count > 240 { textCache.removeAll() }
            mesh = MeshResource.generateText(
                string, extrusionDepth: 0.0015,
                font: .systemFont(ofSize: 0.017, weight: .semibold))
            textCache[string] = mesh
        }
        readout.model = ModelComponent(mesh: mesh, materials: [readoutMaterial])
        let bounds = mesh.bounds
        readout.position = [-(bounds.min.x + bounds.max.x) / 2, 0, 0]
    }
}
