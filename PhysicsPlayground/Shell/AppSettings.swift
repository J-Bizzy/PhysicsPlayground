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

    // MARK: Time Capsule

    /// Whether every lab records its last thirty seconds, so a pause can
    /// be scrubbed. **On by default** since 2026-09-01 (owner's call,
    /// reversing 2026-08-07).
    ///
    /// The 08-07 argument — a default is a claim about what the app IS,
    /// and someone meeting it for the first time should meet the labs —
    /// was made against a build that put a 34 cm rail in every pause.
    /// The reel answered that the same day: a pause shows one small
    /// object and nothing else until it is pinched, so with the capsule
    /// on the first thing a wearer meets is still six labs. What OFF
    /// cost was that every buyer met the app without its most
    /// distinctive feature. DECISIONS.md 2026-09-01.
    ///
    /// It gates the RECORDING, not just the reel, and that is the whole
    /// reason it is a setting rather than a preference about furniture:
    /// switched off, no model snapshots itself, so the several megabytes
    /// and the per-frame copy are not spent on a capability the wearer
    /// declined. `TimeCapsuleSettings.isEnabled` reads this, and
    /// turning it off drops whatever was already recorded — a capsule
    /// that survived being switched off would be a recording made after
    /// the user said stop.
    var timeCapsule: Bool {
        didSet {
            UserDefaults.standard.set(timeCapsule, forKey: "settings.timeCapsule")
            TimeCapsuleSettings.isEnabled = timeCapsule
        }
    }

    // MARK: What is NOT here any more
    //
    // No `titleStyle`: the home speaks in the machined plaque, full
    // stop (owner's call, 2026-07-31). No arc geometry either — the
    // `arcDistance`/`arcHeight` sliders, the session `hubYaw` and the
    // `layoutVersion` rebuild signal all left on 2026-08-03, when the
    // gallery gained its grab bar: repositioning by rebuild duplicated
    // the whole room, and where the gallery stands is a spatial fact
    // now, owned by `GalleryPlacement` and persisted under its own
    // keys. A decision that has been made is not a preference, and a
    // position is not a slider.

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
        var capsule = defaults.object(forKey: "settings.timeCapsule") as? Bool ?? true
        #if DEBUG
        // `-timeCapsule 0` switches the feature OFF for a launch without
        // writing the preference — the way to photograph a plain pause
        // now that recording is the default. (`-timeCapsule 1` still
        // works, and is a no-op on a fresh install.) The argument domain
        // stores a string; `bool(forKey:)` reads "0" as false, the same
        // conversion `-kinBalls` relies on.
        if defaults.object(forKey: "timeCapsule") != nil {
            capsule = defaults.bool(forKey: "timeCapsule")
        }
        #endif
        timeCapsule = capsule
        seenHints = Set(defaults.stringArray(forKey: "settings.seenHints") ?? [])
        // Same reason as the volume below: `didSet` does not fire during
        // init, so the restored answer has to be handed to the recording
        // gate by hand or every model would record until Settings was
        // opened.
        TimeCapsuleSettings.isEnabled = timeCapsule
        // didSet does not fire during init, so hand the restored volume to
        // the sound engine here — otherwise a debug `-openModule` launch
        // (which skips the hub) would play at full volume regardless.
        SoundPalette.masterVolume = masterVolume
    }
}
