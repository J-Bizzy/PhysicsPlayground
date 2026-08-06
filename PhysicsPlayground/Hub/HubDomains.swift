//
//  HubDomains.swift
//  Physics Playground — Hub
//
//  The app's two doors. Six experiences, grouped into the two domains
//  the app actually ships: pick a domain on the Home Screen, then pick
//  the specific experience inside it. The domain is a WAYFINDING layer,
//  not a new hierarchy: experiences keep their own accents everywhere
//  they already use them, and the domain colour appears in exactly
//  three places — the floating header over each group, the progress
//  ring around each miniature, and the chip on the focus panel.
//  Everywhere else the room stays calm.
//
//  Two, deliberately, after trying one-world-per-domain and measuring
//  why it failed (DECISIONS.md 2026-07-30): standing a domain's
//  benches in one room pushed every bench a step out of reach, and the
//  orrery could not fit at all. The domain now lives HERE, as a door,
//  and each experience behind it gets the room to itself.
//

import SwiftUI

/// A physics domain: a named, coloured door on the Home Screen, holding
/// its experiences in display order.
enum HubDomain: String, CaseIterable, Identifiable {
    case electricity
    case mechanics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .electricity: "Electricity & Magnetism"
        case .mechanics: "Mechanics & Energy"
        }
    }

    /// The door hues live in `DesignTokens.Palette` (2026-08-06) — the
    /// domain and its flagship module wear the SAME colour now, where
    /// they used to be two independently-typed near-matches (#30D158
    /// beside stock `.green`, #FF9F0A beside stock `.orange`).
    var color: Color {
        switch self {
        case .electricity: DesignTokens.Palette.circuitsAccent
        case .mechanics: DesignTokens.Palette.kinematicsAccent
        }
    }

    /// The experiences behind this door, in their display order.
    ///
    /// E&M reads as the subject builds: charges make fields, moving
    /// charges make circuits, circuits make magnets. Mechanics runs
    /// from a thrown ball to a held one to an orbiting one.
    var moduleIDs: [String] {
        switch self {
        case .electricity: ["electrostatics", "circuits", "magnetism"]
        case .mechanics: ["kinematics", "pendulums", "gravitylab"]
        }
    }

    static func domain(for moduleID: String) -> HubDomain {
        allCases.first { $0.moduleIDs.contains(moduleID) } ?? .mechanics
    }

    /// The hub's left-to-right order: every experience, grouped by domain.
    static var arcOrder: [String] { allCases.flatMap(\.moduleIDs) }

    /// One line per experience: what you DO in it, as a promise rather
    /// than a syllabus entry. The descriptor blurbs are two sentences of
    /// what-and-why, right for the reading panel; this is the single
    /// line the panel leads with.
    static func promise(for moduleID: String) -> String {
        switch moduleID {
        case "electrostatics": "Place charges and walk through the field they make"
        case "circuits": "Build a live circuit and watch charge become current and light"
        case "magnetism": "Carry bar magnets and feel their field reorganise the room"
        case "kinematics": "Fire projectiles and bend their arcs with gravity and drag"
        case "pendulums": "Throw a pendulum into a true 3-D orbit above your floor"
        case "gravitylab": "Grow a solar system and hear its orbits as a chord"
        default: ""
        }
    }
}
