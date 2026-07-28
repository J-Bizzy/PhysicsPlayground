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

    /// Friction off = ideal oscillator: the amplitude survives ten
    /// seconds essentially untouched (RK4 at 90 Hz barely leaks).
    func testFrictionToggleMakesTheOscillatorIdeal() {
        let model = SpringsModel()
        model.frictionOn = false
        model.damping = 2.0   // would kill the motion fast if it applied
        model.beginGrab(block: 0)
        model.moveGrabbed(toWorld: SpringsModel.center + SIMD3(0.2, 0, 0))
        model.release(handVelocityX: 0)
        var earlyPeak = 0.0
        var latePeak = 0.0
        for step in 0..<900 {
            model.step(dt: 1.0 / 90.0)
            let x = abs(model.state.displacement)
            if step < 180 { earlyPeak = max(earlyPeak, x) }
            if step >= 720 { latePeak = max(latePeak, x) }
        }
        XCTAssertGreaterThan(latePeak, earlyPeak * 0.98,
                             "no friction, no decay — the swing keeps its amplitude")
        model.frictionOn = true
        XCTAssertEqual(model.effectiveDamping, 2.0, "friction back on restores damping")
    }


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
