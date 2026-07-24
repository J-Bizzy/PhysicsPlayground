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
import RenderKit

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

    private static let orbRadius: Float = 0.048

    // The cluster: four bubbles centred and strung on a shallow glass rail
    // that bows gently toward the user, like beads on a wire.
    private static let orbY: Float = 0.85
    private static let orbZ: Float = -0.72
    private static let orbSpacing: Float = 0.185
    private static func orbPosition(_ index: Int) -> SIMD3<Float> {
        let x = (Float(index) - 1.5) * orbSpacing
        return SIMD3(x, orbY, orbZ + bow(atX: x))
    }
    /// A gentle forward bow (toward the user) that grows toward the ends.
    private static func bow(atX x: Float) -> Float {
        let t = x / (orbSpacing * 1.5)
        return 0.028 * t * t
    }

    func build() {
        buildRail()
        backOrb = makeOrb(
            name: "orb-back",
            at: Self.orbPosition(0),
            accessibilityLabel: "Back to the exhibit menu"
        )
        pauseOrb = makeOrb(
            name: "orb-pause",
            at: Self.orbPosition(1),
            accessibilityLabel: "Pause or resume the physics"
        )
        podsOrb = makeOrb(
            name: "orb-pods",
            at: Self.orbPosition(2),
            accessibilityLabel: "Show or hide the floating control pods"
        )
        resetOrb = makeOrb(
            name: "orb-reset",
            at: Self.orbPosition(3),
            accessibilityLabel: "Reset the module. Pinch once to arm, again to reset."
        )

        // Icons are small, smooth, chrome-like models that catch the room
        // light and read against any background — not flat glyphs that wash
        // out inside the clear glass, and not jagged box assemblies.
        attachIcon(chevronIcon(), to: backOrb)

        // Pause bars vs a play triangle, toggled by state.
        pauseBars = pauseBarsIcon()
        playTriangle = playTriangleIcon()
        playTriangle.isEnabled = false
        let pauseIcon = Entity()
        pauseIcon.addChild(pauseBars)
        pauseIcon.addChild(playTriangle)
        attachIcon(pauseIcon, to: pauseOrb)

        // Pods shown (a 2×2 grid of tiles) vs hidden (one dim tile).
        podTiles = podGridIcon()
        podTileSolo = podSoloIcon()
        podTileSolo.isEnabled = false
        let podsIcon = Entity()
        podsIcon.addChild(podTiles)
        podsIcon.addChild(podTileSolo)
        attachIcon(podsIcon, to: podsOrb)

        // Reset: a smooth counter-clockwise ring-arrow.
        attachIcon(resetRingIcon(), to: resetOrb)
    }

    // MARK: Icon geometry
    //
    // Every glyph is built from smooth primitives — rounded boxes, a filled
    // triangle, and a tube-swept ring — in a faintly-lit chrome so it reads
    // as a crafted little instrument through the glass, on light walls or
    // dark furniture alike.

    /// Chrome with a whisper of self-illumination, so the icon never sinks
    /// to a flat silhouette even when it falls into shadow.
    private static func iconMetal(_ tint: UIColor = UIColor(white: 0.9, alpha: 1),
                                  emissive: Float = 0.14) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: tint)
        m.metallic = 0.9
        m.roughness = 0.24
        m.clearcoat = .init(floatLiteral: 0.6)
        m.clearcoatRoughness = .init(floatLiteral: 0.2)
        m.emissiveColor = .init(color: tint)
        m.emissiveIntensity = emissive
        return m
    }

    /// A flat, filled triangle pointing along +X, facing the camera (+Z),
    /// double-sided so the billboard can never show its back.
    private static func triangleMesh(width: Float, height: Float) -> MeshResource {
        let w = width * 0.5, h = height * 0.5
        var d = MeshDescriptor(name: "triangle")
        d.positions = MeshBuffers.Positions([[w, 0, 0], [-w, h, 0], [-w, -h, 0]])
        d.normals = MeshBuffers.Normals([[0, 0, 1], [0, 0, 1], [0, 0, 1]])
        d.primitives = .triangles([0, 1, 2, 0, 2, 1])
        return (try? MeshResource.generate(from: [d])) ?? .generateBox(size: 0.01)
    }

    /// A "‹" chevron: two rounded bars meeting at a left-hand vertex.
    private func chevronIcon() -> Entity {
        let icon = Entity()
        let bar = MeshResource.generateBox(size: [0.021, 0.007, 0.007], cornerRadius: 0.0035)
        let vertexX: Float = -0.013
        let half: Float = 0.0105
        for sign: Float in [1, -1] {
            let arm = ModelEntity(mesh: bar, materials: [Self.iconMetal()])
            let angle = sign * (.pi * 0.28)   // ~50° open
            arm.orientation = simd_quatf(angle: angle, axis: [0, 0, 1])
            arm.position = [vertexX + half * cos(angle), half * sin(angle), 0]
            icon.addChild(arm)
        }
        return icon
    }

    private func pauseBarsIcon() -> Entity {
        let icon = Entity()
        let bar = MeshResource.generateBox(size: [0.008, 0.03, 0.008], cornerRadius: 0.004)
        for x: Float in [-0.008, 0.008] {
            let e = ModelEntity(mesh: bar, materials: [Self.iconMetal()])
            e.position = [x, 0, 0]
            icon.addChild(e)
        }
        return icon
    }

    private func playTriangleIcon() -> Entity {
        let icon = Entity()
        let tri = ModelEntity(mesh: Self.triangleMesh(width: 0.028, height: 0.032),
                              materials: [Self.iconMetal()])
        tri.position = [0.028 / 6, 0, 0]   // centre the triangle's centroid
        icon.addChild(tri)
        return icon
    }

    private func podGridIcon() -> Entity {
        let icon = Entity()
        let tile = MeshResource.generateBox(size: [0.013, 0.013, 0.006], cornerRadius: 0.0028)
        for x: Float in [-0.008, 0.008] {
            for y: Float in [-0.008, 0.008] {
                let e = ModelEntity(mesh: tile, materials: [Self.iconMetal()])
                e.position = [x, y, 0]
                icon.addChild(e)
            }
        }
        return icon
    }

    private func podSoloIcon() -> Entity {
        let icon = Entity()
        let tile = ModelEntity(
            mesh: .generateBox(size: [0.017, 0.017, 0.006], cornerRadius: 0.003),
            materials: [Self.iconMetal(UIColor(white: 0.55, alpha: 1), emissive: 0.06)])
        icon.addChild(tile)
        return icon
    }

    /// A smooth ~290° ring swept as a tube, capped by a tangent arrowhead —
    /// the universal "start over" glyph, with no faceted segments.
    private func resetRingIcon() -> Entity {
        let icon = Entity()
        let radius: Float = 0.016
        let start: Float = .pi * 0.35
        let sweep: Float = .pi * 1.62
        let steps = 44
        let points: [SIMD3<Float>] = (0...steps).map { i in
            let a = start + sweep * Float(i) / Float(steps)
            return [cos(a) * radius, sin(a) * radius, 0]
        }
        if let mesh = TubeMesh.tube(lines: [points], radius: 0.0034, sides: 8) {
            icon.addChild(ModelEntity(mesh: mesh, materials: [Self.iconMetal()]))
        }
        // Arrowhead at the swept end, aimed along the counter-clockwise tangent.
        let endAngle = start + sweep
        let head = ModelEntity(mesh: Self.triangleMesh(width: 0.013, height: 0.013),
                               materials: [Self.iconMetal()])
        head.position = [cos(endAngle) * radius, sin(endAngle) * radius, 0]
        head.orientation = simd_quatf(angle: endAngle + .pi / 2, axis: [0, 0, 1])
        icon.addChild(head)
        return icon
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

    /// The glass rail the bubbles are strung on — a slim, gently-bowed
    /// tube of frosted glass with a soft inner glow, threaded just under
    /// the bubbles so the cluster reads as one crafted control, not four
    /// stray spheres. Extends a little past the end bubbles.
    private func buildRail() {
        let points: [SIMD3<Float>] = stride(from: -0.36, through: 0.36, by: 0.02).map { x in
            SIMD3(x, Self.orbY - 0.05, Self.orbZ + Self.bow(atX: x))
        }
        guard let mesh = TubeMesh.tube(lines: [points], radius: 0.008, sides: 10) else { return }
        let rail = ModelEntity(mesh: mesh, materials: [Self.orbGlass(opacity: 0.4, emissive: 0.16)])
        root.addChild(rail)

        // Two small end-caps so the rail reads as a finished bar.
        for x: Float in [-0.36, 0.36] {
            let cap = ModelEntity(
                mesh: .generateSphere(radius: 0.011),
                materials: [Self.orbGlass(opacity: 0.45, emissive: 0.18)])
            cap.position = SIMD3(x, Self.orbY - 0.05, Self.orbZ + Self.bow(atX: x))
            root.addChild(cap)
        }
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
        // Ride toward the front of the bead so the icon reads crisply
        // instead of sinking behind a hemisphere of glass.
        icon.position = [0, 0, 0.024]
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
