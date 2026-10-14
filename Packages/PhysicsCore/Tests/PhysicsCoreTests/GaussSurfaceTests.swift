//
//  GaussSurfaceTests.swift
//  PhysicsCoreTests
//
//  Theorem-recovery tests, the kind that catch real errors: the closed
//  surface has to give back Q_enclosed/ε₀ — not because the code says so
//  but because the quadrature of the actual Coulomb field says so.
//

import XCTest
import simd
@testable import PhysicsCore

final class GaussSurfaceTests: XCTestCase {

    private func charge(_ q: Double, at position: SIMD3<Double>) -> PointCharge {
        PointCharge(id: UUID(), position: position, charge: q)
    }

    // MARK: The theorem

    /// A charge at the centre: flux = q/ε₀, independent of the radius.
    /// This is Gauss's law in its baldest form and the quadrature has to
    /// reproduce it without being told.
    func testClosedSphereRecoversEnclosedChargeOverEpsilonZero() {
        let charges = [charge(3e-6, at: .zero)]
        for radius in [0.2, 0.5, 1.3] {
            let flux = GaussSurface.flux(throughSphereAt: .zero, radius: radius,
                                         charges: charges)
            let predicted = GaussSurface.predictedFlux(inSphereAt: .zero, radius: radius,
                                                       charges: charges)
            XCTAssertEqual(flux / predicted, 1, accuracy: 1e-6,
                           "radius \(radius) m must not change the flux")
        }
    }

    /// The part that actually surprises people: a charge outside the
    /// surface contributes exactly nothing, however close it is.
    func testChargeOutsideTheSurfaceContributesNoNetFlux() {
        let outside = [charge(5e-6, at: SIMD3(0.9, 0, 0))]
        let flux = GaussSurface.flux(throughSphereAt: .zero, radius: 0.4,
                                     charges: outside, samples: 6000)
        // Scale the tolerance to the flux that charge would produce if it
        // were enclosed — otherwise "small" means nothing at 1e-12 F/m.
        let scale = 5e-6 / GaussSurface.epsilonZero
        XCTAssertEqual(flux / scale, 0, accuracy: 2e-3)
    }

    /// Off-centre inside still gives the same answer — the law cares
    /// about enclosure, not placement.
    func testOffCentreChargeGivesTheSameFlux() {
        let charges = [charge(2e-6, at: SIMD3(0.15, -0.1, 0.05))]
        let flux = GaussSurface.flux(throughSphereAt: .zero, radius: 0.5,
                                     charges: charges, samples: 8000)
        let predicted = GaussSurface.predictedFlux(inSphereAt: .zero, radius: 0.5,
                                                   charges: charges)
        XCTAssertEqual(flux / predicted, 1, accuracy: 5e-3)
    }

    /// A dipole entirely inside: net enclosed charge zero, net flux zero.
    func testEnclosedDipoleHasZeroNetFlux() {
        let charges = [charge(4e-6, at: SIMD3(-0.1, 0, 0)),
                       charge(-4e-6, at: SIMD3(0.1, 0, 0))]
        let flux = GaussSurface.flux(throughSphereAt: .zero, radius: 0.6,
                                     charges: charges, samples: 8000)
        let scale = 4e-6 / GaussSurface.epsilonZero
        XCTAssertEqual(flux / scale, 0, accuracy: 2e-3)
        XCTAssertEqual(GaussSurface.enclosedCharge(inSphereAt: .zero, radius: 0.6,
                                                   charges: charges), 0, accuracy: 1e-18)
    }

    /// Superposition: two enclosed charges add.
    func testEnclosedChargesAdd() {
        let charges = [charge(1e-6, at: SIMD3(-0.1, 0, 0)),
                       charge(3e-6, at: SIMD3(0.12, 0.05, 0))]
        let flux = GaussSurface.flux(throughSphereAt: .zero, radius: 0.55,
                                     charges: charges, samples: 8000)
        let predicted = GaussSurface.predictedFlux(inSphereAt: .zero, radius: 0.55,
                                                   charges: charges)
        XCTAssertEqual(flux / predicted, 1, accuracy: 5e-3)
    }

    // MARK: The open disc

    /// A disc facing a distant charge intercepts the fraction of the
    /// total flux that its solid angle subtends. Far away, a disc of
    /// radius a at distance d subtends Ω ≈ πa²/d², so the flux is
    /// approximately (q/4πε₀d²)·πa² — the field times the area.
    func testDistantDiscSeesFieldTimesArea() {
        let d = 2.0, a = 0.05, q = 1e-6
        let charges = [charge(q, at: .zero)]
        let flux = GaussSurface.flux(
            throughDiscAt: SIMD3(d, 0, 0), normal: SIMD3(1, 0, 0),
            radius: a, charges: charges)
        let fieldStrength = q / (4 * .pi * GaussSurface.epsilonZero * d * d)
        XCTAssertEqual(flux / (fieldStrength * .pi * a * a), 1, accuracy: 2e-3)
    }

    /// A disc turned edge-on to the field passes no flux at all.
    func testEdgeOnDiscPassesNoFlux() {
        let charges = [charge(1e-6, at: .zero)]
        let flux = GaussSurface.flux(
            throughDiscAt: SIMD3(1.0, 0, 0), normal: SIMD3(0, 1, 0),
            radius: 0.1, charges: charges)
        let facing = GaussSurface.flux(
            throughDiscAt: SIMD3(1.0, 0, 0), normal: SIMD3(1, 0, 0),
            radius: 0.1, charges: charges)
        XCTAssertEqual(flux / facing, 0, accuracy: 1e-9)
    }

    /// Flipping the normal flips the sign, nothing else.
    func testReversingTheNormalReversesTheSign() {
        let charges = [charge(1e-6, at: .zero)]
        let forward = GaussSurface.flux(
            throughDiscAt: SIMD3(0.8, 0, 0), normal: SIMD3(1, 0, 0),
            radius: 0.12, charges: charges)
        let backward = GaussSurface.flux(
            throughDiscAt: SIMD3(0.8, 0, 0), normal: SIMD3(-1, 0, 0),
            radius: 0.12, charges: charges)
        XCTAssertEqual(forward, -backward, accuracy: abs(forward) * 1e-12)
    }

    /// A disc through the exact centre of a dipole's midplane sees the
    /// two contributions reinforce, not cancel — a good sanity check
    /// that the quadrature is not silently symmetric-zeroing.
    func testDipoleMidplaneDiscSeesRealFlux() {
        let charges = [charge(2e-6, at: SIMD3(-0.2, 0, 0)),
                       charge(-2e-6, at: SIMD3(0.2, 0, 0))]
        let flux = GaussSurface.flux(
            throughDiscAt: .zero, normal: SIMD3(1, 0, 0),
            radius: 0.15, charges: charges)
        XCTAssertGreaterThan(flux, 0, "field runs + → − through the midplane")
    }

    func testBasisIsOrthonormalForAnyNormal() {
        for normal in [SIMD3<Double>(0, 1, 0), SIMD3(1, 0, 0),
                       simd_normalize(SIMD3(0.3, 0.9, -0.2))] {
            let n = simd_normalize(normal)
            let (u, v) = GaussSurface.basis(perpendicularTo: n)
            XCTAssertEqual(simd_length(u), 1, accuracy: 1e-12)
            XCTAssertEqual(simd_length(v), 1, accuracy: 1e-12)
            XCTAssertEqual(simd_dot(u, n), 0, accuracy: 1e-12)
            XCTAssertEqual(simd_dot(v, n), 0, accuracy: 1e-12)
            XCTAssertEqual(simd_dot(u, v), 0, accuracy: 1e-12)
        }
    }
}
