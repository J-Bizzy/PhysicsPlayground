//
//  MagnetismInductionTests.swift
//  PhysicsPlaygroundTests
//
//  Faraday in the app model: waving a magnet toward the coil must
//  drive an EMF, a parked magnet must not, and the signal must decay
//  once motion stops. The flux math itself is held to the closed form
//  in PhysicsCore's InductionTests; this guards the plumbing — the
//  model wiring that turns magnet motion into the number the filament
//  glows by.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class MagnetismInductionTests: XCTestCase {

    func testWavingAMagnetThroughTheCoilDrivesAnEMF() {
        let model = MagnetismModel()
        model.electromagnetOn = true
        model.dynamicsOn = false
        guard let magnet = model.magnets.first else {
            return XCTFail("cold open should stage magnets")
        }

        let axis = model.electromagnetAxis
        let start = model.electromagnetPosition + axis * 0.15
        model.move(id: magnet.id, to: start)
        model.step(dt: 1.0 / 60)

        // A centimetre-scale approach in one frame: a brisk hand wave.
        model.move(id: magnet.id, to: start - axis * 0.03)
        model.step(dt: 1.0 / 60)

        XCTAssertGreaterThan(abs(model.inducedEMF), 1e-4,
                             "changing flux through the coil must induce an EMF")

        // Motion stops; the smoothed EMF must decay toward zero.
        for _ in 0..<180 { model.step(dt: 1.0 / 60) }
        XCTAssertLessThan(abs(model.inducedEMF), 5e-4,
                          "a parked magnet is a constant flux — no EMF")
    }

    func testStillMagnetsInduceNothing() {
        let model = MagnetismModel()
        model.electromagnetOn = true
        model.dynamicsOn = false
        for _ in 0..<30 { model.step(dt: 1.0 / 60) }
        XCTAssertLessThan(abs(model.inducedEMF), 1e-6)
    }

    func testCoilOffReportsZero() {
        let model = MagnetismModel()
        model.electromagnetOn = false
        model.dynamicsOn = false
        guard let magnet = model.magnets.first else { return XCTFail() }
        model.move(id: magnet.id, to: model.electromagnetPosition + SIMD3(0.1, 0, 0))
        model.step(dt: 1.0 / 60)
        XCTAssertEqual(model.inducedEMF, 0)
    }
}
