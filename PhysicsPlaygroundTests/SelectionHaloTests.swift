//
//  SelectionHaloTests.swift
//  PhysicsPlaygroundTests
//
//  Selection halos, end to end through the renderers that own them:
//  select a part and the veil appears; select another and it moves.
//  Not a screenshot, because neither module can be made to select
//  anything from the command line — `-circRing` and `-magRing` open a
//  ring, which is not a selection.
//

import XCTest
import PhysicsCore
import RealityKit
import RenderKit
import UIKit
import simd
@testable import PhysicsPlayground

@MainActor
final class SelectionHaloTests: XCTestCase {

    /// Long enough for a 0.15 s ramp at ~90 Hz, with room to spare.
    private func settle(_ body: () -> Void) {
        for _ in 0..<40 {
            body()
            Thread.sleep(forTimeInterval: 1.0 / 90.0)
        }
    }

    override func setUp() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled,
                      "Reduce Motion snaps; these exercise the ramp")
    }

    /// Every halo under `root`, by the shape `SelectionHalo` makes: a
    /// model entity with no collider and no input target.
    private func halos(under entity: Entity) -> [ModelEntity] {
        var found: [ModelEntity] = []
        if let model = entity as? ModelEntity, model.model != nil,
           model.name == SelectionHalo.entityName {
            // The factory's other guarantees, asserted where every halo passes
            // through: decoration, never a target.
            XCTAssertNil(model.components[CollisionComponent.self],
                         "a selection halo grew a collider — it is decoration")
            XCTAssertNil(model.components[InputTargetComponent.self],
                         "a selection halo grew an input target")
            found.append(model)
        }
        for child in entity.children { found += halos(under: child) }
        return found
    }

    /// Where the one lit halo is, in world space — nil if none is lit.
    /// Position rather than identity, because the halos live inside
    /// per-object visuals the renderers keep privately.
    private func litHaloPosition(under root: Entity) -> SIMD3<Float>? {
        let lit = halos(under: root).filter(\.isEnabled)
        guard lit.count == 1 else { return nil }
        return lit[0].position(relativeTo: nil)
    }

    // MARK: Magnetism

    func testMagnetismShowsAHaloOnTheSelectedMagnet() {
        let model = MagnetismModel()
        model.reset()
        guard let magnet = model.magnets.first else { return XCTFail("no magnet") }
        model.select(id: magnet.id)

        let renderer = MagnetismRenderer()
        settle { renderer.tick(model) }

        let shown = halos(under: renderer.root).filter(\.isEnabled)
        XCTAssertFalse(shown.isEmpty, """
            no halo is enabled after selecting a magnet and settling.

            SelectionHalo builds every halo disabled and Fade.tick is the only \
            thing that enables one, so this failing means selection is invisible \
            in this module — which is what shipped until 2026-08-09.
            """)
    }

    /// The veil moves: neither module has a public deselect, so selecting a
    /// second object asserts both that the new one lights and the old one
    /// goes out.
    func testTheMagnetismHaloMovesToTheNewlySelectedMagnet() {
        let model = MagnetismModel()
        model.reset()
        guard let first = model.magnets.first else { return XCTFail("no magnet") }
        guard let second = model.addMagnet(at: SIMD3(0.42, 1.35, -0.70)) else {
            return XCTFail("could not add a second magnet")
        }
        model.select(id: first.id)

        let renderer = MagnetismRenderer()
        settle { renderer.tick(model) }
        guard let onFirst = litHaloPosition(under: renderer.root) else {
            return XCTFail("no halo lit on the first magnet, so moving proves nothing")
        }

        // `addMagnet(at:)` already hands back the id.
        model.select(id: second)
        settle { renderer.tick(model) }
        guard let onSecond = litHaloPosition(under: renderer.root) else {
            return XCTFail("the halo went out and did not come back on the second magnet")
        }

        XCTAssertGreaterThan(simd_distance(onFirst, onSecond), 0.05, """
            the lit halo did not move when the selection did — it is still \
            sitting on the magnet that is no longer selected.
            """)
    }

    // MARK: Circuits

    func testCircuitsShowsAHaloOnTheSelectedPart() {
        let model = CircuitsModel()
        guard let part = model.components.first else {
            return XCTFail("the starter loop built no components")
        }
        model.select(id: part.id)

        let renderer = CircuitsRenderer()
        settle { renderer.tick(dt: 1.0 / 90.0, model: model) }

        let shown = halos(under: renderer.root).filter(\.isEnabled)
        XCTAssertFalse(shown.isEmpty,
                       "no halo is enabled after selecting a part and settling")
    }

    func testTheCircuitsHaloMovesToTheNewlySelectedPart() {
        let model = CircuitsModel()
        guard model.components.count > 1 else {
            return XCTFail("the starter loop built fewer than two parts")
        }
        let first = model.components[0], second = model.components[1]
        model.select(id: first.id)

        let renderer = CircuitsRenderer()
        settle { renderer.tick(dt: 1.0 / 90.0, model: model) }
        guard let onFirst = litHaloPosition(under: renderer.root) else {
            return XCTFail("no halo lit on the first part, so moving proves nothing")
        }

        model.select(id: second.id)
        settle { renderer.tick(dt: 1.0 / 90.0, model: model) }
        guard let onSecond = litHaloPosition(under: renderer.root) else {
            return XCTFail("the halo went out and did not come back on the second part")
        }

        XCTAssertGreaterThan(simd_distance(onFirst, onSecond), 0.05, """
            the lit halo did not move when the selection did — it is still \
            sitting on the part that is no longer selected.
            """)
    }

    /// Exactly one thing wears the veil at a time.
    func testOnlyTheSelectedPartWearsAHalo() {
        let model = CircuitsModel()
        guard model.components.count > 1, let part = model.components.first else {
            return XCTFail("need at least two parts to tell one halo from many")
        }
        model.select(id: part.id)

        let renderer = CircuitsRenderer()
        settle { renderer.tick(dt: 1.0 / 90.0, model: model) }

        let shown = halos(under: renderer.root).filter(\.isEnabled)
        XCTAssertEqual(shown.count, 1, """
            \(shown.count) halos are lit with one part selected, on a bench of \
            \(model.components.count).

            A veil on everything says as little as a veil on nothing.
            """)
    }
}
