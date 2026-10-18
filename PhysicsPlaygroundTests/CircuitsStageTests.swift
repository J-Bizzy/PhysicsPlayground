//
//  CircuitsStageTests.swift
//  PhysicsPlaygroundTests
//
//  The turntable under the floating circuit (2026-10-18, the owner's
//  choice of a designed container): a slim disc that keeps a set clearance
//  under the circuit's lowest point, sits inside the zoom with the bench,
//  fades out as a two-hand zoom dives in, and stands clear of the parts
//  shelf and the meter.
//

import XCTest
import PhysicsCore
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class CircuitsStageTests: XCTestCase {

    private func lowestPoint(_ model: CircuitsModel) -> Double {
        model.components.flatMap {
            [$0.position.y, $0.terminalPosition(0).y, $0.terminalPosition(1).y]
        }.min() ?? 0
    }

    func testTheStageSitsItsClearanceUnderTheCircuit() {
        let model = CircuitsModel()
        model.reset()
        XCTAssertEqual(model.stage.top, lowestPoint(model) - CircuitsModel.stageClearance,
                       accuracy: 1e-9)
        for preset in CircuitsModel.Preset.allCases {
            model.loadPreset(preset)
            XCTAssertEqual(model.stage.top,
                           max(CircuitsModel.stageFloor,
                               lowestPoint(model) - CircuitsModel.stageClearance),
                           accuracy: 1e-9, "\(preset)")
        }
    }

    func testTheStageFollowsAPartReleasedLowerButNeverBelowItsFloor() throws {
        let model = CircuitsModel()
        model.reset()
        let part = try XCTUnwrap(model.components.first?.id)
        model.drag(id: part, toward: SIMD3(0.5, 0.4, -0.9))
        model.release(id: part)
        XCTAssertEqual(model.stage.top, CircuitsModel.stageFloor, accuracy: 1e-9)
    }

    /// The renderer stands it where the model says, inside the zoom.
    func testTheRendererStandsTheStageWhereTheModelSays() throws {
        let model = CircuitsModel()
        model.reset()
        let renderer = CircuitsRenderer()
        renderer.tick(dt: 1.0 / 90.0, model: model)
        let stage = try XCTUnwrap(renderer.root.findEntity(named: "circuit-stage"))
        let world = stage.position(relativeTo: renderer.root)
        XCTAssertEqual(world.y, Float(model.stage.top), accuracy: 1e-4)
        XCTAssertEqual(world.x, Float(model.stage.center.x), accuracy: 1e-4)
        XCTAssertEqual(world.z, Float(model.stage.center.y), accuracy: 1e-4)
        XCTAssertNotNil(renderer.root.findEntity(named: "circuit-stage-deck"), "no deck asset")
        XCTAssertNotNil(renderer.root.findEntity(named: "circuit-stage-rim"), "no rim asset")
    }

    func testTheStageFadesAsTheZoomDivesIn() {
        XCTAssertEqual(CircuitsRenderer.stageOpacity(atZoom: 1), 1)
        XCTAssertEqual(CircuitsRenderer.stageOpacity(atZoom: 1.25), 1, accuracy: 1e-6)
        XCTAssertEqual(CircuitsRenderer.stageOpacity(atZoom: 2), 0)
        XCTAssertEqual(CircuitsRenderer.stageOpacity(atZoom: 8), 0)
        XCTAssertGreaterThan(CircuitsRenderer.stageOpacity(atZoom: 1.6), 0)
    }

    /// Clear of the parts shelf, under its lowest slot, and in reach.
    func testTheStageClearsTheShelfAndIsWithinReach() {
        let model = CircuitsModel()
        model.reset()
        let radius = CircuitsModel.stageRadius
        let center = model.stage.center
        XCTAssertLessThan(center.x + radius, Double(CircuitsPartsLayout.rightColumnX) - 0.06,
                          "the stage runs into the parts shelf")
        let viewer = SIMD3<Double>(CircuitsPartsLayout.viewer)
        let nearRim = SIMD3(center.x, model.stage.top, center.y + radius)
        XCTAssertLessThan(simd_distance(nearRim, viewer), Double(CircuitsPartsLayout.maximumReach))
        XCTAssertGreaterThanOrEqual(lowestPoint(model) - model.stage.top, 0.25)
    }
}
