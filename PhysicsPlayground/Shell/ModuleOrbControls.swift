//
//  ModuleOrbControls.swift
//  Physics Playground — Shell
//
//  The four floating orb controls every module inherits, hovering
//  low in front of the user: a BACK orb (chevron) that returns to
//  the exhibit ring, a PAUSE orb (bars/triangle) that freezes the
//  module's physics in time, a PODS orb (tiles) that clears the
//  floating control pods away, and a RESET orb (ring-arrow) that
//  needs two pinches — the first arms it red for three seconds, the
//  second restores the module's opening scene, so a stray gaze-pinch
//  can never wipe a build. Glass spheres with 3D icons
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
    @State private var showPodTip = !UserDefaults.standard.bool(forKey: "hint.pods.dismissed")
    @State private var resetArmedUntil = Date.distantPast

    var body: some View {
        RealityView { content, attachments in
            scene.build()
            content.add(scene.root)
            if let tip = attachments.entity(for: "pod-tip") {
                tip.position = [0, 1.02, -0.72]
                tip.components.set(BillboardComponent())
                scene.root.addChild(tip)
            }
            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                scene.showPausedState(module.isPaused())
                scene.showPodsState(appModel.controlPodsVisible)
                scene.showResetArmed(Date() < resetArmedUntil)
            }
        } attachments: {
            Attachment(id: "pod-tip") {
                if showPodTip {
                    Text("Pinch a glass bar to carry a pod anywhere — the tiles orb clears them all")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: 300)
                        .multilineTextAlignment(.center)
                        .glassBackgroundEffect()
                        .transition(.opacity)
                }
            }
        }
        .task {
            // The tip shows once per install, then bows out.
            guard showPodTip else { return }
            try? await Task.sleep(for: .seconds(14))
            withAnimation(.easeOut(duration: 1)) { showPodTip = false }
            UserDefaults.standard.set(true, forKey: "hint.pods.dismissed")
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
                    case .pods:
                        appModel.controlPodsVisible.toggle()
                        SoundPalette.play(.pop, on: scene.podsOrb, volume: 0.5)
                        scene.pulse(scene.podsOrb)
                    case .reset:
                        if Date() < resetArmedUntil {
                            resetArmedUntil = .distantPast
                            module.reset()
                            SoundPalette.play(.chime, on: scene.resetOrb, volume: 0.6)
                        } else {
                            resetArmedUntil = Date().addingTimeInterval(3)
                            SoundPalette.play(.pop, on: scene.resetOrb, volume: 0.5)
                        }
                        scene.pulse(scene.resetOrb)
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
    enum Action { case pause, back, pods, reset }

    let root = Entity()
    var subscription: EventSubscription?

    private(set) var pauseOrb = ModelEntity()
    private(set) var backOrb = ModelEntity()
    private(set) var podsOrb = ModelEntity()
    private(set) var resetOrb = ModelEntity()
    private var pauseBars = Entity()
    private var playTriangle = Entity()
    private var podTiles = Entity()
    private var podTileSolo = Entity()
    private var showingPaused = false
    private var showingPods = true
    private var showingResetArmed = false

    private static let orbRadius: Float = 0.05
    private static let iconColor = UIColor(white: 0.95, alpha: 1)

    func build() {
        backOrb = makeOrb(
            name: "orb-back",
            at: SIMD3(-0.22, 0.85, -0.72),
            accessibilityLabel: "Back to the exhibit menu"
        )
        pauseOrb = makeOrb(
            name: "orb-pause",
            at: SIMD3(0, 0.85, -0.72),
            accessibilityLabel: "Pause or resume the physics"
        )
        podsOrb = makeOrb(
            name: "orb-pods",
            at: SIMD3(0.22, 0.85, -0.72),
            accessibilityLabel: "Show or hide the floating control pods"
        )
        resetOrb = makeOrb(
            name: "orb-reset",
            at: SIMD3(0.44, 0.85, -0.72),
            accessibilityLabel: "Reset the module. Pinch once to arm, again to reset."
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

        // Pods: three little cards fanned out; a lone dim card while
        // the pods are hidden.
        let tileMesh = MeshResource.generateBox(
            size: [0.016, 0.0115, 0.004], cornerRadius: 0.002)
        for offset in [SIMD3<Float>(-0.011, 0.010, 0), SIMD3(0.011, 0.004, 0),
                       SIMD3(0, -0.009, 0)] {
            let tile = ModelEntity(mesh: tileMesh, materials: [iconMaterial])
            tile.position = offset
            podTiles.addChild(tile)
        }
        let soloTile = ModelEntity(
            mesh: tileMesh,
            materials: [UnlitMaterial(color: UIColor(white: 0.55, alpha: 1))])
        podTileSolo.addChild(soloTile)
        podTileSolo.isEnabled = false
        let podsIcon = Entity()
        podsIcon.addChild(podTiles)
        podsIcon.addChild(podTileSolo)
        attachIcon(podsIcon, to: podsOrb)

        // Reset: a ring with a little arrowhead — the universal ↺.
        let resetIcon = Entity()
        // Ring built from short segments (RealityKit has no torus).
        let segmentMesh = MeshResource.generateBox(
            size: [0.0105, 0.0055, 0.0055], cornerRadius: 0.0025)
        for step in 0..<10 {
            let angle = Float(step) / 10 * 2 * .pi
            let segment = ModelEntity(mesh: segmentMesh, materials: [iconMaterial])
            segment.position = [0.0155 * cos(angle), 0.0155 * sin(angle), 0]
            segment.orientation = simd_quatf(angle: angle + .pi / 2, axis: [0, 0, 1])
            resetIcon.addChild(segment)
        }
        let head = ModelEntity(
            mesh: .generateCone(height: 0.012, radius: 0.0065),
            materials: [iconMaterial])
        head.position = [-0.004, 0.0155, 0]
        head.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        resetIcon.addChild(head)
        attachIcon(resetIcon, to: resetOrb)
    }

    /// A crafted lit-glass bead: clear-coated for a crisp highlight and
    /// faintly self-lit so it reads as a present instrument, not a ghost.
    static func orbGlass(tint: UIColor = .white, opacity: Float = 0.34,
                         emissive: Float = 0.14) -> PhysicallyBasedMaterial {
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: tint)
        glass.roughness = 0.1
        glass.metallic = 0.0
        glass.clearcoat = .init(floatLiteral: 1.0)
        glass.clearcoatRoughness = .init(floatLiteral: 0.1)
        glass.blending = .transparent(opacity: .init(floatLiteral: opacity))
        glass.emissiveColor = .init(color: tint)
        glass.emissiveIntensity = emissive
        return glass
    }

    /// Armed: the orb warms to red until the confirming pinch (or the
    /// three-second window closes).
    func showResetArmed(_ armed: Bool) {
        guard armed != showingResetArmed else { return }
        showingResetArmed = armed
        resetOrb.model?.materials = [armed
            ? Self.orbGlass(tint: UIColor(red: 1, green: 0.32, blue: 0.28, alpha: 1),
                            opacity: 0.55, emissive: 0.35)
            : Self.orbGlass()]
    }

    private func makeOrb(name: String, at position: SIMD3<Float>,
                         accessibilityLabel: String) -> ModelEntity {
        let orb = ModelEntity(
            mesh: .generateSphere(radius: Self.orbRadius),
            materials: [Self.orbGlass()]
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

    /// Fanned tiles while pods are out, one dim tile while hidden.
    func showPodsState(_ visible: Bool) {
        guard visible != showingPods else { return }
        showingPods = visible
        podTiles.isEnabled = visible
        podTileSolo.isEnabled = !visible
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
            if candidate.name == "orb-pods" { return .pods }
            if candidate.name == "orb-reset" { return .reset }
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
