//
//  HubDomains.swift
//  Physics Playground — Hub
//
//  The nine modules, grouped into the four domains a physics course
//  would group them into. The domain is a WAYFINDING layer, not a new
//  hierarchy: modules keep their own accents everywhere they already
//  use them, and the domain colour appears in exactly three places —
//  the floating header over each group, the progress ring around each
//  miniature, and the chip on the focus panel. Everywhere else the
//  room stays calm.
//

import SwiftUI

/// A physics domain: a named, coloured group of modules on the hub arc.
enum HubDomain: String, CaseIterable, Identifiable {
    case mechanics
    case electricity
    case fluidsGravity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mechanics: "Mechanics"
        case .electricity: "Electricity & Magnetism"
        case .fluidsGravity: "Fluids & Gravity"
        }
    }

    var color: Color {
        switch self {
        case .mechanics: Color(red: 1.00, green: 0.62, blue: 0.04)   // #FF9F0A
        case .electricity: Color(red: 0.19, green: 0.82, blue: 0.35) // #30D158
        case .fluidsGravity: Color(red: 0.75, green: 0.35, blue: 0.95) // #BF5AF2
        }
    }

    /// The modules in this domain, in their display order on the arc.
    var moduleIDs: [String] {
        switch self {
        case .mechanics: ["kinematics", "pendulums"]
        case .electricity: ["electrostatics", "magnetism", "circuits"]
        case .fluidsGravity: ["windtunnel", "gravitylab"]
        }
    }

    static func domain(for moduleID: String) -> HubDomain {
        allCases.first { $0.moduleIDs.contains(moduleID) } ?? .mechanics
    }

    /// The hub's left-to-right order: every module, grouped by domain.
    static var arcOrder: [String] { allCases.flatMap(\.moduleIDs) }

    /// One line per module: what you DO in it, as a promise rather than
    /// a syllabus entry. The descriptor blurbs are two sentences of
    /// what-and-why, right for the reading panel; this is the single
    /// line the panel leads with.
    static func promise(for moduleID: String) -> String {
        switch moduleID {
        case "kinematics": "Fire projectiles and bend their arcs with gravity and drag"
        case "pendulums": "Throw a pendulum into a true 3-D orbit above your floor"
        case "electrostatics": "Place charges and walk through the field they make"
        case "magnetism": "Carry bar magnets until they snap head-to-tail into line"
        case "circuits": "Wire real parts and watch the electrons do the work"
        case "windtunnel": "Raise a wind indoors and watch the flow find its way around"
        case "gravitylab": "Grow a solar system and hear its orbits as a chord"
        default: ""
        }
    }
}
