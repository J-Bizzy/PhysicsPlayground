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
//  an exhibit and it lifts off its puck, names itself, and says in one
//  line what you actually do in there (`HubDomain.promise`).
//
//  ONE DOOR, REACHED TWO WAYS — and the door is the pad. An exhibit
//  standing on the plate floating front and centre turns there with Load
//  hanging over it, and that button is the only thing in this room that
//  opens a lab.
//
//  · TAP an exhibit and it flies to the pad by itself.
//  · Or CARRY it there, which is the better story and always was.
//
//  Neither one enters. That is the whole design: DECISIONS.md 2026-07-29
//  removed tap-to-enter because a shelf of six live miniatures you are
//  meant to look at makes a terrible activation surface, and a tap that
//  merely moves an object across the room does not bring the problem
//  back. The second pinch, on a button that names the lab it opens, is
//  where the commitment happens.
//
//  WHAT THIS REPLACED. From 2026-08-04 to 08-07 the pad was the ONLY way
//  in — a sustained ~1.1 m pinch-drag onto a 0.105 m plate — which broke
//  the app's own rule that nothing may be the only path to a capability.
//  An ENTER plaque on every puck fixed that and stood until 2026-08-09,
//  when the owner cut it along with the "Or carry a lab to the pad" card
//  at the pad's rim. Both were furniture explaining a gesture; the tap
//  performs the gesture instead. VoiceOver keeps a direct route — the
//  exhibit publishes an "Enter" action and a plain activate — because
//  a two-step ceremony is a worse deal for someone sweeping the room.
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
            // Stillness FIRST: `build` ends by starting the arrival
            // intro, and Reduce Motion's answer to it is a plain
            // dissolve — the decision has to exist before the decider.
            scene.stillness = systemReduceMotion
            #if DEBUG
            // `-hubIntro <seconds>` freezes the arrival at that instant
            // — the intro is wall-clock and gone in four seconds, which
            // no simctl invocation can reliably catch mid-flight. Read
            // BEFORE `build`, because `build` ends by starting the
            // intro and `beginIntro` decides both the once-per-session
            // skip and the chime off this value.
            // `double(forKey:)` coerces the argument domain's string.
            let frozenIntro = UserDefaults.standard.double(forKey: "hubIntro")
            if frozenIntro > 0 {
                scene.introFrozenAt = frozenIntro
            }
            #endif
            // The ceremony is for ARRIVING. This scene is rebuilt on
            // every return from a lab, and a walk back from Circuits
            // is not an arrival — so the flight, the cascade and the
            // bell play once per session and every later entry opens
            // on the finished room.
            //
            // MARKED PLAYED WHEN THE INTRO FINISHES, NOT HERE. This
            // closure can run for a view the system then discards
            // while presenting the space — marking at build time let
            // that invisible first pass consume the session's one
            // arrival, and the pass the wearer actually saw opened on
            // the finished room. That was the launch-day symptom:
            // title already at the wall, everything "loaded in too
            // soon". A ceremony only counts once somebody has seen it
            // land.
            scene.arrivalAlreadyPlayed = appModel.hasPlayedArrival
            scene.onArrivalPlayed = { appModel.hasPlayedArrival = true }
            SoundPalette.warmUp()
            scene.build(modules: modules)
            scene.placement = appModel.galleryPlacement
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

            // VOICEOVER CAN OPEN A LAB.
            //
            // Every exhibit's label has promised "Enter <module>" since
            // the gallery shipped, against a tap handler that only
            // flashed a distant plate — so the one thing the label said
            // you could do was the one thing it could not.
            //
            // AND IT GOES STRAIGHT IN, which is the one place this door
            // is not the pad. A sighted tap flies the lab to the plate
            // and asks for a second pinch on the Load button; routing
            // VoiceOver the same way would mean sweeping the room again
            // to find a button that moved somewhere new — a ceremony
            // whose whole payload is visual, charged to the person who
            // cannot collect it. The exhibit publishes both a plain
            // `.activate` and an "Enter" custom action, and both enter.
            //
            // This is the app's FIRST `AccessibilityEvents`
            // subscription. A grep for `systemActions` returned zero
            // matches across the whole project before it, so every
            // plate, petal, disc, rail and well in six labs is
            // announced, readable, and impossible to operate. Phase 2
            // closes that with one subscription in `PlaygroundSpaceView`;
            // the front door could not wait for it.
            //
            // ONE MECHANISM, NOT TWO. This walked entity names looking
            // for the `enter-` prefix, which was the right call on
            // 2026-08-07 — the front door could not wait for Phase 2's
            // component to exist. It exists now, and a second bespoke
            // route is how the two drift apart: the ENTER plaque worked
            // and the exhibit beside it did not, because only one of
            // them was in this closure. `SpatialActions.activate` walks
            // ancestors for whatever knows what to do, exactly as it
            // does in every lab.
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
                    openNotebook: { openWindow(id: NotebookView.windowID) })
            }
            // THE PAD TEACHES ITSELF NOW (2026-08-09). A card reading
            // "Or carry a lab to the pad" used to hang at the pad's rim,
            // because the carry was a gesture nobody discovers on their
            // own and the plaque beside each exhibit was the path that
            // did not need explaining. Both are gone: a tap on an exhibit
            // now SENDS it to the pad, so the first thing anyone tries
            // performs the ceremony and shows them where it lands. A
            // sentence describing a gesture is worth less than a gesture
            // that demonstrates itself, and this one cost a collider
            // standing in the path of the very drag it described.
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
            scene.accessibilitySubscriptions.forEach { $0.cancel() }
            scene.accessibilitySubscriptions = []
            // An exhibit still in the hand when the gallery goes away.
            // Nothing else clears the carry: without this it survives in
            // `scene` and every later drag re-targets the same exhibit.
            scene.cancelExhibitDrag()
            appModel.room.release()
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // A TAP SENDS THE LAB TO THE PAD (owner, 2026-08-09).
                    //
                    // This is the third answer to "how do you get into a
                    // lab", and it is the first one that does not have to
                    // be explained. A bare tap-to-ENTER was removed on
                    // 2026-07-29 because it made the whole gallery an
                    // accidental-activation surface — glance at a shelf
                    // of six live miniatures, pinch by reflex, and you
                    // are somewhere else. That reasoning still stands and
                    // this does not violate it: a tap moves an object
                    // across the room, it does not leave the room. The
                    // door is still the Load button, and it is still a
                    // second, deliberate pinch at a different place.
                    //
                    // What it replaces is `hintPodium`, which flashed the
                    // pad to say "bring it here" — a demonstration that
                    // asked you to go and do the thing yourself. Doing it
                    // FOR you teaches the same lesson, leaves the lab
                    // sitting where the carry would have put it, and
                    // means the ceremony's destination is discovered by
                    // the most obvious gesture in the room rather than by
                    // a caption at its rim.
                    guard let id = scene.moduleID(for: value.entity) else { return }
                    scene.sendToPad(id: id)
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
        // Against the DRAG'S OWN START — see `RelativeDrag.travel`. This
        // measured against `placement.offset`, which the next line
        // overwrites, so moving the whole gallery at a human speed was
        // read as a tap and snapped it home again.
        barTravelled = max(barTravelled, Float(barDrag.travel(forHand: hand)))
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

    /// What VoiceOver calls the exhibit's "open this lab" action.
    ///
    /// `AccessibilityEvents.CustomAction` reports the action by its
    /// `LocalizedStringResource`, and the delivered copy is not the same
    /// instance, so the match is on `.key` — which for a resource built
    /// from a literal IS that literal. One constant, used both to
    /// declare the action on each exhibit and to recognise it coming
    /// back, so the two cannot drift apart.
    static let enterAction = LocalizedStringResource("Enter")

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
    /// Held for the same reason `subscription` is — an `EventSubscription`
    /// outlives the view that made it. See `HubSpaceView.onDisappear`.
    var accessibilitySubscriptions: [EventSubscription] = []

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
        /// The focus value the opacity components were last WRITTEN at.
        /// `-1` forces a rewrite — the idle loop used to push three
        /// `OpacityComponent`s per exhibit per frame (eighteen a frame,
        /// forever, mostly carrying values that had long settled), and
        /// now writes only when focus has actually moved. The special
        /// states (carried, gliding home, docked) park this at -1 so
        /// their first idle frame always repaints, which is what keeps
        /// the "stale invisible label" bug this replaced from coming
        /// back.
        var appliedFocus: Float = -1
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

    // MARK: The arrival

    /// Everything that is not the wordmark, under one entity so the
    /// intro can raise the room as a unit while the title holds the
    /// stage. Identity transform — reparenting changes no coordinates.
    private let stageRoot = Entity()
    private enum IntroPhase { case pending, running, done }
    /// Once per scene: a placement rebuild must not replay the theatre.
    private var introPhase: IntroPhase = .pending
    private var introStart = 0.0
    /// `-hubIntro <seconds>` pins the intro clock here — the arrival is
    /// wall-clock and over in under four seconds, which no `simctl`
    /// invocation can reliably catch mid-flight. Frozen, it never
    /// finishes; that is the point of a photograph.
    var introFrozenAt: Double?
    /// True when this SESSION has already seen the ceremony — set from
    /// `AppModel` before `build`, because the scene itself is remade
    /// on every hub entry and cannot remember across its own lifetime.
    /// A frozen screenshot intro overrides it: `-hubIntro` exists to
    /// photograph the flight, and a skip would photograph its absence.
    var arrivalAlreadyPlayed = false
    /// Fired the frame the ceremony completes — the view marks the
    /// session's `hasPlayedArrival` off this, and ONLY this, so a
    /// discarded pre-presentation build can never spend the arrival.
    var onArrivalPlayed: (() -> Void)?

    /// The intro's clock: frozen for screenshots, infinite (= finished)
    /// under stillness, live otherwise.
    private var introTime: Double {
        stillness ? .infinity : (introFrozenAt ?? (time - introStart))
    }
    /// The 3-D bubble title the exhibits ring, bobbing at the centre.
    private let titleAnchor = Entity()

    // MARK: Layout — the Gallery
    //
    // A crescent of TWO domain terraces — six labs behind two doors
    // since the 2026-07-30 rebuild; this said "four" until 2026-08-09.
    // Authored and computed in
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

    func build(modules: [ModuleDescriptor]) {
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

        // 0.70 ABOVE THE ARC UNTIL 2026-08-08, then 0.52 on the owner's
        // call to bring it down, and 0.62 once a screenshot showed what
        // 0.52 collided with.
        //
        // The collision is between two changes made the same day and
        // neither wrong alone: the main window STOPPED BLANKING when the
        // gallery opens (Phase 1 — the flat catalog is the accessibility
        // path and hiding it was the defect), and the wordmark came
        // down. The window now sits permanently where the mark was
        // lowered into, and the two overlapped in the first picture of
        // the gallery anyone has taken.
        //
        // 0.66 is the compromise: lower than it was, and clear of the
        // window's top edge, which 0.62 still grazed. Some overlap is
        // inherent — the catalog is a system window the wearer can move
        // and the mark is anchored to the arc — so this buys separation
        // at the DEFAULT placement rather than pretending to guarantee
        // it everywhere.
        titlePosition = SIMD3(0, arcHeight + 0.66, -(arcRadius + 0.45))
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
                             at: terrace.exhibitPositions[index])
            }
        }

        // THE STAGE: the furniture — terraces, podium, rail — under one
        // entity so the arrival can raise it as a unit (`HubIntro`).
        // The exhibits and the door signs deliberately STAY top-level:
        // they cascade on their own components, and the tap chain and
        // `GalleryDoorTests` both resolve exhibits as direct children
        // of the root — a contract worth keeping over a tidier tree.
        // Reparenting after the build touches no coordinates (the stage
        // sits at identity) and no stored reference.
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

    /// Starts the arrival — once per scene, and never under Reduce
    /// Motion, whose entrance is the root dissolve `fadeIn` already
    /// provides: no flying title, no wave.
    private func beginIntro() {
        guard introPhase == .pending else { return }
        guard !stillness else { introPhase = .done; return }
        if arrivalAlreadyPlayed && introFrozenAt == nil {
            introPhase = .done
            return
        }
        introPhase = .running
        introStart = time
        // Hidden before the first frame draws, so nothing pops in
        // ahead of its cue.
        titleAnchor.components.set(OpacityComponent(opacity: 0))
        stageRoot.components.set(OpacityComponent(opacity: 0))
        for exhibit in exhibits {
            exhibit.anchor.components.set(OpacityComponent(opacity: 0))
        }
        for title in domainTitles.values {
            title.root.components.set(OpacityComponent(opacity: 0))
        }
        // The room's clock, made audible: the swell under the beat and
        // the bell at the landing are baked into one file whose timing
        // HubIntroTests pins to this choreography. Played from the
        // title, so the sound stands where the eye is — and not at all
        // for a frozen screenshot intro, where the visuals hold still
        // and a real-time WAV playing under them belongs to nothing.
        if introFrozenAt == nil {
            SoundPalette.play(.calibration, on: titleAnchor, volume: 0.55)
        }
    }

    /// Drives every intro curve, then removes its components and goes
    /// quiet — the per-frame path stops touching what stopped changing.
    private func updateIntro() {
        guard introPhase == .running else { return }
        // Reduce Motion arriving mid-flight parks everything at rest.
        // A FROZEN intro never finishes — that is the point of a
        // photograph. Without this exemption, `-hubIntro` past the
        // landing (~2.6 s) fell through `isFinished` and shot the
        // completed room instead of the held pose the argument
        // promised. Stillness still wins: its answer to the intro is
        // the plain dissolve, frozen or not.
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
            // The bar sat out the flight; the mark has landed, so the
            // controls may take their seat under it.
            titleBar?.isEnabled = true
            // The ceremony has been SEEN — only now does it count
            // against the session.
            onArrivalPlayed?()
            return
        }
        titleAnchor.components.set(
            OpacityComponent(opacity: HubIntro.titleOpacity(at: t)))
        stageRoot.components.set(
            OpacityComponent(opacity: HubIntro.stageOpacity(at: t)))
        for (index, exhibit) in exhibits.enumerated() {
            // The idle loop's own exemption, mirrored: a lab the hand
            // has docked or is carrying belongs to that interaction.
            // Without this, a lab tapped mid-intro was forced back to
            // arrival opacity every frame and landed on the pad
            // invisible, popping in only when the ceremony ended. The
            // scale write is the handover — nothing else restores it
            // once this loop stops owning the exhibit.
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
    /// One domain's terrace: an optical bench, tiled from modelled bays,
    /// with a lit hairline of the domain's colour lying in the machined
    /// channel along its front edge and a kinematic mount per module.
    /// Architecture BENEATH the physics, never around it — the
    /// miniatures stay shell-free.
    private func buildTerrace(_ terrace: GalleryLayout.Terrace) {
        let slab = Entity()
        slab.position = terrace.center
        slab.orientation = simd_quatf(angle: terrace.yaw, axis: [0, 1, 0])
        buildBenchTop(terrace, on: slab)

        var lit = UnlitMaterial(color: UIColor(terrace.domain.color))
        lit.blending = .transparent(opacity: 0.85)
        let hairline = ModelEntity(
            mesh: .generateBox(width: max(terrace.width - 0.05, 0.1),
                               height: 0.004, depth: 0.004,
                               cornerRadius: 0.002),
            materials: [lit])
        // IN the channel now, not on the surface. It sat 2 mm proud of a
        // featureless slab because there was nothing to sit in; the bay
        // is milled with a trough along its front rail, and a light
        // lying in a trough is a light pipe, while the same light
        // balanced on a flat edge is a strip stuck to it.
        hairline.position = SIMD3(0, GalleryLayout.slabThickness / 2 - 0.002,
                                  GalleryLayout.slabDepth / 2 - 0.0095)
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
            // Placed AT the top face, not at the centre: every modelled
            // platform here is drawn hanging below its own origin, so a
            // call site never repeats a half-thickness.
            let mount = Self.loadPlatform(
                "GalleryMount",
                fallback: {
                    let puck = ModelEntity(
                        mesh: .generateCylinder(
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

    /// Lays the terrace's top out of modelled tiles: two end caps and
    /// one bay per module.
    ///
    /// WHY TILES AND NOT ONE SLAB. `GalleryLayout` sizes a terrace from
    /// its module count — `basePuckPitch · n + baseWidthMargin` — so no
    /// single asset can be the right width for a catalog that changes.
    /// The alternative is stretching one, and stretching a drilled bench
    /// turns every hole into an ellipse, which is the exact tell that
    /// says an object was resized rather than built. Real optical
    /// benches bolt together out of sections, so the honest asset is a
    /// section: `Tools/galleryplatforms.py` writes a 0.36 m bay and a
    /// 0.04 m cap, and 0.36·n + 2 × 0.04 is the layout's own formula.
    ///
    /// The bay is scaled in X ONLY, and by exactly 1.0 at the shipped
    /// geometry. The scale exists because `GalleryLayout` still takes a
    /// distance and multiplies the plan by it — the sliders that drove
    /// that are gone, but the math is live and tested, so the tiling
    /// closes at any of its values rather than leaving a gap that only
    /// appears if someone reopens the setting. Depth and thickness are
    /// never scaled: the layout does not scale them either.
    private func buildBenchTop(_ terrace: GalleryLayout.Terrace,
                               on slab: Entity) {
        let capWidth = GalleryLayout.baseWidthMargin / 2
        let bays = max(terrace.moduleIDs.count, 1)
        let bayWidth = (terrace.width - capWidth * 2) / Float(bays)

        // THE FALLBACK IS A REAL SHELF. Following `TimeRail.buildReel`:
        // if the asset does not load, the gallery must still have
        // terraces, because a missing floor under six exhibits is not a
        // degraded look, it is six labs hanging in the air.
        guard let bay = PropCache.prototype(named: "GalleryBay"),
              let cap = PropCache.prototype(named: "GalleryCap") else {
            let box = ModelEntity(
                mesh: .generateBox(width: terrace.width,
                                   height: GalleryLayout.slabThickness,
                                   depth: GalleryLayout.slabDepth,
                                   cornerRadius: 0.03),
                materials: [Materials.graphite(Self.slabTint)])
            slab.addChild(box)
            return
        }

        // Tiles are modelled with their top face at the origin; the slab
        // node sits at the terrace's mid-thickness, so everything hangs
        // from its top.
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

    /// A modelled platform, cloned from the shared `PropCache`: six
    /// mounts and three bays per terrace are the same mesh, and the
    /// cache is what stops that being six parses.
    private static func loadPlatform(_ name: String,
                                     fallback: () -> Entity) -> Entity {
        PropCache.instance(named: name) ?? fallback()
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

        let podium = Entity()
        podium.position = SIMD3(podiumTop.x, 0, podiumTop.z)

        // THE PAD IS A DOCKING CRADLE, not a larger version of the pucks
        // it takes labs from. It was a plain cylinder, 2 cm wider than a
        // terrace puck and made of the same stock, which is the shape
        // that says "another shelf" — and this is the one platform in
        // the room that is not a shelf. It is the door.
        //
        // Hexagonal, milled with a pocket, and ringed by three latch
        // fingers that close when a lab lands. See `setLatches`.
        let cradle = Self.loadPlatform(
            "GalleryCradle",
            fallback: {
                let plate = ModelEntity(
                    mesh: .generateCylinder(height: Self.podiumPlateThickness,
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

        // The champagne rim — the same jeweller's line the title wears.
        //
        // HEXAGONAL, AND INSET. It was a 48-segment circle at exactly
        // `podiumRadius`, which was right while the pad was a cylinder
        // of that radius and became wrong the moment it became a hex:
        // a circle through a hexagon's circumradius runs OUTSIDE the
        // flats and INSIDE the vertices, so the line sawed through the
        // body six times per lap. Six segments follow the edge it is
        // drawing, and 0.099 keeps it on the top face rather than
        // balanced on the chamfer.
        var rim = UnlitMaterial(color: Self.titleRimColor)
        rim.blending = .transparent(opacity: 0.7)
        if let ring = Self.rimTube(radius: 0.099, y: plateTop + 0.002,
                                   segments: 6) {
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
        // INTO THE POCKET, not onto the lid. The pool was a disc 2 mm
        // above a flat plate, which is what the pad used to be; the
        // cradle is milled 8 mm deep, so the same disc hung in the air
        // over the recess it was meant to be lighting. Sized to the
        // pocket and laid 2.5 mm above its floor, it is light collecting
        // in the receptacle — which is also the only place on this
        // object where a soft glow has a surface to fall on.
        let pool = ModelEntity(
            mesh: .generateCylinder(height: 0.001, radius: 0.068),
            materials: [glowMaterial])
        // −0.0035, measured against the ASSET rather than against the
        // pocket's nominal depth. The pocket is cut to −0.008 but a
        // lighter floor plate lies in it, and its top face is at
        // −0.0045; a pool at −0.0055 — which is where "2.5 mm above the
        // pocket floor" puts it — would have been sealed underneath that
        // plate and drawn nothing at all. This sits 1 mm above the
        // surface the light is supposed to be falling on.
        pool.position.y = plateTop - 0.0035
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

    // MARK: The cradle's latches

    /// The three fingers, held so the dock and the release can turn them.
    private var latchPivots: [Entity] = []

    /// How far a finger stands off the cradle's centre, and the two
    /// angles it lives between. Open is a raised, offering pose; closed
    /// lays the tip down over the pocket's rim.
    /// Mirrors `POST_RADIUS` in `Tools/galleryplatforms.py` — the fingers
    /// have to turn on the posts the cradle actually carries.
    private static let latchRadius: Float = 0.082
    private static let latchOpen: Float = 0.62
    private static let latchClosed: Float = -0.10

    /// Rings the pad with its latch fingers.
    ///
    /// Each finger is two nested entities: a SEAT carrying the placement
    /// around the ring, and a PIVOT inside it carrying nothing but the
    /// hinge angle. One transform per job — the alternative is composing
    /// a yaw and a hinge into a single quaternion on every frame of the
    /// animation, which is how a finger ends up swinging out of its own
    /// socket halfway through.
    ///
    /// The model reaches along −Z from its pivot, so a finger seated at
    /// ring angle θ is yawed by π/2 − θ to point at the centre.
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

    /// Closes the latches over a docked lab, or opens them again.
    ///
    /// THIS IS THE ARRIVAL. A tap now flies a miniature across the room
    /// to the pad, and without this the flight simply stops — the lab is
    /// at the pad because its coordinates say so. Three fingers folding
    /// over it is the difference between stopping there and being
    /// received, and it costs three rotations.
    ///
    /// Stilled under Reduce Motion by jumping to the pose rather than
    /// skipping it: the fingers are a READOUT of whether the pad is
    /// holding something, and a readout that only updates for people who
    /// tolerate animation is not a readout.
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

        // A HANDLE IS A BAR. A 0.09 m sphere on a capsule 11 mm thick
        // put an 18 cm ball in front of the podium the handle stands at.
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

    /// A ring of tube. `segments` is 48 for a circle and 6 for a line
    /// that has to lie on the hex cradle's own edge — a ring whose
    /// segment count disagrees with the solid it decorates intersects it
    /// once per facet.
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

    /// Starts a carry if the drag began on an exhibit. World → root
    /// space happens here, so Recenter's yaw never lies to the hand.
    func beginExhibitDrag(entity: Entity, world: SIMD3<Float>) -> Bool {
        guard draggingID == nil, let id = moduleID(for: entity),
              let exhibit = exhibits.first(where: { $0.moduleID == id }) else {
            return false
        }
        if dockedModuleID == id {
            dockedModuleID = nil
            loadButton?.isEnabled = false
            // Lifted out of the cradle: the fingers let go first.
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

    /// Abandons a carry that will never receive its `onEnded` — the
    /// gallery closing under the hand. The exhibit glides home rather
    /// than being seated, because nobody chose to seat it.
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
            // Docked: the exhibit settles onto the pedestal and the
            // Load button appears above it. 0.28 s, because the hand
            // released it within 34 cm of the pad — it has almost
            // arrived already, and a long glide over a short distance
            // reads as the object being taken off you.
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

    /// Seats an exhibit on the pad: whatever was there goes home, this
    /// one flies in, and the Load button comes up over it.
    ///
    /// ONE dock, three callers — the released carry, the tap, and the
    /// debug seat. They differ only in how long the flight takes, and
    /// that is the whole reason this is a function: the carry's version
    /// grew a chime, a glow, a returning-grace entry and an eviction over
    /// several passes, and a tap that re-implemented "put it on the pad"
    /// would have had to grow all four again, correctly, from memory.
    private func dock(_ exhibit: Exhibit, id: String, duration: Double) {
        // EVICT FIRST. Two labs cannot stand on one pad, and the one
        // being replaced has to be told to go home before `dockedModuleID`
        // forgets it was ever there.
        if let previous = dockedModuleID, previous != id,
           let old = exhibits.first(where: { $0.moduleID == previous }) {
            returningIDs[previous] = time + 0.45
            old.anchor.move(to: Transform(translation: old.basePosition),
                            relativeTo: root, duration: 0.4,
                            timingFunction: .easeInOut)
        }
        dockedModuleID = id
        // NO `returningIDs` GRACE HERE, unlike the glide home. The idle
        // loop's docked branch is the one arm that never writes
        // `anchor.position` — it only turns the miniature and lights its
        // name — so the flight is unopposed, and a grace entry would
        // instead skip the branch and freeze the lab's physics for the
        // whole way in.
        exhibit.anchor.move(to: Transform(translation: podiumTop),
                            relativeTo: root, duration: duration,
                            timingFunction: .easeOut)
        SoundPalette.play(.chime, on: exhibit.anchor, volume: 0.6)
        seatLoadButton()
        loadButton?.isEnabled = true
        podiumGlow?.components.set(OpacityComponent(opacity: 1.0))

        // The latches close AS IT LANDS, not as it sets off — they are
        // the cradle answering the arrival, and fingers that fold shut
        // over an empty pocket while the lab is still crossing the room
        // are a machine closing on nothing.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration * 0.75))
            guard let self, self.dockedModuleID == id else { return }
            self.setLatches(closed: true, duration: 0.26)
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
        setLatches(closed: true, duration: 0)
    }
    #endif

    /// A tap on an exhibit sends it to the pad — the gallery's reachable
    /// door since the ENTER plaque came off on 2026-08-09.
    ///
    /// SLOWER THAN THE CARRY'S LANDING, and deliberately so. A released
    /// carry is already at the pad and 0.28 s finishes a movement the
    /// hand began; this one crosses the better part of a metre from a
    /// terrace the wearer is looking AT, and the flight is the only thing
    /// that says where their lab went. Fast enough not to be a wait,
    /// slow enough to be followed.
    ///
    /// A tap on the lab ALREADY on the pad is not a second door — it is
    /// ignored, because re-flying an object to the spot it occupies is a
    /// glitch, and because the Load button is sitting over it.
    func sendToPad(id: String) {
        guard dockedModuleID != id, !isCarrying,
              let exhibit = exhibits.first(where: { $0.moduleID == id })
        else { return }
        dock(exhibit, id: id, duration: 0.5)
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

    /// The warm edge-light behind the letters — the thing that turns
    /// flat white type into something that looks lit. Champagne rather
    /// than gold: at full saturation it read as a toy.
    private static let titleRimColor = HubTitleStyle.champagne
    /// The lockup's overall width, metres. Both lines are scaled to
    /// exactly this, which is what makes it read as a designed mark.
    private static let titleWidth: Float = 0.60

    // `titleColor` and `titleLeading` were deleted 2026-08-09, both
    // unread. They are what is left of the wordmark BEFORE the machined
    // plaque: a colour and a line gap are the two knobs flat extruded
    // type has, and the plaque draws its own keyline per glyph and
    // spaces its two lines from the cap height it measures. The plaque
    // shipped 2026-08-02 and these two have described nothing since.

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
        //
        // MEASURED FROM WHAT IS BUILT, which both builders below
        // guarantee by returning their own extents. It matters most for
        // the milled line, whose numbers come out of an asset rather
        // than out of the font: ask `extents` instead and the lockup
        // scales a line by a width nothing in the room actually has.
        let reference: CGFloat = 0.17
        // MILLED IF THE ASSET IS THERE, generated if it is not. Both
        // return the same (entity, extents) pair and both come back
        // centred on their own origin, so everything below this line is
        // indifferent to which one answered — which is the point. The
        // generated builder is not a stub: it is what shipped, it is
        // what the tests drive, and it stays correct.
        let built = lines.map { text in
            HubTitleStyle.milled(text, size: reference, accent: nil)
                ?? HubTitleStyle.generated(text, size: reference, accent: nil)
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
        // Kept for the rake. The LINES turn, not the anchor: the utility
        // bar is parented to `titleAnchor` (see `seatTitleBar`), and
        // swinging a row of buttons through a degree and a half would
        // make them harder to hit for the sake of a highlight.
        titleLines = built.map(\.entity)

        // THE BACKING PLATE STOOD HERE FOR ONE DAY, and what replaced it
        // is the same idea with the rectangle taken out.
        //
        // The mark is ivory machined metal and the room behind it is
        // somebody's wall — cream, in the first screenshot ever taken of
        // it, which showed the wordmark as a barely-there ghost. The
        // obvious fix, pushing the emissive from 0.16 to 0.34, did
        // nothing: the letters were never dim, and light-on-light has no
        // contrast however bright the light. DECISIONS.md settled the
        // principle on 2026-07-26 in four words — CASINGS BEAT GLOWS —
        // and the layer-bank plates a metre away in that same screenshot
        // are perfectly legible on dark stock.
        //
        // So on 2026-08-08 the lockup got a 0.10-white plate at 82%
        // behind it, sized from the measured block. It worked, and the
        // owner cut it the next day: the contrast was wanted, a black
        // panel hanging in the room was not.
        //
        // The casing then became PART OF THE LETTERS — a dark shell
        // swelled around each glyph — and on 2026-08-11 the owner cut
        // that too. Three answers to one question in four days: a plate,
        // an outline, nothing.
        //
        // Nothing is the right one now, and it was not before, because
        // the letters changed underneath the question. The mark is
        // milled (`Tools/hubtitles.py`), so every stroke carries a
        // chamfer, and a chamfer holds a bright rim against a wall of
        // any brightness — which is the job the plate and the outline
        // were both hired to do. The contrast is still wanted. It is
        // just in the letterform now, where it costs nothing and reads
        // from every angle.

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

    /// The wordmark's two lines, held so the rake can turn them.
    private var titleLines: [Entity] = []

    /// Local position under the wordmark for the utility bar.
    private var titleBarSeat = SIMD3<Float>(0, -0.35, 0.01)
    /// The seated bar, held so the intro can bench it: window controls
    /// riding the wordmark's opening flight read as loose UI swooping
    /// through the room, so the bar sits out the ceremony and appears
    /// with the landing.
    private var titleBar: Entity?

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
        // Benched while the arrival plays (and for a frozen screenshot
        // intro, which never finishes): the flight is the wordmark
        // alone. `updateIntro`'s landing re-enables it.
        entity.isEnabled = introPhase != .running
        titleAnchor.addChild(entity)
        titleBar = entity
    }

    /// Opens a lab. Set by the view, and reached from the exhibit's
    /// VoiceOver actions and from the Load button — see the note on
    /// `accessibilitySubscriptions`.
    var onEnter: ((String) -> Void)?

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

    /// `domain` WAS A PARAMETER HERE and is not any more. Its only use
    /// was tinting the progress ring, so it left with the experiments —
    /// an exhibit's own accent comes from its `ModuleDescriptor`, and the
    /// terrace it stands on is what says which domain it belongs to.
    private func buildExhibit(for module: ModuleDescriptor,
                              at basePosition: SIMD3<Float>) {
        let anchor = Entity()
        anchor.name = module.id
        anchor.position = basePosition
        // The gaze/pinch target is set at the BOTTOM of this function,
        // once the miniature exists, and is measured from THAT alone —
        // not from the name plate or the progress ring, for reasons
        // given at the site. It was a 0.19 m sphere —
        // 0.38 m across against a puck pitch of 0.36 — so every
        // exhibit's target reached 2 cm into both of its neighbours' and
        // which one you were aiming at was decided by hit order.
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        // The label DESCRIBES; the action is what opens the lab. It read
        // "Enter <module>" against a tap that only flashed a distant
        // plate — a label promising the one thing the object could not
        // do. `HubDomain.promise` is the hand-written "what you actually
        // do here" line, which had no readers at all until 2026-08-07.
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(module.title). \(HubDomain.promise(for: module.id))")
        accessibility.customActions = [HubSpaceView.enterAction]
        anchor.components.set(accessibility)
        // AND PLAIN ACTIVATE OPENS IT TOO. The custom action alone meant
        // the exhibit's default gesture — the one VoiceOver offers first
        // and the only one most people ever use — did nothing at all,
        // while a rotor action nobody would look for was the real door.
        // `attach` preserves the label and the custom action above; it
        // adds the system one and the closure behind it.
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
        // bubble type as the title, tinted in the module's accent.
        // UNBACKED (owner, 2026-08-14): the dark card behind each name
        // blocked the view through the gallery — a row of floating
        // smudges in the one place the eye sweeps across. The bubble
        // type carries its own emissive floor.
        // AND A HEADER, NOT A CAPTION (owner, same day, next breath):
        // it hung at the miniature's foot, in front of the pedestal,
        // which put it exactly in the sightline that sweeps the shelf.
        // Above the model the only thing behind it is the wearer's own
        // wall. The y clears the tallest normalized miniature
        // (`exhibitSize / 2` = 0.12) plus the type's cap height; the
        // small z keeps the billboarded text from shearing into a tall
        // model's crown when seen from above.
        let name = Self.namePlate(module.title, accent: UIColor(module.accent),
                                  size: PlateStyle.exhibitLabelSize,
                                  backed: false)
        let namePivot = Entity()
        namePivot.position = [0, 0.165, 0.06]
        namePivot.components.set(BillboardComponent())
        namePivot.addChild(name)
        pulser.addChild(namePivot)

        // THE PROMISE CAPTION IS GONE (owner, 2026-08-14). The one-line
        // "what you actually do here" faded in under a focused exhibit
        // from 2026-08-04 until today, and the owner asked for it off:
        // the gaze answer is already the lift, the growth and the halo,
        // and a sentence appearing under whatever you look at reads as
        // a tooltip in a room that has none. The TEXT survives where it
        // still works — the flat catalog's rows and every exhibit's
        // VoiceOver label both keep speaking it; what is gone is the
        // floating box. Git history holds the caption stack, including
        // the billboard-depth lesson its comments carried.

        // MEASURED FROM THE MINIATURE, and from nothing else.
        //
        // The obvious move is to measure `pulser`, which is everything
        // this exhibit draws — and it is wrong, because one of the
        // things it draws is the focus glow, whose outer disc is 0.40 m
        // ACROSS (`focusGlow`, three cylinders at r = 0.085 / 0.135 /
        // 0.200). That is a pool of light on the puck, not part of the
        // object, and against a 0.36 m puck pitch a target measured
        // from it reaches 3.5 cm past both neighbours' centres — worse
        // than the 0.19 m sphere this replaced, which reached 1 cm past.
        // `ColliderCriterionTests` cannot catch that: a collider derived
        // from an entity's own bounds satisfies a test that measures it
        // against those bounds, by construction. What catches it is
        // `testGalleryExhibitTargetsDoNotOverlapEachOther`, which asks
        // the question the rule is actually about — does this shield
        // its neighbour.
        //
        // The vignette is normalised to `exhibitSize` (0.24 m), so the
        // target is 0.27 m and clears the pitch with 9 cm to spare.
        //
        // THE NAME PLATE IS DELIBERATELY OUTSIDE THE TARGET, and this
        // is the one place that decision is written down, because it
        // looks like an oversight and it is not.
        //
        // Both earlier versions of this collider happened to contain
        // the plate, so leaving it out is a real narrowing and the
        // obvious repair is to union it back in. That was tried, and
        // `testGalleryExhibitTargetsDoNotOverlapEachOther` failed
        // immediately: the plate carries the module's TITLE at 0.030 m
        // ("Circuit Workshop", "Electric Fields"), which is wider than
        // the 0.36 m puck pitch all by itself. A target containing it
        // necessarily reaches into both neighbours, which is the exact
        // defect this whole change exists to remove. The plate is a
        // caption, and captions of adjacent exhibits are allowed to sit
        // near each other; touch targets are not.
        //
        // Set directly rather than through `Grabbable`, which would also
        // hang a grounding shadow off every exhibit. The gallery's
        // lighting is composed; six new contact shadows is a visual
        // change and this is not the pass for one.
        let reach = Grabbable.reach
        let exhibitBounds = vignette.visualBounds(relativeTo: anchor)
        anchor.components.set(InputTargetComponent())
        anchor.components.set(CollisionComponent(shapes: [
            .generateBox(size: exhibitBounds.extents + SIMD3<Float>(repeating: 2 * reach))
                .offsetBy(translation: exhibitBounds.center),
        ]))
        anchor.components.set(HoverEffectComponent())

        // THE ENTER PLAQUE STOOD HERE, and its removal (owner,
        // 2026-08-09) took a whole spacing problem with it.
        //
        // It was a machined slab reading ENTER, standing on the terrace
        // in front of each puck at y −0.160, z 0.165. It had to stand
        // FORWARD rather than lower because the exhibit's own 0.27 m
        // touch target covers the entire puck top, so anything seated
        // there loses every pinch to the miniature above it; and the day
        // before it was deleted, an attempt to derive its y from the
        // measured caption height sank all six into the slab, invisible,
        // with every test green.
        //
        // What replaces it is `sendToPad`: the tap that used to be
        // "wrong object, nothing happens" now flies the lab to the pad,
        // so the door needs no furniture on the terrace at all. The
        // caption stack is ONE billboarded object now — the name alone,
        // since the promise caption came off on 2026-08-14 —
        // which is also the end of the y-arithmetic-between-different-
        // depths trap that this file warned about twice and fell into
        // anyway.

        exhibits.append(Exhibit(
            moduleID: module.id, anchor: anchor, pulser: pulser,
            vignette: vignette, namePivot: namePivot, halo: glow,
            basePosition: basePosition, animate: built.animate))
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

    // `namePlateHeight` was deleted 2026-08-09 with the ENTER plaque it
    // spaced. Keeping the lesson, which outlived its caller: it asked
    // the SAME arithmetic the builder uses rather than the built
    // entity's `visualBounds`, because a freshly built, unparented
    // entity does not report its plate — the first attempt measured the
    // caption, moved the plaque down by less than the caption was tall,
    // and still crossed its second line. A number you can compute
    // before you build is a number you can also TEST, which is the
    // difference between that fix and another screenshot.

    /// A nameplate, optionally WRAPPED.
    ///
    /// Single-line was right while every caller passed a lab's name.
    /// `HubDomain.promise` is a sentence, and the first photograph of the
    /// focused exhibit's caption stack (2026-08-08) showed it as one long
    /// unwrapped plate running straight through the neighbouring
    /// exhibits' names and behind its own ENTER plaque. Pucks are
    /// `GalleryLayout.basePuckPitch` apart, so anything wider than that
    /// belongs to more than one exhibit.
    ///
    /// The comment at the promise's call site asked exactly this
    /// question — "whether they read as one tidy caption or as three
    /// things piled up" — and answered itself the moment there was a
    /// picture. Placement is what this project has got wrong three times
    /// with the numbers looking fine.
    static func namePlate(_ text: String, accent: UIColor,
                          size: CGFloat = 0.036,
                          wrapWidth: CGFloat = 0,
                          backed: Bool = true) -> Entity {
        let plate = Entity()

        let extents = wrapWidth > 0
            ? Callout.textMesh(text, size: size, wrapWidth: wrapWidth).bounds.extents
            : textExtents(text, size: size)
        // Padding scales WITH the type: fixed values authored for the
        // gallery's 36 mm plates made a 10 mm palette label wear a
        // plate three text-heights wide — neighbouring labels collided
        // into one smear of backing.
        let padY = Float(size) * 0.44
        let width = wrapWidth > 0
            ? extents.x + Float(size) * 0.72 * 2
            : namePlateWidth(text, size: size)
        let height = extents.y + padY * 2

        // `backed: false` is the exhibit titles' setting (owner,
        // 2026-08-14: the card behind each gallery name read as a smear
        // that blocked the room). The card stays right for the small
        // apparatus labels, which sit ON instruments rather than
        // floating in the space the eye looks through.
        if backed {
            var backing = UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))
            backing.blending = .transparent(opacity: 0.58)
            // Same lesson as `BackedLabel.backing`: `height / 2` is a pill
            // for one line and a lozenge for several, and a lozenge's curved
            // ends eat the first and last words of every line.
            let card = ModelEntity(
                mesh: .generatePlane(width: width, height: height,
                                     cornerRadius: min(height / 2,
                                                       Float(size) * 1.2)),
                materials: [backing])
            card.position.z = -0.006
            plate.addChild(card)
        }

        if wrapWidth > 0 {
            // Wrapped runs use a flat mesh: the bubble builder extrudes
            // and clear-coats one line of display type, which is the
            // wrong voice for a caption and unreadable stacked.
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
    /// The focus pool's entity name — the pool of the module's colour
    /// that appears on the platform under whichever exhibit you face.
    static let focusPoolName = "focus-pool"

    private static func focusGlow(accent: UIColor) -> Entity {
        // A pool of the module's colour ON the puck beneath the
        // miniature — the slab relights under the exhibit you face.
        // (It used to be a billboarded halo floating behind the model;
        // with real furniture underneath, light falling on a surface
        // reads as light.)
        // THE THREE DISCS SHARED ONE PLANE, and this is the fix.
        //
        // All three were built at the glow's own origin — three
        // transparent cylinders 1 mm thick at identical y — so their
        // faces were coplanar to the micron and the depth buffer had to
        // choose between them per pixel, per frame, as the head moved.
        // That is the flicker under a focused exhibit, and it is most
        // obvious on the pad, where the docked lab holds still and gives
        // the eye time to watch it happen.
        //
        // A LADDER, WIDEST AT THE BOTTOM. Half a millimetre apart is
        // plenty for the depth buffer, and stacking the faint wide disc
        // lowest means the tighter, brighter ones read as lying on top
        // of it — which is the order the falloff is trying to describe
        // anyway.
        let glow = Entity()
        // Named so the stacking rule can be TESTED. Reaching for these
        // discs by shape instead — flat, wide, translucent — also finds
        // the Gravity Lab miniature's two orbit tracks, which are rings
        // at different radii and never overlap, and the test fails on an
        // exhibit that is drawn correctly.
        glow.name = Self.focusPoolName
        let layers: [(radius: Float, opacity: Float)] = [
            (0.200, 0.06), (0.135, 0.15), (0.085, 0.30),
        ]
        for (index, layer) in layers.enumerated() {
            var material = UnlitMaterial(color: accent)
            material.blending = .transparent(
                opacity: .init(floatLiteral: layer.opacity))
            let disc = ModelEntity(
                mesh: .generateCylinder(height: 0.001, radius: layer.radius),
                materials: [material])
            disc.position.y = Float(index) * 0.0005
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
        // CLAMPED, because the first event after the space presents
        // can carry everything the renderer swallowed while opening —
        // seconds, in one delta. Unclamped, that single frame spent
        // the arrival's entire centred beat before anyone saw a frame:
        // the launch-day symptom was a room already cascading, title
        // already at the wall, on the first visible frame. A ceiling
        // of a thirtieth of a second means a stall shows up as slow
        // motion for one frame instead of as time travel.
        let dt = min(dt, 1.0 / 30.0)
        time += dt
        if let placement {
            root.position = placement.offset
            root.orientation = simd_quatf(angle: placement.yaw, axis: [0, 1, 0])
        }
        fadeIn(dt: dt)
        updateIntro()
        updateFocus(lookRay: lookRay, dt: dt)

        for index in exhibits.indices {
            let focus = exhibits[index].focus
            let exhibit = exhibits[index]

            // An exhibit riding a hand, gliding home, or standing on
            // the podium owns its own position — the idle life must
            // not fight the carry, stomp the glide, or yank it off
            // the pedestal.
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
                // Standing centre stage, it says its own name — without
                // this the label keeps whatever opacity it happened to
                // have when it was carried off the arc, which for an
                // unfocused exhibit is invisible. Written when focus
                // moves (or on the first frame after a carry, which
                // parks appliedFocus at -1), not on every frame.
                if abs(focus - exhibits[index].appliedFocus) > 0.0005 {
                    exhibits[index].appliedFocus = focus
                    exhibit.namePivot.components.set(OpacityComponent(opacity: 1))
                    exhibit.halo.components.set(OpacityComponent(opacity: focus))
                }
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

            // Opacity follows focus, but is WRITTEN only when focus has
            // actually moved: once the ease settles, rewriting the same
            // three components per exhibit per frame is pure churn —
            // eighteen component sets a frame across the gallery,
            // forever, carrying values that had stopped changing.
            if abs(focus - exhibits[index].appliedFocus) > 0.0005 {
                exhibits[index].appliedFocus = focus
                exhibit.halo.components.set(OpacityComponent(opacity: focus))
                // Every name stays legible ALL the time (owner,
                // 2026-08-04, reversing the materialise-on-gaze fade): a
                // gallery whose captions vanish until you stare at them
                // cannot be read at a glance, and the focus answer is
                // already carried by the lift, the growth and the halo.
                exhibit.namePivot.components.set(OpacityComponent(opacity: 1))
            }

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
        // The title floats and breathes, like a balloon on a string —
        // and during the arrival it rides `HubIntro`'s flight from its
        // centred opening pose back to this anchor, a shade oversized
        // so landing reads as settling into place.
        let bob = stillness ? 0 : 0.02 * Float(sin(time * 0.6))
        let blend = introPhase == .running
            ? HubIntro.titleBlend(at: introTime) : 1
        let rest = titlePosition + SIMD3(0, bob, 0)
        titleAnchor.position = rest + (HubIntro.titlePose - rest) * (1 - blend)
        let titleBreathe = stillness ? 1 : 1 + 0.015 * Float(sin(time * 0.9))
        let introSwell = 1 + (HubIntro.titlePoseScale - 1) * (1 - blend)
        titleAnchor.scale = SIMD3(repeating: titleBreathe * introSwell)

        // Each line rakes on its own phase, so the wordmark reads as two
        // milled plates catching the light rather than one board turning.
        // Under stillness they PARK square to the reader, which is where
        // the mark looks composed — not frozen mid-turn.
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
            // A FLASK STOOD FIRST HERE from 2026-08-08 to 08-09, opening
            // the experiments window, on the reasoning that it was the
            // only one of the four you consult mid-session rather than
            // once. The experiments are gone (owner, 2026-08-09) and the
            // bar is back to three verbs, all errands.
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
