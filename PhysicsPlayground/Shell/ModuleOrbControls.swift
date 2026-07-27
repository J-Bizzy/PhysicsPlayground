//
//  ModuleOrbControls.swift
//  Physics Playground — Shell
//
//  The control rail: the things you reach for WHILE YOUR HANDS ARE IN
//  THE SCENE, floating low in front of you — pause the physics, dim the
//  room, note a measurement, clear the pods away.
//
//  It used to carry six beads including Back and Reset, both of which
//  the module's title bar already has. Duplicating navigation into an
//  in-space rail made the rail longer, made it unclear which control
//  lived where, and put a destructive action (reset) within reach of a
//  stray gaze-pinch — which is why reset needed a two-pinch arming
//  dance to be safe at all. Navigation and destruction belong on the
//  window; the rail is for working.
//
//  Every bead carries a one-word caption. Six identical glass spheres
//  with tiny chrome glyphs inside them was a guessing game: nobody
//  works out from a crescent that it dims the room. VoiceOver had the
//  answer and sighted users had nothing.
//
//  The pause icon tracks the model every frame (pause can also be
//  toggled from panels), so rail and panels never disagree.
//

import SwiftUI
import RealityKit
import RenderKit

struct ModuleOrbControlsView: View {
    let module: ModuleDescriptor

    @Environment(AppModel.self) private var appModel
    @State private var scene = OrbScene()
    @State private var showPodTip = !UserDefaults.standard.bool(forKey: "hint.pods.dismissed")
    /// A brief confirmation over the rail after a notebook capture.
    @State private var captureFlash: String?

    var body: some View {
        RealityView { content, attachments in
            scene.build(accent: UIColor(module.accent))
            content.add(scene.root)
            if let tip = attachments.entity(for: "pod-tip") {
                tip.position = [0, 1.02, -0.72]
                tip.components.set(BillboardComponent())
                scene.root.addChild(tip)
            }
            if let flash = attachments.entity(for: "capture-flash") {
                flash.position = [0, 1.0, -0.7]
                flash.components.set(BillboardComponent())
                scene.root.addChild(flash)
            }
            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                scene.showPausedState(module.isPaused())
                scene.showPodsState(appModel.controlPodsVisible)
                scene.showDimming(appModel.roomDimming)
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
            Attachment(id: "capture-flash") {
                if let captureFlash {
                    Label(captureFlash, systemImage: "checkmark.seal.fill")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
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
                    case .dim:
                        appModel.cycleDimming()
                        SoundPalette.play(.pop, on: scene.dimOrb, volume: 0.4)
                        scene.pulse(scene.dimOrb)
                    case .capture:
                        let entry = appModel.notebook.record(
                            moduleID: module.id, moduleTitle: module.title,
                            title: module.title,
                            readings: module.captureReadings())
                        SoundPalette.play(.chime, on: scene.captureOrb, volume: 0.55)
                        scene.pulse(scene.captureOrb)
                        captureFlash = "Noted — \(entry.readings.count) readings"
                        Task {
                            try? await Task.sleep(for: .seconds(2.4))
                            captureFlash = nil
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
    enum Action { case pause, pods, dim, capture }

    let root = Entity()
    var subscription: EventSubscription?

    private var accent: UIColor = .white

    private(set) var pauseOrb = ModelEntity()
    private(set) var podsOrb = ModelEntity()
    private(set) var dimOrb = ModelEntity()
    private(set) var captureOrb = ModelEntity()
    private var dimCrescent = Entity()
    private var pauseBars = Entity()
    private var playTriangle = Entity()
    private var podTiles = Entity()
    private var podTileSolo = Entity()
    private var showingPaused = false
    private var showingPods = true
    private var showingDimming = -1.0

    private static let orbRadius: Float = 0.048

    // The cluster: six bubbles centred and strung on a shallow glass rail
    // that bows gently toward the user, like beads on a wire.
    private static let orbCount = 4
    private static let orbY: Float = 0.92
    private static let orbZ: Float = -0.72
    private static let orbSpacing: Float = 0.15
    private static func orbPosition(_ index: Int) -> SIMD3<Float> {
        let x = (Float(index) - Float(orbCount - 1) / 2) * orbSpacing
        return SIMD3(x, orbY, orbZ + bow(atX: x))
    }
    /// A gentle forward bow (toward the user) that grows toward the ends.
    private static func bow(atX x: Float) -> Float {
        let t = x / (orbSpacing * Float(orbCount - 1) / 2)
        return 0.014 * t * t
    }

    func build(accent: UIColor) {
        self.accent = accent
        pauseOrb = makeOrb(
            name: "orb-pause", label: "Pause",
            at: Self.orbPosition(0),
            accessibilityLabel: "Pause or resume the physics"
        )
        dimOrb = makeOrb(
            name: "orb-dim", label: "Dim",
            at: Self.orbPosition(1),
            accessibilityLabel: "Dim the room. Pinch to cycle off, half, and full."
        )
        captureOrb = makeOrb(
            name: "orb-capture", label: "Note",
            at: Self.orbPosition(2),
            accessibilityLabel: "Write this moment into the lab notebook"
        )
        podsOrb = makeOrb(
            name: "orb-pods", label: "Pods",
            at: Self.orbPosition(3),
            accessibilityLabel: "Show or hide the floating control pods"
        )

        // Dim: a crescent — a filled disc with a smaller one cut in front
        // of it, the universal "shade" mark, sized like the other glyphs.
        attachIcon(dimIcon(), to: dimOrb)
        // Capture: a small open book, the notebook's own mark.
        attachIcon(notebookIcon(), to: captureOrb)

        // Icons are small, smooth, chrome-like models that catch the room
        // light and read against any background — not flat glyphs that wash
        // out inside the clear glass, and not jagged box assemblies.
        //
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

    }

    // MARK: Icon geometry
    //
    // Every glyph is built from smooth primitives — rounded boxes, a filled
    // triangle, and a tube-swept ring — in a faintly-lit chrome so it reads
    // as a crafted little instrument through the glass, on light walls or
    // dark furniture alike.

    /// Chrome with a whisper of self-illumination, so the icon never sinks
    /// to a flat silhouette even when it falls into shadow.
    private static func iconMetal(_ tint: UIColor = UIColor(white: 0.24, alpha: 1),
                                  emissive: Float = 0.02) -> PhysicallyBasedMaterial {
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

    /// A frosted core that gives the button a solid, pressable body —
    /// the icon floats just above it, inside the clear outer shell.
    private static func frostedCore() -> PhysicallyBasedMaterial {
        var core = PhysicallyBasedMaterial()
        core.baseColor = .init(tint: UIColor(white: 0.96, alpha: 1))
        core.roughness = 0.38
        core.metallic = 0.0
        core.emissiveColor = .init(color: .white)
        core.emissiveIntensity = 0.08
        core.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        return core
    }

    /// A small caption under a bead.
    ///
    /// Six identical glass spheres with tiny chrome glyphs inside them
    /// is not a control bar, it is a guessing game — nobody is going to
    /// work out from a crescent that it dims the room, or from a little
    /// book that it writes a measurement into a notebook. VoiceOver had
    /// the answer all along and sighted users had nothing. One word each
    /// costs almost nothing and removes the guessing.
    private func makeOrbLabel(_ text: String) -> Entity {
        let pivot = Entity()
        pivot.components.set(BillboardComponent())
        let mesh = MeshResource.generateText(
            text, extrusionDepth: 0.0004,
            font: .systemFont(ofSize: 0.016, weight: .semibold),
            alignment: .center)
        let bounds = mesh.bounds
        let centre = SIMD3<Float>(-(bounds.min.x + bounds.max.x) / 2,
                                  -(bounds.min.y + bounds.max.y) / 2, 0)
        // Dark casing behind pale type, the same trick the field lines
        // and the hub title use — captions on glass sit over whatever
        // the room happens to be.
        var shadowMaterial = UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))
        shadowMaterial.blending = .transparent(opacity: 0.75)
        let shadow = ModelEntity(mesh: mesh, materials: [shadowMaterial])
        shadow.position = centre + SIMD3(0, 0, -0.002)
        shadow.scale = SIMD3(repeating: 1.14)
        pivot.addChild(shadow)

        var textMaterial = UnlitMaterial(color: UIColor(white: 0.94, alpha: 1))
        textMaterial.blending = .transparent(opacity: 0.92)
        let letters = ModelEntity(mesh: mesh, materials: [textMaterial])
        letters.position = centre
        pivot.addChild(letters)
        return pivot
    }

    private func makeOrb(name: String, label: String, at position: SIMD3<Float>,
                         accessibilityLabel: String) -> ModelEntity {
        let orb = ModelEntity(
            mesh: .generateSphere(radius: Self.orbRadius),
            materials: [Self.orbGlass(opacity: 0.26)]
        )

        // The frosted heart of the button.
        let core = ModelEntity(
            mesh: .generateSphere(radius: Self.orbRadius * 0.76),
            materials: [Self.frostedCore()])
        orb.addChild(core)

        // A thin accent band on the equator — the one piece of module
        // colour, like an inlaid ring on a physical instrument button.
        let bandPoints: [SIMD3<Float>] = (0...48).map { step in
            let angle = Float(step) / 48 * 2 * .pi
            return SIMD3(cos(angle) * Self.orbRadius * 1.01,
                         0,
                         sin(angle) * Self.orbRadius * 1.01)
        }
        if let bandMesh = TubeMesh.tube(lines: [bandPoints], radius: 0.0022, sides: 6) {
            var bandMaterial = UnlitMaterial(color: accent)
            bandMaterial.blending = .transparent(opacity: 0.75)
            let band = ModelEntity(mesh: bandMesh, materials: [bandMaterial])
            orb.addChild(band)
        }

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

        let caption = makeOrbLabel(label)
        caption.position = position + SIMD3(0, -Self.orbRadius - 0.028, 0)
        root.addChild(caption)
        return orb
    }

    /// A crescent: a bright disc with a darker one overlapping it, the
    /// universal "shade" mark. Its fill tracks how far the room is dimmed.
    private func dimIcon() -> Entity {
        let icon = Entity()
        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.0025, radius: 0.014),
            materials: [Self.iconMetal(UIColor(white: 0.30, alpha: 1), emissive: 0.04)])
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        icon.addChild(disc)

        // The bite out of it — shown when the room is dimmed at all.
        let bite = ModelEntity(
            mesh: .generateCylinder(height: 0.004, radius: 0.0105),
            materials: [Self.iconMetal(UIColor(white: 0.07, alpha: 1), emissive: 0.0)])
        bite.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        bite.position = [0.007, 0.005, 0.0012]
        dimCrescent = bite
        icon.addChild(bite)
        return icon
    }

    /// A little open book — two thin leaves tilted apart on a spine.
    private func notebookIcon() -> Entity {
        let icon = Entity()
        let leaf = MeshResource.generateBox(size: [0.014, 0.0022, 0.019],
                                            cornerRadius: 0.0012)
        for sign: Float in [1, -1] {
            let page = ModelEntity(mesh: leaf, materials: [
                Self.iconMetal(UIColor(white: 0.82, alpha: 1), emissive: 0.06)])
            page.orientation = simd_quatf(angle: sign * 0.30, axis: [0, 0, 1])
            page.position = [sign * 0.0075, -0.0015, 0]
            icon.addChild(page)
        }
        // The spine, in the module accent.
        var spineMaterial = UnlitMaterial(color: accent)
        spineMaterial.blending = .transparent(opacity: 0.9)
        let spine = ModelEntity(
            mesh: .generateBox(size: [0.0026, 0.0055, 0.019], cornerRadius: 0.0012),
            materials: [spineMaterial])
        icon.addChild(spine)
        // Reading the page as a page: the icon lies flat, facing the user.
        icon.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        return icon
    }

    /// The crescent's bite grows as the room darkens, so the bead reads
    /// its own state at a glance.
    func showDimming(_ level: Double) {
        guard abs(level - showingDimming) > 0.02 else { return }
        showingDimming = level
        dimCrescent.isEnabled = level > 0.02
        let slide = Float(0.004 + 0.006 * (1 - level))
        dimCrescent.position = [slide, 0.005, 0.0012]
    }

    private func attachIcon(_ icon: Entity, to orb: ModelEntity) {
        let pivot = Entity()
        pivot.components.set(BillboardComponent())
        // Ride toward the front of the bead so the icon reads crisply
        // instead of sinking behind a hemisphere of glass.
        icon.position = [0, 0, Self.orbRadius * 0.86]
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
            if candidate.name == "orb-pods" { return .pods }
            if candidate.name == "orb-dim" { return .dim }
            if candidate.name == "orb-capture" { return .capture }
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
