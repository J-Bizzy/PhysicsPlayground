//
//  CelestialSphereTests.swift
//  The sky's frames: the galactic matrix against the published one, the
//  galactic centre and pole where they belong, and the house evening —
//  Orion's belt ahead at 30°, the celestial pole at the observer's latitude.
//

import XCTest
import simd
@testable import PhysicsCore

final class CelestialSphereTests: XCTestCase {

    private let degree = Double.pi / 180

    /// The ICRS → galactic rotation as Hipparcos published it.
    func testTheGalacticMatrixIsTheHipparcosOne() {
        let published: [[Double]] = [
            [-0.0548755604162154, -0.8734370902348850, -0.4838350155487132],
            [0.4941094278755837, -0.4448296299600112, 0.7469822444972189],
            [-0.8676661490190047, -0.1980763734312015, 0.4559837761750669],
        ]
        let m = CelestialSphere.equatorialToGalactic
        for row in 0..<3 {
            for column in 0..<3 {
                XCTAssertEqual(m[column][row], published[row][column], accuracy: 1e-8,
                               "row \(row), column \(column)")
            }
        }
        XCTAssertEqual(simd_determinant(m), 1, accuracy: 1e-12)
    }

    func testTheGalacticCentreAndPoleAreWhereTheyBelong() {
        // Sgr A*, as the galactic centre's defining direction (J2000).
        let centre = CelestialSphere.equatorial(rightAscension: 266.40510 * degree,
                                                declination: -28.936175 * degree)
        let (l, b) = CelestialSphere.galactic(fromEquatorial: centre)
        XCTAssertEqual(l, 0, accuracy: 0.07 * degree)
        XCTAssertEqual(b, 0, accuracy: 0.07 * degree)
        let pole = CelestialSphere.equatorial(
            rightAscension: CelestialSphere.northGalacticPole.rightAscension,
            declination: CelestialSphere.northGalacticPole.declination)
        XCTAssertEqual(CelestialSphere.galactic(fromEquatorial: pole).latitude, .pi / 2, accuracy: 1e-9)
        // Round trip.
        let v = CelestialSphere.equatorial(galacticLongitude: 1.1, galacticLatitude: -0.4)
        let back = CelestialSphere.galactic(fromEquatorial: v)
        XCTAssertEqual(back.longitude, 1.1, accuracy: 1e-12)
        XCTAssertEqual(back.latitude, -0.4, accuracy: 1e-12)
    }

    /// The house evening: Alnilam straight ahead, 30° up, rising; the
    /// celestial pole at the latitude; Polaris behind and to the left.
    func testTheHouseSkyStandsOrionAheadAndThePoleAtTheLatitude() {
        let sky = SkyOrientation.house
        let alnilam = CelestialSphere.equatorial(
            rightAscension: SkyOrientation.alnilam.rightAscension,
            declination: SkyOrientation.alnilam.declination)
        let ahead = sky.world(alnilam)
        XCTAssertEqual(ahead.x, 0, accuracy: 1e-12)
        XCTAssertEqual(ahead.y, sin(30 * degree), accuracy: 1e-12)
        XCTAssertEqual(ahead.z, -cos(30 * degree), accuracy: 1e-12)
        XCTAssertGreaterThan(sky.horizon(alnilam).x, 0, "rising, so in the east")

        let pole = sky.world(SIMD3(0, 0, 1))
        XCTAssertEqual(asin(pole.y), 40 * degree, accuracy: 1e-12)

        let polaris = sky.world(CelestialSphere.equatorial(rightAscension: 37.95456 * degree,
                                                           declination: 89.26411 * degree))
        XCTAssertGreaterThan(polaris.z, 0, "Polaris is behind")
        XCTAssertLessThan(polaris.x, 0, "and to the left")

        XCTAssertEqual(simd_determinant(sky.matrix), 1, accuracy: 1e-12, "a rotation, not a mirror")
    }

    /// The ecliptic's pole is 23.44° from the celestial pole.
    func testTheEclipticIsTiltedByTheObliquity() {
        let pole = CelestialSphere.equatorial(fromEcliptic: SIMD3(0, 0, 1))
        XCTAssertEqual(acos(pole.z), CelestialSphere.obliquity, accuracy: 1e-12)
    }
}
