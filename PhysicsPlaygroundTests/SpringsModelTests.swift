//
//  SpringsModelTests.swift
//  PhysicsPlaygroundTests
//
//  The spring lab's app state: hanging the spring adds mg, sags the
//  equilibrium to mg/k, keeps the period — and the coupled mode stays
//  a horizontal exhibit.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class SpringsModelTests: XCTestCase {

    /// Hanging: bias is +mg (down-positive), and with damping the block
    /// settles exactly mg/k below the natural length.
    func testVerticalModeSagsToMgOverK() {
        let model = SpringsModel()
        model.setOrientation(.vertical)
        XCTAssertEqual(model.biasForce, 9.81 * model.mass, accuracy: 1e-12)

        model.damping = 2.0
        for _ in 0..<4000 {
            model.step(dt: 1.0 / 90.0)
        }
        XCTAssertEqual(model.state.displacement, model.equilibriumSag,
                       accuracy: 2e-3,
                       "the hanging block settles at mg/k")
        // And the world position hangs below the overhead anchor.
        XCTAssertLessThan(model.blockWorld.y, model.anchorWorld.y)
    }

    /// The period is untouched by hanging — gravity shifts the center,
    /// not the physics.
    func testVerticalPeriodMatchesHorizontal() {
        let model = SpringsModel()
        let horizontal = model.period
        model.setOrientation(.vertical)
        XCTAssertEqual(model.period, horizontal, accuracy: 1e-12)
    }

    /// Coupled mode is horizontal-only; picking it stands the rig back up.
    func testCoupledModeForcesHorizontal() {
        let model = SpringsModel()
        model.setOrientation(.vertical)
        model.setMode(.coupled)
        XCTAssertEqual(model.orientation, .horizontal)
        XCTAssertEqual(model.mode, .coupled)
        // And vertical while coupled resets to single.
        model.setOrientation(.vertical)
        XCTAssertEqual(model.mode, .single)
    }
}
