//
//  DeepSpaceEnvironmentTests.swift
//  PhysicsPlaygroundTests
//
//  Deep space is four things and nothing else: the real sky, the distant
//  Sun, the platform and the floor's reach. The platform's top is the
//  floor, the floor's pane reaches as far as a ball can land, the sky
//  stands beyond everything, the Sun is where Pluto sees it and goes away
//  for a lab with its own, and nothing in it glows.
//

import XCTest
import PhysicsCore
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class DeepSpaceEnvironmentTests: XCTestCase {

    private func environment() async -> Entity {
        let resources = await SkyResources.prepare()
        return DeepSpace.make(resources: resources)
    }

    func testItIsTheSkyTheSunThePlatformAndTheReachOnly() async {
        let space = await environment()
        XCTAssertEqual(space.children.map(\.name),
                       ["sky", DeepSpace.sunName, DeepSpace.reachName, DeepSpace.platformName],
                       "anything else is decoration in the one place with nothing else to look at")
    }

    /// The wearer stands on it: its top is the real floor.
    func testThePlatformsTopIsTheFloor() async throws {
        let space = await environment()
        let platform = try XCTUnwrap(space.findEntity(named: DeepSpace.platformName))
        let bounds = platform.visualBounds(relativeTo: nil)
        XCTAssertEqual(bounds.max.y, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.extents.x, 2 * DeepSpace.platformRadius, accuracy: 0.02)
    }

    /// A ball lands on the physics floor out to where it is retired, so the
    /// pane that marks the floor reaches that far.
    func testTheFloorsReachIsWhereABallCanLand() async throws {
        let space = await environment()
        let reach = try XCTUnwrap(space.findEntity(named: DeepSpace.reachName))
        let bounds = reach.visualBounds(relativeTo: nil)
        XCTAssertGreaterThanOrEqual(bounds.extents.x / 2 + 0.001, Float(KinematicsModel.escapeRadius))
        XCTAssertLessThan(bounds.max.y, 0, "the pane stands above the platform")
    }

    /// The sky stands beyond every lab and the floor's whole reach.
    func testTheSkyIsBeyondEverything() async throws {
        let space = await environment()
        let sky = try XCTUnwrap(space.findEntity(named: "sky"))
        let stars = try XCTUnwrap(sky.findEntity(named: "sky-stars"))
        let bounds = stars.visualBounds(relativeTo: nil)
        XCTAssertGreaterThan(bounds.extents.x / 2, 40)
        XCTAssertGreaterThan(bounds.extents.y / 2, 40)
    }

    /// The Sun stands where it is seen from Pluto on the sky's date, inside
    /// the stars' sphere so it is drawn on the sky.
    func testTheSunIsWherePlutoSeesIt() async throws {
        let space = await environment()
        let light = try XCTUnwrap(space.findEntity(named: "deep-space-sun-light"))
        let seen = MeanElements.pluto.sunSeen(julianDate: Sky.epoch)
        XCTAssertLessThan(seen.magnitude, -18.5, "a magnitude −19 star")
        let expected = Sky.orientation.act(SIMD3<Float>(simd_normalize(seen.direction)))
        let direction = simd_normalize(light.position(relativeTo: nil) - Sky.centre)
        XCTAssertGreaterThan(simd_dot(direction, expected), 0.99999)
        XCTAssertLessThan(simd_distance(light.position(relativeTo: nil), Sky.centre),
                          SkyResources.starRadius)
    }

    /// Orbital Mechanics draws its own Sun; deep space puts its distant one
    /// away there, and only there.
    func testTheDistantSunGoesAwayForALabWithItsOwn() {
        let suns = ModuleCatalog.all(appModel: AppModel()).filter(\.drawsItsOwnSun).map(\.id)
        XCTAssertEqual(suns, [OrbitalMechanicsModule.id])

        let stage = DeepSpaceStage()
        stage.build(showsSun: false)
        XCTAssertEqual(stage.root.findEntity(named: DeepSpace.sunName)?.isEnabled, false)
        let shown = DeepSpaceStage()
        shown.build(showsSun: true)
        XCTAssertEqual(shown.root.findEntity(named: DeepSpace.sunName)?.isEnabled, true)
    }

    /// In this app a glow means "live": nothing in deep space is emissive.
    func testNothingInItGlows() async {
        let space = await environment()
        var lit: [String] = []
        func walk(_ entity: Entity) {
            if LiveGlow.isLive(entity) { lit.append(entity.name) }
            for case let material as PhysicallyBasedMaterial in entity.components[ModelComponent.self]?.materials ?? [] {
                var white: CGFloat = 0
                material.emissiveColor.color.getWhite(&white, alpha: nil)
                if white > 0.001 { lit.append(entity.name) }
            }
            entity.children.forEach(walk)
        }
        walk(space)
        XCTAssertEqual(lit, [])
    }
}
