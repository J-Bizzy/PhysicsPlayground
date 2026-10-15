//
//  Glass.swift
//  PhysicsCore — Optics
//
//  What a piece of glass does to light, from its catalogue data:
//
//    Dispersion   the Sellmeier equation, n²(λ) = 1 + Σ Bᵢλ²/(λ² − Cᵢ),
//                 with Schott's published coefficients. Blue sees a
//                 higher index than red — the whole reason a prism
//                 makes a rainbow.
//    Fresnel      how much of the light a surface reflects, from the
//                 two indices and the angle: the s and p reflectances
//                 of Maxwell's boundary conditions, averaged for the
//                 unpolarised light a laser pointer or torch gives off.
//                 Past the critical angle all of it reflects.
//
//  Wavelengths are nanometres; angles radians.
//

import Foundation
import simd

/// An optical glass, by catalogue name.
public enum Glass: Sendable, Equatable, Hashable {
    /// Schott N-BK7, the crown glass of nearly every lens and prism.
    case nbk7
    /// Schott SF11, a dense flint: about three times BK7's dispersion.
    case sf11
    /// A medium of fixed index, with no dispersion — for tests and for
    /// stating a result in terms of n alone.
    case constant(Double)

    /// Schott's Sellmeier coefficients: B₁₋₃ dimensionless, C₁₋₃ in µm².
    private var sellmeier: (b: SIMD3<Double>, c: SIMD3<Double>)? {
        switch self {
        case .nbk7:
            return (SIMD3(1.03961212, 0.231792344, 1.01046945),
                    SIMD3(0.00600069867, 0.0200179144, 103.560653))
        case .sf11:
            return (SIMD3(1.73759695, 0.313747346, 1.89878101),
                    SIMD3(0.013188707, 0.0623068142, 155.23629))
        case .constant:
            return nil
        }
    }

    /// The refractive index at `nanometers`.
    public func index(nanometers: Double) -> Double {
        guard let (b, c) = sellmeier else {
            if case .constant(let n) = self { return n }
            return 1
        }
        let l2 = (nanometers / 1000) * (nanometers / 1000)
        let n2 = 1 + b.x * l2 / (l2 - c.x) + b.y * l2 / (l2 - c.y) + b.z * l2 / (l2 - c.z)
        return n2.squareRoot()
    }

    /// The Fraunhofer lines the catalogue quotes indices at: F (hydrogen
    /// blue), d (helium yellow) and C (hydrogen red), nanometres.
    public static let fLine = 486.1327
    public static let dLine = 587.5618
    public static let cLine = 656.2725

    /// The Abbe number V_d = (n_d − 1)/(n_F − n_C): how little the glass
    /// disperses. Crown glass is high (BK7: 64), flint low (SF11: 26).
    public var abbeNumber: Double {
        let spread = index(nanometers: Self.fLine) - index(nanometers: Self.cLine)
        guard spread > 0 else { return .infinity }
        return (index(nanometers: Self.dLine) - 1) / spread
    }
}

/// How much light a smooth surface between two media reflects.
public enum Fresnel {
    /// The reflectances for light arriving at the surface with
    /// `cosIncidence` (cosine of the angle from the normal, 0…1), going
    /// from index `n1` into `n2`: s- and p-polarised, and their mean for
    /// unpolarised light. All three are 1 under total internal
    /// reflection. The transmitted fraction is 1 − R: a smooth
    /// dielectric surface absorbs nothing.
    public static func reflectance(cosIncidence: Double, n1: Double, n2: Double)
        -> (s: Double, p: Double, unpolarised: Double) {
        let cosI = min(max(cosIncidence, 0), 1)
        let eta = n1 / n2
        let sinT2 = eta * eta * (1 - cosI * cosI)
        guard sinT2 < 1 else { return (1, 1, 1) }
        let cosT = (1 - sinT2).squareRoot()
        let rs = (n1 * cosI - n2 * cosT) / (n1 * cosI + n2 * cosT)
        let rp = (n2 * cosI - n1 * cosT) / (n2 * cosI + n1 * cosT)
        let s = rs * rs, p = rp * rp
        return (s, p, (s + p) / 2)
    }

    /// Brewster's angle from n₁ into n₂, tan θ_B = n₂/n₁: p-polarised
    /// light is transmitted entirely there.
    public static func brewsterAngle(n1: Double, n2: Double) -> Double {
        atan2(n2, n1)
    }
}
