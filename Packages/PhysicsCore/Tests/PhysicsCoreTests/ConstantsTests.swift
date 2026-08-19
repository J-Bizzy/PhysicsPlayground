//
//  ConstantsTests.swift
//  PhysicsCoreTests
//
//  Identity checks between constants, not table lookups: a wrong constant used
//  consistently is invisible to tests written in terms of it.
//

import XCTest
@testable import PhysicsCore

final class ConstantsTests: XCTestCase {

    /// μ₀ε₀c² = 1, exact in SI — pins three constants at once. Asserted to
    /// 1e-15 because ε₀ is DERIVED from the other two.
    func testPermeabilityTimesPermittivityTimesCSquaredIsOne() {
        let product = Constants.vacuumPermeability
            * Constants.vacuumPermittivity
            * Constants.speedOfLight * Constants.speedOfLight
        XCTAssertEqual(product, 1.0, accuracy: 1e-15,
                       """
                       μ₀ε₀c² = \(product), not 1. These three are not \
                       independent — ε₀ is defined as 1/(μ₀c²) — so this \
                       failing means one of them was typed rather than \
                       derived.
                       """)
    }

    /// **k = 1/(4πε₀).** The relation that was actually broken.
    func testCoulombsConstantIsTheReciprocalOfFourPiEpsilonZero() {
        let expected = 1 / (4 * Double.pi * Constants.vacuumPermittivity)
        XCTAssertEqual(Constants.coulomb, expected, accuracy: 1e-15 * expected)
    }

    /// Per-module aliases must resolve to the shared definitions — stops a
    /// forward quietly becoming a second definition.
    func testEveryModulesAliasPointsAtTheSharedConstant() {
        XCTAssertEqual(ElectricField.k, Constants.coulomb)
        XCTAssertEqual(GaussSurface.epsilonZero, Constants.vacuumPermittivity)
        XCTAssertEqual(ChargeTransport.elementaryCharge, Constants.elementaryCharge)
        XCTAssertEqual(ChargeTransport.speedOfLight, Constants.speedOfLight)
        XCTAssertEqual(NBody.gravitationalConstant, Constants.gravitational)
        XCTAssertEqual(CurrentLoop.mu0, Constants.vacuumPermeability)
        XCTAssertEqual(WireField.mu0, Constants.vacuumPermeability)
        XCTAssertEqual(MagneticField.mu0over4pi, Constants.permeabilityOver4Pi)
    }

    /// μ₀ was declared three times, twice as itself and once as μ₀/4π.
    func testTheTwoFormsOfPermeabilityAgree() {
        XCTAssertEqual(MagneticField.mu0over4pi * 4 * Double.pi,
                       CurrentLoop.mu0,
                       accuracy: 1e-15 * CurrentLoop.mu0)
    }

    /// Order-of-magnitude floor: a dropped exponent cannot pass the identity
    /// tests by scaling everything together.
    func testEachConstantIsInTheRightDecade() {
        XCTAssertEqual(log10(Constants.speedOfLight), 8.48, accuracy: 0.01)
        XCTAssertEqual(log10(Constants.elementaryCharge), -18.80, accuracy: 0.01)
        // μ₀ = 4π × 10⁻⁷ ⇒ log₁₀ ≈ −5.90, not −6.10: the 4π is most of a decade.
        XCTAssertEqual(log10(Constants.vacuumPermeability), -5.90, accuracy: 0.01)
        XCTAssertEqual(log10(Constants.vacuumPermittivity), -11.05, accuracy: 0.01)
        XCTAssertEqual(log10(Constants.coulomb), 9.95, accuracy: 0.01)
        XCTAssertEqual(log10(Constants.gravitational), -10.18, accuracy: 0.01)
        XCTAssertEqual(log10(Constants.electronMass), -30.04, accuracy: 0.01)
    }
}
