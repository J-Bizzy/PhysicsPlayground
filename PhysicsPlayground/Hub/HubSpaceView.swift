//
//  HubSpaceView.swift
//  Physics Playground — Hub
//
//  The spatial menu: the app title floats in front of the user, and each
//  module is a glass bubble on an arc around them — a living miniature
//  of the experience inside, its name floating beneath. Look at a bubble
//  (the system hover effect lights it) and pinch to enter.
//
//  Everything idles gently: bubbles bob out of phase and the vignettes
//  slowly turn. The whole scene is a handful of entities — the per-frame
//  work is a few transform writes.
//
//  Vignettes are keyed by module id with a generic fallback, so a new
//  module gets a bubble for free and a bespoke miniature with one case.
//

import SwiftUI
import RealityKit
import RenderKit

struct HubSpaceView: View {
    @Environment(AppModel.self) private var appModel
    @State private var scene = HubScene()

    var body: some View {
        RealityView { content in
            scene.build(modules: ModuleCatalog.all(appModel: appModel))
            content.add(scene.root)

            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                scene.animate(dt: event.deltaTime)
            }
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard let id = scene.moduleID(for: value.entity) else { return }
                    scene.pulseBubble(id: id)
                    Task {
                        // Let the pulse land before the scene switches.
                        try? await Task.sleep(for: .milliseconds(160))
                        appModel.activeModuleID = id
                    }
                }
        )
    }
}

/// The hub's entity graph and idle animation state.
@MainActor
@Observable
final class HubScene {
    let root = Entity()
    var subscription: EventSubscription?

    private struct Bubble {
        let moduleID: String
        let anchor: Entity      // bobbing position
        let shell: ModelEntity  // tap target
        let vignette: Entity    // slowly rotating miniature
    }
    private var bubbles: [Bubble] = []
    private var time = 0.0

    // Pushed well past the default window position (~1.3 m) so the menu
    // reads as a room-scale layer behind and around the window.
    private static let bubbleRadius: Float = 0.15
    private static let arcRadius: Float = 2.1
    private static let bubbleHeight: Float = 1.5

    // MARK: Build

    func build(modules: [ModuleDescriptor]) {
        buildTitle()

        // Bubbles flank the user, alternating right and left and leaving
        // the center corridor (±20°) free for the title and the window.
        for (index, module) in modules.enumerated() {
            let side: Float = index % 2 == 0 ? -1 : 1
            let ring = Float(index / 2)
            let angle = side * (24 + 28 * ring) * .pi / 180
            let position = SIMD3<Float>(
                Self.arcRadius * sin(angle),
                Self.bubbleHeight,
                -Self.arcRadius * cos(angle)
            )
            buildBubble(for: module, at: position)
        }
    }

    private func buildTitle() {
        let titleMesh = MeshResource.generateText(
            "Physics Playground",
            extrusionDepth: 0.016,
            font: .systemFont(ofSize: 0.13, weight: .bold)
        )
        // Metallic text picks up the room's light and shimmers as you move.
        var titleMaterial = PhysicallyBasedMaterial()
        titleMaterial.baseColor = .init(tint: .white)
        titleMaterial.metallic = 0.65
        titleMaterial.roughness = 0.32
        let title = ModelEntity(mesh: titleMesh, materials: [titleMaterial])
        let titleBounds = titleMesh.bounds
        title.position = [
            -(titleBounds.min.x + titleBounds.max.x) / 2, 2.06, -2.35,
        ]
        root.addChild(title)

        let subtitleMesh = MeshResource.generateText(
            "Look at an exhibit and pinch to step inside",
            extrusionDepth: 0.002,
            font: .systemFont(ofSize: 0.03, weight: .regular)
        )
        let subtitle = ModelEntity(
            mesh: subtitleMesh,
            materials: [UnlitMaterial(color: UIColor(white: 0.85, alpha: 0.8))]
        )
        let subtitleBounds = subtitleMesh.bounds
        subtitle.position = [
            -(subtitleBounds.min.x + subtitleBounds.max.x) / 2, 1.98, -2.35,
        ]
        root.addChild(subtitle)
    }

    private func buildBubble(for module: ModuleDescriptor, at position: SIMD3<Float>) {
        let anchor = Entity()
        anchor.position = position
        root.addChild(anchor)

        // The glass shell — also the gaze/pinch target.
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: .white)
        glass.roughness = 0.08
        glass.metallic = 0.0
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.14))
        let shell = ModelEntity(
            mesh: .generateSphere(radius: Self.bubbleRadius),
            materials: [glass]
        )
        shell.name = module.id
        shell.components.set(InputTargetComponent())
        shell.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: Self.bubbleRadius * 1.15)]))
        shell.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "Enter \(module.title). \(module.blurb)")
        shell.components.set(accessibility)
        anchor.addChild(shell)

        // The living miniature inside.
        let vignette = Self.vignette(for: module)
        anchor.addChild(vignette)

        // The floating name beneath, always facing the user.
        let nameMesh = MeshResource.generateText(
            module.title,
            extrusionDepth: 0.003,
            font: .systemFont(ofSize: 0.034, weight: .semibold)
        )
        let name = ModelEntity(
            mesh: nameMesh,
            materials: [UnlitMaterial(color: UIColor(module.accent))]
        )
        let nameBounds = nameMesh.bounds
        name.position = [-(nameBounds.min.x + nameBounds.max.x) / 2, 0, 0]
        let namePivot = Entity()
        namePivot.position = [0, -Self.bubbleRadius - 0.075, 0]
        namePivot.components.set(BillboardComponent())
        namePivot.addChild(name)
        anchor.addChild(namePivot)

        bubbles.append(Bubble(moduleID: module.id, anchor: anchor, shell: shell, vignette: vignette))
    }

    // MARK: Vignettes (miniatures of each experience)

    private static func vignette(for module: ModuleDescriptor) -> Entity {
        let vignette = Entity()
        switch module.id {
        case "electrostatics": buildFieldVignette(in: vignette)
        case "kinematics": buildProjectileVignette(in: vignette)
        case "gravitylab": buildOrbitVignette(in: vignette)
        case "waves": buildWavesVignette(in: vignette)
        case "windtunnel": buildWindTunnelVignette(in: vignette)
        default:
            // A new module gets a simple accent sphere until it has art.
            vignette.addChild(ModelEntity(
                mesh: .generateSphere(radius: 0.035),
                materials: [SimpleMaterial(color: UIColor(module.accent),
                                           roughness: 0.4, isMetallic: false)]))
        }
        return vignette
    }

    /// A dipole: red and blue charges joined by two arcing field lines.
    private static func buildFieldVignette(in parent: Entity) {
        let positive = ModelEntity(
            mesh: .generateSphere(radius: 0.026),
            materials: [SimpleMaterial(color: DesignTokens.Palette.positiveUI,
                                       roughness: 0.35, isMetallic: false)])
        positive.position = [-0.045, 0, 0]
        let negative = ModelEntity(
            mesh: .generateSphere(radius: 0.026),
            materials: [SimpleMaterial(color: DesignTokens.Palette.negativeUI,
                                       roughness: 0.35, isMetallic: false)])
        negative.position = [0.045, 0, 0]
        parent.addChild(positive)
        parent.addChild(negative)

        var lineMaterial = UnlitMaterial(color: DesignTokens.Palette.fieldLineUI)
        lineMaterial.blending = .transparent(opacity: 0.85)
        for flip: Float in [1, -1] {
            let arc: [SIMD3<Float>] = (0...20).map { step in
                let theta = Float(step) / 20 * .pi
                return SIMD3(-0.045 * cos(theta), flip * 0.042 * sin(theta), 0)
            }
            if let mesh = TubeMesh.tube(lines: [arc], radius: 0.0022) {
                parent.addChild(ModelEntity(mesh: mesh, materials: [lineMaterial]))
            }
        }
    }

    /// A ball frozen mid-flight over its strobe-dot parabola.
    private static func buildProjectileVignette(in parent: Entity) {
        let ball = ModelEntity(
            mesh: .generateSphere(radius: 0.02),
            materials: [SimpleMaterial(color: DesignTokens.Palette.projectileUI,
                                       roughness: 0.5, isMetallic: false)])
        ball.position = [0.014, 0.037, 0]
        parent.addChild(ball)

        var dotMaterial = UnlitMaterial(color: DesignTokens.Palette.projectileUI)
        dotMaterial.blending = .transparent(opacity: 0.75)
        let dotMesh = MeshResource.generateSphere(radius: 0.0045)
        for step in 0...7 {
            let t = Float(step) / 7
            let x = -0.055 + t * 0.11
            // A parabola through the ball's position, peak just left of it.
            let y = 0.04 - 0.16 * (x - 0.01) * (x - 0.01)
            let dot = ModelEntity(mesh: dotMesh, materials: [dotMaterial])
            dot.position = [x, y - 0.01, 0]
            parent.addChild(dot)
        }
    }

    /// A cylinder with streamlines parting around it.
    private static func buildWindTunnelVignette(in parent: Entity) {
        let cylinder = ModelEntity(
            mesh: .generateCylinder(height: 0.05, radius: 0.016),
            materials: [SimpleMaterial(color: DesignTokens.Palette.launcherUI,
                                       roughness: 0.35, isMetallic: true)])
        parent.addChild(cylinder)

        var lineMaterial = UnlitMaterial(color: DesignTokens.Palette.streamlineUI)
        lineMaterial.blending = .transparent(opacity: 0.7)
        for offset: Float in [-0.034, -0.012, 0.012, 0.034] {
            let line: [SIMD3<Float>] = (0...24).map { step in
                let x = -0.055 + 0.11 * Float(step) / 24
                // Bend away from the cylinder, strongest near x = 0.
                let bulge = 0.014 * exp(-x * x / 0.0012) * (offset > 0 ? 1 : -1)
                    / max(abs(offset) / 0.02, 1)
                return SIMD3(x, 0, offset + bulge)
            }
            if let mesh = TubeMesh.tube(lines: [line], radius: 0.0013) {
                parent.addChild(ModelEntity(mesh: mesh, materials: [lineMaterial]))
            }
        }
    }

    /// Two source pucks with interleaving ripple rings.
    private static func buildWavesVignette(in parent: Entity) {
        var ringMaterial = UnlitMaterial(color: DesignTokens.Palette.waveSourceUI)
        ringMaterial.blending = .transparent(opacity: 0.55)

        for (center, radii): (SIMD3<Float>, [Float]) in [
            (SIMD3(-0.035, -0.01, 0), [0.02, 0.038]),
            (SIMD3(0.035, -0.01, 0), [0.02, 0.038]),
        ] {
            let puck = ModelEntity(
                mesh: .generateCylinder(height: 0.008, radius: 0.011),
                materials: [UnlitMaterial(color: DesignTokens.Palette.waveSourceUI)])
            puck.position = center
            parent.addChild(puck)

            for radius in radii {
                let circle: [SIMD3<Float>] = (0...28).map { step in
                    let theta = 2 * Float.pi * Float(step) / 28
                    return center + SIMD3(radius * cos(theta), 0, radius * sin(theta))
                }
                if let mesh = TubeMesh.tube(lines: [circle], radius: 0.0014) {
                    parent.addChild(ModelEntity(mesh: mesh, materials: [ringMaterial]))
                }
            }
        }
    }

    /// A tiny sun, an orbit ring, and a planet parked on it.
    private static func buildOrbitVignette(in parent: Entity) {
        let sun = ModelEntity(
            mesh: .generateSphere(radius: 0.028),
            materials: [UnlitMaterial(color: DesignTokens.Palette.celestialUI("Sun"))])
        parent.addChild(sun)

        var ringMaterial = UnlitMaterial(color: .white)
        ringMaterial.blending = .transparent(opacity: 0.4)
        let ring: [SIMD3<Float>] = (0...36).map { step in
            let theta = Float(step) / 36 * 2 * .pi
            return SIMD3(0.062 * cos(theta), 0, 0.062 * sin(theta))
        }
        if let mesh = TubeMesh.tube(lines: [ring], radius: 0.0016) {
            let orbit = ModelEntity(mesh: mesh, materials: [ringMaterial])
            orbit.orientation = simd_quatf(angle: 0.35, axis: [1, 0, 0])
            parent.addChild(orbit)

            let planet = ModelEntity(
                mesh: .generateSphere(radius: 0.011),
                materials: [SimpleMaterial(color: DesignTokens.Palette.celestialUI("Earth"),
                                           roughness: 0.5, isMetallic: false)])
            planet.position = SIMD3(0.062, 0, 0)
            orbit.addChild(planet)
        }
    }

    // MARK: Idle animation & interaction

    /// Gentle out-of-phase bobbing; vignettes turn once per ~20 s.
    func animate(dt: Double) {
        time += dt
        for (index, bubble) in bubbles.enumerated() {
            let phase = time * 0.8 + Double(index) * 2.1
            var position = bubble.anchor.position
            position.y = Self.bubbleHeight + 0.012 * Float(sin(phase))
            bubble.anchor.position = position
            bubble.vignette.orientation = simd_quatf(
                angle: Float(time * 0.3 + Double(index)), axis: [0, 1, 0])
        }
    }

    /// Maps a tapped entity (shell or any child) back to its module.
    func moduleID(for entity: Entity) -> String? {
        var current: Entity? = entity
        while let candidate = current {
            if bubbles.contains(where: { $0.moduleID == candidate.name }) {
                return candidate.name
            }
            current = candidate.parent
        }
        return nil
    }

    /// A quick swell as the chosen bubble accepts the pinch.
    func pulseBubble(id: String) {
        guard let bubble = bubbles.first(where: { $0.moduleID == id }) else { return }
        bubble.anchor.move(
            to: Transform(scale: SIMD3(repeating: 1.14),
                          translation: bubble.anchor.position),
            relativeTo: root,
            duration: 0.14,
            timingFunction: .easeOut
        )
    }
}
