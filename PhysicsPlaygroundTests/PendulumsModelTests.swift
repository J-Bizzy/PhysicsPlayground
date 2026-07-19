//
//  PendulumsModelTests.swift
//  PhysicsPlaygroundTests
//
//  The friction kill-switch: off bypasses every pendulum's damping,
//  making an ideal pendulum whose amplitude survives indefinitely.
//

import PhysicsCore
import XCTest
import simd
@testable import PhysicsPlayground

@MainActor
final class PendulumsModelTests: XCTestCase {

    /// With friction off (and damping deliberately cranked), ten
    /// simulated seconds of swinging lose essentially no amplitude —
    /// the energy-exact integrator plus a severed loss term.
    func testFrictionToggleMakesThePendulumIdeal() {
        let model = PendulumsModel()
        model.frictionOn = false
        guard let first = model.pendulums.first else {
            return XCTFail("no pendulum in the opening scene")
        }
        model.setDamping(id: first.id, 1.0)   // would kill the swing fast

        // Pull the bob out and release it from rest.
        model.beginGrab(id: first.id)
        let start = first.pivot + SIMD3(0.35, -first.length * 0.8, 0)
        model.moveGrabbed(id: first.id, toWorld: start)
        model.release(id: first.id, handVelocity: .zero)

        var earlyPeak = 0.0
        var latePeak = 0.0
        for step in 0..<900 {
            model.step(dt: 1.0 / 90.0)
            let x = abs(model.pendulums[0].state.position.x)
            if step < 180 { earlyPeak = max(earlyPeak, x) }
            if step >= 720 { latePeak = max(latePeak, x) }
        }
        XCTAssertGreaterThan(latePeak, earlyPeak * 0.97,
                             "no friction, no decay")

        // Friction back on: the same setup audibly dies down.
        model.frictionOn = true
        var dampedPeak = 0.0
        for step in 0..<900 {
            model.step(dt: 1.0 / 90.0)
            if step >= 720 {
                dampedPeak = max(dampedPeak, abs(model.pendulums[0].state.position.x))
            }
        }
        XCTAssertLessThan(dampedPeak, latePeak * 0.7,
                          "heavy damping now applies and eats the swing")
    }
}
