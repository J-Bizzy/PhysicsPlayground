//
//  PickupCoilTests.swift
//  PhysicsCoreTests
//
//  A magnet through a coil, against the closed forms: the loop flux of a
//  coaxial dipole, finite and right as the dipole crosses the loop's own
//  plane; Faraday's peak EMF for a thin coil, N·0.429 μ₀mv/R²; a full pass
//  integrating to nothing, entering and leaving with opposite signs; the
//  LED pair dark below its threshold, obeying Kirchhoff above it, red one
//  way and green the other; and the copper's resistance, ρL/A.
//

import XCTest
import simd
@testable import PhysicsCore

final class PickupCoilTests: XCTestCase {

    private let mu0 = 4 * Double.pi * 1e-7

    private func magnet(at z: Double, moment: Double = 6) -> BarMagnet {
        BarMagnet(position: SIMD3(0, 0, z), moment: SIMD3(0, 0, moment))
    }

    /// The loop integral recovers Φ = μ₀mR²/(2(R²+z²)^{3/2}) for a coaxial
    /// dipole, at the loop's centre as well as along the axis.
    func testLoopFluxMatchesTheCoaxialClosedForm() {
        let radius = 0.05
        for z in [0, radius / 2, -radius / 2, radius, 2 * radius, -3 * radius] {
            let flux = Induction.flux(throughLoopAt: .zero, normal: SIMD3(0, 0, 1),
                                      radius: radius, magnets: [magnet(at: z)])
            let expected = Induction.axialDipoleFlux(moment: 6, distance: z, discRadius: radius)
            XCTAssertEqual(flux / expected, 1, accuracy: 1e-9, "z = \(z)")
        }
        // At the centre it is the textbook μ₀m/(2R).
        let centre = Induction.flux(throughLoopAt: .zero, normal: SIMD3(0, 0, 1),
                                    radius: radius, magnets: [magnet(at: 0)])
        XCTAssertEqual(centre, mu0 * 6 / (2 * radius), accuracy: 1e-15)
    }

    /// Off the axis the loop integral and the disc sum must agree, wherever
    /// the disc sum is itself trustworthy (the dipole well clear of the disc).
    func testLoopFluxAgreesWithTheDiscOffAxis() {
        let radius = 0.05
        let tilted = BarMagnet(position: SIMD3(0.03, -0.02, 0.12),
                               moment: SIMD3(1.5, -2, 5))
        let loop = Induction.flux(throughLoopAt: .zero, normal: SIMD3(0, 0, 1),
                                  radius: radius, magnets: [tilted])
        let disc = Induction.flux(throughDiscAt: .zero, normal: SIMD3(0, 0, 1),
                                  radius: radius, magnets: [tilted], rings: 60, spokes: 120)
        XCTAssertEqual(loop / disc, 1, accuracy: 2e-3)
    }

    /// A magnet carried along the axis of a very short coil at speed v:
    /// the EMF peaks at N·(dΦ/dz)ₘₐₓ·v, and (dΦ/dz)ₘₐₓ = 0.42933 μ₀m/R²,
    /// a quarter of a radius either side of the coil.
    func testAThinCoilsPeakEMFIsFaradaysClosedForm() {
        let radius = 0.05, speed = 1.0, moment = 6.0
        let coil = PickupCoil(center: .zero, axis: SIMD3(0, 0, 1), radius: radius,
                              length: 1e-6, turns: 1000, wireDiameter: 0.25e-3)
        let dt = 1e-5
        var peak = 0.0
        var previous = coil.linkage(magnets: [magnet(at: -0.3, moment: moment)])
        var z = -0.3
        while z < 0.3 {
            z += speed * dt
            let now = coil.linkage(magnets: [magnet(at: z, moment: moment)])
            peak = max(peak, abs(-(now - previous) / dt))
            previous = now
        }
        let expected = 1000 * 0.42933 * mu0 * moment * speed / (radius * radius)
        XCTAssertEqual(peak / expected, 1, accuracy: 1e-3)
    }

    /// Through and out the other side: the EMF entering and the EMF
    /// leaving have opposite signs, and they cancel — the linkage is the
    /// same far away on either side.
    func testAPassThroughTheCoilIntegratesToNothing() {
        let coil = PickupCoil(center: .zero, axis: SIMD3(0, 0, 1), radius: 0.056,
                              length: 0.08, turns: 2000, wireDiameter: 0.25e-3)
        let dt = 1.0 / 90, speed = 1.5
        var z = -0.8
        var previous = coil.linkage(magnets: [magnet(at: z)])
        var integral = 0.0
        var entering = 0.0, leaving = 0.0
        while z < 0.8 {
            z += speed * dt
            let now = coil.linkage(magnets: [magnet(at: z)])
            let emf = -(now - previous) / dt
            integral += emf * dt
            if z < 0 { entering += emf } else { leaving += emf }
            previous = now
        }
        XCTAssertEqual(integral, 0, accuracy: 1e-3 * coil.linkage(magnets: [magnet(at: 0)]))
        XCTAssertLessThan(entering * leaving, 0, "entering and leaving should light opposite colours")
    }

    func testTheLEDPairIsDarkBelowItsThresholdAndObeysKirchhoffAbove() {
        let resistance = 240.0
        // A volt is far below the red LED's knee: essentially no current.
        XCTAssertLessThan(abs(BicolourLED.current(emf: 1.0, resistance: resistance)), 1e-6)
        for emf in [2.0, 3.0, 5.0, -2.5, -4.0] {
            let current = BicolourLED.current(emf: emf, resistance: resistance)
            XCTAssertEqual(BicolourLED.residual(emf: emf, resistance: resistance, current: current),
                           0, accuracy: 1e-12)
            // Red lights for a positive EMF, green for a negative one.
            XCTAssertEqual(current.sign, emf.sign)
        }
        // The LED drops its rated voltage at its rated current.
        XCTAssertEqual(BicolourLED.red.voltage(current: 0.010), 1.8, accuracy: 1e-12)
        XCTAssertEqual(BicolourLED.green.voltage(current: 0.010), 2.1, accuracy: 1e-12)
    }

    /// 2000 turns of 0.25 mm copper on a 5.6 cm mean radius: about 700 m of
    /// wire and a couple of hundred ohms.
    func testTheCoilsResistanceIsTheCoppersRhoLOverA() {
        let coil = PickupCoil(center: .zero, axis: SIMD3(1, 0, 0), radius: 0.056,
                              length: 0.08, turns: 2000, wireDiameter: 0.25e-3)
        let wire = 2000 * 2 * Double.pi * 0.056
        let area = Double.pi * 0.25e-3 * 0.25e-3 / 4
        XCTAssertEqual(coil.resistance, 1.68e-8 * wire / area, accuracy: 1e-9)
        XCTAssertEqual(coil.resistance, 240, accuracy: 15)
    }
}
