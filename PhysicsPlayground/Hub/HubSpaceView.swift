//  HubSpaceView.swift — the home: six portals standing around the wearer, each running its
//  lab's physics in a loop. A pinch on a portal enters that lab. The home is the end state of
//  the opening (`Opening`): particles that fall, swirl and ripple, then settle onto the
//  portals' rims. Any pinch skips the opening; Reduce Motion fades the portals in instead.
//  Secondary things — the flat lab list, Settings, About — are behind the one More.

import SwiftUI
import RealityKit
import RenderKit

struct HubSpaceView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.openWindow) private var openWindow
    @State private var scene = HubScene()

    var body: some View {
        RealityView { content, attachments in
            let modules = ModuleCatalog.all(appModel: appModel)
            // Stillness first: `build` ends by starting the opening — the
            // decision must exist before the decider.
            scene.stillness = systemReduceMotion
            #if DEBUG
            // `-hubIntro <seconds>` pins the opening at that instant for a
            // screenshot (a large value shows the end state, the home).
            // `double(forKey:)` coerces the argument domain's string.
            let frozen = UserDefaults.standard.double(forKey: "hubIntro")
            if frozen > 0 { scene.openingFrozenAt = frozen }
            #endif
            // Once per session; marked played when the opening finishes, since
            // this closure can run for a view the system discards while presenting.
            scene.openingAlreadyPlayed = appModel.hasPlayedArrival
            scene.onOpeningPlayed = { appModel.hasPlayedArrival = true }
            scene.onEnter = enter
            SoundPalette.warmUp()
            #if DEBUG
            let buildStarted = ContinuousClock.now
            #endif
            scene.build(modules: modules)
            #if DEBUG
            LaunchTrace.mark("home built in "
                             + String(format: "%.2f", (ContinuousClock.now - buildStarted) / .seconds(1))
                             + " s")
            #endif
            content.add(scene.root)
            if let more = attachments.entity(for: "more") {
                scene.seatMore(more)
            }

            // `[weak scene]`: the subscription is stored on the scene, and a strong
            // capture is a cycle that leaks a home animating forever.
            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak scene] event in
                scene?.animate(dt: event.deltaTime)
            }
            // VoiceOver opens a lab directly: activating a portal is pinching it.
            scene.accessibilitySubscriptions = [
                content.subscribe(to: AccessibilityEvents.Activate.self) { event in
                    SpatialActions.activate(event.entity)
                },
            ]
        } update: { _, _ in
            scene.stillness = systemReduceMotion
        } attachments: {
            Attachment(id: "more") {
                HomeMore(
                    // Never a second one — see `AppModel.mainWindowCount`.
                    openCatalog: {
                        if appModel.wantsMainWindow {
                            openWindow(id: MainWindowView.windowID)
                        }
                    },
                    openSettings: { openWindow(id: SettingsView.windowID) },
                    openAbout: { openWindow(id: AboutView.windowID) })
            }
        }
        // The room session starts here, a second after launch, so the World
        // Sensing ask comes while the wearer is at the front door rather than
        // in the middle of a lab.
        .task { await appModel.room.retain() }
        // An EventSubscription is not tied to the view that made it — left alone it
        // keeps animating the off-screen home.
        .onDisappear {
            scene.subscription?.cancel()
            scene.subscription = nil
            scene.accessibilitySubscriptions.forEach { $0.cancel() }
            scene.accessibilitySubscriptions = []
            appModel.room.release()
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // Any pinch during the opening skips to its end.
                    if scene.isOpening {
                        scene.skipOpening()
                        return
                    }
                    guard let id = scene.moduleID(for: value.entity) else { return }
                    enter(id)
                }
        )
    }

    /// How long the chosen portal swells before its lab takes the stage; the
    /// swell and the home's fade both agree with it.
    static let enterDelay: Double = 0.42

    /// One enter path for every caller: the portal swells and the lab takes
    /// over at the peak.
    private func enter(_ id: String) {
        // Reduce Motion: the lab, now — no swell.
        guard !Motion.isReduced else {
            appModel.go(to: id)
            return
        }
        guard scene.beginEnterTransition(id: id) else { return }
        Task {
            try? await Task.sleep(for: .seconds(Self.enterDelay))
            appModel.go(to: id)
        }
    }
}

/// The home's one way to what is secondary: the flat lab list (the
/// accessibility path — nothing may be reachable only in space), Settings
/// and About, behind More. They open as one row beneath it, above the
/// portals rather than behind them; the button never moves.
private struct HomeMore: View {
    /// The fixed frame the More stands in, points; the button at its top.
    static let frameHeight: CGFloat = 170
    static let buttonHalfHeight: CGFloat = (ControlMetrics.minimumTarget + 12) / 2

    let openCatalog: () -> Void
    let openSettings: () -> Void
    let openAbout: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: ControlMetrics.spacing) {
            MoreButton(isExpanded: $isExpanded)
                .padding(6)
                .glassBackgroundEffect(in: Capsule())
            if isExpanded {
                HStack(spacing: ControlMetrics.spacing) {
                    ControlButton("Lab list", systemImage: "list.bullet.rectangle",
                                  action: openCatalog)
                        .accessibilityHint("Opens a flat list of every lab in a window")
                    ControlButton("Settings", systemImage: "gearshape",
                                  action: openSettings)
                        .accessibilityHint("Sound, room tone and the Time Capsule")
                    ControlButton("About", systemImage: "info.circle",
                                  action: openAbout)
                        .accessibilityHint("Credits and version")
                }
                .padding(6)
                .glassBackgroundEffect(in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
        .frame(width: 560, height: Self.frameHeight, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: isExpanded)
        #if DEBUG
        // `-moreOpen 1` unfolds it for a screenshot; the simulator cannot pinch.
        .onAppear {
            if UserDefaults.standard.bool(forKey: "moreOpen") { isExpanded = true }
        }
        #endif
    }
}

/// A portal's pane: stock glass, a shade darker inside so the lab running
/// in front of it has depth. A backdrop, never a target — the portal's own
/// collider takes the pinch.
private struct PortalPane: View {
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(Color.black.opacity(0.22))
            .frame(width: diameter, height: diameter)
            .glassBackgroundEffect(in: Circle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The home's entity graph: the portals, the wordmark, the More seat, and
/// the opening while it plays.
@MainActor
@Observable
final class HubScene {
    let root = Entity()
    var subscription: EventSubscription?
    /// Held for the same reason `subscription` is — see `HubSpaceView.onDisappear`.
    var accessibilitySubscriptions: [EventSubscription] = []

    /// True stills all idle motion and replaces the opening with a fade.
    var stillness = false
    /// `-hubIntro <seconds>` pins the opening clock here.
    var openingFrozenAt: Double?
    /// True when this session has seen the opening — set before `build`.
    var openingAlreadyPlayed = false
    /// Fired the frame the opening completes; the view marks the session.
    var onOpeningPlayed: (() -> Void)?
    /// Opens a lab. Set by the view; reached from a pinch and from VoiceOver.
    var onEnter: ((String) -> Void)?

    private struct Portal {
        let moduleID: String
        let anchor: Entity
        let label: Entity
        let animate: (Double) -> Void
        /// Each preview runs on its own phase, so six loops never pulse together.
        let phase: Double
    }
    private var portals: [Portal] = []
    private var time = 0.0

    // MARK: The opening

    private enum OpeningPhase { case pending, running, done }
    private var openingPhase: OpeningPhase = .pending
    private var openingStart = 0.0
    private let particleRoot = Entity()
    private var particles: [(entity: Entity, particle: Opening.Particle)] = []
    private var skipShield: Entity?

    /// Whether the opening is playing — any pinch then skips it.
    var isOpening: Bool { openingPhase == .running }

    /// The opening's clock: pinned for a screenshot, else real time.
    private var openingTime: Double {
        openingFrozenAt ?? (time - openingStart)
    }

    // MARK: The wordmark

    private let titleAnchor = Entity()
    /// Behind and above the centre of the arc.
    private var titlePosition = SIMD3<Float>(0, 2.12, -2.15)
    private static let titleRimColor = HubTitleStyle.champagne
    /// The lockup's overall width, metres. Both lines are scaled to exactly this.
    private static let titleWidth: Float = 0.52
    private var titleLines: [Entity] = []
    /// Where the More stands: under the wordmark's rule.
    private var moreSeatPosition = SIMD3<Float>(0, 1.80, -2.13)
    private var moreSeat: Entity?
    /// An attachment renders at SwiftUI's natural size (1 pt ≈ 0.74 mm); at
    /// two metres that is a doll's house, so the More stands larger.
    private static let moreScale: Float = 2.3

    // MARK: Build

    func build(modules: [ModuleDescriptor]) {
        // Idempotent: a second call on a surviving scene must not stack a
        // second home on the first.
        root.children.removeAll()
        titleAnchor.children.removeAll()
        portals.removeAll()
        particles.removeAll()
        particleRoot.children.removeAll()

        // Arc order: the two domains, left to right, as the flat catalog lists them.
        let byID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
        let ordered = HubDomain.arcOrder.compactMap { byID[$0] }
            + modules.filter { !HubDomain.arcOrder.contains($0.id) }
        let layout = PortalLayout.portals(count: ordered.count)
        for (index, (module, slot)) in zip(ordered, layout).enumerated() {
            buildPortal(module, at: slot, phase: Double(index) * 0.73)
        }
        buildBubbleTitle()
        beginOpening(layout: layout)
    }

    private func buildPortal(_ module: ModuleDescriptor, at slot: PortalLayout.Portal,
                             phase: Double) {
        let radius = Float(PortalLayout.rimRadius)
        let anchor = Entity()
        anchor.name = module.id
        anchor.position = SIMD3<Float>(slot.position)
        anchor.orientation = simd_quatf(angle: Float(slot.yaw), axis: [0, 1, 0])

        // The pane: glass, behind everything.
        let diameter = CGFloat(2 * radius) * CGFloat(ControlMetrics.pointsPerMeter)
        let pane = ControlAttachment.entity(PortalPane(diameter: diameter),
                                            name: "portal-pane")
        pane.position.z = -0.03
        anchor.addChild(pane)

        // The rim the opening's particles draw: a thin white frame, not a glow —
        // the glow means a hand is on something.
        let points = (0...72).map { step -> SIMD3<Float> in
            let angle = Float(step) / 72 * 2 * .pi
            return SIMD3(cos(angle) * radius, sin(angle) * radius, 0)
        }
        if let mesh = TubeMesh.tube(lines: [points], radius: 0.0035, sides: 6) {
            let rim = ModelEntity(mesh: mesh,
                                  materials: [Materials.unlit(UIColor(white: 0.94, alpha: 1),
                                                              opacity: 0.9)])
            rim.name = "portal-rim"
            anchor.addChild(rim)
        }

        // The lab's own physics, looping: what the portal says it does.
        let built = HubVignettes.make(for: module.id)
        let bounds = built.entity.visualBounds(relativeTo: nil).extents
        let largest = max(bounds.x, max(bounds.y, 1e-4))
        built.entity.scale = SIMD3(repeating: Self.previewSize / largest)
        built.entity.position = [0, 0, 0.03]
        anchor.addChild(built.entity)

        // One short word under it, in the lab's own accent.
        let label = HubScene.namePlate(module.shortTitle ?? module.title,
                                       accent: UIColor(module.accent),
                                       size: PlateStyle.exhibitLabelSize)
        label.position = [0, -(radius + Self.labelDrop), 0.01]
        anchor.addChild(label)

        // The whole portal is the target, its name included.
        let bottom = radius + Self.labelDrop + Float(PlateStyle.exhibitLabelSize)
        let top = radius + 0.01
        anchor.components.set(InputTargetComponent())
        anchor.components.set(CollisionComponent(shapes: [
            Primitives.collisionBox(size: [2 * radius + 0.02, top + bottom, 0.08],
                                    offset: [0, (top - bottom) / 2, 0]),
        ]))
        anchor.components.set(HoverEffectComponent())
        SpatialActions.attach(
            to: anchor,
            label: "\(module.title). \(HubDomain.promise(for: module.id))",
            activate: { [weak self] in self?.onEnter?(module.id) })
        root.addChild(anchor)
        portals.append(Portal(moduleID: module.id, anchor: anchor, label: label,
                              animate: built.animate, phase: phase))
    }

    /// The preview's largest extent, metres — inside the 34 cm rim with air
    /// around it.
    private static let previewSize: Float = 0.22
    /// From the rim to the label's centre: clear of the rim's tube.
    private static let labelDrop: Float = 0.075

    /// Seats the More attachment under the wordmark.
    func seatMore(_ entity: Entity) {
        // The attachment is centred on its entity, and its button sits at the
        // top of a fixed frame: drop it by the distance from the frame's centre
        // to the button's, so the button lands on the seat.
        let lift = ControlMetrics.meters(HomeMore.frameHeight / 2 - HomeMore.buttonHalfHeight)
        entity.position = moreSeatPosition - SIMD3(0, lift * Self.moreScale, 0)
        entity.scale = SIMD3(repeating: Self.moreScale)
        root.addChild(entity)
        moreSeat = entity
        if openingPhase == .running {
            entity.components.set(OpacityComponent(opacity: 0))
        }
    }

    // MARK: The opening

    private func beginOpening(layout: [PortalLayout.Portal]) {
        guard openingPhase == .pending else { return }
        let frozen = openingFrozenAt != nil
        if (stillness || openingAlreadyPlayed) && !frozen {
            // Reduce Motion, or a walk back from a lab: the portals fade in.
            openingPhase = .done
            presence = 0
            return
        }
        openingPhase = .running
        openingStart = time
        presence = 1

        // The cloud: one shared mesh, two charges' worth of light.
        let mesh = Primitives.sphere(radius: Self.particleRadius)
        let positive = Materials.unlit(UIColor(red: 1.0, green: 0.62, blue: 0.56, alpha: 1))
        let negative = Materials.unlit(UIColor(red: 0.58, green: 0.75, blue: 1.0, alpha: 1))
        for particle in Opening.particles(for: layout) {
            let entity = ModelEntity(mesh: mesh,
                                     materials: [particle.charge > 0 ? positive : negative])
            entity.position = SIMD3<Float>(particle.start)
            particleRoot.addChild(entity)
            particles.append((entity, particle))
        }
        root.addChild(particleRoot)

        let shield = Self.makeSkipShield()
        root.addChild(shield)
        skipShield = shield

        // Swell and bell, baked into one WAV whose bell is pinned to the landing.
        if !frozen {
            SoundPalette.play(.calibration, on: titleAnchor, volume: 0.55)
        }
        updateOpening()
    }

    /// Each particle's radius, metres: a point of light at two metres.
    private static let particleRadius: Float = 0.0085

    /// Drives every curve of the opening, then clears it away and goes quiet.
    private func updateOpening() {
        guard openingPhase == .running else { return }
        let t = openingTime
        if openingFrozenAt == nil, Opening.isFinished(at: t) {
            finishOpening()
            return
        }
        let light = Opening.particleOpacity(at: t)
        particleRoot.isEnabled = light > 0.001
        particleRoot.components.set(OpacityComponent(opacity: light))
        if particleRoot.isEnabled {
            for (entity, particle) in particles {
                entity.position = SIMD3<Float>(Opening.position(of: particle, at: t))
            }
        }
        let portalLight = Opening.portalOpacity(at: t)
        let labelLight = Opening.labelOpacity(at: t)
        for portal in portals {
            portal.anchor.components.set(OpacityComponent(opacity: portalLight))
            portal.label.components.set(OpacityComponent(opacity: labelLight))
        }
        titleAnchor.components.set(OpacityComponent(opacity: labelLight))
        moreSeat?.components.set(OpacityComponent(opacity: labelLight))
    }

    /// Any pinch: straight to the home.
    func skipOpening() {
        guard openingPhase == .running else { return }
        openingFrozenAt = nil
        finishOpening()
    }

    private func finishOpening() {
        openingPhase = .done
        particleRoot.removeFromParent()
        particleRoot.children.removeAll()
        particles.removeAll()
        skipShield?.removeFromParent()
        skipShield = nil
        for portal in portals {
            portal.anchor.components.remove(OpacityComponent.self)
            portal.label.components.remove(OpacityComponent.self)
        }
        titleAnchor.components.remove(OpacityComponent.self)
        moreSeat?.components.remove(OpacityComponent.self)
        // The opening has been seen — only now does it count against the session.
        onOpeningPlayed?()
    }

    /// The opening's "any pinch": walls of collider around the wearer, there
    /// only while it plays, so a pinch anywhere lands on something. Named so a
    /// tap on it is never mistaken for a portal.
    static let skipShieldName = "opening-skip"

    private static func makeSkipShield() -> Entity {
        let shield = Entity()
        shield.name = skipShieldName
        // A box room around the wearer: any look ray from inside meets a wall.
        let half: Float = 3.2
        let thin: Float = 0.05
        let span = 2 * half + thin
        let shapes: [ShapeResource] = [
            Primitives.collisionBox(size: [thin, 5, span], offset: [-half, 1.5, 0]),
            Primitives.collisionBox(size: [thin, 5, span], offset: [half, 1.5, 0]),
            Primitives.collisionBox(size: [span, 5, thin], offset: [0, 1.5, -half]),
            Primitives.collisionBox(size: [span, 5, thin], offset: [0, 1.5, half]),
            Primitives.collisionBox(size: [span, thin, span], offset: [0, 4.0, 0]),
            Primitives.collisionBox(size: [span, thin, span], offset: [0, -1.0, 0]),
        ]
        shield.components.set(InputTargetComponent())
        shield.components.set(CollisionComponent(shapes: shapes))
        return shield
    }

    // MARK: Every frame

    func animate(dt: Double) {
        // Clamped: the first event after the space presents can carry seconds
        // in one delta, which would spend the opening before anyone saw it.
        let dt = min(dt, 1.0 / 30.0)
        time += dt
        fadePresence(dt: dt)
        updateOpening()

        // Every portal runs its lab's physics. Under stillness they park.
        for portal in portals {
            portal.animate(stillness ? 0 : time + portal.phase)
        }
        for (index, line) in titleLines.enumerated() {
            line.orientation = stillness ? simd_quatf(angle: 0, axis: [0, 1, 0])
                : HubTitleStyle.rake(time: time, phase: Double(index) * 1.3)
        }
    }

    /// How far the home has faded up, 0…1; the root dissolve that is the
    /// whole entrance under Reduce Motion, and the exit when a lab is chosen.
    private var presence: Float = 1
    private var presenceTarget: Float = 1

    private func fadePresence(dt: Double) {
        guard presence != presenceTarget else { return }
        presence += (presenceTarget - presence) * Float(1 - exp(-dt / 0.18))
        if abs(presence - presenceTarget) < 0.001 { presence = presenceTarget }
        if presence == 1 {
            root.components.remove(OpacityComponent.self)
        } else {
            root.components.set(OpacityComponent(opacity: presence))
        }
    }

    // MARK: Entering

    /// Maps a tapped entity (a portal or any part of it) back to its lab.
    func moduleID(for entity: Entity) -> String? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name == Self.skipShieldName { return nil }
            if portals.contains(where: { $0.anchor === candidate }) {
                return candidate.name
            }
            current = candidate.parent
        }
        return nil
    }

    /// The chosen portal swells toward the wearer while the home fades —
    /// an arrival, not a hard cut. False when nothing should happen.
    @discardableResult
    func beginEnterTransition(id: String) -> Bool {
        guard openingPhase != .running,
              let portal = portals.first(where: { $0.moduleID == id }) else { return false }
        SoundPalette.play(.pop, on: portal.anchor, volume: 0.7)
        presenceTarget = 0
        var target = portal.anchor.transform
        let toward = -simd_normalize(SIMD3(portal.anchor.position.x, 0, portal.anchor.position.z))
        target.translation += toward * 0.25
        target.scale = SIMD3(repeating: 1.35)
        portal.anchor.move(to: target, relativeTo: root,
                           duration: HubSpaceView.enterDelay, timingFunction: .easeIn)
        return true
    }

    /// The portals, in arc order — for tests and the debug arguments.
    var portalIDs: [String] { portals.map(\.moduleID) }
    /// A portal's anchor, by lab.
    func portal(_ id: String) -> Entity? {
        portals.first { $0.moduleID == id }?.anchor
    }

    // MARK: The 3-D bubble title

    private func buildBubbleTitle() {
        titleAnchor.position = titlePosition

        let lines = ["Physics", "Playground"]
        // Build at a reference size, then scale to the common width. Extents come from
        // what was built (the milled asset's numbers, not the font's).
        let reference: CGFloat = 0.17
        // Milled if the asset is there, generated if not; both return a centred
        // (entity, extents) pair.
        let built = lines.map { text in
            HubTitleStyle.milled(text, size: reference, accent: nil)
                ?? HubTitleStyle.generated(text, size: reference, accent: nil)
        }
        let scales = built.map { Self.titleWidth / max($0.extents.x, 1e-4) }
        // Cap heights after scaling — a wider scale makes taller letters.
        let heights = zip(built, scales).map { $0.0.extents.y * $0.1 }
        // Leading off the tallest line, not the average — an average-derived gap lets
        // the scaled-up short line collide with its neighbour.
        let gap = (heights.max() ?? 0) * HubTitleStyle.leadingFactor
        let blockHeight = heights.reduce(0, +) + gap * Float(heights.count - 1)

        // Walk down from the block's top, so the lockup centres on the anchor.
        var cursor = blockHeight / 2
        for (index, item) in built.enumerated() {
            let scale = scales[index]
            let height = heights[index]
            item.entity.scale = SIMD3(repeating: scale)
            item.entity.position.y = cursor - height / 2
            titleAnchor.addChild(item.entity)
            cursor -= height + gap
        }
        // Kept for the rake. The lines turn, not the anchor.
        titleLines = built.map(\.entity)

        // A thin champagne rule under the lockup. No backing plate: the milled
        // chamfer holds a bright rim against a wall of any brightness.

        let ruleMaterial = Materials.unlit(Self.titleRimColor, opacity: 0.65)
        let rule = ModelEntity(
            mesh: Primitives.box(width: 0.5, height: 0.004, depth: 0.004,
                               cornerRadius: 0.002),
            materials: [ruleMaterial])
        rule.position = SIMD3(0, -blockHeight / 2 - 0.09, 0)
        titleAnchor.addChild(rule)

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Physics Playground"
        titleAnchor.components.set(accessibility)
        root.addChild(titleAnchor)

        // The More seat: below the rule, clear of the lockup whatever its metrics.
        moreSeatPosition = titlePosition + SIMD3(0, -blockHeight / 2 - 0.15, 0.02)
    }

}

// MARK: The house type

extension HubScene {
    /// Measured size of a run of the title face. Internal, not private:
    /// `HubDomainTitle` uses the same lockup math.
    static func textExtents(_ text: String, size: CGFloat) -> SIMD3<Float> {
        bubbleMesh(text, size: size).bounds.extents
    }

    /// Bubble-type meshes by content and size: measuring a label and
    /// building it are the same mesh, and every nameplate did both.
    /// Bounded, like `Callout`'s glyph cache.
    private static var bubbleMeshes: [String: MeshResource] = [:]

    private static func bubbleMesh(_ text: String, size: CGFloat) -> MeshResource {
        let key = "\(size)|\(text)"
        if let cached = bubbleMeshes[key] { return cached }
        let mesh = MeshResource.generateText(
            text, extrusionDepth: Float(size) * 0.45,
            font: roundedFont(size: size), alignment: .center)
        if bubbleMeshes.count > 400 { bubbleMeshes.removeAll(keepingCapacity: true) }
        bubbleMeshes[key] = mesh
        return mesh
    }

    /// The app's signature 3-D bubble type: heavy rounded glyphs extruded and clear-coated,
    /// centred on both axes, returned as a group. `opacity` < 1 = smoky glass; `emissive` = glow.
    static func bubbleText(_ text: String, size: CGFloat, color: UIColor,
                           opacity: Float = 1, emissive: Float = 0.28) -> Entity {
        let group = Entity()
        let mesh = bubbleMesh(text, size: size)
        let bounds = mesh.bounds
        let centerX = -(bounds.min.x + bounds.max.x) / 2
        let centerY = -(bounds.min.y + bounds.max.y) / 2

        var glossy = Materials.glossy(color, glow: emissive)
        if opacity < 1 {
            glossy.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        let letters = ModelEntity(mesh: mesh, materials: [glossy])
        letters.position = [centerX, centerY, 0]
        group.addChild(letters)
        return group
    }

    /// SF Rounded at a heavy weight — what makes the extruded text read as bubbles.
    private static func roundedFont(size: CGFloat) -> MeshResource.Font {
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    /// How wide the pill `namePlate` will build for this text — the plate
    /// is centred on its own origin, so a caller mounting a label beside
    /// something needs its reach.
    static func namePlateWidth(_ text: String, size: CGFloat = 0.036) -> Float {
        textExtents(text, size: size).x + Float(size) * 0.72 * 2
    }

    /// A nameplate, optionally wrapped: an unwrapped sentence runs through
    /// the neighbouring exhibits.
    static func namePlate(_ text: String, accent: UIColor,
                          size: CGFloat = 0.036,
                          wrapWidth: CGFloat = 0,
                          backed: Bool = true) -> Entity {
        let plate = Entity()

        let extents = wrapWidth > 0
            ? Callout.textMesh(text, size: size, wrapWidth: wrapWidth).bounds.extents
            : textExtents(text, size: size)
        // Padding scales with the type, or a 10 mm label wears a plate sized
        // for 36 mm.
        let padY = Float(size) * 0.44
        let width = wrapWidth > 0
            ? extents.x + Float(size) * 0.72 * 2
            : namePlateWidth(text, size: size)
        let height = extents.y + padY * 2

        // `backed: false` is the exhibit titles' setting: a card behind each
        // gallery name blocked the room. The card stays for small apparatus
        // labels, which sit on instruments.
        if backed {
            let backing = Materials.unlit(UIColor(white: 0.02, alpha: 1), opacity: 0.58)
            // `height / 2` is a pill for one line and a lozenge for several, and a
            // lozenge's ends eat the first and last words of every line.
            let card = ModelEntity(
                mesh: Primitives.plane(width: width, height: height,
                                     cornerRadius: min(height / 2,
                                                       Float(size) * 1.2)),
                materials: [backing])
            card.position.z = -0.006
            plate.addChild(card)
        }

        if wrapWidth > 0 {
            // Wrapped runs use a flat mesh: the bubble builder is one line of
            // display type.
            let mesh = Callout.textMesh(text, size: size, wrapWidth: wrapWidth)
            var material = UnlitMaterial(color: accent)
            material.blending = .opaque
            let run = ModelEntity(mesh: mesh, materials: [material])
            let bounds = mesh.bounds
            run.position = [-(bounds.min.x + bounds.max.x) / 2,
                            -(bounds.min.y + bounds.max.y) / 2, 0]
            plate.addChild(run)
        } else {
            plate.addChild(bubbleText(text, size: size,
                                      color: accent, emissive: 0.6))
        }
        return plate
    }

}
