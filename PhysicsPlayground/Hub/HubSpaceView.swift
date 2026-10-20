//  HubSpaceView.swift — the home: the labs standing around the wearer in miniature, each on its
//  own plinth and running its lab's physics in a loop. A pinch on one (a "portal") enters that
//  lab. The home is the end state of the opening (`Opening`): particles that fall, swirl and
//  ripple, then settle onto the plinths' rims. Any pinch skips the opening; Reduce Motion fades
//  the labs in instead.
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
            // `-hubYaw <degrees>` turns the whole home about the wearer, so a
            // portal off the simulator's view can be photographed: 300 brings
            // the leftmost to the front (positive only — a value starting
            // with "-" is read as the next key).
            let yaw = UserDefaults.standard.double(forKey: "hubYaw")
            if yaw != 0 { scene.root.orientation = simd_quatf(angle: Float(yaw) * .pi / 180, axis: [0, 1, 0]) }
            #endif
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
                    deepSpace: Binding(get: { appModel.surroundings == .deepSpace },
                                       set: { appModel.choose($0 ? .deepSpace : .room) }),
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
                    // A pinch on a letter of the wordmark hops it.
                    if scene.hopTitleLetter(value.entity) { return }
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

/// The home's one way to what is secondary: Deep space, the flat lab list
/// (the accessibility path — nothing may be reachable only in space),
/// Settings and About, behind More. They open as one row beneath it, above
/// the portals rather than behind them; the button never moves.
private struct HomeMore: View {
    /// The fixed frame the More stands in, points; the button at its top.
    static let frameHeight: CGFloat = 170
    /// Wide enough for the row of four.
    static let frameWidth: CGFloat = 760
    static let buttonHalfHeight: CGFloat = (ControlMetrics.minimumTarget + 12) / 2

    /// The surroundings: deep space or the room, as every lab's More offers.
    @Binding var deepSpace: Bool
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
                    ControlToggle("Deep space", systemImage: "sparkles", isOn: $deepSpace)
                        .accessibilityHint("Stands you among the stars instead of in your room")
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
        .frame(width: Self.frameWidth, height: Self.frameHeight, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: isExpanded)
        #if DEBUG
        // `-moreOpen 1` unfolds it for a screenshot; the simulator cannot pinch.
        .onAppear {
            if UserDefaults.standard.bool(forKey: "moreOpen") { isExpanded = true }
        }
        #endif
    }
}

/// A portal's name: the system's own type on a glass capsule, with a dot
/// of the lab's colour — crisp at any distance, legible against any wall,
/// and native where extruded neon on a dark pill was not. Never a target:
/// the portal's collider covers it.
private struct PortalLabel: View {
    let title: String
    let accent: Color

    static let fontSize: CGFloat = 36
    static let dot: CGFloat = 14
    static let gap: CGFloat = 10
    static let padding = (horizontal: CGFloat(22), vertical: CGFloat(10))

    var body: some View {
        HStack(spacing: Self.gap) {
            Circle()
                .fill(accent)
                .frame(width: Self.dot, height: Self.dot)
            Text(title)
                .font(.system(size: Self.fontSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, Self.padding.horizontal)
        .padding(.vertical, Self.padding.vertical)
        .glassBackgroundEffect(in: Capsule())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The capsule's size in metres, measured with the font it draws in,
    /// so the portal's target and its measuring proxy fit the real label.
    static func size(for title: String) -> SIMD2<Float> {
        let base = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: fontSize) } ?? base
        let text = (title as NSString).size(withAttributes: [.font: font])
        let width = text.width + dot + gap + 2 * padding.horizontal
        let height = max(text.height, dot) + 2 * padding.vertical
        return SIMD2(ControlMetrics.meters(width), ControlMetrics.meters(height))
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
        /// Everything you see. It floats and grows in; the anchor, which
        /// carries the target, does not.
        let body: Entity
        let label: Entity
        let animate: (Double) -> Void
        /// Each preview runs on its own phase, so the loops never pulse together.
        let phase: Double
        /// The lab on its plinth, turned slowly about `swayAxis` — the
        /// plinth's own normal, through its top centre.
        let sway: Entity
        let swayAxis: SIMD3<Float>
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
    /// The opening's clock — for tests.
    var openingClock: Double { openingTime }

    // MARK: The wordmark

    private let titleAnchor = Entity()
    /// Behind and above the centre of the arc.
    private var titlePosition = SIMD3<Float>(0, 2.12, -2.15)
    private static let titleRimColor = HubTitleStyle.champagne
    /// The lockup's overall width, metres. The machined lines are each scaled to
    /// exactly this; the living wordmark's longer line is.
    private static let titleWidth: Float = 0.52
    /// The living wordmark's leading, as a fraction of a line's height.
    private static let livingLeading: Float = 0.08
    /// The glass round the living wordmark, metres either side and above/below.
    private static let plaquePadding = SIMD2<Float>(0.075, 0.055)
    private var titleLines: [Entity] = []
    /// The wordmark's letters on hinges (`HubTitleGlyphs`), when the
    /// per-letter assets are bundled; nil means the still milled lines.
    private var livingTitle: HubTitleGlyphs?
    /// What the lockup stands on — the glass plaque, or the machined lines'
    /// rule — faded on its own while the letters arrive.
    private var titleRule: Entity?
    /// Whether the letters arrive with this opening (false on a walk back
    /// or under Reduce Motion, where they are simply there).
    private var titleArrives = false
    /// Where the More stands: under the wordmark's footing.
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
        let anchor = Entity()
        anchor.name = module.id
        anchor.position = SIMD3<Float>(slot.position)
        anchor.orientation = simd_quatf(angle: Float(slot.yaw), axis: [0, 1, 0])
        let body = Entity()
        body.name = "portal-body"
        anchor.addChild(body)

        // The lab in miniature, looping its own physics: what the portal says
        // it does. Nothing frames it (2026-10-19, owner's call — the glass
        // circles and their rings read as badges): it stands on its plinth,
        // and every plinth is the same size at the same height, so the row
        // is the frame. The plinth's top centre is the pivot it turns on.
        let built = HubVignettes.make(for: module.id)
        // `fit`'s invisible square, a pose-independent box to measure by;
        // placed by its plinth, the lab needs none, and here it would only
        // stretch the bounds the target is measured against.
        built.entity.findEntity(named: Self.vignetteSquareName)?.removeFromParent()
        let pivot = Entity()
        pivot.name = "portal-plinth"
        pivot.position = [0, -Float(PortalLayout.plinthDrop), 0]
        body.addChild(pivot)
        pivot.addChild(built.entity)
        var axis = SIMD3<Float>(0, 1, 0)
        if let stage = built.entity.findEntity(named: HubVignettes.stageName) {
            let centre = stage.convert(position: .zero, to: built.entity)
            let edge = stage.convert(position: [HubVignettes.stageRadius, 0, 0], to: built.entity)
            let scale = Float(PortalLayout.plinthRadius) / max(simd_distance(centre, edge), 1e-6)
            built.entity.scale = SIMD3(repeating: scale)
            built.entity.position -= stage.position(relativeTo: pivot)
            axis = simd_normalize(stage.convert(direction: [0, 1, 0], to: pivot))
        }

        // Its name under the plinth's front edge: system type on glass, with
        // the lab's colour as a dot. A transparent proxy the label's size
        // stands with it, so the portal's target is measured against the
        // label it covers. It hangs from the anchor, not the floating body:
        // a SwiftUI attachment that moves every frame is laid out again
        // every frame (seven of them were a tenth of the home's main thread),
        // and four millimetres of float is not worth that.
        let plinthLow = built.entity.findEntity(named: HubVignettes.stageName)?
            .visualBounds(relativeTo: body).min.y
            ?? -Float(PortalLayout.plinthDrop + PortalLayout.plinthRadius * 0.3)
        let title = module.shortTitle ?? module.title
        let labelSize = PortalLabel.size(for: title)
        let label = Entity()
        label.name = "portal-label"
        let labelTop = plinthLow - Self.labelGap
        label.position = [0, labelTop - labelSize.y / 2,
                          Float(PortalLayout.plinthRadius) * Self.labelForward]
        label.addChild(ControlAttachment.entity(
            PortalLabel(title: title, accent: module.accent), name: "portal-label-text"))
        let proxy = ModelEntity(
            mesh: Primitives.plane(width: labelSize.x, height: labelSize.y, cornerRadius: 0),
            materials: [Materials.unlit(.white, opacity: 0)])
        proxy.name = "portal-label-extent"
        proxy.components.set(OpacityComponent(opacity: 0))
        label.addChild(proxy)
        anchor.addChild(label)

        // The whole exhibit is the target — the plinth, the lab over its
        // whole motion and its name. `contentExtents` is the lab swept over
        // its cycle and centred on the miniature's origin.
        let radius = Float(PortalLayout.plinthRadius)
        let origin = built.entity.position(relativeTo: body).y
        let contentTop = origin + built.entity.scale.y * built.contentExtents.y / 2
        let top = max(contentTop, pivot.position.y + 0.08) + 0.01
        let bottom = labelTop - labelSize.y
        let width = max(2 * radius + 0.02, labelSize.x)
        let depth = 2 * radius + 0.02
        anchor.components.set(InputTargetComponent())
        anchor.components.set(CollisionComponent(shapes: [
            Primitives.collisionBox(size: [width, top - bottom, depth],
                                    offset: [0, (top + bottom) / 2, 0]),
        ]))
        anchor.components.set(HoverEffectComponent())
        SpatialActions.attach(
            to: anchor,
            label: "\(module.title). \(HubDomain.promise(for: module.id))",
            activate: { [weak self] in self?.onEnter?(module.id) })
        root.addChild(anchor)
        portals.append(Portal(moduleID: module.id, anchor: anchor, body: body,
                              label: label, animate: built.animate, phase: phase,
                              sway: pivot, swayAxis: axis))
    }

    /// `HubVignettes.fit`'s invisible square.
    static let vignetteSquareName = "vignette-square"
    /// From the plinth's lowest point to its name's top edge.
    private static let labelGap: Float = 0.02
    /// How far forward the name hangs, as a share of the plinth's radius:
    /// under its front edge, where a museum puts a plinth's label.
    private static let labelForward: Float = 0.75

    /// The slow turn: each plinth swings ±12° about its own axis over 14 s,
    /// so the lab on it shows its depth — the turntable's turn, never a
    /// spin, and never under stillness. It builds over `swayRise` once the
    /// labs have landed, so nothing jumps.
    private static let swayAmplitude: Float = 0.21
    private static let swayPeriod = 14.0
    private static let swayRise = 2.0
    /// The scene time the turn began from.
    private var swayOrigin = 0.0

    /// How far a portal's plinth is turned at `elapsed` seconds into the turn.
    static func swayAngle(elapsed: Double, phase: Double) -> Float {
        guard elapsed > 0 else { return 0 }
        let x = min(elapsed / swayRise, 1)
        let rise = Float(x * x * (3 - 2 * x))
        return swayAmplitude * rise * Float(sin(2 * .pi * elapsed / swayPeriod + phase * 2.3))
    }

    /// The portals' idle float: a few millimetres over several seconds, so
    /// the home breathes rather than hangs. Never under stillness.
    private static let floatHeight: Float = 0.004
    private static let floatPeriod = 7.5

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
            swayOrigin = time
            presence = Settle.hiddenOpacity
            root.components.set(OpacityComponent(opacity: presence))
            return
        }
        openingPhase = .running
        openingStart = time
        titleArrives = true
        presence = 1

        // The cloud: points of light, not beads — one soft glow sprite
        // (a bright core in a fading halo), turned to face the wearer, in a
        // warm and a cool tint for the two charges. Sizes vary a little, so
        // the sheet has depth instead of reading as a printed pattern.
        let mesh = Primitives.plane(width: Self.particleSpan, height: Self.particleSpan,
                                    cornerRadius: 0)
        let warm = UIColor(red: 1.0, green: 0.70, blue: 0.58, alpha: 1)
        let cool = UIColor(red: 0.62, green: 0.80, blue: 1.0, alpha: 1)
        let mask = Self.glowMask()
        let positive = Self.particleMaterial(warm, mask: mask)
        let negative = Self.particleMaterial(cool, mask: mask)
        for (index, particle) in Opening.particles(for: layout).enumerated() {
            let entity = ModelEntity(mesh: mesh,
                                     materials: [particle.charge > 0 ? positive : negative])
            entity.position = SIMD3<Float>(particle.start)
            entity.components.set(BillboardComponent())
            // A fixed, irregular spread of sizes (golden-ratio steps), 0.7–1.3×.
            let spread = (Double(index) * 0.618_034).truncatingRemainder(dividingBy: 1)
            entity.scale = SIMD3(repeating: Float(0.7 + 0.6 * spread))
            particleRoot.addChild(entity)
            particles.append((entity, particle))
        }
        root.addChild(particleRoot)

        let shield = Self.makeSkipShield()
        root.addChild(shield)
        skipShield = shield

        // The swell and bell start with the clock, once the scene has
        // settled (`animate`); pinned for a still, there is neither.
        updateOpening()
    }

    /// Each particle's sprite, metres across: its bright core is about a
    /// fifth of that — a point of light at two metres — and the rest halo.
    private static let particleSpan: Float = 0.05

    /// How bright the glow is at each radius, centre (0) to edge (1):
    /// a hot core, a soft halo, nothing at the sprite's edge.
    private static let glowStops: [(at: CGFloat, level: CGFloat)] = [
        (0, 1), (0.16, 0.85), (0.34, 0.22), (0.62, 0.06), (1, 0),
    ]

    /// Draws the glow's radial profile into a square image: `colour(level)`
    /// at each stop, on an opaque ground of `colour(0)`.
    private static func radialImage(size: Int, _ colour: (CGFloat) -> UIColor) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size),
                                               format: format)
        let image = renderer.image { context in
            colour(0).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let colours = glowStops.map { colour($0.level).cgColor } as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colours,
                                            locations: glowStops.map(\.at)) else { return }
            let centre = CGPoint(x: size / 2, y: size / 2)
            context.cgContext.drawRadialGradient(
                gradient, startCenter: centre, startRadius: 0,
                endCenter: centre, endRadius: CGFloat(size) / 2, options: [])
        }
        return image.cgImage
    }

    /// The glow's shape as an opacity mask: white where it is lit, black
    /// where it is not. RealityKit reads transparency from a mask like this,
    /// not from a colour texture's alpha (which drew every particle as a
    /// pale square).
    private static func glowMask() -> TextureResource? {
        guard let image = radialImage(size: 128, { UIColor(white: $0, alpha: 1) }) else { return nil }
        return try? TextureResource(image: image, options: .init(semantic: .raw))
    }

    /// The particle's light: its tint, running white-hot at the core.
    private static func particleMaterial(_ tint: UIColor, mask: TextureResource?) -> UnlitMaterial {
        var material = UnlitMaterial(color: tint)
        let hot = radialImage(size: 64) { level in
            // White at the very centre, the tint everywhere the halo is.
            let white = max(0, (level - 0.85) / 0.15)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            tint.getRed(&r, green: &g, blue: &b, alpha: &a)
            return UIColor(red: r + (1 - r) * white, green: g + (1 - g) * white,
                           blue: b + (1 - b) * white, alpha: 1)
        }
        if let hot, let colour = try? TextureResource(image: hot, options: .init(semantic: .color)) {
            material.color = .init(tint: .white, texture: .init(colour))
        }
        if let mask {
            material.blending = .transparent(opacity: .init(scale: 1, texture: .init(mask)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        }
        // Light, not a surface: a sprite that wrote depth cut its whole square
        // out of the room's dimming shell behind it (and out of its neighbours'
        // halos), so each particle stood in a pale, undimmed tile.
        material.writesDepth = false
        return material
    }

    /// Drives every curve of the opening, then clears it away and goes quiet.
    private func updateOpening() {
        guard openingPhase == .running else { return }
        let t = openingTime
        if openingFrozenAt == nil, Opening.isFinished(at: t) {
            finishOpening()
            return
        }
        // Never quite 0 while the clock holds, so the particles are drawn
        // (and ready) before they are seen; see `Settle.hiddenOpacity`.
        let light = openingClockStarted || openingFrozenAt != nil
            ? Opening.particleOpacity(at: t) : Settle.hiddenOpacity
        particleRoot.isEnabled = light > 0.001
        particleRoot.components.set(OpacityComponent(opacity: light))
        if particleRoot.isEnabled {
            for (entity, particle) in particles {
                entity.position = SIMD3<Float>(Opening.position(of: particle, at: t))
            }
        }
        let portalLight = Opening.portalOpacity(at: t)
        let labelLight = Opening.labelOpacity(at: t)
        // The portals grow the last few per cent into place as their glass
        // comes up; the wordmark rises the last few centimetres as it does.
        let growth = SIMD3<Float>(repeating: Opening.portalScale(at: t))
        for portal in portals {
            portal.anchor.components.set(OpacityComponent(opacity: portalLight))
            portal.label.components.set(OpacityComponent(opacity: labelLight))
            portal.body.scale = growth
        }
        if livingTitle != nil {
            // The letters bring themselves in; only their footing fades.
            titleRule?.components.set(OpacityComponent(opacity: labelLight))
        } else {
            titleAnchor.components.set(OpacityComponent(opacity: labelLight))
            titleAnchor.position = titlePosition + SIMD3(0, Opening.titleOffset(at: t), 0)
        }
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
        // The turn carries on from the landing; a skip before it starts it now.
        swayOrigin = min(time, openingStart + Opening.landingTime)
        particleRoot.removeFromParent()
        particleRoot.children.removeAll()
        particles.removeAll()
        skipShield?.removeFromParent()
        skipShield = nil
        for portal in portals {
            portal.anchor.components.remove(OpacityComponent.self)
            portal.label.components.remove(OpacityComponent.self)
            portal.body.scale = .one
        }
        titleAnchor.components.remove(OpacityComponent.self)
        titleAnchor.position = titlePosition
        titleRule?.components.remove(OpacityComponent.self)
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

    func animate(dt rawDt: Double) {
        // Clamped: the first event after the space presents can carry seconds
        // in one delta, which would spend the opening before anyone saw it.
        let dt = min(rawDt, 1.0 / 30.0)
        time += dt
        // Nothing shows until the scene has settled (`Settle`): the frames
        // just after the build run long, and the opening's first particles —
        // or the fade back in from a lab — stuttered through them. Until
        // then the opening's clock holds at zero, where nothing is lit.
        let arrived = settle.tick(dt: rawDt)
        if openingPhase == .running, openingFrozenAt == nil, !openingClockStarted {
            openingStart = time
            if arrived {
                openingClockStarted = true
                // Swell and bell, baked into one WAV whose bell is pinned to
                // the landing — so it starts with the clock, not the build.
                SoundPalette.play(.calibration, on: titleAnchor, volume: 0.55)
                #if DEBUG
                LaunchTrace.mark("[frames] the opening's clock starts")
                #endif
            }
        }
        if arrived { fadePresence(dt: dt) }
        updateOpening()

        // Every portal runs its lab's physics, floats a few millimetres and
        // turns slowly on its plinth, each on its own phase so they never
        // move together. Under stillness they park. The turn waits for the
        // landing, on the opening's clock while it plays (pinned with it
        // for a screenshot).
        let swayElapsed: Double = switch openingPhase {
        case .pending: 0
        case .running: openingTime - Opening.landingTime
        case .done: time - swayOrigin
        }
        for portal in portals {
            portal.animate(stillness ? 0 : time + portal.phase)
            portal.sway.orientation = simd_quatf(
                angle: stillness ? 0 : Self.swayAngle(elapsed: swayElapsed, phase: portal.phase),
                axis: portal.swayAxis)
            portal.body.position.y = stillness ? 0
                : Self.floatHeight * Float(sin(2 * .pi * time / Self.floatPeriod
                                               + portal.phase * 2.1))
        }
        // The living title runs on the opening's clock while it arrives —
        // pinned with it for a screenshot — and on the scene's after.
        livingTitle?.update(
            now: time,
            arrival: titleArrives ? (openingFrozenAt ?? (time - openingStart)) : nil,
            stillness: stillness)
        for (index, line) in titleLines.enumerated() {
            line.orientation = stillness ? simd_quatf(angle: 0, axis: [0, 1, 0])
                : HubTitleStyle.rake(time: time, phase: Double(index) * 1.3)
        }
    }

    /// Whether the scene has taken in its build (`Settle`).
    private var settle = Settle()
    /// Whether the opening's clock has started from its hold at zero.
    private var openingClockStarted = false

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

    /// A pinch on one of the wordmark's letters: it hops. True when it was one.
    func hopTitleLetter(_ entity: Entity) -> Bool {
        livingTitle?.hop(entity, now: time, stillness: stillness) ?? false
    }

    /// The wordmark's letters, when it is alive — for tests.
    var titleLetters: [Entity] { livingTitle?.letterEntities ?? [] }

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
        // Alive if the per-letter assets are there (`HubTitleGlyphs`), else
        // milled, else generated; all three return a centred (entity,
        // extents) pair, so the lockup below is the same for each.
        let living = HubTitleGlyphs()
        let built = lines.map { text in
            living.line(text)
                ?? HubTitleStyle.milled(text, size: reference, accent: nil)
                ?? HubTitleStyle.generated(text, size: reference, accent: nil)
        }
        // The machined plaque forces both lines flush to one width. The living
        // wordmark is set the way every label in the room is: one type size,
        // lines centred, the longer line taking the width.
        let scales: [Float]
        if living.isAlive {
            let widest = built.map(\.extents.x).max() ?? 1
            scales = built.map { _ in Self.titleWidth / max(widest, 1e-4) }
            living.lineScales = scales
            livingTitle = living
        } else {
            scales = built.map { Self.titleWidth / max($0.extents.x, 1e-4) }
        }
        // Cap heights after scaling — a wider scale makes taller letters.
        let heights = zip(built, scales).map { $0.0.extents.y * $0.1 }
        // Leading off the tallest line, not the average — an average-derived gap lets
        // the scaled-up short line collide with its neighbour. Title case carries its
        // own air in its ascenders and descenders, so it needs far less.
        let leading = living.isAlive ? Self.livingLeading : HubTitleStyle.leadingFactor
        let gap = (heights.max() ?? 0) * leading
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

        // What the lockup stands on, which fades in with the portals' glass while
        // the letters bring themselves in. The living wordmark stands on glass,
        // like every label and panel in the room — the glass is also what keeps
        // white letters legible on a white wall. The machined plaque has a thin
        // champagne rule and no backing: its chamfer holds a bright rim on any wall.
        let footing: Entity
        let footingBottom: Float
        if let livingTitle {
            let width = Self.titleWidth + 2 * Self.plaquePadding.x
            let height = blockHeight + 2 * Self.plaquePadding.y
            footing = livingTitle.plaque(width: width, height: height)
            // Behind the letters' backs, so they stand off it.
            footing.position = SIMD3(0, 0, -0.03)
            footingBottom = -height / 2
        } else {
            let ruleMaterial = Materials.unlit(Self.titleRimColor, opacity: 0.65)
            footing = ModelEntity(
                mesh: Primitives.box(width: 0.5, height: 0.004, depth: 0.004,
                                   cornerRadius: 0.002),
                materials: [ruleMaterial])
            footing.position = SIMD3(0, -blockHeight / 2 - 0.09, 0)
            footingBottom = -blockHeight / 2 - 0.09
        }
        titleAnchor.addChild(footing)
        titleRule = footing

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Physics Playground"
        titleAnchor.components.set(accessibility)
        livingTitle?.makeOperable(titleAnchor, label: "Physics Playground",
                                  now: { [weak self] in self?.time ?? 0 },
                                  stillness: { [weak self] in self?.stillness ?? true })
        root.addChild(titleAnchor)

        // The More seat: below the footing with air between them — at 0.06 under
        // the rule the button's glass sat on it — clear of the lockup whatever
        // its metrics.
        moreSeatPosition = titlePosition + SIMD3(0, footingBottom - 0.12, 0.02)
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
