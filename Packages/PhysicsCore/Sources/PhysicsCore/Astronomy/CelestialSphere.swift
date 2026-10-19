//
//  CelestialSphere.swift
//  PhysicsCore — Astronomy
//
//  Where a star is: right ascension and declination (J2000) as a unit
//  vector, the same vector in galactic coordinates, and the rigid turn
//  that stands the whole sky over a wearer — a real evening at a real
//  latitude, yawed so a chosen star is straight ahead.
//
//  Equatorial frame: x̂ toward the vernal equinox, ẑ toward the north
//  celestial pole, ŷ completing a right-handed set (RA 90°). The app's
//  world frame is +Y up and −Z ahead; `SkyOrientation` maps one to the
//  other.
//

import Foundation
import simd

public enum CelestialSphere {

    /// The unit vector toward (α, δ), radians, in the equatorial frame.
    public static func equatorial(rightAscension alpha: Double,
                                  declination delta: Double) -> SIMD3<Double> {
        SIMD3(cos(delta) * cos(alpha), cos(delta) * sin(alpha), sin(delta))
    }

    /// (α, δ), radians, of an equatorial vector; α in [0, 2π).
    public static func rightAscensionDeclination(of v: SIMD3<Double>)
    -> (rightAscension: Double, declination: Double) {
        let u = simd_normalize(v)
        var alpha = atan2(u.y, u.x)
        if alpha < 0 { alpha += 2 * .pi }
        return (alpha, asin(min(max(u.z, -1), 1)))
    }

    // MARK: The galaxy

    /// The north galactic pole and the galactic longitude of the north
    /// celestial pole that define the galactic frame (J2000, as Hipparcos
    /// adopted them).
    public static let northGalacticPole = (rightAscension: 192.85948 * Double.pi / 180,
                                           declination: 27.12825 * Double.pi / 180)
    public static let northCelestialPoleLongitude = 122.93192 * Double.pi / 180

    /// Equatorial → galactic: its rows are the galactic x̂ (toward the
    /// galactic centre), ŷ (toward l = 90°) and ẑ (the north galactic pole),
    /// written in equatorial components. Built from the three defining
    /// angles rather than typed in, so it is exactly orthonormal.
    public static let equatorialToGalactic: simd_double3x3 = {
        let pole = equatorial(rightAscension: northGalacticPole.rightAscension,
                              declination: northGalacticPole.declination)
        let celestialPole = SIMD3<Double>(0, 0, 1)
        // The celestial pole projected onto the galactic plane lies at
        // galactic longitude l_NCP; the direction 90° on from it is ẑ × that.
        let projected = simd_normalize(celestialPole - simd_dot(celestialPole, pole) * pole)
        let ahead = simd_cross(pole, projected)
        let l = northCelestialPoleLongitude
        let x = cos(l) * projected - sin(l) * ahead
        let y = sin(l) * projected + cos(l) * ahead
        return simd_double3x3(rows: [x, y, pole])
    }()

    /// Galactic (l, b), radians, of an equatorial vector; l in (−π, π].
    public static func galactic(fromEquatorial v: SIMD3<Double>)
    -> (longitude: Double, latitude: Double) {
        let g = equatorialToGalactic * simd_normalize(v)
        return (atan2(g.y, g.x), asin(min(max(g.z, -1), 1)))
    }

    /// The equatorial unit vector toward galactic (l, b), radians.
    public static func equatorial(galacticLongitude l: Double,
                                  galacticLatitude b: Double) -> SIMD3<Double> {
        let g = SIMD3(cos(b) * cos(l), cos(b) * sin(l), sin(b))
        return equatorialToGalactic.transpose * g
    }

    // MARK: The ecliptic

    /// The obliquity of the ecliptic at J2000, radians.
    public static let obliquity = 23.43928 * Double.pi / 180

    /// An ecliptic vector (x̂ toward the equinox, ẑ toward the north
    /// ecliptic pole) in the equatorial frame.
    public static func equatorial(fromEcliptic v: SIMD3<Double>) -> SIMD3<Double> {
        let c = cos(obliquity), s = sin(obliquity)
        return SIMD3(v.x, c * v.y - s * v.z, s * v.y + c * v.z)
    }
}

// MARK: - The sky over a wearer

/// A rigid turn of the equatorial sky into the app's world frame (+Y up,
/// −Z ahead): an observer at `latitude` at local sidereal time
/// `siderealTime`, faced toward `heading` (an azimuth in their horizon).
public struct SkyOrientation: Sendable, Equatable {
    public var latitude: Double
    public var siderealTime: Double
    /// Azimuth faced, radians east of north.
    public var heading: Double

    public init(latitude: Double, siderealTime: Double, heading: Double) {
        self.latitude = latitude
        self.siderealTime = siderealTime
        self.heading = heading
    }

    /// World = matrix · equatorial.
    public var matrix: simd_double3x3 {
        let phi = latitude, theta = siderealTime
        // The horizon's east, north and zenith in equatorial components.
        let east = SIMD3(-sin(theta), cos(theta), 0)
        let north = SIMD3(-sin(phi) * cos(theta), -sin(phi) * sin(theta), cos(phi))
        let up = SIMD3(cos(phi) * cos(theta), cos(phi) * sin(theta), sin(phi))
        // Ahead is the heading's horizontal direction; right is 90° clockwise
        // from it seen from above.
        let ahead = cos(heading) * north + sin(heading) * east
        let right = cos(heading) * east - sin(heading) * north
        // World x = right, y = up, z = −ahead.
        return simd_double3x3(rows: [right, up, -ahead])
    }

    public func world(_ equatorial: SIMD3<Double>) -> SIMD3<Double> {
        matrix * equatorial
    }

    /// The (east, north, up) components of an equatorial vector here.
    public func horizon(_ equatorial: SIMD3<Double>) -> SIMD3<Double> {
        let phi = latitude, theta = siderealTime
        let east = SIMD3(-sin(theta), cos(theta), 0)
        let north = SIMD3(-sin(phi) * cos(theta), -sin(phi) * sin(theta), cos(phi))
        let up = SIMD3(cos(phi) * cos(theta), cos(phi) * sin(theta), sin(phi))
        return SIMD3(simd_dot(equatorial, east), simd_dot(equatorial, north),
                     simd_dot(equatorial, up))
    }

    /// The evening that stands (α, δ) at `altitude`, RISING (in the east),
    /// at `latitude`, faced straight ahead. Nil when the star never reaches
    /// that altitude there.
    public static func facing(rightAscension alpha: Double, declination delta: Double,
                              altitude: Double, latitude phi: Double) -> SkyOrientation? {
        // sin h = sin δ sin φ + cos δ cos φ cos H.
        let cosH = (sin(altitude) - sin(delta) * sin(phi)) / (cos(delta) * cos(phi))
        guard abs(cosH) <= 1 else { return nil }
        let hourAngle = -acos(cosH)       // negative: east of the meridian
        let theta = alpha + hourAngle
        var orientation = SkyOrientation(latitude: phi, siderealTime: theta, heading: 0)
        let h = orientation.horizon(CelestialSphere.equatorial(rightAscension: alpha,
                                                               declination: delta))
        orientation.heading = atan2(h.x, h.y)
        return orientation
    }

    /// Alnilam, the middle of Orion's belt (HR 1903, J2000).
    public static let alnilam = (rightAscension: 84.05338894 * Double.pi / 180,
                                 declination: -1.20191914 * Double.pi / 180)

    /// The house sky: a winter evening at 40° N with Orion's belt rising
    /// straight ahead, 30° up — Orion over the wordmark, Polaris behind and
    /// to the left at 40°, the Milky Way arching overhead.
    public static let house: SkyOrientation = facing(
        rightAscension: alnilam.rightAscension, declination: alnilam.declination,
        altitude: 30 * Double.pi / 180, latitude: 40 * Double.pi / 180)!
}
