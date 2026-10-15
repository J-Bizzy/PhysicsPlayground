//  HubDomains.swift — the app's two doors: seven experiences grouped into two domains.
//  Wayfinding only: the domain colour appears in exactly two places (terrace hairline,
//  door sign); experiences keep their own accents everywhere else.

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

    /// Door hues live in `DesignTokens.Palette` — a domain and its flagship module wear the same colour.
    var color: Color {
        switch self {
        case .electricity: DesignTokens.Palette.circuitsAccent
        case .mechanics: DesignTokens.Palette.kinematicsAccent
        }
    }

    /// The experiences behind this door, in their display order.
    var moduleIDs: [String] {
        switch self {
        case .electricity: ["electrostatics", "circuits", "magnetism", "optics"]
        case .mechanics: ["kinematics", "pendulums", "gravitylab"]
        }
    }

    static func domain(for moduleID: String) -> HubDomain {
        allCases.first { $0.moduleIDs.contains(moduleID) } ?? .mechanics
    }

    /// The hub's left-to-right order: every experience, grouped by domain.
    static var arcOrder: [String] { allCases.flatMap(\.moduleIDs) }

    /// One line per experience — what you do in it; the line the panel leads with.
    static func promise(for moduleID: String) -> String {
        switch moduleID {
        case "electrostatics": "Place charges and walk through the field they make"
        case "circuits": "Build a live circuit and watch charge become current and light"
        case "magnetism": "Carry bar magnets and feel their field reorganize the room"
        case "optics": "Aim a laser around your room and split white light into a rainbow"
        case "kinematics": "Fire projectiles and bend their arcs with gravity and drag"
        case "pendulums": "Throw a pendulum into a true 3-D orbit above your floor"
        case "gravitylab": "Grow a solar system and hear its orbits as a chord"
        default: ""
        }
    }
}
