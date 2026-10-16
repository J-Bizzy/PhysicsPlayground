//
//  Remark.swift
//  Physics Playground — Design system
//
//  The app's rarest reaction: a gleam (`SoundPalette.Sound.gleam`), once a
//  session for each of three moments a lab can arrive at but never stages.
//    • beamHome — Light & Optics: the laser's own beam, sent back by the
//      optics, re-enters its aperture (a mirror set exactly square to it).
//    • swingPassedAcross — Pendulums: a coupled pair's swing has passed
//      wholly from one bob to the other, the one that started at rest.
//    • firstLight — Magnetism: the pickup coil's LED lights for the first
//      time, from a magnet pushed through it.
//  Each is the physics arriving somewhere on its own, so each is already
//  something to see; the gleam only says "look". It is sound alone: the
//  house allows one glow, `LiveGlow`, on what a hand holds.
//
//  Models claim a moment and, the first time only, emit the gleam as an
//  ordinary spatial sound event from where it happened.
//

@MainActor
enum Remark {
    enum Moment: String, CaseIterable {
        case beamHome, swingPassedAcross, firstLight
    }

    /// How loud a gleam plays, 0…1 — a little under a success's chime.
    static let volume = 0.6

    private static var claimed: Set<Moment> = []

    /// True the first time `moment` happens this session, false ever after.
    static func claim(_ moment: Moment) -> Bool {
        claimed.insert(moment).inserted
    }

    /// Whether `moment` has already been heard this session.
    static func isClaimed(_ moment: Moment) -> Bool {
        claimed.contains(moment)
    }

    #if DEBUG
    /// Tests only: a fresh session.
    static func forgetForTesting() {
        claimed = []
    }
    #endif
}
