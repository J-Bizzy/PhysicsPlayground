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

    /// Which voice the home's display type speaks in — the wordmark
    /// and both door signs. Persisted, because it is a taste decision
    /// being made over several sittings; `HubTitleStyle.audition`
    /// stands all the candidates side by side instead of choosing one.
    var titleStyle: Int {
        didSet { UserDefaults.standard.set(titleStyle, forKey: "settings.titleStyle") }
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

    /// Module ids whose one-time first-run hint has been dismissed.
    /// The hint is the whole of onboarding: one sentence per module,
    /// shown in the module window until the user closes it.
    private(set) var seenHints: Set<String> {
        didSet {
            UserDefaults.standard.set(seenHints.sorted(),
                                      forKey: "settings.seenHints")
        }
    }

    func hasSeenHint(_ moduleID: String) -> Bool {
        seenHints.contains(moduleID)
    }

    /// Marked on DISMISS, not on display — a hint glanced past is a
    /// hint not yet read.
    func markHintSeen(_ moduleID: String) {
        seenHints.insert(moduleID)
    }

    /// Every module's first-run hint appears once more.
    func resetOnboardingTips() {
        seenHints = []
    }

    init() {
        let defaults = UserDefaults.standard
        reduceMotion = defaults.bool(forKey: "settings.reduceMotion")
        masterVolume = defaults.object(forKey: "settings.masterVolume") as? Double ?? 1.0
        ambientAudio = defaults.object(forKey: "settings.ambientAudio") as? Bool ?? true
        titleStyle = defaults.object(forKey: "settings.titleStyle") as? Int
            ?? HubTitleStyle.audition
        arcDistance = defaults.object(forKey: "settings.arcDistance") as? Double ?? 2.0
        arcHeight = defaults.object(forKey: "settings.arcHeight") as? Double ?? 1.4
        seenHints = Set(defaults.stringArray(forKey: "settings.seenHints") ?? [])
        // didSet does not fire during init, so hand the restored volume to
        // the sound engine here — otherwise a debug `-openModule` launch
        // (which skips the hub) would play at full volume regardless.
        SoundPalette.masterVolume = masterVolume
    }
}
