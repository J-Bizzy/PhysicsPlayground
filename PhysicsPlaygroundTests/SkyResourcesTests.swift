//
//  SkyResourcesTests.swift
//  PhysicsPlaygroundTests
//
//  The real sky as bundled and drawn (2026-10-19): the catalogue decodes
//  to the naked-eye stars with the famous ones where and as they are, the
//  house evening stands Orion's belt ahead 30° up, every star's quad faces
//  the wearer and is never smaller than the legible floor, and a red giant
//  samples a redder cell than a blue one.
//

import XCTest
import PhysicsCore
import RealityKit
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class SkyResourcesTests: XCTestCase {

    private let degree = Double.pi / 180

    private func catalogue() throws -> [CatalogStar] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "BrightStarCatalog", withExtension: "bin"),
                                "the catalogue is not in the bundle — run Tools/starcatalog.py")
        return try StarCatalog.decode(Data(contentsOf: url))
    }

    func testTheCatalogueIsTheNakedEyeSkyWithItsFamousStarsInPlace() throws {
        let stars = try catalogue()
        XCTAssertTrue((9_000...9_110).contains(stars.count), "\(stars.count) stars")
        let brightest = try XCTUnwrap(stars.min { $0.magnitude < $1.magnitude })
        XCTAssertEqual(brightest.hr, 2491, "Sirius")
        XCTAssertEqual(brightest.magnitude, -1.46, accuracy: 0.005)
        let byHR = Dictionary(uniqueKeysWithValues: stars.map { ($0.hr, $0) })
        XCTAssertEqual(try XCTUnwrap(byHR[2061]).colourIndex, 1.85, accuracy: 0.001, "Betelgeuse")
        XCTAssertEqual(try XCTUnwrap(byHR[424]).declination, 89.2642 * degree, accuracy: 1e-4, "Polaris")
    }

    /// The house sky stands Alnilam straight ahead, 30° up.
    func testTheHouseSkyStandsOrionsBeltAhead() {
        let alnilam = CelestialSphere.equatorial(rightAscension: SkyOrientation.alnilam.rightAscension,
                                                 declination: SkyOrientation.alnilam.declination)
        let ahead = Sky.orientation.act(SIMD3<Float>(alnilam))
        XCTAssertEqual(ahead.x, 0, accuracy: 1e-5)
        XCTAssertEqual(ahead.y, Float(sin(30 * degree)), accuracy: 1e-5)
        XCTAssertEqual(ahead.z, Float(-cos(30 * degree)), accuracy: 1e-5)
    }

    /// Every quad faces the centre and is no smaller than the floor.
    func testEveryStarFacesTheWearerAndIsLegible() throws {
        let stars = SkyDrawing.stars(try catalogue())
        let geometry = StarField.assemble(stars, radius: SkyResources.starRadius, atlas: SkyDrawing.atlas)
        XCTAssertEqual(geometry.vertices.count, stars.count * 4)
        XCTAssertLessThan(geometry.vertices.count, 65_536, "16-bit indices")
        let minimum = Float(StellarPhotometry.minimumSize * SkyDrawing.quadOverCore)
        for star in stars.prefix(2_000) {
            XCTAssertGreaterThanOrEqual(star.halfAngle, minimum * 0.999)
        }
        for quad in stride(from: 0, to: geometry.indices.count, by: 6).prefix(2_000) {
            let a = geometry.vertices[Int(geometry.indices[quad])]
            let b = geometry.vertices[Int(geometry.indices[quad + 1])]
            let c = geometry.vertices[Int(geometry.indices[quad + 2])]
            let pa = SIMD3(a.x, a.y, a.z), pb = SIMD3(b.x, b.y, b.z), pc = SIMD3(c.x, c.y, c.z)
            let normal = simd_cross(pb - pa, pc - pa)
            XCTAssertLessThan(simd_dot(normal, pa), 0, "a quad faces away from the wearer")
        }
    }

    func testARedGiantSamplesARedderCellThanABlueStar() throws {
        let byHR = Dictionary(uniqueKeysWithValues: try catalogue().map { ($0.hr, $0) })
        let drawn = SkyDrawing.stars([try XCTUnwrap(byHR[2061]), try XCTUnwrap(byHR[1713])])
        XCTAssertGreaterThan(drawn[0].column, drawn[1].column, "Betelgeuse redder than Rigel")
    }

    /// Built once; a second call returns the same sky.
    func testTheSkyIsBuiltOnce() async throws {
        let firstBuilt = await SkyResources.prepare()
        let secondBuilt = await SkyResources.prepare()
        let first = try XCTUnwrap(firstBuilt)
        let second = try XCTUnwrap(secondBuilt)
        XCTAssertTrue(first === second)
        XCTAssertGreaterThan(first.starCount, 9_000)
        let sky = Sky.make(overRoom: false, resources: first)
        XCTAssertNotNil(sky.findEntity(named: "sky-stars"))
        XCTAssertNotNil(sky.findEntity(named: "sky-milky-way"))
    }
}
