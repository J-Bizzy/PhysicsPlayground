//
//  ModuleOrbControls.swift
//  Physics Playground — Shell
//
//  The two floating orb controls every module inherits, hovering low
//  in front of the user: a BACK orb (left, chevron) that returns to
//  the exhibit ring, and a PAUSE orb (right, bars/triangle) that
//  freezes the module's physics in time. Glass spheres with 3D icons
//  billboarded toward the user; the system hover effect lights them
//  on gaze, pinch activates.
//
//  The pause icon tracks the model every frame (pause can also be
//  toggled from panels), so orb and panels never disagree.
//

import SwiftUI
import RealityKit

struct ModuleOrbControlsView: View {
    let module: ModuleDescriptor

    @Environment(AppModel.self) private var appModel
    @State private var scene = OrbScene()

    var body: some View {
        RealityView { content in
            scene.build()
            content.add(scene.root)
            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                scene.showPausedState(module.isPaused())
            }
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    switch scene.action(for: value.entity) {
                    case .pause:
                        module.togglePause()
                        SoundPalette.play(.pop, on: scene.pauseOrb, volume: 0.5)
                        scene.pulse(scene.pauseOrb)
                    case .back:
                        SoundPalette.play(.pop, on: scene.backOrb, volume: 0.5)
                        scene.pulse(scene.backOrb)
                        Task {
                            try? await Task.sleep(for: .milliseconds(140))
                            appModel.activeModuleID = nil
                        }
                    case nil:
                        break
                    }
                }
        )
    }
}

/// The orbs' entity graph.
@MainActor
@Observable
final class OrbScene {
    enum Action { case pause, back }

    let root = Entity()
    var subscription: EventSubscription?

    private(set) var pauseOrb = ModelEntity()
    private(set) var backOrb = ModelEntity()
    private var pauseBars = Entity()
    private var playTriangle = Entity()
    private var showingPaused = false

    private static let orbRadius: Float = 0.05
    private static let iconColor = UIColor(white: 0.95, alpha: 1)

    func build() {
        backOrb = makeOrb(
            name: "orb-back",
            at: SIMD3(-0.11, 0.85, -0.72),
            accessibilityLabel: "Back to the exhibit menu"
        )
        pauseOrb = makeOrb(
            name: "orb-pause",
            at: SIMD3(0.11, 0.85, -0.72),
            accessibilityLabel: "Pause or resume the physics"
        )

        // Back: a chevron pointing left.
        let chevron = Entity()
        let strokeMesh = MeshResource.generateBox(
            size: [0.032, 0.009, 0.009], cornerRadius: 0.004)
        let iconMaterial = UnlitMaterial(color: Self.iconColor)
        let upper = ModelEntity(mesh: strokeMesh, materials: [iconMaterial])
        upper.orientation = simd_quatf(angle: 0.65, axis: [0, 0, 1])
        upper.position = [0.004, 0.0105, 0]
        let lower = ModelEntity(mesh: strokeMesh, materials: [iconMaterial])
        lower.orientation = simd_quatf(angle: -0.65, axis: [0, 0, 1])
        lower.position = [0.004, -0.0105, 0]
        chevron.addChild(upper)
        chevron.addChild(lower)
        attachIcon(chevron, to: backOrb)

        // Pause: two bars; play: a triangle (cone lying on its side).
        let barMesh = MeshResource.generateBox(
            size: [0.011, 0.036, 0.009], cornerRadius: 0.004)
        for x: Float in [-0.0105, 0.0105] {
            let bar = ModelEntity(mesh: barMesh, materials: [iconMaterial])
            bar.position = [x, 0, 0]
            pauseBars.addChild(bar)
        }
        let triangle = ModelEntity(
            mesh: .generateCone(height: 0.038, radius: 0.022),
            materials: [iconMaterial]
        )
        // Cones point +y; lay it over so it points +x — a play glyph.
        triangle.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        triangle.position = [0.004, 0, 0]
        playTriangle.addChild(triangle)
        playTriangle.isEnabled = false

        let pauseIcon = Entity()
        pauseIcon.addChild(pauseBars)
        pauseIcon.addChild(playTriangle)
        attachIcon(pauseIcon, to: pauseOrb)
    }

    private func makeOrb(name: String, at position: SIMD3<Float>,
                         accessibilityLabel: String) -> ModelEntity {
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: .white)
        glass.roughness = 0.12
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        let orb = ModelEntity(
            mesh: .generateSphere(radius: Self.orbRadius),
            materials: [glass]
        )
        orb.name = name
        orb.position = position
        orb.components.set(InputTargetComponent())
        orb.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: Self.orbRadius * 1.4)]))
        orb.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: accessibilityLabel)
        orb.components.set(accessibility)
        root.addChild(orb)
        return orb
    }

    private func attachIcon(_ icon: Entity, to orb: ModelEntity) {
        let pivot = Entity()
        pivot.components.set(BillboardComponent())
        pivot.addChild(icon)
        orb.addChild(pivot)
    }

    /// Bars while running (pinch to pause), triangle while frozen.
    func showPausedState(_ paused: Bool) {
        guard paused != showingPaused else { return }
        showingPaused = paused
        pauseBars.isEnabled = !paused
        playTriangle.isEnabled = paused
    }

    func action(for entity: Entity) -> Action? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name == "orb-pause" { return .pause }
            if candidate.name == "orb-back" { return .back }
            current = candidate.parent
        }
        return nil
    }

    /// A quick swell acknowledging the pinch.
    func pulse(_ orb: ModelEntity) {
        orb.move(
            to: Transform(scale: SIMD3(repeating: 1.14), translation: orb.position),
            relativeTo: root, duration: 0.1, timingFunction: .easeOut
        )
        Task { [weak orb, weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let orb, let self else { return }
            orb.move(
                to: Transform(scale: SIMD3(repeating: 1.0), translation: orb.position),
                relativeTo: self.root, duration: 0.12, timingFunction: .easeInOut
            )
        }
    }
}
