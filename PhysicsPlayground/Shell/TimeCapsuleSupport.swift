//
//  TimeCapsuleSupport.swift
//  Physics Playground — Shell
//
//  Adoption contract for the Time Capsule: a model records itself into
//  a `TimeCapsule` every physics step and can be scrubbed back to any
//  recorded instant while paused. The snapshot is the experiment, not
//  the observer: dynamical state and entity sets go in; display layers,
//  selections and anything a hand is holding stay out (Electric Fields'
//  field flags are the exception, because they change the physics). A
//  scrub restores an exactly recorded frame; the only re-simulation is
//  the forward run after resume, from a truncated recording.
//

import Foundation
import PhysicsCore

/// The one place that answers "is the Time Capsule switched on?" — a
/// global rather than a reference to `AppSettings`, because the models
/// ask and none of them knows the shell exists.
@MainActor
enum TimeCapsuleSettings {
    /// The default before `AppSettings` exists; `AppModel.init` overwrites
    /// it from the stored preference, and the two defaults must agree.
    static var isEnabled = true
}

@MainActor
protocol TimeCapsuleRecording: AnyObject {
    associatedtype CapsuleSnapshot: Equatable

    /// `@ObservationIgnored` in every adopter: they mutate once per step.
    var capsule: TimeCapsule<CapsuleSnapshot> { get set }
    var capsuleClock: Double { get set }

    /// nil = live; non-nil = frozen at this recorded capsule time. The one
    /// observed member; it changes only on user action.
    var scrubTime: Double? { get set }

    /// Bumped on every restore so renderers can reseed the presentation
    /// caches a discontinuous jump invalidates.
    var scrubNonce: Int { get set }

    var isPaused: Bool { get set }

    func captureCapsuleSnapshot() -> CapsuleSnapshot
    func restoreCapsuleSnapshot(_ snapshot: CapsuleSnapshot)
}

extension TimeCapsuleRecording {
    /// Seconds of recording available to scrub over.
    var capsuleSpan: ClosedRange<Double>? { capsule.span }

    /// Call at the end of every unpaused step with the dt the physics just
    /// advanced by. Switched off, no snapshot is taken and the buffer is
    /// dropped.
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
        // Set before the restore: a model that rebuilds derived state from the
        // capsule needs to know which instant it is restoring.
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

    /// Un-pause from the scrubbed instant: the rejected future is truncated
    /// and the simulation runs forward from a state that occurred.
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

    /// Every `reset()` calls this: a fresh bench carries no past.
    func clearCapsule() {
        capsule.removeAll()
        capsuleClock = 0
        scrubTime = nil
    }
}

extension TimeScrubControls {
    /// The descriptor's scrub contract, wired to an adopting model. The
    /// model is retained by AppModel for the app's life.
    init<Model: TimeCapsuleRecording>(model: Model) {
        self.init(
            span: { model.capsuleSpan },
            scrubTime: { model.scrubTime },
            scrub: { model.scrub(toOffset: $0) },
            stepFrames: { model.stepScrub(frames: $0) },
            resume: { model.commitScrubAndResume() })
    }
}
