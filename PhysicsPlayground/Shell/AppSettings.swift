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
    //
    // There is no `reduceMotion` here any more. The hub's idle life
    // still stills — it reads the SYSTEM accessibility switch, in
    // `HubSpaceView`, which is the switch someone who needs it has
    // already set. An in-app duplicate of a device-wide accessibility
    // setting is a second place for the same answer to live, and the
    // second place is the one that goes stale.

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

    // There is no `titleStyle` here any more either. The home speaks in
    // the machined plaque, full stop (owner's call, 2026-07-31) —
    // `HubTitleStyle.shipping`. The specimen wall did its job: it is how
    // the plaque was chosen, off three candidates hanging side by side
    // in the room. A decision that has been made is not a preference,
    // and leaving it in Settings invites every user to re-litigate the
    // app's own identity from a menu.

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
        masterVolume = defaults.object(forKey: "settings.masterVolume") as? Double ?? 1.0
        ambientAudio = defaults.object(forKey: "settings.ambientAudio") as? Bool ?? true
        arcDistance = defaults.object(forKey: "settings.arcDistance") as? Double ?? 2.0
        arcHeight = defaults.object(forKey: "settings.arcHeight") as? Double ?? 1.4
        seenHints = Set(defaults.stringArray(forKey: "settings.seenHints") ?? [])
        // didSet does not fire during init, so hand the restored volume to
        // the sound engine here — otherwise a debug `-openModule` launch
        // (which skips the hub) would play at full volume regardless.
        SoundPalette.masterVolume = masterVolume
    }
}
