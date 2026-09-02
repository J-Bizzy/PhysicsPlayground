//
//  TimeCapsuleSupport.swift
//  Physics Playground — Shell
//
//  Adoption contract for the Time Capsule: a model that records itself
//  into a `TimeCapsule` every physics step and can be scrubbed back to
//  any recorded instant while paused.
//
//  The snapshot is the experiment, not the observer: dynamical state,
//  entity sets and physics clocks go in; display layers, bank flags,
//  selections and anything a hand is currently holding stay out. The one
//  admitted exception is a flag that changes the physics itself (Electric
//  Fields' capacitor and B-field) — a recorded motion scrubbed back into
//  a room whose field is off would be a lie.
//
//  Scrubbing never fabricates state: a scrub restores an exactly-recorded
//  frame. The only re-simulation anywhere in the feature is the forward
//  run after resume, which is disclosed by the truncation itself — the
//  rejected future is discarded and the room genuinely re-runs.
//

import Foundation
import PhysicsCore

/// The one place that answers "is the Time Capsule switched on?".
///
/// A `@MainActor` global rather than a reference to `AppSettings`,
/// because the six models are the things that have to ask and none of
/// them knows the shell exists — a model reaching up to the app object
/// to find out whether to record would invert the layering the whole
/// project is built on. `AppSettings.timeCapsule` is the writer; this is
/// the reader.
@MainActor
enum TimeCapsuleSettings {
    /// On by default since 2026-09-01 — see `AppSettings.timeCapsule`
    /// for why. This static only matters before `AppSettings` exists
    /// (`AppModel.init` overwrites it from the stored preference); the
    /// two defaults must agree, or a model built before the settings
    /// would record differently from one built after.
    static var isEnabled = true
}

@MainActor
protocol TimeCapsuleRecording: AnyObject {
    associatedtype CapsuleSnapshot: Equatable

    /// Both are `@ObservationIgnored` in every adopter: they mutate once
    /// per physics step, and observation-tracking them would invalidate
    /// every observing view at frame rate.
    var capsule: TimeCapsule<CapsuleSnapshot> { get set }
    var capsuleClock: Double { get set }

    /// nil = live. Non-nil = frozen at this recorded capsule time. This is
    /// the one observed member — it changes only on user action and
    /// drives the rail readout. (An optional Double rather than a
    /// separate Bool, deliberately: `ResetCoverageTests` sweeps Bools,
    /// and this carries the same information without widening that
    /// surface.)
    var scrubTime: Double? { get set }

    /// Bumped on every restore so renderers can reseed the presentation
    /// caches (trail clocks, ghost counters) that a discontinuous state
    /// jump invalidates — the `resetNonce` pattern, per model.
    var scrubNonce: Int { get set }

    var isPaused: Bool { get set }

    func captureCapsuleSnapshot() -> CapsuleSnapshot
    func restoreCapsuleSnapshot(_ snapshot: CapsuleSnapshot)
}

extension TimeCapsuleRecording {
    /// Seconds of recording available to scrub over.
    var capsuleSpan: ClosedRange<Double>? { capsule.span }

    /// Call at the end of every successful (unpaused) step with the same
    /// dt the physics just advanced by.
    ///
    /// Switched off, this is the cheapest possible no-op: no snapshot is
    /// taken, so a lab with the capsule off costs exactly what it cost
    /// before the feature existed. The buffer is dropped on the way out
    /// rather than left sitting on the model, because holding several
    /// megabytes of a recording the user has switched off is the same
    /// mistake in slower motion.
    func recordCapsuleFrame(dt: Double) {
        guard TimeCapsuleSettings.isEnabled else {
            if !capsule.isEmpty { clearCapsule() }
            return
        }
        capsuleClock += dt
        capsule.record(captureCapsuleSnapshot(), at: capsuleClock)
    }

    /// Freezes the room (if it isn't already) and restores the recorded
    /// frame `seconds` behind the newest one. Clamped to the recording.
    func scrub(toOffset seconds: Double) {
        guard let span = capsule.span else { return }
        isPaused = true
        let target = span.upperBound - max(0, seconds)
        guard let frame = capsule.frame(at: target) else { return }
        // `scrubTime` is set BEFORE the restore, not after: a model that
        // rebuilds derived state from the capsule — Gravity Lab's orbit
        // trails, Electric Fields' probe trail — needs to know which
        // instant it is being restored to WHILE restoring. Set after,
        // those rebuilds read nil and quietly produce nothing.
        scrubTime = frame.time
        restoreCapsuleSnapshot(frame.snapshot)
        scrubNonce &+= 1
    }

    /// One recorded physics tick at a time, clamped at the recording's
    /// ends. Stepping while live starts from the newest frame.
    func stepScrub(frames: Int) {
        guard !capsule.isEmpty else { return }
        isPaused = true
        let origin = scrubTime ?? capsule.span!.upperBound
        guard let frame = capsule.frame(steppedFrom: origin, by: frames) else { return }
        scrubTime = frame.time
        restoreCapsuleSnapshot(frame.snapshot)
        scrubNonce &+= 1
    }

    /// Un-pause FROM the scrubbed instant: the rejected future is
    /// truncated and the simulation runs forward from a state that
    /// genuinely occurred.
    func commitScrubAndResume() {
        if let time = scrubTime {
            capsule.truncate(after: time)
            capsuleClock = time
            scrubTime = nil
        }
        isPaused = false
    }

    /// The pause petal's entry point, replacing `isPaused.toggle()`.
    func togglePauseRespectingScrub() {
        if isPaused {
            commitScrubAndResume()
        } else {
            isPaused = true
        }
    }

    /// A fresh bench must not carry the old bench's past — every
    /// `reset()` calls this.
    func clearCapsule() {
        capsule.removeAll()
        capsuleClock = 0
        scrubTime = nil
    }
}

extension TimeScrubControls {
    /// One line per module: the descriptor's scrub contract, wired
    /// straight to an adopting model. The model is retained by AppModel
    /// for the app's life, so the strong captures here match every other
    /// descriptor closure.
    init<Model: TimeCapsuleRecording>(model: Model) {
        self.init(
            span: { model.capsuleSpan },
            scrubTime: { model.scrubTime },
            scrub: { model.scrub(toOffset: $0) },
            stepFrames: { model.stepScrub(frames: $0) },
            resume: { model.commitScrubAndResume() })
    }
}
