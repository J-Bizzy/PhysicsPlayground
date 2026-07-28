//
//  InductionTests.swift
//  PhysicsCoreTests
//
//  The numeric flux must recover the closed form it will never be
//  told, and the finite-difference EMF must recover the analytic
//  derivative — Faraday's law rediscovered from the sampled field,
//  not asserted into it.
//

import XCTest
import simd
@testable import PhysicsCore

final class InductionTests: XCTestCase {

    private func axialMagnet(moment: Double, z: Double) -> BarMagnet {
        BarMagnet(position: SIMD3(0, 0, z), moment: SIMD3(0, 0, moment))
    }

    func testNumericFluxRecoversTheClosedFormOnAxis() {
        let R = 0.05
        for z in [0.06, 0.1, 0.2, 0.4] {
            let numeric = Induction.flux(
                throughDiscAt: .zero, normal: SIMD3(0, 0, 1), radius: R,
                magnets: [axialMagnet(moment: 5.6, z: z)])
            let closed = Induction.axialDipoleFlux(moment: 5.6, distance: z, discRadius: R)
            XCTAssertEqual(numeric / closed, 1.0, accuracy: 0.015,
                           "flux at z=\(z) must match μ₀mR²/2(R²+z²)^³ᐟ²")
        }
    }

    func testEMFRecoversTheAnalyticDerivative() {
        // Magnet approaching along the axis at v: ε = −N dΦ/dz · ż.
        let R = 0.05, m = 5.6, z = 0.12, v = 0.8, turns = 400
        let dt = 1e-4
        let fluxBefore = Induction.flux(
            throughDiscAt: .zero, normal: SIMD3(0, 0, 1), radius: R,
            magnets: [axialMagnet(moment: m, z: z)])
        let fluxNow = Induction.flux(
            throughDiscAt: .zero, normal: SIMD3(0, 0, 1), radius: R,
            magnets: [axialMagnet(moment: m, z: z - v * dt)])
        let measured = Induction.emf(turns: turns, fluxNow: fluxNow,
                                     fluxBefore: fluxBefore, dt: dt)

        // Analytic: dΦ/dz = −3 μ₀/2 · m R² z / (R²+z²)^{5/2}; ż = −v.
        let mu0half = 2 * Double.pi * 1e-7
        let dPhidZ = -3 * mu0half * m * R * R * z / pow(R * R + z * z, 2.5)
        let analytic = -Double(turns) * dPhidZ * (-v)
        XCTAssertEqual(measured / analytic, 1.0, accuracy: 0.01)
        // Approaching north-first must drive a nonzero EMF.
        XCTAssertGreaterThan(abs(measured), 1e-4)
    }

    func testFluxFlipsWithTheMagnet() {
        let R = 0.05
        let north = Induction.flux(
            throughDiscAt: .zero, normal: SIMD3(0, 0, 1), radius: R,
            magnets: [axialMagnet(moment: 5.6, z: 0.1)])
        let south = Induction.flux(
            throughDiscAt: .zero, normal: SIMD3(0, 0, 1), radius: R,
            magnets: [axialMagnet(moment: -5.6, z: 0.1)])
        XCTAssertEqual(north, -south, accuracy: abs(north) * 1e-9)
        XCTAssertGreaterThan(north, 0)
    }

    func testDistantMagnetContributesNothingMeasurable() {
        let nearby = Induction.flux(
            throughDiscAt: .zero, normal: SIMD3(0, 0, 1), radius: 0.05,
            magnets: [axialMagnet(moment: 5.6, z: 0.1)])
        let distant = Induction.flux(
            throughDiscAt: .zero, normal: SIMD3(0, 0, 1), radius: 0.05,
            magnets: [axialMagnet(moment: 5.6, z: 5)])
        XCTAssertLessThan(abs(distant), abs(nearby) * 1e-4)
    }
}
