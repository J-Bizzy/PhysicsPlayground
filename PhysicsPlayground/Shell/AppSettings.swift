//
//  AppSettings.swift
//  Physics Playground — Shell
//
//  Every user-facing preference, in one observable object backed by
//  UserDefaults. The rule for what belongs here: a setting must DO
//  something the moment it is flipped. A settings screen full of rows
//  that are quietly ignored is worse than no settings screen — every
//  row here is wired to the surface it claims to control.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppSettings {
    // MARK: Comfort

    /// Stops the hub's idle life — the bob, the sway, the running
    /// miniatures. The system-wide Reduce Motion accessibility switch
    /// also forces this on; the in-app toggle exists for people who want
    /// a calm menu without changing a device-wide setting.
    var reduceMotion: Bool {
        didSet { UserDefaults.standard.set(reduceMotion, forKey: "settings.reduceMotion") }
    }

    // MARK: Audio

    /// Scales every one-shot effect the app plays. 0 is silence.
    var masterVolume: Double {
        didSet {
            UserDefaults.standard.set(masterVolume, forKey: "settings.masterVolume")
            SoundPalette.masterVolume = masterVolume
        }
    }

    /// The quiet lab room tone under every module.
    var ambientAudio: Bool {
        didSet { UserDefaults.standard.set(ambientAudio, forKey: "settings.ambientAudio") }
    }

    // MARK: Space — the hub arc's geometry

    /// How far away the exhibit arc stands, metres.
    var arcDistance: Double {
        didSet { UserDefaults.standard.set(arcDistance, forKey: "settings.arcDistance") }
    }

    /// How high the exhibits float, metres.
    var arcHeight: Double {
        didSet { UserDefaults.standard.set(arcHeight, forKey: "settings.arcHeight") }
    }

    /// Bumped whenever the arc needs rebuilding (sliders committed,
    /// recenter). The hub view keys its RealityView identity to this, so
    /// changing it tears the old scene down and builds a fresh one with
    /// the new geometry. Not persisted — it is a rebuild signal, not a
    /// preference.
    var layoutVersion = 0

    /// A yaw applied to the whole hub scene so "Recenter" can swing the
    /// arc round to wherever the user is now facing. Radians about Y.
    /// Session-only: the room the app reopens into is not the room it
    /// closed in.
    var hubYaw: Float = 0

    // MARK: Onboarding

    /// The coach-mark sequence, as a stage counter:
    /// 0 — has never focused an exhibit ("look at a module")
    /// 1 — has focused, never entered ("pinch to step inside")
    /// 2 — has entered, never opened the notebook ("your lab notebook")
    /// 3 — done; no more coaching, ever.
    var coachStage: Int {
        didSet { UserDefaults.standard.set(coachStage, forKey: "settings.coachStage") }
    }

    /// Advances the coach sequence, never backwards — wandering back to
    /// an earlier trigger must not resurrect a dismissed tip.
    func advanceCoach(past stage: Int) {
        if coachStage == stage { coachStage = stage + 1 }
    }

    /// Puts onboarding back to a first launch: the coach sequence
    /// restarts and the wordmark plays once more. The wordmark's
    /// one-shot flag lives outside this object (the hub owns the read),
    /// so it is cleared by key here.
    func resetOnboardingTips() {
        coachStage = 0
        UserDefaults.standard.removeObject(forKey: "hasSeenWordmark")
        layoutVersion += 1
    }

    init() {
        let defaults = UserDefaults.standard
        reduceMotion = defaults.bool(forKey: "settings.reduceMotion")
        masterVolume = defaults.object(forKey: "settings.masterVolume") as? Double ?? 1.0
        ambientAudio = defaults.object(forKey: "settings.ambientAudio") as? Bool ?? true
        arcDistance = defaults.object(forKey: "settings.arcDistance") as? Double ?? 2.0
        arcHeight = defaults.object(forKey: "settings.arcHeight") as? Double ?? 1.4
        coachStage = defaults.integer(forKey: "settings.coachStage")
        // didSet does not fire during init, so hand the restored volume to
        // the sound engine here — otherwise a debug `-openModule` launch
        // (which skips the hub) would play at full volume regardless.
        SoundPalette.masterVolume = masterVolume
    }
}
