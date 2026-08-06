//
//  HubSpaceView.swift
//  Physics Playground — Hub
//
//  The spatial menu: the GALLERY. Two floating graphite terraces arc
//  around the user in a crescent — one per physics domain, each with a
//  domain-coloured hairline along its front edge — and every module
//  stands on its own pedestal puck as a live, shell-free miniature,
//  under a persistent "Physics / Playground" wordmark. Domains are
//  physical structure: where a lab sits tells you what kind of physics
//  it is, and one sweep of the head reads the whole room. Look toward
//  an exhibit and it lifts off its puck, naming itself and opening its
//  focus panel.
//
//  Two ways in, and the panel's "Load Module" button is the one that
//  always works — gaze plus a pinch, nothing to aim or carry. The other
//  is the pad: drag an exhibit onto the plate floating front and centre
//  and it stands there and turns, with Load hanging over it. The pad is
//  the delightful path; the button is the reachable one, so neither is
//  load-bearing alone.
//
//  The only motion is idle life: miniatures breathe out of phase and
//  their physics runs. A handful of entities; per-frame work is a few
//  transform writes.
//
//  Geometry lives in GalleryLayout (pure, tested math). Vignettes are
//  keyed by module id with a generic fallback, so a new module lands
//  on its domain's terrace for free and gets a bespoke miniature with
//  one case.
//

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
            var progress: [String: (done: Int, total: Int)] = [:]
            for module in modules {
                let entries = ExperimentCatalog.experiments(for: module.id,
                                                            appModel: appModel)
                progress[module.id] = (
                    entries.filter {
                        appModel.experiments.completed.contains($0.experiment.id)
                    }.count,
                    entries.count)
            }
            scene.build(modules: modules, progress: progress)
            scene.placement = appModel.galleryPlacement
            scene.stillness = systemReduceMotion
            content.add(scene.root)

            // There is no focus PANEL any more (owner, 2026-08-04): the
            // gaze answer is the exhibit itself — the lift, the growth,
            // the halo — and the one way into a lab is carrying it to
            // the pad. The panel and its full-width Load button went
            // through three placements without earning their keep; the
            // pad is the door.
            if let load = attachments.entity(for: "load") {
                // The Load button hangs over the podium, shown only
                // while an exhibit stands there.
                load.components.set(BillboardComponent())
                load.isEnabled = false
                scene.root.addChild(load)
                scene.loadButton = load
                // After the assignment, not before — seating it reads
                // `loadButton`, so the other order silently does nothing.
                scene.seatLoadButton()
            }
            if let bar = attachments.entity(for: "bar") {
                scene.seatTitleBar(bar)
            }
            if let hint = attachments.entity(for: "podiumHint") {
                scene.seatPodiumHint(hint)
            }
            #if DEBUG
            // `-hubDock <module id>` seats an exhibit on the podium at
            // launch, so the docked state and Load button can be
            // screenshot from the CLI.
            if let forced = UserDefaults.standard.string(forKey: "hubDock") {
                scene.dockForDebug(id: forced)
            }
            #endif

            // `[weak scene]` matters here, and every module already knew
            // it. The subscription is stored ON the scene, so a strong
            // capture makes scene → subscription → closure → scene: a
            // cycle that no amount of leaving the hub can break. Each
            // return to the hub built another one, and every one of them
            // went on animating its own orphaned copy of the gallery,
            // forever, while you were somewhere else entirely.
            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak scene] event in
                scene?.animate(dt: event.deltaTime, lookRay: appModel.room.lookRay)
            }
        } update: { _, _ in
            scene.stillness = systemReduceMotion
        } attachments: {
            Attachment(id: "bar") {
                HubUtilityBar(
                    openSettings: { openWindow(id: SettingsView.windowID) },
                    openAbout: { openWindow(id: AboutView.windowID) },
                    openNotebook: { openWindow(id: NotebookView.windowID) })
            }
            Attachment(id: "podiumHint") {
                // What the podium is FOR, said once, quietly, where the
                // action happens. The focus panel's Load button remains
                // the guaranteed way in; this teaches the fun one.
                // "pad", not "podium": the plinth came off on 2026-08-03
                // and copy that names a stand the wearer cannot see sends
                // them looking for one.
                Text("Drag a lab onto the pad to open it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassBackgroundEffect(in: Capsule())
                    // The ONE readout in the app that was missing this.
                    // An attachment carries a collider for its content,
                    // and this one is seated at the podium rim, 12 cm
                    // toward the user — inside the volume the
                    // exhibit-carry drag sweeps through on its way to
                    // the podium. So the hint telling you to drag a lab
                    // onto the podium was standing in the way of doing
                    // it. All six module cards get this right.
                    .allowsHitTesting(false)
            }
            Attachment(id: "load") {
                if let module = ModuleCatalog.all(appModel: appModel)
                    .first(where: { $0.id == scene.dockedModuleID }) {
                    HubLoadButton(module: module) { enter(module.id) }
                }
            }
        }
        // The hub's gaze focus reads `room.lookRay`, which only exists
        // while the ARKit session runs — and the session is
        // reference-counted. Modules retain it through their occlusion
        // view; the hub has to retain it itself, or `lookRay` is nil
        // here forever and no exhibit ever focuses on device.
        .task { await appModel.room.retain() }
        // Entering a module replaces this view, and an EventSubscription
        // is not tied to the view that made it — left alone it keeps
        // calling `animate` on a hub that is no longer on screen, for
        // the whole time you are inside a module, holding the entire
        // exhibit graph alive behind it.
        .onDisappear {
            scene.subscription?.cancel()
            scene.subscription = nil
            appModel.room.release()
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // A tap no longer enters — carrying a lab to the
                    // podium does. The tap teaches the gesture: the
                    // podium flashes to say "bring it here."
                    guard scene.moduleID(for: value.entity) != nil else { return }
                    scene.hintPodium()
                }
        )
        // Carry a lab to the podium — or the whole gallery by its bar.
        // The exhibit rides the hand, the podium brightens as it nears,
        // and release either seats it (Load Module appears) or glides
        // it home. The bar branch comes first: a hand on the handle is
        // moving the room, not shopping for a lab.
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

    /// The gallery bar's drag session, in the LabAnchorView pattern:
    /// a RelativeDrag on the placement offset, and a press that never
    /// moves it folds into a tap that recentres — no second recogniser
    /// to contend with anything.
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
        barTravelled = max(barTravelled, simd_distance(next, placement.offset))
        placement.move(to: next)
    }

    private func endGalleryBarDrag() {
        if barTravelled < Self.barTapTravel {
            // A tap: home, facing the wearer if the room knows where
            // they are looking. This is the old Settings "Recenter"
            // verb, on the object it recentres.
            let yaw = appModel.room.lookRay.map { ray in
                atan2(-Float(ray.direction.x), -Float(ray.direction.z))
            }
            appModel.galleryPlacement.recentre(facing: yaw)
        }
        barDrag = nil
        barTravelled = 0
    }

    /// One enter path for both the pinch and the panel's button: the
    /// chosen exhibit swells toward you while the rest of the hub holds,
    /// and the module takes over as the swell peaks — an arrival, not a
    /// hard cut.
    private func enter(_ id: String) {
        scene.beginEnterTransition(id: id)
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            appModel.activeModuleID = id
        }
    }
}

/// The hub's entity graph and idle animation state.
@MainActor
@Observable
final class HubScene {
    let root = Entity()
    var subscription: EventSubscription?

    private struct Exhibit {
        let moduleID: String
        let anchor: Entity      // ring position (bobbed every frame)
        let pulser: Entity      // scale pulse on selection
        let vignette: Entity    // slowly rotating miniature
        let namePivot: Entity   // billboarded name plate
        let halo: Entity        // accent glow, focused only
        let basePosition: SIMD3<Float>
        /// The animation the miniature was built with — captured
        /// alongside its own geometry, so a model and its motion cannot
        /// drift apart. They did: the old table matched children by
        /// NAME, and those names only existed in the procedural
        /// fallbacks, so every module that loaded an asset instead
        /// silently never animated at all.
        let animate: (Double) -> Void
        /// 0 = resting in the ring, 1 = the one you are facing. Eased.
        var focus: Float = 0
        /// This exhibit's own animation clock. Runs a little fast while
        /// focused — the "come alive" answer to being looked at — and
        /// pauses entirely while the exhibit is outside the field of
        /// view, where animating it is work nobody can see.
        var animTime: Double = 0
        /// Set by updateFocus: whether the exhibit is near enough to the
        /// look direction to be worth animating.
        var inView: Bool = true
    }

    /// True stills all idle motion — the bob, the sway, the running
    /// miniatures. Set from Reduce Motion (system or in-app setting).
    var stillness = false

    /// Which exhibit the user is facing, published only when it CHANGES
    /// so nothing downstream sees sixty updates a second. (It fed a
    /// focus PANEL until 2026-08-04; the panel is gone — the id now
    /// only steadies the focus hysteresis.)
    private(set) var focusedModuleID: String?
    private var exhibits: [Exhibit] = []
    private var time = 0.0
    /// The 3-D bubble title the exhibits ring, bobbing at the centre.
    private let titleAnchor = Entity()

    // MARK: Layout — the Gallery
    //
    // A crescent of four domain terraces, authored and computed in
    // GalleryLayout. The constellation scatter this replaces put every
    // lab at its own azimuth/height/depth; position was designed but
    // it EXPLAINED nothing — the room read as bubbles. The terraces
    // make the grouping physical: architecture beneath the physics,
    // never around it.
    //
    // Geometry comes from settings (distance and height sliders,
    // recenter yaw), with the defaults at 2.0 m and 1.4 m.

    private var arcRadius: Float = 2.0
    private var arcHeight: Float = 1.4

    /// Every miniature is normalised to this WORLD size, so a terrace
    /// further away genuinely looks further away. Constant apparent
    /// size would throw the depth away.
    private static let exhibitSize: Float = 0.24

    /// The graphite the terraces and pucks are cut from.
    private static let slabTint = UIColor(white: 0.09, alpha: 1)

    // MARK: Focus
    //
    // A menu in a headset can do what a menu on a screen cannot: notice
    // which one you have TURNED TOWARD, and answer. The one you face
    // grows, lifts, and lights an accent halo; the others recede a
    // touch. Nothing moves on its own — the motion is yours. Every
    // exhibit keeps its NAME at full strength all the time (owner,
    // 2026-08-04: the fading captions made the room unreadable at a
    // glance), and there is no panel — the answer to the gaze is the
    // object itself, and the way in is carrying it to the pad.
    //
    // Head direction, not eye gaze: visionOS never hands an app the
    // eyes. Turning your head at something is the honest signal, and it
    // is the same look ray the field probes use.

    /// How far off your look direction an exhibit can be and still take
    /// focus, radians.
    private static let focusCone: Float = 26 * .pi / 180
    /// The focused exhibit has to be this much closer to your look
    /// direction than the current one before focus jumps — hysteresis,
    /// so a scanning glance doesn't strobe the ring.
    private static let focusStickiness: Float = 0.72
    /// Resting scale of an unfocused exhibit once ANY exhibit is
    /// focused, and how much the focused one grows.
    private static let unfocusedScale: Float = 0.90
    private static let focusedScale: Float = 1.22
    /// How far the focused exhibit lifts off its puck. (It used to step
    /// toward the user, but a step off a pedestal reads as falling;
    /// lifting reads as the exhibit answering.)
    private static let focusedLift: Float = 0.09

    // MARK: Build

    /// The gallery's fixed geometry. These were Settings sliders until
    /// 2026-08-03; the whole-room grab bar replaced them — moving the
    /// gallery is a transform now, not a rebuild, so the geometry it
    /// builds AT is simply the good default the sliders defaulted to.
    private static let arcDistanceDefault: Float = 2.0
    private static let arcHeightDefault: Float = 1.4

    func build(modules: [ModuleDescriptor],
               progress: [String: (done: Int, total: Int)] = [:]) {
        // Idempotent on purpose: `build` is additive below, and a
        // second call on a surviving scene used to stack a second
        // gallery on top of the first — the Settings reposition bug.
        // Nothing triggers a rebuild any more, but the insurance is a
        // few lines.
        root.children.removeAll()
        titleAnchor.children.removeAll()
        exhibits.removeAll()
        terraceHairlines.removeAll()
        domainTitles.removeAll()

        let distance = Self.arcDistanceDefault
        arcRadius = distance
        arcHeight = Self.arcHeightDefault

        titlePosition = SIMD3(0, arcHeight + 0.70, -(arcRadius + 0.45))
        buildBubbleTitle()
        buildPodium(distance: distance)
        buildGalleryBar(distance: distance)

        // Each terrace carries its domain's name as three-dimensional
        // signage (HubDomainTitle) — owner's call 2026-07-30, reversing
        // the earlier no-headers doctrine. The terraces are the app's
        // two DOORS now, and a door needs a name over it; four shelves
        // of two could speak through colour alone, two doors of three
        // cannot.
        let byID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
        for terrace in GalleryLayout.terraces(moduleIDs: modules.map(\.id),
                                              distance: distance,
                                              height: arcHeight) {
            buildTerrace(terrace)
            for (index, id) in terrace.moduleIDs.enumerated() {
                guard let module = byID[id] else { continue }
                buildExhibit(for: module,
                             at: terrace.exhibitPositions[index],
                             domain: terrace.domain,
                             progress: progress[id] ?? (0, 0))
            }
        }
    }

    // MARK: Terraces

    /// Each terrace's hairline, kept for the enter flare and shimmer.
    private var terraceHairlines: [HubDomain: ModelEntity] = [:]
    /// Each terrace's signage, driven from the idle loop.
    private var domainTitles: [HubDomain: HubDomainTitle] = [:]
    /// One domain's slab: a floating graphite shelf with a lit hairline
    /// of the domain's colour along its front edge, and a pedestal puck
    /// per module. Architecture BENEATH the physics, never around it —
    /// the miniatures stay shell-free.
    private func buildTerrace(_ terrace: GalleryLayout.Terrace) {
        let graphite = Materials.graphite(Self.slabTint)

        let slab = Entity()
        slab.position = terrace.center
        slab.orientation = simd_quatf(angle: terrace.yaw, axis: [0, 1, 0])
        let box = ModelEntity(
            mesh: .generateBox(width: terrace.width,
                               height: GalleryLayout.slabThickness,
                               depth: GalleryLayout.slabDepth,
                               cornerRadius: 0.03),
            materials: [graphite])
        slab.addChild(box)

        var lit = UnlitMaterial(color: UIColor(terrace.domain.color))
        lit.blending = .transparent(opacity: 0.85)
        let hairline = ModelEntity(
            mesh: .generateBox(width: max(terrace.width - 0.05, 0.1),
                               height: 0.004, depth: 0.004,
                               cornerRadius: 0.002),
            materials: [lit])
        hairline.position = SIMD3(0, GalleryLayout.slabThickness / 2 + 0.002,
                                  GalleryLayout.slabDepth / 2 - 0.006)
        slab.addChild(hairline)
        terraceHairlines[terrace.domain] = hairline

        // The signage, floating over the slab's miniatures. A child of
        // the slab, so it inherits the terrace's yaw and faces the user
        // the way the shelf does. High enough that a focus-lifted
        // exhibit (puck + lift + miniature, ~0.31 above the slab)
        // clears the sign's underline rule and the Mechanics ball's
        // landing points with room to spare.
        let title = HubDomainTitle(domain: terrace.domain,
                                   width: terrace.width * 0.54)
        title.root.position = SIMD3(0, 0.62, -0.02)
        slab.addChild(title.root)
        domainTitles[terrace.domain] = title
        root.addChild(slab)

        for top in terrace.puckTops {
            let puck = ModelEntity(
                mesh: .generateCylinder(height: GalleryLayout.puckHeight,
                                        radius: GalleryLayout.puckRadius),
                materials: [graphite])
            puck.position = top - SIMD3(0, GalleryLayout.puckHeight / 2, 0)
            root.addChild(puck)
        }
    }

    // MARK: The podium — where a lab is brought to be opened

    /// The plate's own dimensions. Its thickness is the terrace puck's,
    /// so a docked exhibit stands on it at exactly the clearance it had
    /// on its own puck (`GalleryLayout.exhibitLift`) — the docking spot
    /// is a puck held in the air, not a second kind of pedestal.
    ///
    /// THE COLUMN IS GONE (2026-08-03). A 1.05 m graphite plinth stood
    /// under this plate, and everything else in this gallery floats: the
    /// terraces, the wordmark, the exhibits on their pucks. One leg
    /// touching a floor the app cannot see — y = 0 is where the user
    /// happened to be standing when the space opened, not their floor,
    /// the same error that killed the light pool below — made the one
    /// object in the room that claimed to know where the ground was, and
    /// it was the object the eye is asked to go to.
    ///
    /// The plate keeps the exact height the column gave it, because that
    /// number was measured, not chosen: how far DOWN a thing sits in view
    /// is set by its height AND its distance, and an earlier pass got the
    /// second half wrong. At 0.82 m and 1.05 m away the docking spot hung
    /// ~26° below eye level while the terraces, no higher but twice as
    /// far, sit at ~14° — so it and the lab standing on it fell to the
    /// bottom of the view and the Load button floated up on its own,
    /// attached to nothing. Deleting the column moved no geometry at all.
    ///
    /// The name `podium` outlives the plinth throughout this file. It is
    /// the docking spot's name now, not a description of its shape; the
    /// wearer-facing copy says "pad".
    private static let podiumPlateHeight: Float = 1.05
    private static let podiumPlateThickness: Float = GalleryLayout.puckHeight
    private static let podiumRadius: Float = 0.105
    /// How far the hover ring hangs below the plate. Far enough to read
    /// as a separate object suspending it, near enough to belong to it.
    private static let podiumHoverGap: Float = 0.045
    /// Distance out from the user at the 2.0 m arc default; scales with it.
    private static let podiumReach: Float = 1.35
    /// How high the Load button hangs over the docked exhibit. Small on
    /// purpose: it has to read as that exhibit's button. At 0.34 m it
    /// floated up level with the user's eye, a good half-metre of empty
    /// air above the lab it belonged to, looking like loose UI. It went
    /// 0.20 → 0.23 when the button grew a badge and a second line: the
    /// gap that matters is to the button's BOTTOM EDGE, and that edge
    /// dropped ~1.5 cm when the card got taller.
    private static let podiumButtonLift: Float = 0.23
    /// How near the cap counts as offering the exhibit to it. Shares no
    /// constant with the button's lift — the two were the same number by
    /// coincidence, in five places, which is how one of them silently
    /// changes the other.
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
    /// Exhibits mid-glide back to their pucks (id → clock time when the
    /// idle loop may take their positions back). Without this grace the
    /// per-frame breathe write would stomp the return animation on its
    /// first frame and the exhibit would teleport home.
    private var returningIDs: [String: Double] = [:]

    /// A floating plate, front and centre: carry a lab here and it
    /// presents itself, with the Load button hanging above.
    private func buildPodium(distance: Float) {
        // Reach scales with the arc so the plate keeps its place in
        // front of the crescent at every distance setting; its HEIGHT
        // does not — it hangs at a fixed height, and nothing about the
        // gallery being pushed back changes how high a wearer's chest is.
        let plateBottom = Self.podiumPlateHeight
        let plateTop = plateBottom + Self.podiumPlateThickness
        podiumTop = SIMD3(0,
                          plateTop + GalleryLayout.exhibitLift,
                          -Self.podiumReach * (distance / 2.0))

        let graphite = Materials.graphite(Self.slabTint)

        let podium = Entity()
        podium.position = SIMD3(podiumTop.x, 0, podiumTop.z)
        let plate = ModelEntity(
            mesh: .generateCylinder(height: Self.podiumPlateThickness,
                                    radius: Self.podiumRadius),
            materials: [graphite])
        plate.position.y = plateBottom + Self.podiumPlateThickness / 2
        podium.addChild(plate)

        // The champagne rim — the same jeweller's line the title wears.
        var rim = UnlitMaterial(color: Self.titleRimColor)
        rim.blending = .transparent(opacity: 0.7)
        if let ring = Self.rimTube(radius: Self.podiumRadius, y: plateTop + 0.002) {
            ring.model?.materials = [rim]
            podium.addChild(ring)
        }

        // A soft pool on the plate that brightens when an exhibit is
        // near or docked — the pad answering the offer — and, hanging
        // below the plate, a smaller ring of the same light.
        //
        // The ring is what makes the plate read as DELIBERATELY
        // suspended rather than as a plinth whose column failed to
        // build: a floating slab with nothing under it is ambiguous,
        // and a floating slab over a second, smaller ring of light is
        // a thing being held up. It brightens with the pool because it
        // is the same answer to the same approach.
        let glow = Entity()
        var glowMaterial = UnlitMaterial(color: Self.titleRimColor)
        glowMaterial.blending = .transparent(opacity: 0.22)
        let pool = ModelEntity(
            mesh: .generateCylinder(height: 0.001, radius: Self.podiumRadius - 0.015),
            materials: [glowMaterial])
        pool.position.y = plateTop + 0.002
        glow.addChild(pool)
        if let hover = Self.rimTube(radius: Self.podiumRadius - 0.032,
                                    y: plateBottom - Self.podiumHoverGap) {
            var hoverMaterial = UnlitMaterial(color: Self.titleRimColor)
            hoverMaterial.blending = .transparent(opacity: 0.55)
            hover.model?.materials = [hoverMaterial]
            glow.addChild(hover)
        }
        glow.components.set(OpacityComponent(opacity: 0.35))
        podium.addChild(glow)
        podiumGlow = glow

        root.addChild(podium)
    }

    // MARK: The gallery's grab bar

    /// The whole-room move handle: a slim glass capsule hanging under
    /// the pad, front and centre — the same affordance as the bar under
    /// every visionOS window, for the same verb. Drag it and the whole
    /// gallery comes; a press that never moves it recentres.
    ///
    /// It replaced the Settings window's "Gallery" section
    /// (2026-08-03): distance/height sliders that repositioned by
    /// REBUILDING, on a rebuild path that duplicated the gallery.
    /// See `GalleryPlacement`.
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
            mesh: .generateBox(width: 0.24, height: 0.011, depth: 0.011,
                               cornerRadius: 0.0055),
            materials: [glass])
        bar.addChild(capsule)

        Grabbable.configureTouchTarget(bar, collisionRadius: 0.09)
        bar.components.set(HoverEffectComponent())
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

    private static func rimTube(radius: Float, y: Float) -> ModelEntity? {
        let points = (0...48).map { step -> SIMD3<Float> in
            let angle = Float(step) / 48 * 2 * .pi
            return SIMD3(cos(angle) * radius, y, sin(angle) * radius)
        }
        guard let mesh = TubeMesh.tube(lines: [points], radius: 0.0014, sides: 4)
        else { return nil }
        return ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
    }

    // MARK: Carrying an exhibit to the podium

    /// Starts a carry if the drag began on an exhibit. World → root
    /// space happens here, so Recenter's yaw never lies to the hand.
    func beginExhibitDrag(entity: Entity, world: SIMD3<Float>) -> Bool {
        guard draggingID == nil, let id = moduleID(for: entity),
              let exhibit = exhibits.first(where: { $0.moduleID == id }) else {
            return false
        }
        if dockedModuleID == id { dockedModuleID = nil; loadButton?.isEnabled = false }
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

    func endExhibitDrag() {
        guard let id = draggingID,
              let exhibit = exhibits.first(where: { $0.moduleID == id }) else {
            draggingID = nil
            return
        }
        draggingID = nil
        dragOffset = nil

        if simd_distance(exhibit.anchor.position, podiumTop) < Self.podiumSnapRadius {
            // Docked: the exhibit settles onto the pedestal and the
            // Load button appears above it.
            if let previous = dockedModuleID, previous != id,
               let old = exhibits.first(where: { $0.moduleID == previous }) {
                returningIDs[previous] = time + 0.45
                old.anchor.move(to: Transform(translation: old.basePosition),
                                relativeTo: root, duration: 0.4,
                                timingFunction: .easeInOut)
            }
            dockedModuleID = id
            exhibit.anchor.move(to: Transform(translation: podiumTop),
                                relativeTo: root, duration: 0.28,
                                timingFunction: .easeOut)
            SoundPalette.play(.chime, on: exhibit.anchor, volume: 0.6)
            seatLoadButton()
            loadButton?.isEnabled = true
            podiumGlow?.components.set(OpacityComponent(opacity: 1.0))
        } else {
            // Not offered: it glides home.
            returningIDs[id] = time + 0.5
            exhibit.anchor.move(to: Transform(translation: exhibit.basePosition),
                                relativeTo: root, duration: 0.45,
                                timingFunction: .easeInOut)
            podiumGlow?.components.set(OpacityComponent(opacity: 0.35))
        }
    }

    #if DEBUG
    /// Seats an exhibit on the podium immediately — CLI screenshots
    /// have no hand to carry one with.
    func dockForDebug(id: String) {
        guard let exhibit = exhibits.first(where: { $0.moduleID == id }) else { return }
        dockedModuleID = id
        exhibit.anchor.position = podiumTop
        seatLoadButton()
        loadButton?.isEnabled = true
        podiumGlow?.components.set(OpacityComponent(opacity: 1.0))
    }
    #endif

    /// A tap on an exhibit teaches the gesture: the podium flashes.
    func hintPodium() {
        guard let podiumGlow else { return }
        podiumGlow.components.set(OpacityComponent(opacity: 1.0))
        Task { @MainActor [weak podiumGlow] in
            try? await Task.sleep(for: .milliseconds(650))
            podiumGlow?.components.set(OpacityComponent(opacity: 0.35))
        }
    }

    // THE FLOOR POOL IS GONE (2026-07-31), and it is not coming back in
    // this form. It was three concentric translucent discs — 0.55, 0.85
    // and 1.10 m — laid 6 mm above y = 0 under the crescent's centre,
    // meant as "a soft warm pool that ties the floating architecture to
    // the room."
    //
    // It could not do that, because it did not know where the room was.
    // y = 0 is where the user happened to be standing when the immersive
    // space opened, not where their floor is; 6 mm of clearance is
    // nothing against that error or against depth precision at 1.5 m, so
    // the discs z-fought the passthrough floor and each other. And they
    // sat directly under the podium, which is the one place in the
    // gallery the eye is asked to go.
    //
    // Anything that wants to touch the real floor has to be placed off
    // `RoomModel`'s scanned geometry, like the labs' own room-aware
    // furniture. A guess at 6 mm is not a light pool, it is a bug with a
    // rationale.

    // MARK: The 3-D bubble title

    /// Just above the arc's centre — part of the gallery, not painted on
    /// the ceiling. Set from the arc geometry in build().
    private var titlePosition = SIMD3<Float>(0, 1.98, -2.05)

    /// Warm ivory, opaque, self-lit enough to hold its own against
    /// daylight. (It was a frosted grey at 80% opacity, which over a
    /// cream wall is a smudge.)
    private static let titleColor = HubTitleStyle.ivory
    /// The warm edge-light behind the letters — the thing that turns
    /// flat white type into something that looks lit. Champagne rather
    /// than gold: at full saturation it read as a toy.
    private static let titleRimColor = HubTitleStyle.champagne
    /// The lockup's overall width, metres. Both lines are scaled to
    /// exactly this, which is what makes it read as a designed mark.
    private static let titleWidth: Float = 0.60
    /// Gap between the two lines, as a fraction of a line's cap height.
    private static let titleLeading: Float = 0.30

    /// "Physics / Playground" as a two-line LOCKUP, not two words that
    /// happen to be near each other.
    ///
    /// Three things were wrong. It was not actually centred: `bubbleText`
    /// only ever centred on X, so every line hung with its baseline on
    /// the anchor and the whole block floated high. The two lines were
    /// spaced by a hard-coded ±12 cm unrelated to how tall the glyphs
    /// actually are. And "Physics" is seven characters against
    /// "Playground"'s ten, so at one point size the lines were wildly
    /// different widths and the pair read as an accident.
    ///
    /// Now both lines are measured and scaled to a common width, stacked
    /// with leading derived from their real cap height, and the whole
    /// block is centred on its anchor — the flush-both-sides two-line
    /// lockup that every good wordmark uses.
    private func buildBubbleTitle() {
        // Persistent. The wordmark was one-shot for a while (shown on
        // first launch only, then never again), and the room lost its
        // name: a gallery without a sign over the door reads as
        // someone's shelf, not a place. High over the crescent's
        // centre, it is the one piece of branding the room carries —
        // see DECISIONS.md 2026-07-29.
        titleAnchor.position = titlePosition

        let lines = ["Physics", "Playground"]
        // Build at a reference size, then scale each to the common width.
        let reference: CGFloat = 0.17
        let built = lines.map { text -> (entity: Entity, extents: SIMD3<Float>) in
            (HubTitleStyle.line(text, size: reference, accent: nil),
             HubTitleStyle.extents(text, size: reference))
        }
        let scales = built.map { Self.titleWidth / max($0.extents.x, 1e-4) }
        // Cap heights AFTER scaling — a wider scale makes taller letters.
        let heights = zip(built, scales).map { $0.0.extents.y * $0.1 }
        // Leading off the TALLEST line, not the average. The flush
        // lockup scales a short line up (7-character "Physics" against
        // 10-character "Playground"), so its cap height can far exceed
        // the mean — and an average-derived gap then lets the tall line
        // collide with its neighbour. Uppercase makes it worse, which
        // is how the plaque exposed it.
        let gap = (heights.max() ?? 0) * HubTitleStyle.leadingFactor
        let blockHeight = heights.reduce(0, +) + gap * Float(heights.count - 1)

        // Walk down from the top of the block, so the whole lockup ends
        // up centred on the anchor whatever the words are.
        var cursor = blockHeight / 2
        for (index, item) in built.enumerated() {
            let scale = scales[index]
            let height = heights[index]
            item.entity.scale = SIMD3(repeating: scale)
            item.entity.position.y = cursor - height / 2
            titleAnchor.addChild(item.entity)
            cursor -= height + gap
        }

        // A thin champagne rule under the lockup — the jeweller's line
        // that makes the mark read as set type rather than floating
        // words.
        var ruleMaterial = UnlitMaterial(color: Self.titleRimColor)
        ruleMaterial.blending = .transparent(opacity: 0.65)
        let rule = ModelEntity(
            mesh: .generateBox(width: 0.5, height: 0.004, depth: 0.004,
                               cornerRadius: 0.002),
            materials: [ruleMaterial])
        rule.position = SIMD3(0, -blockHeight / 2 - 0.09, 0)
        titleAnchor.addChild(rule)

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Physics Playground"
        titleAnchor.components.set(accessibility)
        root.addChild(titleAnchor)

        // Where the utility bar hangs: below the rule, clear of the
        // lockup whatever the current style's metrics did to it.
        titleBarSeat = SIMD3(0, -blockHeight / 2 - 0.20, 0.01)
    }

    // MARK: Attachment seats — SwiftUI riding the scene

    /// Local position under the wordmark for the utility bar.
    private var titleBarSeat = SIMD3<Float>(0, -0.35, 0.01)

    /// Parents the utility-bar attachment under the wordmark, so it
    /// inherits the title's bob and breathe — part of the lockup, not
    /// furniture floating near it.
    ///
    /// Scaled up: an attachment renders at SwiftUI's natural size
    /// (1 pt ≈ 0.7 mm), which is right for a panel at arm's length and
    /// doll's-house small on a wordmark two metres out. ×2.2 lands the
    /// buttons at about the wordmark rule's weight.
    func seatTitleBar(_ entity: Entity) {
        entity.position = titleBarSeat
        entity.scale = SIMD3(repeating: 2.2)
        titleAnchor.addChild(entity)
    }

    /// Parents the podium hint just under the cap's front rim, facing
    /// the user — a small plaque saying what the podium is FOR. The
    /// Load button hangs over the podium's top, so the two never
    /// collide. Same distance-compensating scale story as the bar.
    func seatPodiumHint(_ entity: Entity) {
        entity.components.set(BillboardComponent())
        entity.scale = SIMD3(repeating: 1.6)
        entity.position = SIMD3(podiumTop.x,
                                podiumTop.y - GalleryLayout.exhibitLift - 0.09,
                                podiumTop.z + 0.12)
        // Belt AND braces, per `stripInput`'s own doc comment:
        // `.allowsHitTesting(false)` governs the SwiftUI view's interior
        // and is not a promise about the entity hosting it, which can
        // still carry an input target and a collider sized to the card.
        // This one sits in the path of the very gesture it describes.
        stripInput(from: entity)
        root.addChild(entity)
    }

    /// The measured size of a run of the title face, for the lockup.
    /// Internal, not private: `HubDomainTitle` builds its two-line
    /// signage with the same measured-and-scaled lockup math.
    static func textExtents(_ text: String, size: CGFloat) -> SIMD3<Float> {
        MeshResource.generateText(
            text, extrusionDepth: Float(size) * 0.45,
            font: roundedFont(size: size), alignment: .center
        ).bounds.extents
    }

    /// The app's signature 3-D "bubble" type, in one reusable builder:
    /// fat rounded heavy glyphs extruded into a glossy clear-coated
    /// solid, centred on its own origin and returned as a group. The hub
    /// title and every exhibit name plate share this one treatment.
    ///
    /// "Centred" now means centred on BOTH axes. It only ever centred on
    /// X, so every run of this type hung with its baseline on the anchor
    /// and its visible mass floating above — which is why the hub title
    /// sat high in its ring and every exhibit name sat high under its
    /// miniature. One line, two words of a fix.
    ///
    /// `opacity` < 1 turns the letters to smoky glass; `emissive` sets
    /// how much they glow against the room.
    static func bubbleText(_ text: String, size: CGFloat, color: UIColor,
                           opacity: Float = 1, emissive: Float = 0.28) -> Entity {
        let group = Entity()
        let font = roundedFont(size: size)
        let mesh = MeshResource.generateText(
            text, extrusionDepth: Float(size) * 0.45,
            font: font, alignment: .center)
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

    /// SF Rounded at a heavy weight — the fat, round glyphs that make
    /// the extruded text read as bubbles.
    private static func roundedFont(size: CGFloat) -> MeshResource.Font {
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    private func buildExhibit(for module: ModuleDescriptor,
                              at basePosition: SIMD3<Float>,
                              domain: HubDomain,
                              progress: (done: Int, total: Int)) {
        let anchor = Entity()
        anchor.name = module.id
        anchor.position = basePosition
        // Invisible gaze/pinch target wrapping the whole miniature; the
        // hover highlight lights the miniature itself — no shell.
        anchor.components.set(InputTargetComponent())
        anchor.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: 0.19)]))
        anchor.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "Enter \(module.title). \(module.blurb)")
        anchor.components.set(accessibility)
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
        // MEASURED, then fitted to a common apparent size. Authoring
        // six models to a nominal size is not the same as six models
        // being the same size, and a gallery whose exhibits are wildly
        // different scales reads as an accident. Normalising from the
        // real bounds means a future model cannot break the rhythm
        // however it happens to be drawn.
        let bounds = vignette.visualBounds(relativeTo: nil).extents
        let largest = max(bounds.x, max(bounds.y, 1e-4))
        vignette.scale = SIMD3(repeating: Self.exhibitSize / largest)
        vignette.position = .zero
        pulser.addChild(vignette)

        // The floating name, always facing the user — the same 3-D
        // bubble type as the title, tinted in the module's accent. It
        // hangs just in front of the puck's edge, below the miniature,
        // so it captions the pedestal rather than the physics.
        let name = Self.namePlate(module.title, accent: UIColor(module.accent),
                                  size: 0.030)
        let namePivot = Entity()
        namePivot.position = [0, -0.105, 0.11]
        namePivot.components.set(BillboardComponent())
        namePivot.addChild(name)
        pulser.addChild(namePivot)

        // The module's own progress, worn as an arc behind the exhibit:
        // the domain-coloured arc of what is done, and a gold band once
        // everything is — the reward lives on the home screen itself.
        if progress.total > 0 {
            let ring = Self.progressRing(
                done: progress.done, total: progress.total,
                accent: UIColor(domain.color))
            ring.components.set(BillboardComponent())
            pulser.addChild(ring)
        }

        exhibits.append(Exhibit(
            moduleID: module.id, anchor: anchor, pulser: pulser,
            vignette: vignette, namePivot: namePivot, halo: glow,
            basePosition: basePosition, animate: built.animate))
    }

    /// The completed fraction drawn as an arc behind the miniature,
    /// billboarded so it reads as a dial without ever framing the model.
    /// There is deliberately no full-circle track under it: the faint
    /// white ring read as a halo AROUND every exhibit rather than as a
    /// dial, and came off at the owner's direction (2026-08-03).
    private static func progressRing(done: Int, total: Int,
                                     accent: UIColor) -> Entity {
        let ring = Entity()
        let radius: Float = 0.15
        let z: Float = -0.10
        let gold = DesignTokens.Palette.completionGoldUI
        let complete = done == total

        func circlePoints(fraction: Float, z: Float) -> [SIMD3<Float>] {
            let segments = max(Int(48 * fraction), 2)
            // Start at 12 o'clock, sweep clockwise as seen by the user.
            return (0...segments).map { step in
                let angle = .pi / 2 - 2 * .pi * fraction * Float(step) / Float(segments)
                return SIMD3(radius * cos(angle), radius * sin(angle), z)
            }
        }

        let fraction = Float(done) / Float(total)
        if fraction > 0.01,
           let arc = TubeMesh.tube(lines: [circlePoints(fraction: fraction,
                                                        z: z + 0.002)],
                                   radius: 0.0024, sides: 4) {
            var lit = UnlitMaterial(color: complete ? gold : accent)
            lit.blending = .transparent(opacity: complete ? 0.6 : 0.5)
            ring.addChild(ModelEntity(mesh: arc, materials: [lit]))
        }
        return ring
    }

    /// An exhibit's name, built to survive the room behind it.
    ///
    /// Saturated accent glyphs alone were legible while each exhibit sat
    /// on a dark card. With the cards gone the wall shows through, and a
    /// bright room under a mid-tone accent is the worst case for reading
    /// type: cyan on white, red on white, green on white.
    ///
    /// The title's trick — a slightly larger dark copy of the same text
    /// behind the glyphs — does not survive being shrunk to name size.
    /// Scaling a whole string moves every glyph outward from the centre,
    /// so at 36 mm the casing letters land between their own neighbours
    /// and the name reads as if it were printed twice, badly. What works
    /// at this size is an actual backing: one small dark plate, sized to
    /// the words it carries. Crisp accent type, guaranteed contrast, and
    /// nothing around the MODEL — which is the part that has to stay
    /// unframed.
    /// Internal, not private: the palette ring borrows this exact
    /// treatment for its slot labels, so the app has ONE nameplate.
    /// How wide the pill `namePlate` will build for this text.
    ///
    /// Exposed because a caller that mounts a label BESIDE something has
    /// to know how far it reaches: `namePlate` returns a plate centred on
    /// its own origin, so positioning it by a fixed offset works only
    /// while the text is short enough. The layers bank did exactly that
    /// and every label longer than 14 mm straddled the switch it named.
    /// One formula, two callers — a second copy of the padding arithmetic
    /// would drift the moment either changed.
    static func namePlateWidth(_ text: String, size: CGFloat = 0.036) -> Float {
        textExtents(text, size: size).x + Float(size) * 0.72 * 2
    }

    static func namePlate(_ text: String, accent: UIColor,
                          size: CGFloat = 0.036) -> Entity {
        let plate = Entity()

        let extents = textExtents(text, size: size)
        // Padding scales WITH the type: fixed values authored for the
        // gallery's 36 mm plates made a 10 mm palette label wear a
        // plate three text-heights wide — neighbouring labels collided
        // into one smear of backing.
        let padY = Float(size) * 0.44
        let width = namePlateWidth(text, size: size)
        let height = extents.y + padY * 2

        var backing = UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))
        backing.blending = .transparent(opacity: 0.58)
        let card = ModelEntity(
            mesh: .generatePlane(width: width, height: height,
                                 cornerRadius: height / 2),
            materials: [backing])
        card.position.z = -0.006
        plate.addChild(card)

        plate.addChild(bubbleText(text, size: size, color: accent, emissive: 0.6))
        return plate
    }

    /// The focus glow: a soft pool of the module's own colour behind the
    /// miniature, lit only for the exhibit you are facing.
    ///
    /// The exhibits wore CARDS for a while — a gradient face, a frame, a
    /// rule, a shadow. It made a tidy gallery and it buried the physics:
    /// nine little machines, each behind a pane. The models are the
    /// point, and they read better with nothing around them. So the
    /// furniture is gone and focus is expressed the only way that does
    /// not add any: the thing you are facing gets bigger, comes toward
    /// you, and sits in a pool of its own light.
    private static func focusGlow(accent: UIColor) -> Entity {
        // A pool of the module's colour ON the puck beneath the
        // miniature — the slab relights under the exhibit you face.
        // (It used to be a billboarded halo floating behind the model;
        // with real furniture underneath, light falling on a surface
        // reads as light.)
        let glow = Entity()
        for (radius, opacity) in [(Float(0.085), Float(0.30)),
                                  (Float(0.135), Float(0.15)),
                                  (Float(0.200), Float(0.06))] {
            var material = UnlitMaterial(color: accent)
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
            let disc = ModelEntity(
                mesh: .generateCylinder(height: 0.001, radius: radius),
                materials: [material])
            glow.addChild(disc)
        }
        glow.position = SIMD3(0, -GalleryLayout.exhibitLift + 0.006, 0)
        return glow
    }


    // MARK: Idle animation & interaction

    /// The exhibits hold their places on the ring; the life in them is
    /// their own physics running, plus a gentle bob — and the ANSWER to
    /// where you are looking.
    /// The gallery's whole-room placement, applied to `root` every
    /// frame. A transform, never a rebuild — see `GalleryPlacement`.
    var placement: GalleryPlacement?

    func animate(dt: Double, lookRay: (origin: SIMD3<Double>, direction: SIMD3<Double>)?) {
        time += dt
        if let placement {
            root.position = placement.offset
            root.orientation = simd_quatf(angle: placement.yaw, axis: [0, 1, 0])
        }
        fadeIn(dt: dt)
        updateFocus(lookRay: lookRay, dt: dt)

        for index in exhibits.indices {
            let focus = exhibits[index].focus
            let exhibit = exhibits[index]

            // An exhibit riding a hand, gliding home, or standing on
            // the podium owns its own position — the idle life must
            // not fight the carry, stomp the glide, or yank it off
            // the pedestal.
            if exhibit.moduleID == draggingID { continue }
            if let until = returningIDs[exhibit.moduleID] {
                if time < until { continue }
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
                // Standing centre stage, it says its own name — without
                // this the label keeps whatever opacity it happened to
                // have when it was carried off the arc, which for an
                // unfocused exhibit is invisible.
                exhibit.namePivot.components.set(OpacityComponent(opacity: 1))
                exhibit.halo.components.set(OpacityComponent(opacity: focus))
                exhibits[index].animTime += dt
                exhibit.animate(exhibits[index].animTime)
                continue
            }

            // Reduce Motion: the gallery holds still. Focus scaling
            // stays — it answers the user's own head, which is exactly
            // the motion Reduce Motion is not about.
            // Breathe, not bob: ±8 mm on a slow desynced period. The
            // exhibits stand on pedestals now, and furniture that
            // wanders off its pedestal reads as broken.
            let breathe = stillness ? 0
                : 0.008 * Float(sin(time * 1.05 + Double(index) * 2.1))
            // The focused exhibit lifts off its puck as it grows.
            let lift = Self.focusedLift * focus
            exhibit.anchor.position = exhibit.basePosition
                + SIMD3(0, breathe + lift, 0)

            let resting = hasLookRay ? Self.unfocusedScale : 1
            let scale = resting + (Self.focusedScale - resting) * focus
            exhibit.pulser.scale = SIMD3(repeating: scale)

            exhibit.halo.components.set(OpacityComponent(opacity: focus))
            // Every name stays legible ALL the time (owner, 2026-08-04,
            // reversing the materialise-on-gaze fade): a gallery whose
            // captions vanish until you stare at them cannot be read at
            // a glance, and the focus answer is already carried by the
            // lift, the growth and the halo.
            exhibit.namePivot.components.set(OpacityComponent(opacity: 1))

            if stillness { continue }

            // A gentle SWAY rather than a full turn. Spinning a
            // miniature all the way round shows it is a 3-D object, and
            // also swings the flat ones — the drumhead, the lens —
            // edge-on for half of every rotation, where they vanish.
            // It eases to a stop on the exhibit being read.
            let sway = 0.44 * Float(sin(time * 0.4 + Double(index) * 1.3))
            exhibit.vignette.orientation = simd_quatf(
                angle: sway * (1 - focus * 0.75), axis: [0, 1, 0])

            // Each exhibit runs on its own clock: paused outside the
            // field of view (work nobody can see), and a touch fast
            // while focused, so the one you turn to visibly comes alive.
            if exhibit.inView || focus > 0.01 || !hasLookRay {
                exhibits[index].animTime += dt * Double(1 + 0.6 * focus)
                exhibit.animate(exhibits[index].animTime)
            }
        }
        // The title floats and breathes, like a balloon on a string.
        let bob = stillness ? 0 : 0.02 * Float(sin(time * 0.6))
        titleAnchor.position = titlePosition + SIMD3(0, bob, 0)
        let titleBreathe = stillness ? 1 : 1 + 0.015 * Float(sin(time * 0.9))
        titleAnchor.scale = SIMD3(repeating: titleBreathe)

        // The hairlines shimmer slowly, each on its own phase — the
        // terraces are lit, not painted.
        if !stillness {
            for (index, domain) in HubDomain.allCases.enumerated() {
                guard let hairline = terraceHairlines[domain] else { continue }
                let shimmer = 0.72 + 0.16 * Float(sin(time * 0.5 + Double(index) * 1.7))
                hairline.components.set(OpacityComponent(opacity: shimmer))
            }
        }

        // The signage performs its physics — the electron laps the E&M
        // sign, the ball lobs over the Mechanics one — each door on its
        // own phase so the room never moves in lockstep. Called under
        // stillness too: that is how the signs PARK rather than freeze
        // mid-flight.
        for (index, domain) in HubDomain.allCases.enumerated() {
            domainTitles[domain]?.animate(time: time + Double(index) * 1.9,
                                          stillness: stillness)
        }
    }

    /// How far the gallery has faded up, 0…1.
    private var presence: Float = 0

    /// The gallery arrives rather than appears.
    ///
    /// A scene rebuild is a hard cut: the whole room is replaced between
    /// two frames. That is invisible on first entry — there was nothing
    /// there before — but changing the home's type style rebuilds the
    /// same room around you, and a hard cut there reads as a glitch
    /// rather than a change. Easing the whole tree up makes the switch
    /// a dissolve, and costs one opacity write per frame for half a
    /// second.
    ///
    /// Deliberately on the ROOT, not per-entity: every exhibit, sign
    /// and slab fades on the same curve, so nothing arrives early and
    /// breaks the illusion that the room re-set itself as one thing.
    private func fadeIn(dt: Double) {
        guard presence < 1 else { return }
        // Exponential approach, frame-rate independent, τ ≈ 0.18 s.
        presence = min(1, presence + (1 - presence)
            * Float(1 - exp(-dt / 0.18)))
        if presence > 0.999 {
            presence = 1
            // Land exactly, then stop touching the component at all —
            // a permanent OpacityComponent forces the whole gallery
            // down a transparency path it does not otherwise need.
            root.components.remove(OpacityComponent.self)
        } else {
            root.components.set(OpacityComponent(opacity: presence))
        }
    }

    private var hasLookRay = false

    /// Picks the exhibit nearest the user's look direction and eases
    /// every exhibit's focus value toward its target.
    /// Where to aim at an exhibit — for the gaze cone and the caption.
    ///
    /// Its puck on the arc, except while it stands on the podium, where
    /// it is somewhere else entirely. Aiming at the base regardless is
    /// what the first podium pass did, and it meant the exhibit centre
    /// stage could not be looked at while its abandoned puck went on
    /// catching the gaze — and the caption hung over the empty puck.
    /// Deliberately NOT the live anchor position: that carries the
    /// breathe and the focus lift, so focus would feed back into its
    /// own aim.
    private func aimPosition(of exhibit: Exhibit) -> SIMD3<Float> {
        if exhibit.moduleID == dockedModuleID { return podiumTop }
        // Riding a hand it is wherever the hand is. Reading the live
        // anchor is safe for exactly these two cases: the idle loop
        // skips them, so no breathe or lift is written into it.
        if exhibit.moduleID == draggingID { return exhibit.anchor.position }
        return exhibit.basePosition
    }

    private func updateFocus(lookRay: (origin: SIMD3<Double>,
                                       direction: SIMD3<Double>)?, dt: Double) {
        var winner: String?
        #if DEBUG
        // `-hubFocus <module id>` pins the focus so the focused state can
        // be screenshot-checked from the CLI: the simulator has no world
        // tracking, so there is no look ray to aim with.
        if let forced = UserDefaults.standard.string(forKey: "hubFocus"),
           exhibits.contains(where: { $0.moduleID == forced }) {
            hasLookRay = true
            applyFocus(winner: forced, dt: dt)
            return
        }
        #endif
        if let lookRay {
            hasLookRay = true
            // The whole scene may be moved and yawed by the grab bar;
            // bring the ray into the scene's own frame so the base
            // positions the math uses stay honest. `convert` carries
            // the translation as well as the yaw — the old
            // orientation-only inverse broke the moment the gallery
            // could be dragged.
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
                // Anything within ~60° is worth animating; the rest is
                // outside the headset's view and pauses.
                exhibits[index].inView = angle < 1.05
                // Hysteresis: the exhibit already in focus keeps it
                // unless another is clearly closer to where you look.
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
        // (A focus PANEL hung off this until 2026-08-04, positioned here
        // every frame through three placements — behind the exhibit,
        // below it, in front of the door sign. The owner cut it: the
        // gaze answer is the exhibit's own lift and halo, and the way
        // into a lab is the pad.)
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

    /// The chosen exhibit swells toward the user over the ~0.4 s before
    /// the module takes the stage — entering reads as an arrival rather
    /// than a hard cut. (A true cross-dissolve into the module scene
    /// would need both scenes alive at once; the swell carries the
    /// continuity on its own.)
    func beginEnterTransition(id: String) {
        guard let exhibit = exhibits.first(where: { $0.moduleID == id }) else { return }
        SoundPalette.play(.pop, on: exhibit.anchor, volume: 0.7)
        // The exhibit swells and rises off its pedestal as the module
        // takes the stage; its terrace's hairline flares with it.
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

// `HubFocusPanel` stood here until 2026-08-04 — the card that appeared
// over a focused exhibit with its promise, its progress and a Load
// button. The owner cut it: the gaze answer is the exhibit itself, and
// the ONE way into a lab is carrying it to the pad. Git history holds
// the card, including the experiment-step surface it carried; the flat
// catalog's next-step line still renders those strings.

/// The button that hangs over the pad while a lab stands on it — the
/// payoff for having carried that object across the room, and since
/// 2026-08-04 the only Load button in the gallery.
///
/// So it is built as a plaque rather than a control: the module's own
/// symbol in a disc of its own accent, the verb small and spaced above
/// the name, and the name at `.title2` — roughly 2× the old cap height,
/// ~22 cm wide, which is the width of the plate it stands over. At two
/// metres that is a target the eye lands on without hunting.
///
/// One thing here is load-bearing and looks cosmetic: the custom
/// `.hoverEffect` on the capsule. `.buttonStyle(.plain)` buys the
/// custom look by giving up the platform's own hover highlight, and on
/// visionOS the highlight is not decoration — it is the only feedback
/// that says "your gaze is on this and a pinch will land". The bare
/// default `.hoverEffect()` turned out to be invisible over this glass
/// on device (2026-08-03), so the effect is explicit: the plaque swells
/// and brightens under the gaze, unmistakably.
private struct HubLoadButton: View {
    let module: ModuleDescriptor
    let enter: () -> Void

    var body: some View {
        Button(action: enter) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(module.accent.gradient)
                    Image(systemName: module.icon)
                        // Semantic, so the glyph scales with Dynamic
                        // Type instead of rattling inside a fixed disc.
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 1) {
                    Text("LOAD MODULE")
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
            // Inside the glass, not around it: the stroke is the accent
            // catching the plate's edge, and a ring drawn outside the
            // glass reads as a second object.
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

/// The utility bar under the wordmark: the home's small chrome, kept to
/// three verbs, all real. Settings and the Lab Notebook open their
/// existing windows; About opens the credits panel. An Exit button
/// stood in the third seat briefly and was cut — visionOS offers no
/// supported way for an app to quit itself, and a button that can
/// never do what its icon promises is worse than no button.
private struct HubUtilityBar: View {
    let openSettings: () -> Void
    let openAbout: () -> Void
    let openNotebook: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
            }
            .accessibilityLabel("Settings")
            .accessibilityHint("Sound, hints and progress")

            Button(action: openNotebook) {
                Image(systemName: "book.closed.fill")
                    .font(.title3)
            }
            .accessibilityLabel("Lab Notebook")
            .accessibilityHint("Your captured observations")

            Button(action: openAbout) {
                Image(systemName: "info.circle")
                    .font(.title3)
            }
            .accessibilityLabel("About Physics Playground")
            .accessibilityHint("Credits and version")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassBackgroundEffect(in: Capsule())
    }
}
