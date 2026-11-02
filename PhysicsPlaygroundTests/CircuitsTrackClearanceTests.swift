//
//  CircuitsTrackClearanceTests.swift
//  PhysicsPlaygroundTests
//
//  A part's value track must be pinchable along its whole length: no ray
//  from the wearer's eye to any point of the rail, or to the top of the
//  bead anywhere on it, may pass through the part's own targets first —
//  its carry box, its dots, a switch's blade. Hit-testing takes the nearest
//  collider, so where one does, a pinch aimed at the slider carries the
//  part instead. Until 2026-11-02 the rail hung a fixed 6.5 cm (at a
//  metre) under the part's centre, inside the carry box's reach as seen
//  from above, and under a standing part's lower dot; the owner found the
//  sliders "sometimes hard to grab".
//

import XCTest
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsTrackClearanceTests: XCTestCase {

    /// Where the eyes are when a hand reaches for a slider: at the bench,
    /// leaning in close (about 35° down, the steepest the clearance allows
    /// for), and off to one side.
    private func eyes(lookingAt part: SIMD3<Float>) -> [(String, SIMD3<Float>)] {
        [("standing", part + SIMD3(0, 0.33, 0.85)),
         ("leaning in", part + SIMD3(0.05, 0.30, 0.43)),
         ("off to the side", part + SIMD3(0.45, 0.30, 0.70))]
    }

    func testNoPartCoversItsOwnValueTrack() throws {
        var failures: [String] = []
        for kind in CircuitsModel.ComponentKind.allCases {
            let range = CircuitsModel.valueRange(for: kind)
            guard range.upperBound > range.lowerBound else { continue }
            for standing in [false, true] {
                let model = CircuitsModel()
                model.clearBench()
                let id = try XCTUnwrap(model.add(kind, at: CircuitsModel.buildCenter))
                if standing { model.setAxis(id: id, axis: [0, 1, 0]) }
                let renderer = CircuitsRenderer()
                // Long enough for the part to finish turning to its pose.
                for _ in 0..<120 { renderer.tick(dt: 1.0 / 90.0, model: model) }
                let part = try XCTUnwrap(model.components.first { $0.id == id })
                let anchor = SIMD3<Float>(part.position)

                for (pose, eye) in eyes(lookingAt: anchor) {
                    let bloom = openTrack(kind: kind, id: id, model: model,
                                          renderer: renderer, anchor: anchor, eye: eye)
                    defer { bloom.root.removeFromParent() }
                    let blockers = colliders(under: try holder(of: id, in: renderer))
                    for (what, point) in try trackPoints(of: bloom, in: renderer.viewRoot) {
                        for blocker in blockers where blocker.intersects(from: eye, to: point,
                                                                         frame: renderer.viewRoot) {
                            failures.append("\(standing ? "standing" : "lying") \(kind), \(pose), "
                                            + "\(blocker.role) over \(what)")
                        }
                    }
                }
            }
        }
        // One line per part, pose and target, with how much of the rail it covers.
        var tally: [String: Int] = [:]
        for failure in failures {
            let key = failure.components(separatedBy: " over ").first ?? failure
            tally[key, default: 0] += 1
        }
        XCTAssertTrue(failures.isEmpty, """
            \(failures.count) look(s) at a value track pass through the part's own \
            target first, so the part takes the pinch:
            \(tally.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value) of 33 points" }
                .joined(separator: "\n"))
            """)
    }

    /// The old placement, measured the same way, must fail: otherwise this
    /// test passes whatever the track does.
    func testTheOldFixedDropWouldHaveFailed() throws {
        let model = CircuitsModel()
        model.clearBench()
        let id = try XCTUnwrap(model.add(.bulb, at: CircuitsModel.buildCenter))
        model.setAxis(id: id, axis: [0, 1, 0])
        let renderer = CircuitsRenderer()
        for _ in 0..<120 { renderer.tick(dt: 1.0 / 90.0, model: model) }
        let part = try XCTUnwrap(model.components.first { $0.id == id })
        let anchor = SIMD3<Float>(part.position)
        let eye = anchor + SIMD3(0, 0.33, 0.85)
        let bloom = openTrack(kind: .bulb, id: id, model: model, renderer: renderer,
                              anchor: anchor, eye: eye, clearing: false)
        let blockers = colliders(under: try holder(of: id, in: renderer))
        let covered = try trackPoints(of: bloom, in: renderer.viewRoot).contains { _, point in
            blockers.contains { $0.intersects(from: eye, to: point, frame: renderer.viewRoot) }
        }
        XCTAssertTrue(covered, "the fixed drop under a standing bulb was never covered — "
                      + "the ray test cannot see what it was written for")
    }

    // MARK: The ring

    private func openTrack(kind: CircuitsModel.ComponentKind, id: UUID, model: CircuitsModel,
                           renderer: CircuitsRenderer, anchor: SIMD3<Float>,
                           eye: SIMD3<Float>, clearing: Bool = true) -> Bloom {
        let bloom = Bloom()
        renderer.viewRoot.addChild(bloom.root)
        let track = clearing
            ? CircuitsSpaceView.valueTrack(for: kind) { [weak renderer] toward in
                renderer?.targetReachBelow(of: id, towardViewer: toward) ?? 0
            }
            : CircuitsSpaceView.valueTrack(for: kind)
        bloom.configure(petals: [], grip: .init(
            name: "Value", range: CircuitsModel.valueRange(for: kind),
            read: { model.componentValue(id: id) },
            write: { model.setComponentValue(id: id, $0) },
            format: { "\($0)" }, radius: { 0.05 }, track: track))
        for _ in 0..<80 {
            bloom.update(anchor: anchor, viewer: eye, revealTarget: 1, dt: 1.0 / 90.0)
        }
        return bloom
    }

    /// Points a pinch aims at: along the rail's centre and its target's top
    /// edge, and the top of the bead's target wherever on the rail it sits.
    private func trackPoints(of bloom: Bloom, in frame: Entity) throws -> [(String, SIMD3<Float>)] {
        let track = try XCTUnwrap(bloom.root.children.first { $0.name == "bloom-track" })
        let shape = try XCTUnwrap(track.components[CollisionComponent.self]?.shapes.first)
        let box = shape.bounds
        let beadRise = Bloom.clearBeadTargetRadius
        var points: [(String, SIMD3<Float>)] = []
        for step in 0...10 {
            let x = box.min.x + (box.max.x - box.min.x) * Float(step) / 10
            let share = "\(step * 10) %"
            points.append(("the rail at \(share)",
                           track.convert(position: [x, 0, 0], to: frame)))
            points.append(("the rail's top at \(share)",
                           track.convert(position: [x, box.max.y, 0], to: frame)))
            points.append(("the bead's top at \(share)",
                           track.convert(position: [x, beadRise, 0], to: frame)))
        }
        return points
    }

    // MARK: The part's targets

    private func holder(of id: UUID, in renderer: CircuitsRenderer) throws -> Entity {
        try XCTUnwrap(renderer.viewRoot.findEntity(named: id.uuidString))
    }

    private struct Blocker {
        let entity: Entity
        let shape: ShapeResource
        /// The dots' targets are spheres; the carry box and blade are boxes.
        var isSphere: Bool { entity.name.hasPrefix("t0-") || entity.name.hasPrefix("t1-") }
        var role: String {
            isSphere ? "a dot" : entity.name.hasPrefix("k-") ? "the blade" : "the carry box"
        }

        /// Whether the segment from `a` to `b` (in `frame`) passes through
        /// this target before reaching `b`.
        @MainActor
        func intersects(from a: SIMD3<Float>, to b: SIMD3<Float>, frame: Entity) -> Bool {
            let p = entity.convert(position: a, from: frame)
            let q = entity.convert(position: b, from: frame)
            let box = shape.bounds
            let d = q - p
            if isSphere {
                let centre = box.center, radius = box.extents.x / 2
                let f = p - centre
                let qa = simd_dot(d, d), qb = 2 * simd_dot(f, d)
                let qc = simd_dot(f, f) - radius * radius
                let disc = qb * qb - 4 * qa * qc
                guard disc >= 0 else { return false }
                let t = (-qb - disc.squareRoot()) / (2 * qa)
                return t >= 0 && t < 1
            }
            var near: Float = 0, far: Float = 1
            for axis in 0..<3 {
                if abs(d[axis]) < 1e-9 {
                    if p[axis] < box.min[axis] || p[axis] > box.max[axis] { return false }
                    continue
                }
                var t0 = (box.min[axis] - p[axis]) / d[axis]
                var t1 = (box.max[axis] - p[axis]) / d[axis]
                if t0 > t1 { swap(&t0, &t1) }
                near = max(near, t0)
                far = min(far, t1)
                if near > far { return false }
            }
            return near < 1
        }
    }

    private func colliders(under root: Entity) -> [Blocker] {
        var found: [Blocker] = []
        func walk(_ entity: Entity) {
            guard entity.isEnabled else { return }
            for shape in entity.components[CollisionComponent.self]?.shapes ?? [] {
                found.append(Blocker(entity: entity, shape: shape))
            }
            entity.children.forEach(walk)
        }
        walk(root)
        return found
    }
}
