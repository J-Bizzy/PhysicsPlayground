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

    /// The house music, from the space's first frame to its last.
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

    // MARK: Surroundings

    /// The room, or deep space: chosen in More, on the home or in a lab,
    /// and remembered here. A lab with its own preference overrides it for
    /// a visit (`AppModel.surroundings`).
    var surroundings: Surroundings {
        didSet { UserDefaults.standard.set(surroundings.rawValue, forKey: "settings.surroundings") }
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
        var chosen = defaults.string(forKey: "settings.surroundings")
            .flatMap(Surroundings.init(rawValue:)) ?? .room
        #if DEBUG
        // `-surroundings space|room` holds for one launch without writing
        // the choice; `AppModel` hands it to a lab with a preference too.
        if let argument = defaults.string(forKey: "surroundings"),
           let launch = Surroundings(argument: argument) {
            chosen = launch
        }
        #endif
        surroundings = chosen
        // `didSet` does not fire during init, so the restored answer is handed
        // to the recording gate by hand.
        TimeCapsuleSettings.isEnabled = timeCapsule
        // Same: hand the restored volume to the sound engine here.
        SoundPalette.masterVolume = masterVolume
    }
}
