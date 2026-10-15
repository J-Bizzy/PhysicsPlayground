//
//  TimeRail.swift
//  Physics Playground — Shell
//
//  The Time Capsule's instrument: a reel that appears when the room is
//  paused; a pinch draws a rail off it that scrubs the whole experiment
//  back through its recorded past, with buttons to step one recorded
//  tick either way. Resuming from the instant on screen is the title
//  bar's Resume — every lab's pause resumes from a scrub. One implementation serves every module,
//  mounted by `PlaygroundSpaceView` and speaking to the module only
//  through `ModuleDescriptor.timeScrub`. It operates only while paused
//  and only over the recorded past; it never changes how fast physics
//  runs.
//

import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class TimeRail {
    let root = Entity()

    /// Where the rail stands, before the lab-placement offset: under and in
    /// front of the apparatus, ~15° below a 1.5 m eye line so it stays
    /// inside the simulator's frame. Safe under the apparatus because it
    /// exists only while paused.
    static let home = SIMD3<Float>(0, 1.20, -1.20)
    /// The capsule window the rail maps, newest at the right-hand end.
    static let range = -30.0...0.0
    /// A rail over an empty recording is a control over nothing — it
    /// stays folded until there is at least this much to scrub.
    static let minimumSpan = 0.5

    /// Where the reel is mounted relative to `root`: to the left of the
    /// rail, which is tape drawn off it.
    static let reelOffset = SIMD3<Float>(-0.24, 0, 0)
    /// How far the reel turns per second of recording scrubbed; the 30 s
    /// window is about four turns.
    static let radiansPerSecond: Float = 0.9
    /// The rail's length, which is also the length of tape drawn off the
    /// reel when it opens.
    static let railLength: Float = 0.34
    /// The radius the tape is wound at — `TAPE_RADIUS` in
    /// `Tools/timereel.py`; the reel turns by arc ÷ radius as tape comes off.
    static let tapeRadius: Float = 0.038
    /// How fast the reel is still turning when it arrives, rad/s, and the
    /// time constant it dies away over: recording stopped at the instant of
    /// the pause, so it coasts down.
    static let coastSpeed: Float = 6.0
    static let coastTau: Float = 0.35

    private let controls: TimeScrubControls
    private let isPaused: () -> Bool
    private let track: SpatialTrackControl
    private let plates: SpatialActionBank
    /// The reel's mount: where it hangs, what a pinch lands on, and what
    /// carries its nameplate. It never turns.
    private let reel = Entity()
    /// The part that spins. Separate from the mount so the nameplate does
    /// not roll with it.
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
    /// True once the rail is out far enough to operate; mid-draw its
    /// mapping is still moving.
    var isDrawnOut: Bool { openness > 0.98 }
    /// The eased draw, which is also how much tape is off the reel.
    private var drawn: Float = 0

    /// The spin the reel still has when it arrives, and the angle that
    /// spin has carried it through so far.
    private var coastVelocity: Float = 0
    private var coastAngle: Float = 0
    private var wasPresent = false

    /// The system Reduce Motion setting, pushed in by the host. Stops the
    /// coast (decorative) and leaves the draw alone (an answer to a pinch).
    var stillness = false

    var subscription: EventSubscription?

    init(module: ModuleDescriptor) {
        self.controls = module.timeScrub
        self.isPaused = module.isPaused
        let accent = UIColor(module.accent)
        let scrub = module.timeScrub

        // value = seconds relative to now (≤ 0): the bead at the right-hand end
        // is the present and dragging left is the past.
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

        // The frame-step buttons, off the rail's "now" end. No resume here:
        // the title bar's Resume is the same act, and one is enough.
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
            ])
        plates.root.position = [Self.railLength / 2 + 0.11, 0, 0]
        root.addChild(plates.root)

        buildReel(accent: accent)

        root.position = Self.home
        setVisibility(0)
        applyOpenness()
    }

    /// The reel: `TimeReel.usdz` from `Tools/timereel.py`, the only thing
    /// on screen until pinched. If the asset fails to load a machined disc
    /// of the same size stands in, still tappable.
    private func buildReel(accent: UIColor) {
        reel.name = "time-reel"
        if let loaded = PropCache.instance(named: "TimeReel") {
            spindle.addChild(loaded)
        } else {
            let fallback = ModelEntity(
                mesh: Primitives.cylinder(height: 0.020, radius: 0.048),
                materials: [Materials.machined(UIColor(white: 0.31, alpha: 1))])
            fallback.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            spindle.addChild(fallback)
        }
        reel.addChild(spindle)
        reel.position = Self.reelOffset
        reel.components.set(InputTargetComponent())
        // Sized to the reel and no larger, plus the nameplate 72 mm below it:
        // the words saying what it is must be pinchable too.
        reel.components.set(CollisionComponent(shapes: [
            Primitives.collisionSphere(radius: 0.052),
            Primitives.collisionBox(size: [0.11, 0.024, 0.020], offset: [0, -0.072, 0]),
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

        // The house nameplate under it; an unlabelled disc asks to be pinched
        // on faith.
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
    /// model's value.
    func update(dt: Double, viewer: SIMD3<Float>?, placement: SIMD3<Float>,
                nearestHand: SIMD3<Float>? = nil) {
        root.position = Self.home + placement
        // Wound in, the reel is a readout (it turns with the scrub), so like a
        // bank it recedes rather than vanishing.
        Recession.apply(to: root, anchor: root.position(relativeTo: nil),
                        nearestHand: nearestHand)

        if let viewer, let facing = yaw(facing: viewer, from: root.position) {
            root.orientation = facing
        }

        let target: Float = wantsPresence ? 1 : 0
        // The reel arrives coasting: recording stopped at the instant of the
        // pause.
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
        // The tape winds itself back in when the instrument leaves, so the next
        // pause opens on a reel.
        if !wantsPresence, isOpen { isOpen = false }
        guard isVisible else { return }

        let drawTarget: Float = isOpen ? 1 : 0
        if openness != drawTarget {
            let rate = Float(min(dt * 5, 1))
            openness += (drawTarget - openness) * rate
            if abs(openness - drawTarget) < 0.005 { openness = drawTarget }
            applyOpenness()
        }

        // The reel turns for the tape drawn off it (arc ÷ radius), for the
        // scrub (further back, further unwound), and for the coast it arrived
        // with.
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
        // The plates lay out relative to their own root and inherit the rail's
        // yaw. They never recede: they exist only while the tape is out, and a
        // scrub control that dims mid-scrub fights the hand.
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

    /// True when the tap hit the reel (draws the tape out or winds it in)
    /// or one of the plates. The reel is tested first, walking up from
    /// whatever was hit, so a tap on its nameplate is a tap on the reel.
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

    /// Draws the tape out or winds it in without a pinch — for debug
    /// arguments and tests.
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
    /// converts into its own frame, offset and yaw included.
    @discardableResult
    func handleDrag(entity: Entity, handWorld: SIMD3<Double>) -> Bool {
        // Only once the tape is fully out: mid-draw the mapping is still moving.
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

/// Mounts the Time Rail in whatever lab is on screen.
struct TimeRailView: View {
    let module: ModuleDescriptor
    @Environment(AppModel.self) private var appModel
    /// The system setting; there is no in-app duplicate.
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
            // `-scrubBack <s>` draws the tape out and scrubs, since the simulator
            // cannot pinch; `-scrubStep <n>` applies frame steps on top. To
            // photograph the reel closed, pass `-pauseAfter` alone.
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
                    // Only ever scrub a pause that happened: this argument stages a state,
                    // it must not create one.
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
