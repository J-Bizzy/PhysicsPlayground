//  HubSpaceView.swift — the gallery: two domain terraces of live miniatures under the wordmark.
//  One door, reached two ways: tap flies an exhibit to the pad, or carry it there; neither
//  enters — the Load button over the pad is the only thing that opens a lab (VoiceOver goes
//  straight in). Geometry lives in GalleryLayout; vignettes keyed by module id with a fallback.

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
            // Stillness first: `build` ends by starting the intro — the decision
            // must exist before the decider.
            scene.stillness = systemReduceMotion
            #if DEBUG
            // `-hubIntro <seconds>` freezes the arrival for screenshots. Read before `build` —
            // `beginIntro` decides the once-per-session skip and the chime off this value.
            // `double(forKey:)` coerces the argument domain's string.
            let frozenIntro = UserDefaults.standard.double(forKey: "hubIntro")
            if frozenIntro > 0 {
                scene.introFrozenAt = frozenIntro
            }
            #endif
            // Once per session; marked played when the intro finishes, since this
            // closure can run for a view the system discards while presenting.
            scene.arrivalAlreadyPlayed = appModel.hasPlayedArrival
            scene.onArrivalPlayed = { appModel.hasPlayedArrival = true }
            SoundPalette.warmUp()
            #if DEBUG
            let buildStarted = ContinuousClock.now
            #endif
            scene.build(modules: modules)
            #if DEBUG
            LaunchTrace.mark("gallery built in "
                             + String(format: "%.2f", (ContinuousClock.now - buildStarted) / .seconds(1))
                             + " s")
            #endif
            scene.placement = appModel.galleryPlacement
            content.add(scene.root)

            if let load = attachments.entity(for: "load") {
                // Load button hangs over the podium, shown only while an exhibit stands there.
                load.components.set(BillboardComponent())
                load.isEnabled = false
                scene.root.addChild(load)
                scene.loadButton = load
                // After the assignment — seating reads `loadButton`; the other order silently does nothing.
                scene.seatLoadButton()
            }
            if let bar = attachments.entity(for: "bar") {
                scene.seatTitleBar(bar)
            }
            #if DEBUG
            // `-hubDock <module id>` seats an exhibit at launch for CLI screenshots.
            if let forced = UserDefaults.standard.string(forKey: "hubDock") {
                scene.dockForDebug(id: forced)
            }
            #endif

            // `[weak scene]`: the subscription is stored on the scene, and a strong
            // capture is a cycle that leaks a gallery animating forever.
            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak scene] event in
                scene?.animate(dt: event.deltaTime, lookRay: appModel.room.lookRay)
            }

            // VoiceOver opens a lab directly — no pad ceremony.
            // `SpatialActions.activate` walks ancestors, as in every lab.
            scene.onEnter = enter
            scene.accessibilitySubscriptions = [
                content.subscribe(to: AccessibilityEvents.Activate.self) { event in
                    SpatialActions.activate(event.entity)
                },
                content.subscribe(to: AccessibilityEvents.CustomAction.self) { event in
                    guard event.key.key == Self.enterAction.key,
                          let id = scene.moduleID(for: event.entity) else { return }
                    enter(id)
                },
            ]
        } update: { _, _ in
            scene.stillness = systemReduceMotion
        } attachments: {
            Attachment(id: "bar") {
                HubUtilityBar(
                    openSettings: { openWindow(id: SettingsView.windowID) },
                    openAbout: { openWindow(id: AboutView.windowID) },
                    openNotebook: { openWindow(id: NotebookView.windowID) },
                    // Never a second one — see `AppModel.mainWindowCount`.
                    openCatalog: {
                        if appModel.wantsMainWindow {
                            openWindow(id: MainWindowView.windowID)
                        }
                    })
            }
            Attachment(id: "load") {
                if let module = ModuleCatalog.all(appModel: appModel)
                    .first(where: { $0.id == scene.dockedModuleID }) {
                    HubLoadButton(module: module) { enter(module.id) }
                }
            }
        }
        // `room.lookRay` only exists while the reference-counted ARKit session runs —
        // the hub must retain it itself, or `lookRay` is nil forever on device.
        .task { await appModel.room.retain() }
        // An EventSubscription is not tied to the view that made it — left alone it keeps
        // animating the off-screen hub and holds the exhibit graph alive.
        .onDisappear {
            scene.subscription?.cancel()
            scene.subscription = nil
            scene.accessibilitySubscriptions.forEach { $0.cancel() }
            scene.accessibilitySubscriptions = []
            // Nothing else clears an in-flight carry: without this it survives in `scene`
            // and every later drag re-targets the same exhibit.
            scene.cancelExhibitDrag()
            appModel.room.release()
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // A tap sends the lab to the pad — it moves an object, never enters;
                    // the door stays the Load button's second, deliberate pinch.
                    guard let id = scene.moduleID(for: value.entity) else { return }
                    scene.sendToPad(id: id)
                }
        )
        // Carry a lab to the podium — or the whole gallery by its bar. The bar branch
        // comes first: a hand on the handle is moving the room, not shopping for a lab.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0.015)
                .targetedToAnyEntity()
                .onChanged { value in
                    let world = SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene))
                    if barDrag != nil || HubScene.isGalleryBar(value.entity) {
                        dragGalleryBar(worldHand: world)
                        return
                    }
                    if !scene.isCarrying {
                        _ = scene.beginExhibitDrag(entity: value.entity, world: world)
                    }
                    scene.dragExhibit(world: world)
                }
                .onEnded { _ in
                    if barDrag != nil {
                        endGalleryBarDrag()
                        return
                    }
                    scene.endExhibitDrag()
                }
        )
    }

    /// Gallery bar drag session (LabAnchorView pattern): RelativeDrag on the placement
    /// offset; a press that never moves folds into a tap that recentres.
    @State private var barDrag: RelativeDrag?
    @State private var barTravelled: Float = 0
    /// How far a press may wander and still count as a tap, metres.
    private static let barTapTravel: Float = 0.012

    private func dragGalleryBar(worldHand: SIMD3<Float>) {
        let hand = SIMD3<Double>(worldHand)
        let placement = appModel.galleryPlacement
        if barDrag == nil {
            barDrag = RelativeDrag(name: HubScene.galleryBarName,
                                   target: SIMD3<Double>(placement.offset),
                                   hand: hand)
        }
        guard let barDrag else { return }
        let next = SIMD3<Float>(barDrag.position(forHand: hand))
        // Against the drag's own start (`RelativeDrag.travel`) — measuring against
        // `placement.offset` (overwritten next line) read a real move as a tap.
        barTravelled = max(barTravelled, Float(barDrag.travel(forHand: hand)))
        placement.move(to: next)
    }

    private func endGalleryBarDrag() {
        if barTravelled < Self.barTapTravel {
            // A tap: home, facing the wearer if the room knows where they are looking.
            let yaw = appModel.room.lookRay.map { ray in
                atan2(-Float(ray.direction.x), -Float(ray.direction.z))
            }
            appModel.galleryPlacement.recentre(facing: yaw)
        }
        barDrag = nil
        barTravelled = 0
    }

    /// VoiceOver's "open this lab" action. Matched on `.key` — the delivered resource is
    /// not the same instance. One constant declares and recognises, so the two cannot drift.
    static let enterAction = LocalizedStringResource("Enter")

    /// How long the exhibit swells before the module takes the stage; the
    /// swell and the gallery's fade both agree with it.
    static let enterDelay: Double = 0.42

    /// One enter path for every caller: the exhibit swells and the module takes over at the peak.
    private func enter(_ id: String) {
        // Reduce Motion: the lab, now — no swell.
        guard !Motion.isReduced else {
            appModel.go(to: id)
            return
        }
        scene.beginEnterTransition(id: id)
        Task {
            try? await Task.sleep(for: .seconds(Self.enterDelay))
            appModel.go(to: id)
        }
    }
}

/// The hub's entity graph and idle animation state.
@MainActor
@Observable
final class HubScene {
    let root = Entity()
    var subscription: EventSubscription?
    /// Held for the same reason `subscription` is — see `HubSpaceView.onDisappear`.
    var accessibilitySubscriptions: [EventSubscription] = []

    private struct Exhibit {
        let moduleID: String
        let anchor: Entity      // ring position (bobbed every frame)
        let pulser: Entity      // scale pulse on selection
        let vignette: Entity    // slowly rotating miniature
        let label: Entity       // its name, lit on the bench's front edge
        let halo: Entity        // accent glow, focused only
        let basePosition: SIMD3<Float>
        /// The animation the miniature was built with — captured alongside its geometry so
        /// model and motion cannot drift (name-matched tables silently skipped asset-loaded models).
        let animate: (Double) -> Void
        /// 0 = resting in the ring, 1 = the one you are facing. Eased.
        var focus: Float = 0
        /// This exhibit's own clock: a touch fast while focused, paused while out of view.
        var animTime: Double = 0
        /// Set by updateFocus: near enough to the look direction to be worth animating.
        var inView: Bool = true
        /// Focus value the opacity components were last written at; -1 forces
        /// a rewrite (the special states park it there so their first idle
        /// frame repaints).
        var appliedFocus: Float = -1
        /// The label's brightness, eased toward `labelTarget`, and the value
        /// its opacity was last written at.
        var labelLevel: Float = HubScene.labelRest
        var appliedLabelLevel: Float = -1
    }

    /// True stills all idle motion. Set from Reduce Motion (system or in-app).
    var stillness = false

    /// Which exhibit the user faces — published only on change, never at 60 Hz.
    private(set) var focusedModuleID: String?
    private var exhibits: [Exhibit] = []
    private var time = 0.0

    // MARK: The arrival

    /// Everything but the wordmark, under one entity so the intro raises the room as a
    /// unit. Identity transform — reparenting changes no coordinates.
    private let stageRoot = Entity()
    private enum IntroPhase { case pending, running, done }
    /// Once per scene: a placement rebuild must not replay the theatre.
    private var introPhase: IntroPhase = .pending
    private var introStart = 0.0
    /// `-hubIntro <seconds>` pins the intro clock here — frozen it never finishes;
    /// that is the point of a photograph.
    var introFrozenAt: Double?
    /// True when this session has seen the ceremony — set from `AppModel` before `build`
    /// (the scene is remade on every hub entry). A frozen screenshot intro overrides it.
    var arrivalAlreadyPlayed = false
    /// Fired the frame the ceremony completes — the view marks `hasPlayedArrival` off this
    /// and only this, so a discarded pre-presentation build can never spend the arrival.
    var onArrivalPlayed: (() -> Void)?

    /// The intro's clock: frozen for screenshots, infinite (= finished) under stillness.
    private var introTime: Double {
        stillness ? .infinity : (introFrozenAt ?? (time - introStart))
    }
    /// The 3-D bubble title the exhibits ring, bobbing at the centre.
    private let titleAnchor = Entity()

    // MARK: Layout — the Gallery
    // Geometry authored and computed in GalleryLayout; defaults 2.0 m and 1.4 m.

    private var arcRadius: Float = 2.0
    private var arcHeight: Float = 1.4

    /// Every miniature is normalised to this world size — constant apparent size would throw depth away.
    private static let exhibitSize: Float = 0.24

    /// The graphite the terraces and pucks are cut from.
    private static let slabTint = UIColor(white: 0.09, alpha: 1)

    // MARK: Focus
    // Head direction, not eye gaze — visionOS never hands an app the eyes.
    // The faced exhibit grows, lifts and lights its halo.

    /// Max angle off the look direction that still takes focus, radians.
    private static let focusCone: Float = 26 * .pi / 180
    /// A challenger must be this fraction closer than the incumbent before focus jumps —
    /// hysteresis, so a scanning glance doesn't strobe the ring.
    private static let focusStickiness: Float = 0.72
    /// Resting scale of an unfocused exhibit once any is focused, and the focused growth.
    private static let unfocusedScale: Float = 0.90
    private static let focusedScale: Float = 1.22
    /// How far the focused exhibit lifts off its puck.
    private static let focusedLift: Float = 0.09

    // MARK: Build

    /// Fixed build geometry — moving the gallery is a transform (grab bar), never a rebuild.
    private static let arcDistanceDefault: Float = 2.0
    private static let arcHeightDefault: Float = 1.4

    func build(modules: [ModuleDescriptor]) {
        // Idempotent on purpose: `build` is additive below, and a second call on a
        // surviving scene used to stack a second gallery on top of the first.
        root.children.removeAll()
        titleAnchor.children.removeAll()
        exhibits.removeAll()
        terraceHairlines.removeAll()
        domainTitles.removeAll()

        let distance = Self.arcDistanceDefault
        arcRadius = distance
        arcHeight = Self.arcHeightDefault

        // 0.66 clears the main window's top edge at the default placement (the catalog
        // stays visible while the gallery is open); some overlap is inherent since the
        // wearer can move the window.
        titlePosition = SIMD3(0, arcHeight + 0.66, -(arcRadius + 0.45))
        buildBubbleTitle()
        buildPodium(distance: distance)
        buildGalleryBar(distance: distance)

        // Each terrace carries its domain's 3-D signage (HubDomainTitle).
        let byID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
        benchLabels.removeAll()
        for terrace in GalleryLayout.terraces(moduleIDs: modules.map(\.id),
                                              distance: distance,
                                              height: arcHeight) {
            buildTerrace(terrace, modules: byID)
            for (index, id) in terrace.moduleIDs.enumerated() {
                guard let module = byID[id] else { continue }
                buildExhibit(for: module,
                             at: terrace.exhibitPositions[index])
            }
        }

        // Furniture under one entity so the arrival raises it as a unit.
        // Exhibits and door signs stay top-level: they cascade on their own
        // components, and the tap chain resolves exhibits as children of root.
        stageRoot.children.removeAll()
        let independents = Set(
            [ObjectIdentifier(titleAnchor), ObjectIdentifier(stageRoot)]
            + exhibits.map { ObjectIdentifier($0.anchor) }
            + domainTitles.values.map { ObjectIdentifier($0.root) })
        for child in Array(root.children)
        where !independents.contains(ObjectIdentifier(child)) {
            stageRoot.addChild(child)
        }
        root.addChild(stageRoot)
        beginIntro()
    }

    /// Starts the arrival — once per scene, and never under Reduce Motion (its entrance
    /// is the root dissolve `fadeIn` already provides).
    private func beginIntro() {
        guard introPhase == .pending else { return }
        guard !stillness else { introPhase = .done; return }
        if arrivalAlreadyPlayed && introFrozenAt == nil {
            introPhase = .done
            return
        }
        introPhase = .running
        introStart = time
        // Hidden before the first frame draws, so nothing pops in ahead of its cue.
        titleAnchor.components.set(OpacityComponent(opacity: 0))
        stageRoot.components.set(OpacityComponent(opacity: 0))
        for exhibit in exhibits {
            exhibit.anchor.components.set(OpacityComponent(opacity: 0))
        }
        for title in domainTitles.values {
            title.root.components.set(OpacityComponent(opacity: 0))
        }
        // Swell + bell are baked into one WAV whose timing HubIntroTests pins to this
        // choreography; not played for a frozen screenshot intro.
        if introFrozenAt == nil {
            SoundPalette.play(.calibration, on: titleAnchor, volume: 0.55)
        }
    }

    /// Drives every intro curve, then removes its components and goes
    /// quiet — the per-frame path stops touching what stopped changing.
    private func updateIntro() {
        guard introPhase == .running else { return }
        // A frozen intro never finishes — without this exemption `-hubIntro` past the
        // landing shot the completed room. Stillness still wins, frozen or not.
        let t = introTime
        if introFrozenAt == nil || stillness,
           HubIntro.isFinished(at: t, exhibitCount: exhibits.count) {
            introPhase = .done
            titleAnchor.components.remove(OpacityComponent.self)
            stageRoot.components.remove(OpacityComponent.self)
            for exhibit in exhibits {
                exhibit.anchor.components.remove(OpacityComponent.self)
                exhibit.anchor.scale = .one
            }
            for title in domainTitles.values {
                title.root.components.remove(OpacityComponent.self)
            }
            // The bar sat out the flight; re-enable on landing.
            titleBar?.isEnabled = true
            // The ceremony has been seen — only now does it count against the session.
            onArrivalPlayed?()
            return
        }
        titleAnchor.components.set(
            OpacityComponent(opacity: HubIntro.titleOpacity(at: t)))
        stageRoot.components.set(
            OpacityComponent(opacity: HubIntro.stageOpacity(at: t)))
        for (index, exhibit) in exhibits.enumerated() {
            // A docked or carried lab belongs to that interaction; forcing arrival
            // opacity landed it on the pad invisible.
            if exhibit.moduleID == dockedModuleID
                || exhibit.moduleID == draggingID {
                exhibit.anchor.components.remove(OpacityComponent.self)
                exhibit.anchor.scale = .one
                continue
            }
            exhibit.anchor.components.set(OpacityComponent(
                opacity: HubIntro.exhibitOpacity(slot: index, at: t)))
            exhibit.anchor.scale = SIMD3(
                repeating: HubIntro.exhibitScale(slot: index, at: t))
        }
        for title in domainTitles.values {
            title.root.components.set(
                OpacityComponent(opacity: HubIntro.signOpacity(at: t)))
        }
    }

    // MARK: Terraces

    /// Each terrace's hairline, kept for the enter flare and shimmer.
    private var terraceHairlines: [HubDomain: ModelEntity] = [:]
    /// Each terrace's signage, driven from the idle loop.
    private var domainTitles: [HubDomain: HubDomainTitle] = [:]
    /// Every exhibit's name on its bench, by module id — built with the
    /// terrace, handed to the exhibit when it is built.
    private var benchLabels: [String: Entity] = [:]

    // MARK: Bench labels

    /// The label's brightness at rest, facing it, and while its lab stands on
    /// the pad (an empty mount still says what belongs there).
    nonisolated static let labelRest: Float = 0.78
    nonisolated static let labelFocused: Float = 1.0
    nonisolated static let labelAway: Float = 0.32
    /// The type's point size — the house exhibit size. The face is 55 mm of
    /// graphite and this is ~28 mm ascender to descender, so the words sit on
    /// the stock with air above and below; at 33 mm "Orbital Mechanics" ran
    /// to the ends of its bay.
    nonisolated static let benchLabelSize: CGFloat = PlateStyle.exhibitLabelSize

    /// One domain's terrace: an optical bench tiled from modelled bays, a lit
    /// domain-colour hairline in the channel along its front edge, a mount per
    /// module, and under each mount, on the bench's front edge, the lab's name.
    private func buildTerrace(_ terrace: GalleryLayout.Terrace,
                              modules: [String: ModuleDescriptor]) {
        let slab = Entity()
        slab.position = terrace.center
        slab.orientation = simd_quatf(angle: terrace.yaw, axis: [0, 1, 0])
        buildBenchTop(terrace, on: slab)

        let lit = Materials.unlit(UIColor(terrace.domain.color), opacity: 0.85)
        let hairline = ModelEntity(
            mesh: Primitives.box(width: max(terrace.width - 0.05, 0.1),
                               height: 0.004, depth: 0.004,
                               cornerRadius: 0.002),
            materials: [lit])
        // In the milled channel, not proud of the surface — a light in a trough reads
        // as a light pipe.
        hairline.position = SIMD3(0, GalleryLayout.slabThickness / 2 - 0.002,
                                  GalleryLayout.slabDepth / 2 - 0.0095)
        slab.addChild(hairline)
        terraceHairlines[terrace.domain] = hairline

        // Child of the slab so it inherits the terrace yaw. High enough that a
        // focus-lifted exhibit (~0.31 above the slab) clears the sign's rule.
        let title = HubDomainTitle(domain: terrace.domain,
                                   width: terrace.width * 0.54)
        title.root.position = SIMD3(0, 0.62, -0.02)
        slab.addChild(title.root)
        domainTitles[terrace.domain] = title

        // The names live on the bench, not over the exhibits: lit type on the
        // dark front edge holds against any wall (the bench is the backing a
        // floating card was refused for), and it never moves, so a lifted or
        // docked exhibit cannot carry its name into the door sign or away.
        let unyaw = simd_quatf(angle: -terrace.yaw, axis: [0, 1, 0])
        for (index, id) in terrace.moduleIDs.enumerated() {
            guard let module = modules[id],
                  index < terrace.puckTops.count else { continue }
            let local = unyaw.act(terrace.puckTops[index] - terrace.center)
            let label = Self.benchLabel(module.title, accent: UIColor(module.accent))
            label.position = SIMD3(local.x, 0, Self.benchFace)
            label.components.set(OpacityComponent(opacity: Self.labelRest))
            slab.addChild(label)
            benchLabels[id] = label
        }
        root.addChild(slab)

        for top in terrace.puckTops {
            // Placed at the top face: modelled platforms hang below their own origin.
            let mount = Self.loadPlatform(
                "GalleryMount",
                fallback: {
                    let puck = ModelEntity(
                        mesh: Primitives.cylinder(
                            height: GalleryLayout.puckHeight,
                            radius: GalleryLayout.puckRadius),
                        materials: [Materials.graphite(Self.slabTint)])
                    puck.position.y = -GalleryLayout.puckHeight / 2
                    let holder = Entity()
                    holder.addChild(puck)
                    return holder
                })
            mount.position = top
            root.addChild(mount)
        }
    }

    /// Tiles the terrace top: two end caps + one bay per module
    /// (`Tools/galleryplatforms.py`). Tiles, not one stretched slab:
    /// stretching a drilled bench turns every hole into an ellipse.
    private func buildBenchTop(_ terrace: GalleryLayout.Terrace,
                               on slab: Entity) {
        let capWidth = GalleryLayout.baseWidthMargin / 2
        let bays = max(terrace.moduleIDs.count, 1)
        let bayWidth = (terrace.width - capWidth * 2) / Float(bays)

        // The fallback is A real shelf (cf. `TimeRail.buildReel`): a missing floor under
        // six exhibits is six labs hanging in the air.
        guard let bay = PropCache.prototype(named: "GalleryBay"),
              let cap = PropCache.prototype(named: "GalleryCap") else {
            let box = ModelEntity(
                mesh: Primitives.box(width: terrace.width,
                                   height: GalleryLayout.slabThickness,
                                   depth: GalleryLayout.slabDepth,
                                   cornerRadius: 0.03),
                materials: [Materials.graphite(Self.slabTint)])
            slab.addChild(box)
            return
        }

        // Tiles are modelled with the top face at origin; the slab node sits at
        // mid-thickness, so everything hangs from its top.
        let top = GalleryLayout.slabThickness / 2
        for index in 0..<bays {
            let piece = bay.clone(recursive: true)
            piece.scale.x = bayWidth / GalleryLayout.basePuckPitch
            piece.position = SIMD3(
                -terrace.width / 2 + capWidth
                    + bayWidth * (Float(index) + 0.5),
                top, 0)
            slab.addChild(piece)
        }
        for side in [Float(-1), 1] {
            let piece = cap.clone(recursive: true)
            piece.position = SIMD3(
                side * (terrace.width / 2 - capWidth / 2), top, 0)
            slab.addChild(piece)
        }
    }

    /// A modelled platform cloned from the shared `PropCache` — one parse, many clones.
    private static func loadPlatform(_ name: String,
                                     fallback: () -> Entity) -> Entity {
        PropCache.instance(named: name) ?? fallback()
    }

    // MARK: The podium — where a lab is brought to be opened

    /// Plate thickness is the terrace puck's, so a docked exhibit stands at
    /// the clearance it had on its puck. `podium` names the docking spot;
    /// wearer-facing copy says "pad".
    private static let podiumPlateHeight: Float = 1.05
    private static let podiumPlateThickness: Float = GalleryLayout.puckHeight
    private static let podiumRadius: Float = 0.105
    /// How far the hover ring hangs below the plate.
    private static let podiumHoverGap: Float = 0.045
    /// Distance out from the user at the 2.0 m arc default; scales with it.
    private static let podiumReach: Float = 1.35
    /// Load button lift over a docked exhibit. The gap that matters is to the button's
    /// Bottom edge, measured from the top of the header name riding 0.215 above the lab.
    private static let podiumButtonLift: Float = 0.30
    /// Dock-offer radius.
    private static let podiumSnapRadius: Float = 0.34

    /// Hangs the Load button over whatever stands on the podium.
    func seatLoadButton() {
        loadButton?.position = podiumTop + SIMD3(0, Self.podiumButtonLift, 0)
    }

    /// Where the docked exhibit centres, root space.
    private(set) var podiumTop = SIMD3<Float>(
        0,
        podiumPlateHeight + podiumPlateThickness + GalleryLayout.exhibitLift,
        -podiumReach)
    private var podiumGlow: Entity?
    /// The exhibit standing on the podium, ready to load.
    private(set) var dockedModuleID: String?
    /// The SwiftUI "Load Module" button, shown while something is docked.
    var loadButton: Entity?
    /// The exhibit currently riding a hand.
    private var draggingID: String?
    var isCarrying: Bool { draggingID != nil }
    private var dragOffset: SIMD3<Float>?
    /// Exhibits mid-glide home (id → clock time when the idle loop may resume). Without
    /// the grace, the per-frame breathe write stomps the return animation on its first frame.
    private var returningIDs: [String: Double] = [:]

    /// A floating plate, front and centre: carry a lab here and it presents itself.
    private func buildPodium(distance: Float) {
        // Reach scales with the arc; height does not — pushing the gallery back changes
        // nothing about how high a wearer's chest is.
        let plateBottom = Self.podiumPlateHeight
        let plateTop = plateBottom + Self.podiumPlateThickness
        podiumTop = SIMD3(0,
                          plateTop + GalleryLayout.exhibitLift,
                          -Self.podiumReach * (distance / 2.0))

        let podium = Entity()
        podium.position = SIMD3(podiumTop.x, 0, podiumTop.z)

        // The pad is a docking cradle, not a bigger puck: hexagonal, milled pocket,
        // three latch fingers that close when a lab lands — see `setLatches`.
        let cradle = Self.loadPlatform(
            "GalleryCradle",
            fallback: {
                let plate = ModelEntity(
                    mesh: Primitives.cylinder(height: Self.podiumPlateThickness,
                                            radius: Self.podiumRadius),
                    materials: [Materials.graphite(Self.slabTint)])
                plate.position.y = -Self.podiumPlateThickness / 2
                let holder = Entity()
                holder.addChild(plate)
                return holder
            })
        cradle.position.y = plateTop
        podium.addChild(cradle)
        buildLatches(on: podium, at: plateTop)

        // Champagne rim, hexagonal and inset: a circle through a hexagon's circumradius
        // saws through the body six times per lap — 6 segments follow the edge, and
        // 0.099 keeps the line on the top face rather than the chamfer.
        let rim = Materials.unlit(Self.titleRimColor, opacity: 0.7)
        if let ring = Self.rimTube(radius: 0.099, y: plateTop + 0.002,
                                   segments: 6) {
            ring.model?.materials = [rim]
            podium.addChild(ring)
        }

        // Glow pool in the cradle's pocket + a smaller hover ring beneath the plate —
        // both brighten as an offer nears; the ring makes the plate read as suspended.
        let glow = Entity()
        let glowMaterial = Materials.unlit(Self.titleRimColor, opacity: 0.22)
        let pool = ModelEntity(
            mesh: Primitives.cylinder(height: 0.001, radius: 0.068),
            materials: [glowMaterial])
        // −0.0035 is measured against the asset: a floor plate in the pocket
        // has its top at −0.0045, and a pool below it draws nothing.
        pool.position.y = plateTop - 0.0035
        glow.addChild(pool)
        if let hover = Self.rimTube(radius: Self.podiumRadius - 0.032,
                                    y: plateBottom - Self.podiumHoverGap) {
            let hoverMaterial = Materials.unlit(Self.titleRimColor, opacity: 0.55)
            hover.model?.materials = [hoverMaterial]
            glow.addChild(hover)
        }
        glow.components.set(OpacityComponent(opacity: 0.35))
        podium.addChild(glow)
        podiumGlow = glow

        root.addChild(podium)
    }

    // MARK: The cradle's latches

    /// The three fingers, held so the dock and the release can turn them.
    private var latchPivots: [Entity] = []

    /// Finger stand-off and hinge angles (open = raised offer, closed = tip over the pocket
    /// rim). Mirrors `POST_RADIUS` in `Tools/galleryplatforms.py` — fingers must turn on the
    /// posts the cradle actually carries.
    private static let latchRadius: Float = 0.082
    private static let latchOpen: Float = 0.62
    private static let latchClosed: Float = -0.10

    /// Rings the pad with latch fingers. Each is a seat (ring placement) + a pivot (hinge
    /// angle only) — one transform per job, else yaw and hinge compose wrong mid-animation.
    /// The model reaches along −Z from its pivot: a finger at ring angle θ is yawed π/2 − θ.
    private func buildLatches(on podium: Entity, at plateTop: Float) {
        latchPivots.removeAll()
        guard let finger = PropCache.prototype(named: "GalleryLatch") else { return }

        for index in 0..<3 {
            let theta = Float.pi / 2 + Float(index) * 2 * .pi / 3
            let seat = Entity()
            seat.position = SIMD3(Self.latchRadius * cos(theta),
                                  plateTop + 0.004,
                                  Self.latchRadius * sin(theta))
            seat.orientation = simd_quatf(angle: .pi / 2 - theta,
                                          axis: [0, 1, 0])
            let pivot = Entity()
            pivot.orientation = simd_quatf(angle: Self.latchOpen,
                                           axis: [1, 0, 0])
            pivot.addChild(finger.clone(recursive: true))
            seat.addChild(pivot)
            podium.addChild(seat)
            latchPivots.append(pivot)
        }
    }

    /// Closes the latches over a docked lab, or opens them. Under Reduce
    /// Motion it jumps to the pose: the fingers are a readout of whether
    /// the pad holds something.
    private func setLatches(closed: Bool, duration: Double) {
        let angle = closed ? Self.latchClosed : Self.latchOpen
        for pivot in latchPivots {
            let pose = Transform(rotation: simd_quatf(angle: angle,
                                                      axis: [1, 0, 0]))
            if stillness || duration <= 0 {
                pivot.transform = pose
            } else {
                pivot.move(to: pose, relativeTo: pivot.parent,
                           duration: duration, timingFunction: .easeInOut)
            }
        }
    }

    // MARK: The gallery's grab bar

    /// Whole-room move handle under the pad — same affordance as a visionOS window bar.
    /// Drag moves the whole gallery; a press that never moves recentres. See `GalleryPlacement`.
    static let galleryBarName = "gallery-handle"

    private func buildGalleryBar(distance: Float) {
        let bar = Entity()
        bar.name = Self.galleryBarName
        bar.position = SIMD3(0, Self.podiumPlateHeight - 0.16,
                             -Self.podiumReach * (distance / 2.0))

        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: .white)
        glass.roughness = 0.15
        glass.clearcoat = .init(floatLiteral: 1.0)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        let capsule = ModelEntity(
            mesh: Primitives.box(width: 0.24, height: 0.011, depth: 0.011,
                               cornerRadius: 0.0055),
            materials: [glass])
        bar.addChild(capsule)

        // A handle is a bar — an oversized sphere target put an 18 cm ball in front of the podium.
        Grabbable.configureTouchTarget(bar, matchingVisualBoundsOf: bar)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Gallery handle. Drag it to move the whole gallery; tap it to bring the gallery home."
        bar.components.set(accessibility)
        root.addChild(bar)
    }

    /// True if the entity (or an ancestor) is the gallery's grab bar.
    static func isGalleryBar(_ entity: Entity) -> Bool {
        entity.nearestAncestor { $0.name == galleryBarName } != nil
    }

    /// A ring of tube. `segments`: 48 for a circle, 6 to lie on the hex cradle's edge —
    /// disagree with the solid and the ring intersects it once per facet.
    private static func rimTube(radius: Float, y: Float,
                                segments: Int = 48) -> ModelEntity? {
        let points = (0...segments).map { step -> SIMD3<Float> in
            let angle = Float(step) / Float(segments) * 2 * .pi
            return SIMD3(cos(angle) * radius, y, sin(angle) * radius)
        }
        guard let mesh = TubeMesh.tube(lines: [points], radius: 0.0014, sides: 4)
        else { return nil }
        return ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
    }

    // MARK: Carrying an exhibit to the podium

    /// Starts a carry if the drag began on an exhibit. World → root space happens here,
    /// so Recenter's yaw never lies to the hand.
    func beginExhibitDrag(entity: Entity, world: SIMD3<Float>) -> Bool {
        guard draggingID == nil, let id = moduleID(for: entity),
              let exhibit = exhibits.first(where: { $0.moduleID == id }) else {
            return false
        }
        if dockedModuleID == id {
            dockedModuleID = nil
            loadButton?.isEnabled = false
            // Lifted out of the cradle: fingers let go first.
            setLatches(closed: false, duration: 0.18)
        }
        draggingID = id
        let local = root.convert(position: world, from: nil)
        dragOffset = exhibit.anchor.position - local
        SoundPalette.play(.pop, on: exhibit.anchor, volume: 0.3)
        return true
    }

    func dragExhibit(world: SIMD3<Float>) {
        guard let draggingID, let dragOffset,
              let exhibit = exhibits.first(where: { $0.moduleID == draggingID })
        else { return }
        let local = root.convert(position: world, from: nil)
        exhibit.anchor.position = local + dragOffset
        // The podium brightens as the offer approaches.
        let near = simd_distance(exhibit.anchor.position, podiumTop) < Self.podiumSnapRadius
        podiumGlow?.components.set(OpacityComponent(opacity: near ? 1.0 : 0.35))
    }

    /// Abandons a carry that will never receive its `onEnded` (the gallery closing
    /// under the hand); the exhibit glides home rather than being seated.
    func cancelExhibitDrag() {
        guard draggingID != nil else { return }
        draggingID = nil
        dragOffset = nil
    }

    func endExhibitDrag() {
        guard let id = draggingID,
              let exhibit = exhibits.first(where: { $0.moduleID == id }) else {
            draggingID = nil
            return
        }
        draggingID = nil
        dragOffset = nil

        if simd_distance(exhibit.anchor.position, podiumTop) < Self.podiumSnapRadius {
            // 0.28 s: the hand released within 34 cm — a long glide over a short
            // distance reads as the object being taken off you.
            dock(exhibit, id: id, duration: 0.28)
        } else {
            // Not offered: it glides home.
            returningIDs[id] = time + 0.5
            exhibit.anchor.move(to: Transform(translation: exhibit.basePosition),
                                relativeTo: root, duration: 0.45,
                                timingFunction: .easeInOut)
            podiumGlow?.components.set(OpacityComponent(opacity: 0.35))
        }
    }

    /// Seats an exhibit on the pad: evicts the previous, flies this one in, raises the
    /// Load button. One dock, three callers (carry, tap, debug) differing only in duration.
    private func dock(_ exhibit: Exhibit, id: String, duration: Double) {
        // Evict first: the replaced lab must be sent home before `dockedModuleID` forgets it.
        if let previous = dockedModuleID, previous != id,
           let old = exhibits.first(where: { $0.moduleID == previous }) {
            returningIDs[previous] = time + 0.45
            old.anchor.move(to: Transform(translation: old.basePosition),
                            relativeTo: root, duration: 0.4,
                            timingFunction: .easeInOut)
        }
        dockedModuleID = id
        // No `returningIDs` grace here: the docked branch never writes
        // `anchor.position`, so the flight is unopposed.
        exhibit.anchor.move(to: Transform(translation: podiumTop),
                            relativeTo: root, duration: duration,
                            timingFunction: .easeOut)
        SoundPalette.play(.chime, on: exhibit.anchor, volume: 0.6)
        seatLoadButton()
        loadButton?.isEnabled = true
        podiumGlow?.components.set(OpacityComponent(opacity: 1.0))

        // Latches close as it lands, not as it sets off — the cradle answers the arrival.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration * 0.75))
            guard let self, self.dockedModuleID == id else { return }
            self.setLatches(closed: true, duration: 0.26)
        }
    }

    #if DEBUG
    /// Seats an exhibit immediately — CLI screenshots have no hand to carry one with.
    func dockForDebug(id: String) {
        guard let exhibit = exhibits.first(where: { $0.moduleID == id }) else { return }
        dockedModuleID = id
        exhibit.anchor.position = podiumTop
        seatLoadButton()
        loadButton?.isEnabled = true
        podiumGlow?.components.set(OpacityComponent(opacity: 1.0))
        setLatches(closed: true, duration: 0)
    }
    #endif

    /// A tap on an exhibit sends it to the pad. Slower than the carry's landing — the
    /// flight is the only thing that says where the lab went. A tap on the
    /// already-docked lab is ignored.
    func sendToPad(id: String) {
        guard dockedModuleID != id, !isCarrying,
              let exhibit = exhibits.first(where: { $0.moduleID == id })
        else { return }
        dock(exhibit, id: id, duration: 0.5)
    }

    // No floor-anchored decoration: y = 0 is where the user stood when the space opened,
    // not their floor — anything touching the real floor must come from `RoomModel`'s
    // scanned geometry.

    // MARK: The 3-D bubble title

    /// Just above the arc's centre; set from the arc geometry in build().
    private var titlePosition = SIMD3<Float>(0, 1.98, -2.05)

    /// Warm edge-light behind the letters — champagne, not gold (full saturation read as a toy).
    private static let titleRimColor = HubTitleStyle.champagne
    /// The lockup's overall width, metres. Both lines are scaled to exactly this.
    private static let titleWidth: Float = 0.60

    /// "Physics / Playground" as a flush-both-sides two-line lockup: lines measured, scaled
    /// to a common width, stacked with cap-height leading, block centred on the anchor.
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
        // Kept for the rake. The lines turn, not the anchor: the utility bar is
        // parented to `titleAnchor`.
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

        // Utility bar seat: below the rule, clear of the lockup whatever its metrics.
        titleBarSeat = SIMD3(0, -blockHeight / 2 - 0.20, 0.01)
    }

    // MARK: Attachment seats — SwiftUI riding the scene

    /// The wordmark's two lines, held so the rake can turn them.
    private var titleLines: [Entity] = []

    /// Local position under the wordmark for the utility bar.
    private var titleBarSeat = SIMD3<Float>(0, -0.35, 0.01)
    /// Held so the intro can bench it: the bar sits out the ceremony and appears with the landing.
    private var titleBar: Entity?

    /// Parents the utility bar under the wordmark so it inherits the bob. ×2.2 because an
    /// attachment renders at SwiftUI's natural size (1 pt ≈ 0.7 mm) — doll's-house at two metres.
    func seatTitleBar(_ entity: Entity) {
        entity.position = titleBarSeat
        entity.scale = SIMD3(repeating: 2.2)
        // Benched while the arrival plays (and for a frozen intro, which never
        // finishes); `updateIntro`'s landing re-enables it.
        entity.isEnabled = introPhase != .running
        titleAnchor.addChild(entity)
        titleBar = entity
    }

    /// Opens a lab. Set by the view; reached from VoiceOver actions and the Load button.
    var onEnter: ((String) -> Void)?

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

    private func buildExhibit(for module: ModuleDescriptor,
                              at basePosition: SIMD3<Float>) {
        let anchor = Entity()
        anchor.name = module.id
        anchor.position = basePosition
        // The gaze/pinch target is set at the bottom of this function, measured from
        // the miniature alone — see the note there.
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        // The label describes; the action is what opens the lab.
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(module.title). \(HubDomain.promise(for: module.id))")
        accessibility.customActions = [HubSpaceView.enterAction]
        anchor.components.set(accessibility)
        // Plain activate must open it too — VoiceOver's default gesture, not just a rotor
        // action. `attach` preserves the label and custom action above.
        SpatialActions.attach(
            to: anchor,
            label: "\(module.title). \(HubDomain.promise(for: module.id))",
            activate: { [weak self] in self?.onEnter?(module.id) })
        root.addChild(anchor)

        let pulser = Entity()
        anchor.addChild(pulser)

        // The pool of light that marks the one you are facing.
        let glow = Self.focusGlow(accent: UIColor(module.accent))
        glow.components.set(OpacityComponent(opacity: 0))
        pulser.addChild(glow)

        // The living miniature, and the motion it was authored with.
        let built = HubVignettes.make(for: module.id)
        let vignette = built.entity
        // Measured, then fitted to a common apparent size — six models authored at a
        // nominal size are not six models at the same size.
        let bounds = vignette.visualBounds(relativeTo: nil).extents
        let largest = max(bounds.x, max(bounds.y, 1e-4))
        vignette.scale = SIMD3(repeating: Self.exhibitSize / largest)
        vignette.position = .zero
        pulser.addChild(vignette)

        // Its name is on the bench under the mount (`buildTerrace`); a module
        // outside every terrace gets a detached one, so the type stays total.
        let label = benchLabels[module.id] ?? Entity()

        // Target measured from the miniature alone: `pulser` includes the
        // 0.40 m focus glow, which would reach past both neighbours at 0.36 m
        // puck pitch. Set directly, not via `Grabbable`, which would add a
        // grounding shadow.
        let reach = Grabbable.reach
        let exhibitBounds = vignette.visualBounds(relativeTo: anchor)
        anchor.components.set(InputTargetComponent())
        anchor.components.set(CollisionComponent(shapes: [
            Primitives.collisionBox(size: exhibitBounds.extents + SIMD3<Float>(repeating: 2 * reach), offset: exhibitBounds.center),
        ]))
        anchor.components.set(HoverEffectComponent())

        exhibits.append(Exhibit(
            moduleID: module.id, anchor: anchor, pulser: pulser,
            vignette: vignette, label: label, halo: glow,
            basePosition: basePosition, animate: built.animate))
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

    /// The bench's front face in the slab's frame, plus the inlay's lift off
    /// it: proud enough never to fight the face for depth, too thin to read
    /// as a raised sign.
    private static let benchFace: Float = GalleryLayout.slabDepth / 2 + 0.0006

    private static var labelMeshes: [String: MeshResource] = [:]

    /// A lab's name as an inlay on the bench's front edge: the house's heavy
    /// rounded label voice, lit in the lab's accent, a millimetre deep and
    /// centred on its own origin. Unlit like the hairline above it — a light
    /// in the stock, not a lamp in front of it.
    static func benchLabel(_ text: String, accent: UIColor) -> Entity {
        let key = text
        let mesh: MeshResource
        if let cached = labelMeshes[key] {
            mesh = cached
        } else {
            mesh = MeshResource.generateText(
                text, extrusionDepth: 0.001,
                font: roundedFont(size: benchLabelSize), alignment: .center)
            labelMeshes[key] = mesh
        }
        let bounds = mesh.bounds
        let letters = ModelEntity(mesh: mesh, materials: [Materials.unlit(accent)])
        letters.position = [-(bounds.min.x + bounds.max.x) / 2,
                            -(bounds.min.y + bounds.max.y) / 2, 0]
        let label = Entity()
        label.name = "bench-label"
        label.addChild(letters)
        return label
    }

    /// How wide a bench label is — the type alone, since nothing backs it.
    static func benchLabelWidth(_ text: String) -> Float {
        textExtents(text, size: benchLabelSize).x
    }

    /// The focus pool's entity name — the pool of the module's colour under
    /// whichever exhibit you face.
    static let focusPoolName = "focus-pool"

    private static func focusGlow(accent: UIColor) -> Entity {
        // A ladder of discs half a millimetre apart, widest at the bottom:
        // coplanar faces flicker.
        let glow = Entity()
        // Named so the stacking rule can be tested without finding Gravity
        // Lab's orbit tracks by shape.
        glow.name = Self.focusPoolName
        let layers: [(radius: Float, opacity: Float)] = [
            (0.200, 0.06), (0.135, 0.15), (0.085, 0.30),
        ]
        for (index, layer) in layers.enumerated() {
            var material = UnlitMaterial(color: accent)
            material.blending = .transparent(
                opacity: .init(floatLiteral: layer.opacity))
            let disc = ModelEntity(
                mesh: Primitives.cylinder(height: 0.001, radius: layer.radius),
                materials: [material])
            disc.position.y = Float(index) * 0.0005
            glow.addChild(disc)
        }
        glow.position = SIMD3(0, poolRest, 0)
        return glow
    }

    /// Where the focus pool lies relative to its exhibit at rest: on the
    /// mount's top, 6 mm proud.
    private static let poolRest: Float = -GalleryLayout.exhibitLift + 0.006


    // MARK: Idle animation & interaction

    /// The gallery's whole-room placement, applied to `root` every frame —
    /// a transform, never a rebuild.
    var placement: GalleryPlacement?

    func animate(dt: Double, lookRay: (origin: SIMD3<Double>, direction: SIMD3<Double>)?) {
        // Clamped: the first event after the space presents can carry seconds
        // in one delta, which would spend the arrival's centred beat before
        // anyone saw a frame.
        let dt = min(dt, 1.0 / 30.0)
        time += dt
        if let placement {
            // Once per launch, and only if the restored facing points away from the
            // wearer — see `GalleryPlacement.reFacedYaw`. The offset is left alone.
            if !hasRefaced, let lookRay {
                hasRefaced = true
                placement.refaceIfBehind(
                    lookYaw: atan2(-Float(lookRay.direction.x),
                                   -Float(lookRay.direction.z)))
            }
            root.position = placement.offset
            root.orientation = simd_quatf(angle: placement.yaw, axis: [0, 1, 0])
        }
        fadePresence(dt: dt)
        updateIntro()
        updateFocus(lookRay: lookRay, dt: dt)

        for index in exhibits.indices {
            let focus = exhibits[index].focus
            let exhibit = exhibits[index]

            // The bench label answers before any branch below claims the frame:
            // brighter while faced, dim while its lab is away on the pad.
            let labelTarget = exhibit.moduleID == dockedModuleID
                ? Self.labelAway
                : Self.labelRest + (Self.labelFocused - Self.labelRest) * focus
            exhibits[index].labelLevel = Motion.ease(
                exhibit.labelLevel, toward: labelTarget, dt: dt, rate: 8)
            if abs(exhibits[index].labelLevel - exhibit.appliedLabelLevel) > 0.004 {
                exhibits[index].appliedLabelLevel = exhibits[index].labelLevel
                exhibit.label.components.set(
                    OpacityComponent(opacity: exhibits[index].labelLevel))
            }

            // An exhibit riding a hand, gliding home or standing on the podium owns
            // its own position.
            if exhibit.moduleID == draggingID {
                exhibits[index].appliedFocus = -1
                continue
            }
            if let until = returningIDs[exhibit.moduleID] {
                if time < until {
                    exhibits[index].appliedFocus = -1
                    continue
                }
                returningIDs[exhibit.moduleID] = nil
            }
            if exhibit.moduleID == dockedModuleID {
                if !stillness {
                    // The showcase turntable: a docked lab presents
                    // itself with a slow, full turn.
                    exhibit.vignette.orientation = simd_quatf(
                        angle: Float(time * 0.45), axis: [0, 1, 0])
                }
                exhibit.pulser.scale = SIMD3(repeating: 1.05)
                // In the cradle the pool sits where it was built, in the pocket.
                exhibit.halo.position.y = Self.poolRest
                // Written when focus moves, not every frame.
                if abs(focus - exhibits[index].appliedFocus) > 0.0005 {
                    exhibits[index].appliedFocus = focus
                    exhibit.halo.components.set(OpacityComponent(opacity: focus))
                }
                exhibits[index].animTime += dt
                exhibit.animate(exhibits[index].animTime)
                continue
            }

            // Reduce Motion: the gallery holds still; focus scaling stays, since it
            // answers the user's own head. Breathe, not bob: ±8 mm on a slow
            // desynced period, so nothing wanders off its pedestal.
            let breathe = stillness ? 0
                : 0.008 * Float(sin(time * 1.05 + Double(index) * 2.1))
            // The focused exhibit lifts off its puck as it grows.
            let lift = Self.focusedLift * focus
            exhibit.anchor.position = exhibit.basePosition
                + SIMD3(0, breathe + lift, 0)

            let resting = hasLookRay ? Self.unfocusedScale : 1
            let scale = resting + (Self.focusedScale - resting) * focus
            exhibit.pulser.scale = SIMD3(repeating: scale)
            // The pool lights the mount, so it stays on the mount: the lift and
            // the bob are taken back out of it, and what rises is the exhibit
            // alone. Riding along, it hung as a smudge in the air.
            exhibit.halo.position.y = (Self.poolRest - breathe - lift) / max(scale, 0.01)

            // Written only when focus has actually moved; once the ease settles,
            // rewriting is churn.
            if abs(focus - exhibits[index].appliedFocus) > 0.0005 {
                exhibits[index].appliedFocus = focus
                exhibit.halo.components.set(OpacityComponent(opacity: focus))
            }

            if stillness { continue }

            // A gentle sway rather than a full turn, which swings the flat models
            // edge-on for half of every rotation. It eases to a stop on the exhibit
            // being read.
            let sway = 0.44 * Float(sin(time * 0.4 + Double(index) * 1.3))
            exhibit.vignette.orientation = simd_quatf(
                angle: sway * (1 - focus * 0.75), axis: [0, 1, 0])

            // Each exhibit runs on its own clock: paused outside the field of view,
            // a touch fast while focused.
            if exhibit.inView || focus > 0.01 || !hasLookRay {
                exhibits[index].animTime += dt * Double(1 + 0.6 * focus)
                exhibit.animate(exhibits[index].animTime)
            }
        }
        // The title floats and breathes; during the arrival it rides
        // `HubIntro`'s flight from its centred pose back to this anchor.
        let bob = stillness ? 0 : 0.02 * Float(sin(time * 0.6))
        let blend = introPhase == .running
            ? HubIntro.titleBlend(at: introTime) : 1
        let rest = titlePosition + SIMD3(0, bob, 0)
        titleAnchor.position = rest + (HubIntro.titlePose - rest) * (1 - blend)
        let titleBreathe = stillness ? 1 : 1 + 0.015 * Float(sin(time * 0.9))
        let introSwell = 1 + (HubIntro.titlePoseScale - 1) * (1 - blend)
        titleAnchor.scale = SIMD3(repeating: titleBreathe * introSwell)

        // Each line rakes on its own phase. Under stillness they park square to
        // the reader.
        for (index, line) in titleLines.enumerated() {
            line.orientation = stillness ? simd_quatf(angle: 0, axis: [0, 1, 0])
                : HubTitleStyle.rake(time: time, phase: Double(index) * 1.3)
        }

        // The hairlines shimmer slowly, each on its own phase — the
        // terraces are lit, not painted.
        if !stillness {
            for (index, domain) in HubDomain.allCases.enumerated() {
                guard let hairline = terraceHairlines[domain] else { continue }
                let shimmer = 0.72 + 0.16 * Float(sin(time * 0.5 + Double(index) * 1.7))
                hairline.components.set(OpacityComponent(opacity: shimmer))
            }
        }

        // The signage performs its physics, each door on its own phase. Called
        // under stillness too, so the signs park rather than freeze.
        for (index, domain) in HubDomain.allCases.enumerated() {
            domainTitles[domain]?.animate(time: time + Double(index) * 1.9,
                                          stillness: stillness)
        }
    }

    /// How far the gallery has faded up, 0…1.
    private var presence: Float = 0

    /// Where the gallery is heading: 1 on arrival, 0 once a lab has been chosen.
    private var presenceTarget: Float = 1

    /// The gallery arrives rather than appears, and leaves rather than vanishing —
    /// a rebuild is a hard cut in either direction. Deliberately on the root, not
    /// per-entity, so everything moves on one curve.
    private func fadePresence(dt: Double) {
        guard presence != presenceTarget else { return }
        // Exponential approach, frame-rate independent, τ ≈ 0.18 s.
        presence += (presenceTarget - presence) * Float(1 - exp(-dt / 0.18))
        if abs(presence - presenceTarget) < 0.001 {
            presence = presenceTarget
        }
        if presence == 1 {
            // Land exactly, then remove the component — a permanent OpacityComponent
            // forces the whole gallery down a transparency path it does not need.
            root.components.remove(OpacityComponent.self)
        } else {
            // At 0 the component stays: removing it would restore full opacity for
            // the frames before the module scene takes over.
            root.components.set(OpacityComponent(opacity: presence))
        }
    }

    /// The gallery begins to leave. Called when a lab has been chosen.
    func beginDeparture() { presenceTarget = 0 }

    private var hasLookRay = false

    /// Latches the once-per-launch facing rescue; a nil `lookRay` leaves it
    /// false so the rescue waits for a real look.
    private var hasRefaced = false

    /// Where to aim at an exhibit for the gaze cone: its puck, the podium while docked,
    /// the hand while carried. Deliberately not the live anchor otherwise — it carries
    /// breathe and focus lift, so focus would feed back into its own aim.
    private func aimPosition(of exhibit: Exhibit) -> SIMD3<Float> {
        if exhibit.moduleID == dockedModuleID { return podiumTop }
        // Live anchor is safe for exactly these two cases: the idle loop skips them.
        if exhibit.moduleID == draggingID { return exhibit.anchor.position }
        return exhibit.basePosition
    }

    private func updateFocus(lookRay: (origin: SIMD3<Double>,
                                       direction: SIMD3<Double>)?, dt: Double) {
        var winner: String?
        #if DEBUG
        // `-hubFocus <module id>` pins focus for CLI screenshots — the simulator has no look ray.
        if let forced = UserDefaults.standard.string(forKey: "hubFocus"),
           exhibits.contains(where: { $0.moduleID == forced }) {
            hasLookRay = true
            applyFocus(winner: forced, dt: dt)
            return
        }
        #endif
        if let lookRay {
            hasLookRay = true
            // Bring the ray into the scene's frame — `convert` carries translation as well
            // as yaw; an orientation-only inverse broke once the gallery could be dragged.
            let origin = root.convert(position: SIMD3<Float>(lookRay.origin),
                                      from: nil)
            let forward = simd_normalize(
                root.orientation.inverse.act(SIMD3<Float>(lookRay.direction)))
            var best = Self.focusCone
            for index in exhibits.indices {
                let exhibit = exhibits[index]
                let toExhibit = aimPosition(of: exhibit) - origin
                let distance = simd_length(toExhibit)
                guard distance > 1e-4 else { continue }
                let cosine = simd_dot(toExhibit / distance, forward)
                let angle = acos(min(max(cosine, -1), 1))
                // Anything within ~60° is worth animating; the rest pauses.
                exhibits[index].inView = angle < 1.05
                // Hysteresis: the incumbent keeps focus unless another is clearly closer.
                let bias: Float = exhibit.moduleID == focusedModuleID
                    ? Self.focusStickiness : 1
                if angle * bias < best {
                    best = angle * bias
                    winner = exhibit.moduleID
                }
            }
        } else {
            hasLookRay = false
        }

        applyFocus(winner: winner, dt: dt)
    }

    private func applyFocus(winner: String?, dt: Double) {
        // Publish only on change — SwiftUI must not see this per frame.
        if winner != focusedModuleID {
            focusedModuleID = winner
        }

        let rate = Float(min(dt * 7, 1))
        for index in exhibits.indices {
            let target: Float = exhibits[index].moduleID == winner ? 1 : 0
            exhibits[index].focus += (target - exhibits[index].focus) * rate
        }
    }

    /// Maps a tapped entity (target or any child) back to its module.
    func moduleID(for entity: Entity) -> String? {
        var current: Entity? = entity
        while let candidate = current {
            if exhibits.contains(where: { $0.moduleID == candidate.name }) {
                return candidate.name
            }
            current = candidate.parent
        }
        return nil
    }

    /// The chosen exhibit swells ~0.4 s before the module takes the stage — an arrival,
    /// not a hard cut (a true cross-dissolve would need both scenes alive at once).
    func beginEnterTransition(id: String) {
        guard let exhibit = exhibits.first(where: { $0.moduleID == id }) else { return }
        SoundPalette.play(.pop, on: exhibit.anchor, volume: 0.7)
        // The gallery starts leaving now; the chosen exhibit is a child of
        // `root`, so it fades as it swells.
        beginDeparture()
        // The exhibit swells and rises; its terrace's hairline flares with it.
        exhibit.pulser.move(
            to: Transform(scale: SIMD3(repeating: 1.6),
                          translation: SIMD3(0, 0.14, 0)),
            relativeTo: exhibit.anchor,
            duration: 0.42,
            timingFunction: .easeIn
        )
        if let hairline = terraceHairlines[HubDomain.domain(for: id)] {
            var flare = hairline.transform
            flare.scale = SIMD3(1, 3.2, 3.2)
            hairline.move(to: flare, relativeTo: hairline.parent,
                          duration: 0.2, timingFunction: .easeOut)
        }
    }
}

/// The button over the pad while a lab stands on it. The explicit
/// `.hoverEffect` is load-bearing: `.buttonStyle(.plain)` gives up the
/// platform highlight, and the bare default was invisible on device.
private struct HubLoadButton: View {
    let module: ModuleDescriptor
    let enter: () -> Void

    var body: some View {
        Button(action: enter) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(module.accent.gradient)
                    Image(systemName: module.icon)
                        // Semantic, so the glyph scales with Dynamic Type.
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 1) {
                    // "Lab", the word the wearer reads everywhere else.
                    Text("LOAD LAB")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.7)
                        .foregroundStyle(.secondary)
                    Text(module.title)
                        .font(.title2.weight(.semibold))
                }

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(module.accent)
            }
            .padding(.leading, 13)
            .padding(.trailing, 20)
            .padding(.vertical, 11)
            // Stroke inside the glass — a ring outside it reads as a second object.
            .overlay {
                Capsule().strokeBorder(module.accent.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.highlight)
        .hoverEffect { effect, isActive, _ in
            effect.animation(.easeOut(duration: 0.15)) {
                $0.scaleEffect(isActive ? 1.06 : 1)
            }
        }
        .glassBackgroundEffect(in: Capsule())
        .accessibilityLabel("Load \(module.title)")
        .accessibilityHint("Opens \(module.title)")
    }
}

/// Utility bar under the wordmark: Lab list, Settings, Notebook, About.
/// No Exit button — visionOS offers no supported way for an app to quit.
private struct HubUtilityBar: View {
    let openSettings: () -> Void
    let openAbout: () -> Void
    let openNotebook: () -> Void
    let openCatalog: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // The flat catalog's only door: `syncMainWindow` dismisses the main
            // window while the gallery is up, and nothing may be reachable only in
            // space.
            Button(action: openCatalog) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title3)
            }
            .help("Lab list")
            .accessibilityLabel("Lab list")
            .accessibilityHint("Opens a flat list of every lab in a window")

            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityHint("Sound, room tone and the Time Capsule")

            Button(action: openNotebook) {
                Image(systemName: "book.closed.fill")
                    .font(.title3)
            }
            .help("Lab Notebook")
            .accessibilityLabel("Lab Notebook")
            .accessibilityHint("Your captured observations")

            Button(action: openAbout) {
                Image(systemName: "info.circle")
                    .font(.title3)
            }
            .help("About")
            .accessibilityLabel("About Physics Playground")
            .accessibilityHint("Credits and version")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassBackgroundEffect(in: Capsule())
    }
}
