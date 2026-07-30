//
//  StationFocus.swift
//  Physics Playground — Design System
//
//  Which apparatus in a world is being attended to, and how the others
//  stand back while it is.
//
//  ── Why this exists, and the line it has to hold ──
//
//  This app has undone two module mergers. Both died the same way: a
//  segmented control in the window panel chose which half of the module
//  existed, the controls later moved into spatial pods, and the second
//  half became unreachable. The rule written down afterwards was that a
//  merger is only a merger if both halves are simultaneously present —
//  otherwise it is a picker, and pickers get lost.
//
//  "Turn your head" carried two stations. It does not carry three:
//  three lit apparatus is a room with no subject, and three panels
//  stacked in one window is a wall. So one station is FOCUSED at a time.
//
//  That is a picker unless the difference is real, so here is the
//  difference, and it is four testable properties rather than a claim:
//
//    1. Still solving. The unfocused station's solver runs in the same
//       world tick, in the same fixed order. Pausing dim stations is
//       forbidden — permanently, including as a performance fix. If
//       frame time gets tight, cut an unfocused station's VISUAL work
//       (particle budgets, trail lengths); never its physics.
//    2. Still hittable. Focus never touches CollisionComponent or
//       InputTargetComponent, and no gesture is consumed: a tap or drag
//       on a dim station focuses it AND is forwarded, so a drag that
//       begins on a dim magnet moves it. A dim station is dimmer, not
//       less capable.
//    3. Still in the panel. Sections collapse; they never disappear.
//    4. Never dark. Emphasis floors at `dimFloor`, which is asserted
//       greater than zero.
//
//  If any of the four reaches zero, this is a picker again.
//
//  ── And one hard rule it buys ──
//
//  EMPHASIS IS OPACITY, LIGHT AND SOUND — NEVER GEOMETRY. Focus must
//  not animate a station's root transform. Every grab in this app is a
//  RelativeDrag (target + hand displacement), which a CONSTANT
//  translation leaves untouched — that is exactly why lab placement and
//  the station seats are safe. An ANIMATING one is not: a station
//  receding mid-drag would slide the held body out from under the
//  fingers. It would also make the layout's tested bounds a lie.
//

import Foundation
import RealityKit

/// The emphasis constants, in one non-generic place so tests, debug
/// arguments and docs can reach them without naming a station type.
enum StationEmphasis {
    /// How lit an unfocused station stays. The anti-picker floor:
    /// property 4 above, and the reason `StationFocusTests` asserts this
    /// is greater than zero.
    static let dimFloor: Float = 0.40

    /// How far a station's TRACES fade when it is not the one being
    /// attended to — much deeper than `dimFloor`.
    ///
    /// A trace is a field line, a trajectory, a streamline: the drawing
    /// of something that genuinely extends through the whole room, and
    /// so it is the one part of an apparatus that does not stay inside
    /// its station. Two charges 40 cm apart arch their lines over the
    /// entire world and across both neighbouring benches. That is
    /// honest physics and must not be clipped — but at the apparatus
    /// floor it also means a bench you are not using still fills your
    /// view, and a room with three of those has no subject at all.
    ///
    /// So traces fade further than the things that make them. The
    /// anti-picker floor is untouched: it guards the APPARATUS, which
    /// is what has to stay findable and grabbable. Nobody grabs a field
    /// line.
    static let traceFloor: Float = 0.12

    /// Time constant of the fade, in seconds. Long enough to read as
    /// attention moving rather than a light switch; short enough that a
    /// screenshot taken a third of a second later is settled.
    static let settleTime: Double = 0.22

    #if DEBUG
    /// `-stationDim 1` lifts the floor to 1.0 — every station fully lit,
    /// the control image for judging whether the dim treatment is doing
    /// any work. Clamped so it can never drive a station dark and turn
    /// the mechanic into the picker it is not.
    static var floorOverride: Float? {
        let value = UserDefaults.standard.double(forKey: "stationDim")
        guard value > 0 else { return nil }
        return min(max(Float(value), 0.05), 1)
    }
    #endif

    static var effectiveFloor: Float {
        #if DEBUG
        return floorOverride ?? dimFloor
        #else
        return dimFloor
        #endif
    }
}

/// Which station a world is attending to, and each station's eased
/// emphasis on the way there.
@MainActor
@Observable
final class StationFocus<ID: Hashable & Sendable> {
    /// The station currently being attended to.
    private(set) var focused: ID

    /// Eased emphasis per station. Absent means "not yet ticked", which
    /// `emphasis(for:)` resolves to the settled value.
    private var live: [ID: Float] = [:]

    init(initial: ID) {
        focused = initial
        live[initial] = 1
    }

    // MARK: Focus

    /// Attend to a station. Idempotent — re-focusing the focused station
    /// changes nothing, so a stream of drag events doesn't restart a
    /// fade every frame.
    func focus(_ station: ID) {
        guard station != focused else { return }
        focused = station
    }

    /// Where a station's emphasis is heading: fully lit if focused,
    /// the floor otherwise.
    func target(for station: ID) -> Float {
        station == focused ? 1 : StationEmphasis.effectiveFloor
    }

    /// A station's emphasis right now, part-way through the fade.
    ///
    /// Never returns less than the floor — property 4 is enforced here
    /// rather than trusted to every caller.
    func emphasis(for station: ID) -> Float {
        let value = live[station] ?? target(for: station)
        return min(max(value, StationEmphasis.effectiveFloor), 1)
    }

    /// How lit a station's TRACES are right now — the same eased
    /// journey as `emphasis(for:)`, but landing on `traceFloor`.
    func traceEmphasis(for station: ID) -> Float {
        let floor = StationEmphasis.effectiveFloor
        let span = 1 - floor
        // Recover how far along the fade this station is, so both
        // curves move together and can never disagree about which
        // bench is being attended to.
        let progress = span > 1e-6 ? (emphasis(for: station) - floor) / span : 1
        let traceFloor = min(StationEmphasis.traceFloor, floor)
        return traceFloor + progress * (1 - traceFloor)
    }

    // MARK: Per-frame

    /// Eases every known station toward its target. Exponential
    /// approach, so it is frame-rate independent and never overshoots.
    func tick(dt: Double) {
        guard dt > 0 else { return }
        let alpha = Float(1 - exp(-dt / StationEmphasis.settleTime))
        for (station, value) in live {
            let goal = target(for: station)
            live[station] = value + (goal - value) * alpha
        }
    }

    /// Jump straight to the settled values.
    ///
    /// This is what `-focusStation` uses: the simulator has no hands, so
    /// without it a CLI screenshot catches a mid-fade frame and the
    /// image is of nothing in particular.
    func snap() {
        for station in live.keys {
            live[station] = target(for: station)
        }
    }

    /// Registers a station so it participates in the fade. Called once
    /// per station as the world installs it.
    func register(_ station: ID) {
        if live[station] == nil { live[station] = target(for: station) }
    }

    // MARK: Applying it

    /// Emphasis, on the scene. Opacity ONLY — see the header's hard
    /// rule about geometry.
    func apply(_ station: ID, to root: Entity) {
        set(emphasis(for: station), on: root)
    }

    /// The extra fade for a trace subtree hanging INSIDE a station that
    /// has already been dimmed.
    ///
    /// Nested `OpacityComponent`s multiply, so this is the ratio that
    /// lands the net opacity on `traceEmphasis` rather than the value
    /// itself — writing `traceEmphasis` here directly would dim the
    /// lines twice over.
    func applyTrace(_ station: ID, to traceRoot: Entity) {
        let apparatus = emphasis(for: station)
        guard apparatus > 1e-6 else { return }
        set(min(traceEmphasis(for: station) / apparatus, 1), on: traceRoot)
    }

    private func set(_ value: Float, on root: Entity) {
        if var opacity = root.components[OpacityComponent.self] {
            // Skip sub-perceptual writes: this runs every frame for
            // every station, and a settled world should not be
            // re-touching components at 90 Hz.
            guard abs(opacity.opacity - value) > 0.001 else { return }
            opacity.opacity = value
            root.components.set(opacity)
        } else {
            root.components.set(OpacityComponent(opacity: value))
        }
    }
}
