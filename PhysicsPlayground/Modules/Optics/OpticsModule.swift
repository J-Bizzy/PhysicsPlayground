//
//  OpticsModule.swift
//  Physics Playground — Light & Optics
//
//  Catalog entry, More and live readings. A laser and a torch of white
//  light, and mirrors, prisms, a lens and a glass bar placed anywhere in
//  the room; the light lands on the room's own walls.
//

import SwiftUI
import PhysicsCore
import simd

@MainActor
enum OpticsModule {
    static let id = "optics"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        let model = appModel.opticsModel
        return ModuleDescriptor(
            id: id,
            title: "Light & Optics",
            shortTitle: "Light",
            icon: "rays",
            accent: DesignTokens.Palette.opticsAccent,
            // The house value: a beam carries its own contrast (a bright core in
            // a dark casing), as the field lines do.
            preferredDimming: 0.35,
            isPaused: { model.isPaused },
            togglePause: { model.togglePause() },
            makeScene: {
                AnyView(OpticsSpaceView().environment(model))
            },
            readings: { readings(model) },
            more: more(model),
            timeScrub: .init(model: model),
            reset: { model.reset() }
        )
    }

    /// What More holds: how much of the light is drawn, the glass, and Clear.
    /// Everything a piece offers is on its own ring.
    static func more(_ model: OpticsModel) -> [MoreItem] {
        [
            .toggle(id: "weakReflections", title: "Weak reflections", symbol: "light.max",
                    isOn: { model.showsWeakReflections }, set: { model.showsWeakReflections = $0 }),
            .toggle(id: "angles", title: "Angles", symbol: "angle",
                    isOn: { model.showsAngles }, set: { model.showsAngles = $0 }),
            .choice(id: "glass", title: "Glass",
                    options: [("crown", "Crown"), ("flint", "Flint")],
                    selected: { model.glass == .nbk7 ? "crown" : "flint" },
                    select: { model.glass = $0 == "crown" ? .nbk7 : .sf11 }),
            .action(id: "clear", title: "Clear all", symbol: "trash",
                    confirms: true, destructive: true,
                    isEnabled: { !model.pieces.isEmpty },
                    run: { model.clearPieces() }),
        ]
    }

    /// The live numbers More shows: about the selected piece if there is
    /// one, about the light as a whole if not.
    static func readings(_ model: OpticsModel) -> [Reading] {
        let trace = model.traceIfNeeded()
        var rows: [Reading] = []
        let selected = model.selectedID
        if let id = selected, id == OpticsModel.laserID {
            rows.append(.init("Wavelength", PhysicsFormat.fixed(model.laserNanometers, decimals: 0), "nm"))
        }
        if let piece = model.selectedPiece {
            rows.append(contentsOf: pieceReadings(piece, model: model, trace: trace))
        } else {
            rows.append(.init("Pieces", "\(model.pieces.count)"))
        }
        let emitted = trace.total
        if emitted > 0 {
            rows.append(.init(landingName(model.room),
                              PhysicsFormat.fixed(100 * trace.landed / emitted, decimals: 0), "%"))
        }
        return rows
    }

    /// Where the light that lands lands. With no walls to meet (Deep space,
    /// or a room not yet scanned) the floor is all there is, and "the room"
    /// named one that was not there.
    static func landingName(_ room: LightTracer.Room) -> String {
        room.walls.isEmpty ? "Light reaching the floor" : "Light reaching the room"
    }

    /// The wavelength a reading speaks for: the laser's if it lit the piece,
    /// else the middle of the spectrum.
    private static func readingEvent(_ events: [LightTracer.Event], model: OpticsModel)
        -> LightTracer.Event? {
        events.first { $0.nanometers == model.laserNanometers }
            ?? events.min { abs($0.nanometers - 550) < abs($1.nanometers - 550) }
    }

    private static func pieceReadings(_ piece: OpticsModel.Piece, model: OpticsModel,
                                      trace: LightTracer.Result) -> [Reading] {
        let mine = trace.events.filter { $0.element == piece.id }
        let n = model.glass.index(nanometers: 550)
        var rows: [Reading] = []
        switch piece.kind {
        case .mirror:
            if let hit = readingEvent(mine.filter { $0.reflectance > 0 }, model: model) {
                // The law of reflection: the two angles are one number.
                rows.append(.init("Reflection",
                                  PhysicsFormat.angle(hit.incidence * 180 / .pi),
                                  formula: "θ_r = θ_i"))
            }
        case .prism:
            let apex = PhysicsFormat.angle(OpticsModel.prismApex * 180 / .pi, decimals: 0)
            let halfApex = PhysicsFormat.angle(OpticsModel.prismApex * 90 / .pi, decimals: 0)
            rows.append(.init("Index n at 550 nm", PhysicsFormat.fixed(n, decimals: 4),
                              formula: sellmeier))
            rows.append(.init("Least deviation",
                              PhysicsFormat.angle(LightTracer.minimumDeviation(
                                apexAngle: OpticsModel.prismApex, index: n) * 180 / .pi),
                              formula: "δ_{min} = 2 arcsin(n sin(A/2)) − A"
                                + " = 2 arcsin(\(PhysicsFormat.fixed(n, decimals: 4)) sin \(halfApex)) − \(apex)"))
            if let deviation = deviation(through: piece.id, events: mine, model: model) {
                rows.append(.init("Deviation", PhysicsFormat.angle(deviation * 180 / .pi)))
            }
        case .lens:
            let f = LightTracer.focalLength(frontRadius: OpticsModel.lensRadius,
                                            backRadius: OpticsModel.lensRadius,
                                            thickness: OpticsModel.lensThickness, index: n)
            rows.append(.init("Focal length at 550 nm", PhysicsFormat.fixed(f * 100, decimals: 1), "cm",
                              formula: "1/f = (n − 1)[2/R − (n − 1)d/nR²], R = "
                                + PhysicsFormat.fixed(OpticsModel.lensRadius * 100, decimals: 1) + " cm, d = "
                                + PhysicsFormat.fixed(OpticsModel.lensThickness * 100, decimals: 1) + " cm"))
        case .block:
            rows.append(.init("Index n at 550 nm", PhysicsFormat.fixed(n, decimals: 4),
                              formula: sellmeier))
            rows.append(.init("Critical angle", PhysicsFormat.angle(asin(1 / n) * 180 / .pi),
                              formula: "θ_c = arcsin(1/n) = arcsin(1 ÷ \(PhysicsFormat.fixed(n, decimals: 4)))"))
            let trapped = mine.filter { $0.kind == .totalInternalReflection }.count
            rows.append(.init("Total internal reflections", "\(trapped)"))
        }
        if piece.kind != .mirror,
           let entry = readingEvent(mine.filter { $0.kind == .enter }, model: model),
           let refracted = entry.refraction {
            // Snell's law, as the two angles it relates, at the index of
            // the wavelength the angles were measured in.
            let index = model.glass.index(nanometers: entry.nanometers)
            rows.append(.init("Refraction",
                              "\(PhysicsFormat.angle(entry.incidence * 180 / .pi)) → "
                                + PhysicsFormat.angle(refracted * 180 / .pi),
                              formula: "sin θ₁ = n sin θ₂, n = \(PhysicsFormat.fixed(index, decimals: 4))"
                                + " at \(PhysicsFormat.fixed(entry.nanometers, decimals: 0)) nm"))
        }
        return rows
    }

    /// Sellmeier's dispersion formula, the glass's index at any wavelength.
    static let sellmeier = "n² = 1 + Σ B_iλ²/(λ² − C_i)"

    /// The turn a prism gives the reading's wavelength: the angle between
    /// the light that entered it and the light that left by refraction.
    private static func deviation(through id: UUID, events: [LightTracer.Event],
                                  model: OpticsModel) -> Double? {
        guard let entry = readingEvent(events.filter { $0.kind == .enter }, model: model),
              let exit = events.first(where: {
                  $0.kind == .exit && $0.nanometers == entry.nanometers
              }) else { return nil }
        let n = model.glass.index(nanometers: exit.nanometers)
        guard let out = Refraction.refract(direction: exit.direction, normal: exit.normal,
                                           n1: n, n2: 1) else { return nil }
        return acos(min(1, max(-1, simd_dot(entry.direction, out))))
    }
}
