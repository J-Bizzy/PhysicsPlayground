//
//  Constants.swift
//  PhysicsCore — Math
//
//  The physical constants, in one audited place.
//
//  This project's headline claim is "SI units, real constants, exact
//  closed-form solutions where they exist". Every value below was
//  checked against CODATA 2018 / the 2019 SI redefinition, and they were
//  all correct where they stood — but they stood in SEVEN different
//  files, and two of them disagreed.
//
//  WHAT THE SCATTERING COST, precisely:
//
//  · `ElectricField.k` was 8.9875517923e9, the pre-2019 value, while
//    `GaussSurface.epsilonZero` was CODATA 2018's 8.8541878128e-12.
//    Those two describe the same physical fact and are not consistent:
//    1/(4πε₀) is 8.98755178737e9. The disagreement is 5.5 × 10⁻¹⁰ —
//    physically invisible, and no test could ever have caught it,
//    because every test compared a flux to Q/ε₀ using the SAME ε₀. What
//    it actually cost was the claim: a codebase asserting two values of
//    one constant is not asserting exact constants.
//  · μ₀ was declared three times (`WireField`, `CurrentLoop`, and as
//    μ₀/4π in `MagneticField`), `e` and `c` once each in
//    `ChargeTransport`, G in `NBody`, and mₑ in the APP layer where
//    PhysicsCore could not see it.
//
//  So: derived where a derivation exists, defined where it does not.
//
//  · `c` and `e` are EXACT BY DEFINITION since the 2019 SI redefinition
//    — the metre and the ampere are defined from them — so they are
//    written out.
//  · μ₀ is no longer exact (the ampere's redefinition made it a
//    measured quantity), but 4π × 10⁻⁷ is still right to ten
//    significant figures, which is far past anything here resolves.
//  · ε₀ = 1/(μ₀c²) EXACTLY, so it is derived rather than typed.
//  · k = 1/(4πε₀), likewise derived. It is now impossible for these
//    three to disagree, which is what `ConstantsTests` asserts by
//    recovering μ₀ε₀c² = 1 to the last bits of a Double.
//
//  The old names stay where they were as one-line forwards, because
//  `ElectricField.k` reads better at a call site inside `ElectricField`
//  than `Constants.coulomb` does, and moving them would have touched
//  fifty call sites to no benefit. What matters is that there is exactly
//  one definition behind each.
//

import Foundation

/// Physical constants, SI.
public enum Constants {

    // MARK: Exact by definition (2019 SI)

    /// Speed of light in vacuum, m/s. Exact — the metre is defined from
    /// it.
    public static let speedOfLight = 2.99792458e8

    /// Elementary charge, C. Exact — the ampere is defined from it.
    public static let elementaryCharge = 1.602176634e-19

    // MARK: Measured

    /// Vacuum permeability, T·m/A.
    ///
    /// Exactly 4π × 10⁻⁷ until the 2019 redefinition made it a measured
    /// quantity; the measured value still agrees to ten significant
    /// figures, so the closed form is kept.
    public static let vacuumPermeability = 4e-7 * Double.pi

    /// Newton's gravitational constant, m³/(kg·s²). CODATA 2018 — and
    /// by far the least precisely known constant here, at about one part
    /// in 10⁵.
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
