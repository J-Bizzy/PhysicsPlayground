//
//  TimeRail.swift
//  Physics Playground — Shell
//
//  The Time Capsule's instrument: a rail that appears when the room is
//  paused and scrubs the whole experiment back through its recorded past.
//  The bead's place is "seconds ago"; three plates beside it step one
//  recorded physics tick at a time and resume from the frozen instant.
//
//  Shell chrome, like the Palette: ONE implementation serves all six
//  modules by construction, mounted by `PlaygroundSpaceView` and speaking
//  to the module only through `ModuleDescriptor.timeScrub`. It stands at
//  the apparatus's front hem and rides the lab-placement offset the way
//  every instrument does. It does NOT ride the user-carried palette bead:
//  a rail whose root moves mid-drag shifts its own mapping — the same
//  reason Kinematics' rails refuse to ride the launcher.
//
//  This is not the retired time-scale rail (DECISIONS 2026-08-02): it
//  operates only while paused, only over the recorded past, in units of
//  "seconds ago" — it never changes how fast physics runs. Un-pausing
//  resumes forward from an instant that genuinely occurred.
//

import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class TimeRail {
    let root = Entity()

    /// Where the rail stands, before the lab-placement offset: centred
    /// just under and in front of the apparatus, chest height.
    ///
    /// MEASURED, and the first three guesses were wrong in the same
    /// direction. (0, 0.92, −0.50), (0, 1.02, −0.72) and (0, 1.12, −0.80)
    /// sit 49°, 34° and 28° below a 1.5 m eye line; the simulator's fixed
    /// viewport is about 25° tall below the horizon, so all three
    /// photographed as a scrubbed room with no visible control. What
    /// settled it was logging `visualBounds` — the rail was in the scene,
    /// enabled and opaque the whole time, which ruled out every rendering
    /// theory and left geometry.
    ///
    /// This sits ~15° down, which frames the rail AND the plate column
    /// beside it: clear of the physics overhead, inside the frame, at a
    /// distance a hand reaches. Standing under the apparatus is safe
    /// precisely because the rail EXISTS ONLY WHILE PAUSED — it can
    /// never come between a hand and live physics.
    static let home = SIMD3<Float>(0, 1.20, -1.20)
    /// The capsule window the rail maps, newest at the right-hand end.
    static let range = -30.0...0.0
    /// A rail over an empty recording is a control over nothing — it
    /// stays folded until there is at least this much to scrub.
    static let minimumSpan = 0.5

    /// Where the reel is mounted, relative to `root` — to the LEFT of
    /// where the rail lies, because the rail is tape drawn off it.
    /// Everything else keeps the coordinates it always had, so the OPEN
    /// assembly stands exactly where the always-on rail used to.
    static let reelOffset = SIMD3<Float>(-0.24, 0, 0)
    /// How far the reel turns per second of recording scrubbed. About
    /// 52° a second, so the full 30 s window is four and a bit turns —
    /// fast enough that a small drag visibly moves it, slow enough that
    /// the ports never strobe.
    static let radiansPerSecond: Float = 0.9
    /// The rail's length, which is also the length of tape drawn off the
    /// reel when it opens.
    static let railLength: Float = 0.34
    /// The radius the tape is wound at — `TAPE_RADIUS` in
    /// `Tools/timereel.py`. Shared with the asset by hand, which is
    /// tolerable for one number and is why it is named in both places:
    /// the reel must turn by arc ÷ radius as the tape comes off it, and
    /// a reel that stayed still while a third of a metre unwound from it
    /// would be the one part of this instrument that lied.
    static let tapeRadius: Float = 0.038
    /// How fast the reel is still turning when it arrives, rad/s, and
    /// the time constant it dies away over. The recording stopped at the
    /// instant of the pause, so the reel coasts down rather than
    /// appearing already at rest — about a third of a turn, over
    /// roughly a second.
    static let coastSpeed: Float = 6.0
    static let coastTau: Float = 0.35

    private let controls: TimeScrubControls
    private let isPaused: () -> Bool
    private let track: SpatialTrackControl
    private let plates: SpatialActionBank
    /// The reel's MOUNT: where it hangs, what a pinch lands on, and what
    /// carries its nameplate. It never turns.
    private let reel = Entity()
    /// The part that spins. Separated from the mount because the first
    /// build hung the nameplate on the spinning entity, and scrubbing
    /// back a second rolled the words over onto their side.
    private let spindle = Entity()

    /// 0 folded, 1 out. An opacity ramp, never a scale: scaling a track
    /// stretches the rail without stretching the range it maps.
    private var visibility: Float = 0
    var isVisible: Bool { visibility > 0.02 }

    /// Whether the tape has been drawn off the reel. The reel is what is
    /// on screen while paused; the rail is what a pinch asks for.
    private(set) var isOpen = false
    /// 0 wound, 1 drawn out. Separate from `visibility`, which is the
    /// whole instrument arriving and leaving.
    private var openness: Float = 0
    /// True once the rail is out far enough to be operated. A drag part
    /// way through the draw would read a mapping that is still moving.
    var isDrawnOut: Bool { openness > 0.98 }
    /// The eased draw, which is also how much tape is off the reel.
    private var drawn: Float = 0

    /// The spin the reel still has when it arrives, and the angle that
    /// spin has carried it through so far.
    private var coastVelocity: Float = 0
    private var coastAngle: Float = 0
    private var wasPresent = false

    /// The system's Reduce Motion setting, pushed in by the host — the
    /// same switch the palette bead reads. It stops the coast, which is
    /// decorative, and leaves the draw alone, which is an answer to a
    /// pinch and would read as broken if it did not happen.
    var stillness = false

    var subscription: EventSubscription?

    init(module: ModuleDescriptor) {
        self.controls = module.timeScrub
        self.isPaused = module.isPaused
        let accent = UIColor(module.accent)
        let scrub = module.timeScrub

        // The rail: value = seconds relative to "now" (≤ 0), so the bead
        // at the right-hand end IS the present and dragging left is
        // dragging into the past.
        track = SpatialTrackControl(
            name: "Time",
            center: .zero,
            normal: [0, 0, 1],
            accent: accent,
            range: Self.range,
            layout: TrackLayout(length: Double(Self.railLength)),
            read: {
                guard let time = scrub.scrubTime(), let span = scrub.span()
                else { return 0 }
                return time - span.upperBound
            },
            write: { value in scrub.scrub(-value) },
            format: { value in
                value > -0.005 ? "now" : String(format: "−%.2f s", -value)
            },
            subtitle: { _ in
                let span = scrub.span()
                let seconds = span.map { $0.upperBound - $0.lowerBound } ?? 0
                return String(format: "%.0f s recorded", seconds)
            })
        root.addChild(track.root)

        // The frame-step and resume plates, in the house verb grammar,
        // standing off the rail's "now" end.
        plates = SpatialActionBank(
            accent: accent,
            actions: [
                SpatialAction(id: "back", label: "Back a frame",
                              symbol: "backward.frame.fill") {
                    scrub.stepFrames(-1)
                },
                SpatialAction(id: "ahead", label: "Ahead a frame",
                              symbol: "forward.frame.fill") {
                    scrub.stepFrames(1)
                },
                SpatialAction(id: "resume", label: "Resume here",
                              symbol: "play.fill") {
                    scrub.resume()
                },
            ])
        plates.root.position = [Self.railLength / 2 + 0.11, 0, 0]
        root.addChild(plates.root)

        buildReel(accent: accent)

        root.position = Self.home
        setVisibility(0)
        applyOpenness()
    }

    /// The reel: the modelled object the recording is wound on, and the
    /// only thing on screen until it is pinched.
    ///
    /// `TimeReel.usdz`, built by `Tools/timereel.py`. If the asset ever
    /// fails to load the reel is still a real, tappable object — a
    /// machined disc of the same size — because a control that silently
    /// becomes nothing is worse than a plain one.
    private func buildReel(accent: UIColor) {
        reel.name = "time-reel"
        if let loaded = PropCache.instance(named: "TimeReel") {
            spindle.addChild(loaded)
        } else {
            let fallback = ModelEntity(
                mesh: .generateCylinder(height: 0.020, radius: 0.048),
                materials: [Materials.machined(UIColor(white: 0.31, alpha: 1))])
            fallback.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            spindle.addChild(fallback)
        }
        reel.addChild(spindle)
        reel.position = Self.reelOffset
        reel.components.set(InputTargetComponent())
        // Sized to the reel and no larger, per the standing rule: an
        // input collider bigger than the thing it represents is the
        // invisible-scale-plate failure again.
        // The nameplate hangs 72 mm below the reel, outside the sphere.
        // The reel is the ONLY thing a pause puts on screen, so the words
        // saying what it is were the least pinchable part of the least
        // familiar object in the app.
        reel.components.set(CollisionComponent(shapes: [
            .generateSphere(radius: 0.052),
            .generateBox(size: [0.11, 0.024, 0.020])
                .offsetBy(translation: [0, -0.072, 0]),
        ]))
        reel.components.set(HoverEffectComponent())
        reel.components.set(GroundingShadowComponent(castsShadow: true))
        SpatialActions.attach(
            to: reel, label: "Time capsule",
            value: isOpen ? "drawn out" : "wound in",
            activate: { [weak self] in
                guard let self else { return }
                _ = self.handleTap(self.reel)
            })

        // The house nameplate under it, the same treatment the palette
        // bead wears: an unlabelled disc asks to be pinched on faith,
        // and the bead learned that lesson already.
        let plate = HubScene.namePlate("Time capsule",
                                       accent: UIColor(white: 0.95, alpha: 1),
                                       size: PlateStyle.labelSize)
        plate.position = [0, -0.072, 0]
        reel.addChild(plate)

        root.addChild(reel)
    }

    /// Whether the rail should be out: paused, with a recording worth
    /// scrubbing.
    private var wantsPresence: Bool {
        guard isPaused(), let span = controls.span() else { return false }
        return span.upperBound - span.lowerBound >= Self.minimumSpan
    }

    /// Per frame: stand at the apparatus hem (riding the lab-placement
    /// offset), face the reader, fold in or out, and keep the bead on the
    /// model's value — nothing ticks a track by itself.
    func update(dt: Double, viewer: SIMD3<Float>?, placement: SIMD3<Float>,
                nearestHand: SIMD3<Float>? = nil) {
        root.position = Self.home + placement
        // The reel is a READOUT while it is wound in — it turns with the
        // scrub — so like a bank it recedes rather than vanishing.
        Recession.apply(to: root, anchor: root.position(relativeTo: nil),
                        nearestHand: nearestHand)

        if let viewer, let facing = yaw(facing: viewer, from: root.position) {
            root.orientation = facing
        }

        let target: Float = wantsPresence ? 1 : 0
        // The reel arrives coasting. Recording stopped at the instant of
        // the pause, so a reel already at rest would be a reel that had
        // never been turning — the spin-down is the object agreeing with
        // what just happened.
        if wantsPresence, !wasPresent {
            coastVelocity = stillness ? 0 : -Self.coastSpeed
            coastAngle = 0
        }
        wasPresent = wantsPresence
        if visibility != target {
            let rate = Float(min(dt * 6, 1))
            visibility += (target - visibility) * rate
            if abs(visibility - target) < 0.01 { visibility = target }
            setVisibility(visibility)
        }
        // The tape winds itself back in when the instrument leaves, so
        // the next pause opens on a reel rather than on whatever the
        // last one was left showing.
        if !wantsPresence, isOpen { isOpen = false }
        guard isVisible else { return }

        let drawTarget: Float = isOpen ? 1 : 0
        if openness != drawTarget {
            let rate = Float(min(dt * 5, 1))
            openness += (drawTarget - openness) * rate
            if abs(openness - drawTarget) < 0.005 { openness = drawTarget }
            applyOpenness()
        }

        // The reel turns for three reasons, and each of them is a true
        // statement about the recording rather than an effect:
        //
        //   · the tape drawn off it — arc ÷ radius, so a third of a
        //     metre over a 38 mm spool is very nearly a turn and a half,
        //     and the draw animation spins the reel exactly as much as
        //     pulling that tape really would;
        //   · the scrub, unwinding further the further back you go, so
        //     the closed object is a readout and not a lid;
        //   · the coast it arrived with, dying away.
        if coastVelocity != 0 {
            coastAngle += coastVelocity * Float(dt)
            coastVelocity *= exp(-Float(dt) / Self.coastTau)
            if abs(coastVelocity) < 0.02 { coastVelocity = 0 }
        }
        let fromDraw = -(Self.railLength * drawn) / Self.tapeRadius
        let fromScrub = Float(secondsScrubbedBack) * Self.radiansPerSecond
        spindle.orientation = simd_quatf(
            angle: fromDraw + fromScrub + coastAngle, axis: [0, 0, 1])

        guard openness > 0.02 else { return }
        track.refresh()
        // The plates lay themselves out relative to their own root; the
        // rail already faces the viewer, so they inherit its yaw.
        // The rail's own plates never recede: they only exist while the
        // tape is drawn out, which is already a deliberate act, and a
        // scrub control that dims mid-scrub would fight the hand using
        // it.
        plates.update(anchor: plates.root.position, viewer: nil, dt: dt)
    }

    /// How far back the scrub currently stands, in seconds. Zero while
    /// live — the reel is fully wound.
    private var secondsScrubbedBack: Double {
        guard let time = controls.scrubTime(), let span = controls.span()
        else { return 0 }
        return span.upperBound - time
    }

    /// Draws the tape out, or winds it in: the rail and its plates slide
    /// from behind the reel to their places and fade up as they go.
    private func applyOpenness() {
        let eased = openness * openness * (3 - 2 * openness)
        drawn = eased
        let from = Self.reelOffset.x
        track.root.position.x = from + (0 - from) * eased
        plates.root.position.x =
            from + ((Self.railLength / 2 + 0.11) - from) * eased
        track.root.components.set(OpacityComponent(opacity: eased))
        plates.root.components.set(OpacityComponent(opacity: eased))
        let out = eased > 0.02
        track.isEnabled = out && isVisible
        if !out { plates.root.isEnabled = false }
    }

    private func setVisibility(_ value: Float) {
        root.components.set(OpacityComponent(opacity: value))
        let enabled = value > 0.02
        root.isEnabled = enabled
        track.isEnabled = enabled && openness > 0.02
    }

    // MARK: Input routing (the mounting view's gestures land here)

    /// True when the tap hit the reel (which draws the tape out or winds
    /// it back in) or one of the rail's plates.
    ///
    /// The reel is tested FIRST and by walking up from whatever was hit,
    /// the same contract every station in this app keeps — a tap on its
    /// nameplate is a tap on the reel.
    @discardableResult
    func handleTap(_ entity: Entity) -> Bool {
        guard isVisible else { return false }
        if owns(entity, under: reel) {
            isOpen.toggle()
            SoundPalette.play(.pop, on: reel, volume: 0.45)
            SpatialActions.republish(value: isOpen ? "drawn out" : "wound in",
                                     on: reel)
            return true
        }
        guard isDrawnOut else { return false }
        return plates.handleTap(entity)
    }

    /// Draws the tape out or winds it in without a pinch — for the debug
    /// launch arguments, and for tests, which have no hands either.
    func setOpen(_ open: Bool) { isOpen = open }

    private func owns(_ entity: Entity, under ancestor: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === ancestor { return true }
            current = candidate.parent
        }
        return false
    }

    /// Routes a drag on the rail. `handWorld` is in scene space; the rail
    /// converts into its own frame so `adjust` sees the hand where the
    /// rail actually stands — offset, yaw and all.
    @discardableResult
    func handleDrag(entity: Entity, handWorld: SIMD3<Double>) -> Bool {
        // Only once the tape is fully out: mid-draw the rail is still
        // sliding, and a drag against a moving root would read a mapping
        // that is itself in motion.
        guard isVisible, isDrawnOut else { return false }
        guard track.isAdjusting || track.owns(entity) else { return false }
        let local = root.orientation.inverse.act(
            SIMD3<Float>(handWorld) - root.position)
        track.adjust(hand: SIMD3<Double>(local))
        return true
    }

    var isAdjusting: Bool { track.isAdjusting }

    func endDrag() {
        track.endAdjust()
    }
}

/// Mounts the Time Rail in whatever lab is on screen, exactly like
/// `PaletteView` mounts the bead.
struct TimeRailView: View {
    let module: ModuleDescriptor
    @Environment(AppModel.self) private var appModel
    /// The SYSTEM setting, not an in-app duplicate — the same one the
    /// palette bead reads.
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var rail: TimeRail?

    var body: some View {
        RealityView { content in
            let made = TimeRail(module: module)
            content.add(made.root)
            rail = made
            made.stillness = systemReduceMotion

            made.subscription = content.subscribe(
                to: SceneEvents.Update.self
            ) { [weak made] event in
                made?.update(
                    dt: event.deltaTime,
                    viewer: appModel.room.headPosition.map { SIMD3<Float>($0) },
                    placement: appModel.labPlacement.offset,
                    nearestHand: appModel.room.nearestFingertip(
                        to: TimeRail.home + appModel.labPlacement.offset))
            }

            #if DEBUG
            // The simulator cannot pinch, and the reel is now the only
            // thing a pause puts on screen — so `-scrubBack` DRAWS THE
            // TAPE OUT as well as scrubbing. That is the whole point of
            // these arguments: reach a control a hand could also reach.
            // `-pauseAfter 4 -scrubBack 1.5` runs the experiment, pauses
            // it, pinches the reel and scrubs back 1.5 s; `-scrubStep -3`
            // applies three frame-steps on top, photographing the
            // mapping rather than just the rail. To photograph the reel
            // CLOSED — its resting state — pass `-pauseAfter` alone,
            // because that IS what a pause looks like.
            let back = UserDefaults.standard.double(forKey: "scrubBack")
            if back > 0 {
                let scrub = module.timeScrub
                let isPaused = module.isPaused
                let steps = UserDefaults.standard.integer(forKey: "scrubStep")
                Task { [weak made] in
                    var paused = false
                    for _ in 0..<300 where !paused {
                        paused = isPaused()
                        if !paused {
                            try? await Task.sleep(for: .milliseconds(200))
                        }
                    }
                    // Only ever scrub a pause that actually happened —
                    // this argument STAGES a state, it must not create one.
                    guard paused else { return }
                    made?.setOpen(true)
                    scrub.scrub(back)
                    if steps != 0 { scrub.stepFrames(steps) }
                }
            }
            #endif
        }
        update: { _ in
            rail?.stillness = systemReduceMotion
        }
        .onDisappear {
            rail?.subscription?.cancel()
            rail?.subscription = nil
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in _ = rail?.handleTap(value.entity) }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let world = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    _ = rail?.handleDrag(entity: value.entity, handWorld: world)
                }
                .onEnded { _ in rail?.endDrag() }
        )
    }
}
