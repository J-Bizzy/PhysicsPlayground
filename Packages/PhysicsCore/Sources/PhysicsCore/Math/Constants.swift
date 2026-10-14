//
//  Constants.swift
//  PhysicsCore — Math: the physical constants, SI, in one audited place.
//
//  c and e are exact by the 2019 SI definitions; ε₀ = 1/(μ₀c²) and
//  k = 1/(4πε₀) are derived so the three can never disagree
//  (ConstantsTests recovers μ₀ε₀c² = 1 to the last bits of a Double).
//

import Foundation

/// Physical constants, SI.
public enum Constants {

    // MARK: Exact by definition (2019 SI)

    /// Speed of light in vacuum, m/s. Exact — the metre is defined from it.
    public static let speedOfLight = 2.99792458e8

    /// Elementary charge, C. Exact — the ampere is defined from it.
    public static let elementaryCharge = 1.602176634e-19

    // MARK: Measured

    /// Vacuum permeability, T·m/A. Measured since 2019, but 4π × 10⁻⁷
    /// still agrees to ten significant figures, so the closed form is kept.
    public static let vacuumPermeability = 4e-7 * Double.pi

    /// Newton's gravitational constant, m³/(kg·s²). CODATA 2018.
    public static let gravitational = 6.6743e-11

    /// Electron rest mass, kg. CODATA 2018.
    public static let electronMass = 9.1093837015e-31

    // MARK: Derived — these CANNOT drift from the above

    /// Vacuum permittivity, F/m. ε₀ = 1/(μ₀c²), exactly.
    public static let vacuumPermittivity =
        1 / (vacuumPermeability * speedOfLight * speedOfLight)

    /// Coulomb's constant, N·m²/C². k = 1/(4πε₀), exactly.
    public static let coulomb = 1 / (4 * Double.pi * vacuumPermittivity)

    /// μ₀/4π, the form the dipole and Biot–Savart expressions want.
    public static let permeabilityOver4Pi = vacuumPermeability / (4 * Double.pi)
}
