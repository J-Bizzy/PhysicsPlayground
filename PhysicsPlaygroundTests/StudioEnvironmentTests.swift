//
//  StudioEnvironmentTests.swift
//  PhysicsPlaygroundTests
//
//  Studio Mode's stage is the sky, the floor and the floor's light pool,
//  and nothing else: the two glowing stage rings were cut on 2026-10-14,
//  because in this app a glow means "live" and a ring on the floor is
//  live for nothing.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
final class StudioEnvironmentTests: XCTestCase {

    func testTheStageIsSkyFloorAndPoolOnly() {
        let stage = StudioEnvironmentView.makeEnvironment()
        XCTAssertEqual(stage.children.count, 3, """
            Studio's stage holds \(stage.children.count) things; it should be \
            the sky dome, the floor and the light pool. Anything else is \
            decoration in the one environment with nothing else to look at.
            """)
    }
}
