//
//  ConstantsTests.swift
//  PhysicsCoreTests
//
//  The constants have to agree WITH EACH OTHER, and nothing checked
//  that until 2026-08-03.
//
//  `ElectricField.k` was the pre-2019 value while `GaussSurface`
//  carried CODATA 2018's ε₀ — two numbers describing one physical fact,
//  disagreeing in the tenth significant figure. No existing test could
//  have caught it: every flux test compares against Q/ε₀ using the same
//  ε₀ it was computed with, so the discrepancy cancels perfectly.
//
//  That is the general shape of the risk here. A wrong constant used
//  consistently is invisible to every test written in terms of it. What
//  catches it is a RELATION between constants that the physics demands
//  and no single call site can satisfy on its own.
//
//  So these tests do not check values against a table — the values are
//  in `Constants.swift` with their sources, and re-typing them here
//  would just be the same typo twice. They check the identities.
//

import XCTest
@testable import PhysicsCore

final class ConstantsTests: XCTestCase {

    /// **μ₀ε₀c² = 1.** The defining relation of classical
    /// electromagnetism, exact in SI, and the one line that pins three
    /// constants at once: change any of them independently and this
    /// fails.
    ///
    /// Asserted to 1e-15 — the last couple of bits of a `Double` —
    /// because ε₀ is DERIVED from the other two, so anything worse than
    /// floating-point noise means somebody has gone back to typing it.
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

    /// The per-module aliases must resolve to the shared definitions.
    ///
    /// Seven files declared these before there was one place to declare
    /// them, and they are kept as forwards because `ElectricField.k`
    /// reads better inside `ElectricField` than `Constants.coulomb`
    /// does. This is what stops a forward quietly becoming a second
    /// definition again.
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

    /// A sanity floor, so a catastrophic edit (a dropped exponent, a
    /// sign) cannot pass the identity tests by scaling everything
    /// together. These bounds are deliberately loose — they are checking
    /// the ORDER OF MAGNITUDE, not the digits, which is what
    /// `Constants.swift`'s own sourcing is for.
    func testEachConstantIsInTheRightDecade() {
        XCTAssertEqual(log10(Constants.speedOfLight), 8.48, accuracy: 0.01)
        XCTAssertEqual(log10(Constants.elementaryCharge), -18.80, accuracy: 0.01)
        // μ₀ = 4π × 10⁻⁷ = 1.2566e-6, so log₁₀ is −5.90, not −6.10. The
        // 4π is most of a decade and this test was written as though it
        // were not — the assertion was wrong, the constant was right.
        XCTAssertEqual(log10(Constants.vacuumPermeability), -5.90, accuracy: 0.01)
        XCTAssertEqual(log10(Constants.vacuumPermittivity), -11.05, accuracy: 0.01)
        XCTAssertEqual(log10(Constants.coulomb), 9.95, accuracy: 0.01)
        XCTAssertEqual(log10(Constants.gravitational), -10.18, accuracy: 0.01)
        XCTAssertEqual(log10(Constants.electronMass), -30.04, accuracy: 0.01)
    }
}
