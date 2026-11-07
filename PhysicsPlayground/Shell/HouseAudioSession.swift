//
//  HouseAudioSession.swift
//  Physics Playground — Shell
//
//  The app's place among the wearer's other sound (2026-11-07). The
//  system's default audio category is non-mixable: opening the app stopped
//  whatever they were listening to, and the house music started in its
//  place. `.ambient` mixes instead, and the house music yields while the
//  wearer's own audio plays — the effects still sound, under it, and the
//  music comes back when theirs stops.
//

import AVFAudio

@MainActor
enum HouseAudioSession {
    /// Once, on the launch path, before any sound.
    static func configure() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default,
                                                         options: [.mixWithOthers])
    }

    /// Whether the wearer has audio of their own playing.
    static var othersArePlaying: Bool {
        AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
    }

    /// Whether the house music plays: asked for in Settings, and nothing of
    /// the wearer's own to yield to.
    nonisolated static func musicPlays(wanted: Bool, othersArePlaying: Bool) -> Bool {
        wanted && !othersArePlaying
    }
}
