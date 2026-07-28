//
//  DialConsole.swift
//  Physics Playground — Design System
//
//  A rack of diegetic dials any module can bolt on.
//
//  RenderKit's SpatialDial — a gauge you reach out and TWIST, with the
//  value engraved on its own face — was built for the Optics Studio and
//  then used nowhere else, because every module that wanted one would
//  have had to re-implement the same drag plumbing: find the dial under
//  the pinch, seed a DialDrag from the model's current value, feed hand
//  angles through it, push the result back, and re-point the needle
//  every frame. That is four fiddly places to get wrong per module, and
//  it is why nine modules kept reaching for a slider on a glass card.
//
//  This is that plumbing, once. A module declares its dials — a name, a
//  place, a range, a getter and a setter — and gets:
//
//    · the entities, built and oriented toward the user,
//    · begin/advance/end handling for the twist,
//    · needle and engraved value synced every frame.
//
//  The model still owns every value, exactly as before. A dial is a way
//  to touch a number, not a place to keep one.
//

import Foundation
import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class DialConsole {
    /// One physical gauge, bound to a value in a model.
    struct Binding {
        let name: String
        let title: String
        let center: SIMD3<Float>
        let range: ClosedRange<Double>
        let accent: UIColor
        /// How much of a turn sweeps the whole range.
        var turnsForFullSweep: Double = 0.75
        var radius: Float = 0.055
        /// The face direction. Defaults to facing back toward the user.
        var normal: SIMD3<Float>?
        let read: () -> Double
        let write: (Double) -> Void
        /// How the value is engraved on the dial's face.
        let format: (Double) -> String
    }

    let root = Entity()
    private var dials: [String: SpatialDial] = [:]
    private var bindings: [String: Binding] = [:]
    private var drag: DialDrag?

    /// Builds the rack. `facing` is the point the dials turn toward —
    /// normally where the user stands, so every gauge presents its face.
    init(_ bindings: [Binding], facing: SIMD3<Float> = SIMD3(0, 1.5, 0)) {
        for binding in bindings {
            let normal = binding.normal ?? {
                let toViewer = facing - binding.center
                let length = simd_length(toViewer)
                return length > 1e-5 ? toViewer / length : SIMD3(0, 0, 1)
            }()
            let dial = SpatialDial(
                name: binding.name, center: binding.center, normal: normal,
                radius: binding.radius, accent: binding.accent)
            root.addChild(dial.root)
            dials[binding.name] = dial
            self.bindings[binding.name] = binding
        }
    }

    var isTwisting: Bool { drag != nil }

    /// Whether this console owns the pinched entity — and if so, starts a
    /// twist. Call from the module's drag-begin before its own routing,
    /// so a dial always wins over whatever is behind it.
    func beginTwist(on entity: Entity, hand: SIMD3<Double>) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if let dial = dials[candidate.name], let binding = bindings[candidate.name] {
                drag = DialDrag(
                    name: binding.name, startValue: binding.read(),
                    startAngle: dial.handAngle(hand), range: binding.range,
                    turnsForFullSweep: binding.turnsForFullSweep)
                return true
            }
            current = candidate.parent
        }
        return false
    }

    /// Feeds a hand position into the live twist. Returns false when no
    /// dial is engaged, so the caller can fall through to its own drag.
    @discardableResult
    func advanceTwist(hand: SIMD3<Double>) -> Bool {
        guard var live = drag,
              let dial = dials[live.name],
              let binding = bindings[live.name] else { return false }
        let value = live.advance(toAngle: dial.handAngle(hand))
        drag = live
        binding.write(value)
        return true
    }

    func endTwist() { drag = nil }

    /// Re-points every needle and re-engraves every face. Cheap: the
    /// dial itself skips the text rebuild when the label is unchanged.
    func sync() {
        for (name, dial) in dials {
            guard let binding = bindings[name] else { continue }
            let value = binding.read()
            let span = binding.range.upperBound - binding.range.lowerBound
            let fraction = span > 1e-12
                ? (value - binding.range.lowerBound) / span : 0
            dial.setValueFraction(fraction)
            dial.setLabel(binding.format(value))
        }
    }

    func setVisible(_ visible: Bool) { root.isEnabled = visible }

    /// Moves one dial. This is what lets a dial live ON the apparatus:
    /// the strength gauge rides beneath the magnet you selected, and
    /// follows it when you carry the magnet somewhere else.
    func place(_ name: String, at position: SIMD3<Float>) {
        dials[name]?.root.position = position
    }
}
