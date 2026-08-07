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

    private let controls: TimeScrubControls
    private let isPaused: () -> Bool
    private let track: SpatialTrackControl
    private let plates: SpatialActionBank

    /// 0 folded, 1 out. An opacity ramp, never a scale: scaling a track
    /// stretches the rail without stretching the range it maps.
    private var visibility: Float = 0
    var isVisible: Bool { visibility > 0.02 }

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
            layout: TrackLayout(length: 0.34),
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
        plates.root.position = [0.34 / 2 + 0.11, 0, 0]
        root.addChild(plates.root)

        root.position = Self.home
        setVisibility(0)
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
    func update(dt: Double, viewer: SIMD3<Float>?, placement: SIMD3<Float>) {
        root.position = Self.home + placement

        if let viewer {
            let flat = SIMD3<Float>(viewer.x - root.position.x, 0,
                                    viewer.z - root.position.z)
            if simd_length(flat) > 1e-4 {
                root.orientation = simd_quatf(from: [0, 0, 1],
                                              to: simd_normalize(flat))
            }
        }

        let target: Float = wantsPresence ? 1 : 0
        if visibility != target {
            let rate = Float(min(dt * 6, 1))
            visibility += (target - visibility) * rate
            if abs(visibility - target) < 0.01 { visibility = target }
            setVisibility(visibility)
        }
        guard isVisible else { return }

        track.refresh()
        // The plates lay themselves out relative to their own root; the
        // rail already faces the viewer, so they inherit its yaw.
        plates.update(anchor: plates.root.position, viewer: nil, dt: dt)
    }

    private func setVisibility(_ value: Float) {
        root.components.set(OpacityComponent(opacity: value))
        let enabled = value > 0.02
        root.isEnabled = enabled
        track.isEnabled = enabled
    }

    // MARK: Input routing (the mounting view's gestures land here)

    /// True when the tap hit one of the rail's plates.
    func handleTap(_ entity: Entity) -> Bool {
        guard isVisible else { return false }
        return plates.handleTap(entity)
    }

    /// Routes a drag on the rail. `handWorld` is in scene space; the rail
    /// converts into its own frame so `adjust` sees the hand where the
    /// rail actually stands — offset, yaw and all.
    @discardableResult
    func handleDrag(entity: Entity, handWorld: SIMD3<Double>) -> Bool {
        guard isVisible else { return false }
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
    @State private var rail: TimeRail?

    var body: some View {
        RealityView { content in
            let made = TimeRail(module: module)
            content.add(made.root)
            rail = made

            made.subscription = content.subscribe(
                to: SceneEvents.Update.self
            ) { [weak made] event in
                made?.update(
                    dt: event.deltaTime,
                    viewer: appModel.room.headPosition.map { SIMD3<Float>($0) },
                    placement: appModel.labPlacement.offset)
            }

            #if DEBUG
            // The simulator cannot pinch. `-pauseAfter 4 -scrubBack 1.5`
            // runs the experiment, pauses it, then scrubs the room back
            // 1.5 s; `-scrubStep -3` applies three frame-steps on top —
            // photographing the mapping, not just the rail.
            let back = UserDefaults.standard.double(forKey: "scrubBack")
            if back > 0 {
                let scrub = module.timeScrub
                let isPaused = module.isPaused
                let steps = UserDefaults.standard.integer(forKey: "scrubStep")
                Task {
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
                    scrub.scrub(back)
                    if steps != 0 { scrub.stepFrames(steps) }
                }
            }
            #endif
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
