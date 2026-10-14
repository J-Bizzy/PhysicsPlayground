//
//  AppSettings.swift
//  Physics Playground — Shell
//
//  Every user preference, in one observable object backed by
//  UserDefaults. Every row does something the moment it is flipped.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppSettings {
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

    /// Whether every lab records its last thirty seconds so a pause can be
    /// scrubbed. On by default. Gates the recording itself
    /// (`TimeCapsuleSettings.isEnabled`), not just the reel: switched off,
    /// no model snapshots itself and whatever was recorded is dropped.
    var timeCapsule: Bool {
        didSet {
            UserDefaults.standard.set(timeCapsule, forKey: "settings.timeCapsule")
            TimeCapsuleSettings.isEnabled = timeCapsule
        }
    }

    // MARK: What is NOT here any more

    init() {
        let defaults = UserDefaults.standard
        masterVolume = defaults.object(forKey: "settings.masterVolume") as? Double ?? 1.0
        ambientAudio = defaults.object(forKey: "settings.ambientAudio") as? Bool ?? true
        var capsule = defaults.object(forKey: "settings.timeCapsule") as? Bool ?? true
        #if DEBUG
        // `-timeCapsule 0` switches the feature off for one launch without
        // writing the preference. The argument domain stores a string, and
        // `bool(forKey:)` reads "0" as false.
        if defaults.object(forKey: "timeCapsule") != nil {
            capsule = defaults.bool(forKey: "timeCapsule")
        }
        #endif
        timeCapsule = capsule
        // `didSet` does not fire during init, so the restored answer is handed
        // to the recording gate by hand.
        TimeCapsuleSettings.isEnabled = timeCapsule
        // Same: hand the restored volume to the sound engine here.
        SoundPalette.masterVolume = masterVolume
    }
}
