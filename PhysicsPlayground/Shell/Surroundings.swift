//
//  Surroundings.swift
//  Physics Playground — Shell
//
//  What stands around the wearer: their own room — the default, because
//  the labs are physics in the place you live — or deep space: the real
//  night sky round a slim glass platform, the same physics on it. The
//  wearer chooses in More, on the home or in any lab, and the choice is
//  remembered (`AppSettings.surroundings`). A lab may prefer its own
//  (`ModuleDescriptor.preferredSurroundings` — Orbital Mechanics opens in
//  space), which holds for that visit until the wearer chooses again.
//

nonisolated enum Surroundings: String, CaseIterable, Sendable {
    case room
    case deepSpace

    /// What surrounds the wearer: the lab's own for this visit when it has
    /// one, else the wearer's remembered choice.
    static func resolve(choice: Surroundings, labPrefers: Surroundings?) -> Surroundings {
        labPrefers ?? choice
    }

    /// The launch argument's spelling: `-surroundings space|room`.
    init?(argument: String) {
        switch argument {
        case "space", "deepSpace": self = .deepSpace
        case "room": self = .room
        default: return nil
        }
    }
}
