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
//  And since 2026-11-13: a bright star is drawn over its faint neighbours
//  and over every glare, only the brightest carry a glare, and the dome
//  behind them is NASA's map of the galaxy, the right way round — the
//  Large Magellanic Cloud where it is, the plane bright and the poles
//  black — drawn dim, in one draw, for no more triangles than before.
//

import XCTest
import CoreGraphics
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
        let sky = Sky.make(resources: first)
        XCTAssertNotNil(sky.findEntity(named: "sky-stars"))
        XCTAssertNotNil(sky.findEntity(named: "sky-dome"))
        // The dome carries the galaxy's map (2026-11-13) — measured light,
        // not the model band that was drawn here until 2026-10-24.
        let dome = try XCTUnwrap(sky.findEntity(named: "sky-dome") as? ModelEntity)
        let material = try XCTUnwrap(dome.model?.materials.first as? UnlitMaterial)
        XCTAssertNotNil(first.galaxy, "the map is not in the bundle — run Tools/galaxymap.swift")
        XCTAssertNotNil(material.color.texture)
        // Opaque, so it is drawn first, with nothing sorted before it.
        XCTAssertNil(dome.components[ModelSortGroupComponent.self])
        XCTAssertNil(dome.components[OpacityComponent.self])
    }

    // MARK: Starlight (2026-11-13)

    /// The stars are drawn faintest first, and every glare before any
    /// star, so Sirius lies over its faint neighbours and its own glare.
    func testBrightStarsAreDrawnOverFaintOnesAndOverEveryGlare() throws {
        let catalog = try catalogue()
        let stars = SkyDrawing.stars(catalog)
        XCTAssertEqual(stars.count, catalog.count)
        var lastRow = 0, lastSize: Float = 0
        for star in stars {
            XCTAssertGreaterThanOrEqual(star.row, lastRow)
            XCTAssertGreaterThanOrEqual(star.halfAngle, lastSize * 0.9999)
            XCTAssertLessThan(star.row, StellarPhotometry.brightnessRows, "a core's row")
            lastRow = star.row
            lastSize = star.halfAngle
        }
        let sirius = try XCTUnwrap(catalog.first { $0.hr == 2491 })
        let last = try XCTUnwrap(stars.last)
        let direction = SIMD3<Float>(CelestialSphere.equatorial(
            rightAscension: sirius.rightAscension, declination: sirius.declination))
        XCTAssertGreaterThan(simd_dot(last.direction, direction), 0.999999, "Sirius is drawn last")
    }

    /// Only the stars brighter than magnitude 3 carry a glare, each in a
    /// glare row of its own colour's column, out to its radius.
    func testOnlyTheBrightestStarsCarryAGlare() throws {
        let catalog = try catalogue()
        let glares = SkyDrawing.glares(catalog)
        let bright = catalog.filter { $0.magnitude <= StellarPhotometry.glareMagnitude }
        XCTAssertEqual(glares.count, bright.count)
        XCTAssertTrue((150...200).contains(glares.count), "\(glares.count) glares")
        for glare in glares {
            XCTAssertGreaterThanOrEqual(glare.row, StellarPhotometry.brightnessRows)
            XCTAssertLessThan(glare.row, SkyDrawing.atlas.rows)
        }
        let widest = try XCTUnwrap(glares.map(\.halfAngle).max())
        XCTAssertEqual(Double(widest), 1.25 * degree, accuracy: 0.01 * degree, "Sirius's")
        // Betelgeuse's glare is orange and Rigel's blue-white.
        let byHR = Dictionary(uniqueKeysWithValues: catalog.map { ($0.hr, $0) })
        let pair = SkyDrawing.glares([try XCTUnwrap(byHR[2061]), try XCTUnwrap(byHR[1713])])
        XCTAssertEqual(pair.count, 2)
        // Sorted faintest first: Betelgeuse (0.50) then Rigel (0.12).
        XCTAssertGreaterThan(pair[0].column, pair[1].column)
    }

    /// A glare is a veil that ends in nothing: 1 at the star, half at 0.3
    /// of its radius less the window, and flat zero at the quad's edge.
    func testAGlareFallsToNothingAtItsEdge() {
        XCTAssertEqual(SkyDrawing.glareShape(0), 1, accuracy: 1e-12)
        XCTAssertEqual(SkyDrawing.glareShape(1), 0)
        XCTAssertLessThan(SkyDrawing.glareShape(0.95), 0.001)
        var last = 1.0
        for step in 1...100 {
            let value = SkyDrawing.glareShape(Double(step) / 100)
            XCTAssertLessThanOrEqual(value, last)
            last = value
        }
        // The dither is under half a level either way, so it never lifts
        // an empty pixel.
        for x in 0..<64 { for y in 0..<64 {
            XCTAssertLessThanOrEqual(abs(SkyDrawing.dither(x, y)), 0.5)
        } }
    }

    /// The whole sky is two draws — the dome and the stars — and no more
    /// triangles than a single lab part: the dome's 16,384 and two a quad.
    func testTheSkyIsTwoDrawsAndUnderFortyThousandTriangles() async throws {
        let built = await SkyResources.prepare()
        let resources = try XCTUnwrap(built)
        let sky = Sky.make(resources: resources)
        // A draw is a model's material: the dome's one and the stars' one.
        var draws = 0
        func walk(_ entity: Entity) {
            draws += (entity as? ModelEntity)?.model?.materials.count ?? 0
            entity.children.forEach(walk)
        }
        walk(sky)
        XCTAssertEqual(draws, 2)
        let quads = try catalogue().count + SkyDrawing.glares(try catalogue()).count
        XCTAssertLessThan(quads * 4, 65_536, "16-bit indices")
        XCTAssertLessThan(128 * 64 * 2 + quads * 2, 40_000)
    }

    // MARK: The galaxy (2026-11-13)

    /// The bundled map, as bytes, and its mean LINEAR light (0…1, as the
    /// file holds it: NASA's values times the tool's gain) in a small box
    /// about a place in the sky — read at the texture coordinate the DOME
    /// draws that place with.
    private struct GalaxyMap {
        let width: Int, height: Int
        let pixels: [UInt8]

        func light(rightAscension: Double, declination: Double, half: Int = 6) -> Double {
            let uv = SkyDrawing.galaxyCoordinate(rightAscension: rightAscension,
                                                 declination: declination)
            // A texture's v runs up; an image's rows run down.
            let cx = Int(uv.x * Double(width)), cy = Int((1 - uv.y) * Double(height))
            var sum = 0.0, count = 0.0
            for dy in -half...half {
                for dx in -half...half {
                    let x = ((cx + dx) % width + width) % width
                    let y = min(max(cy + dy, 0), height - 1)
                    let i = (y * width + x) * 4
                    for channel in 0..<3 {
                        sum += SkyDrawing.decode(Double(pixels[i + channel]) / 255) / 3
                    }
                    count += 1
                }
            }
            return sum / count
        }
    }

    private func galaxyMap() throws -> GalaxyMap {
        let image = try XCTUnwrap(SkyDrawing.galaxyMap(),
                                  "the map is not in the bundle — run Tools/galaxymap.swift")
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return GalaxyMap(width: width, height: height, pixels: pixels)
    }

    /// The dome's own coordinates: u along right ascension, v up from the
    /// south pole — what `RenderKit.SkyDome` gives each vertex.
    func testTheMapIsReadWhereTheDomeDrawsIt() {
        let north = SkyDrawing.galaxyCoordinate(rightAscension: 0, declination: .pi / 2)
        XCTAssertEqual(north.y, 1, accuracy: 1e-12)
        let quarter = SkyDrawing.galaxyCoordinate(rightAscension: .pi / 2, declination: 0)
        XCTAssertEqual(quarter.x, 0.25, accuracy: 1e-12)
        XCTAssertEqual(quarter.y, 0.5, accuracy: 1e-12)
    }

    /// The map is the right way round. The Large Magellanic Cloud is at
    /// 5h 24m, −69.8°, and nothing is at its mirror image in right
    /// ascension or in declination; a map flipped either way fails here.
    func testTheGalaxyIsTheRightWayRound() throws {
        let map = try galaxyMap()
        XCTAssertEqual(map.width, 2 * map.height, "plate carrée")
        XCTAssertGreaterThanOrEqual(map.width, 4096)
        let ra = 80.9 * degree, dec = -69.8 * degree
        let cloud = map.light(rightAscension: ra, declination: dec)
        XCTAssertGreaterThan(cloud, 4 * map.light(rightAscension: 2 * .pi - ra, declination: dec),
                             "mirrored in right ascension")
        XCTAssertGreaterThan(cloud, 4 * map.light(rightAscension: ra, declination: -dec),
                             "upside down")
        // The Small Cloud too.
        XCTAssertGreaterThan(map.light(rightAscension: 13.2 * degree, declination: -72.8 * degree),
                             3 * map.light(rightAscension: 346.8 * degree, declination: -72.8 * degree))
    }

    /// The Milky Way lies along the galactic plane as the app's own
    /// frame has it, and the sky off the plane is close to black: the
    /// Sagittarius star cloud against the two galactic poles.
    func testTheMilkyWayLiesAlongTheGalacticPlane() throws {
        let map = try galaxyMap()
        func light(l: Double, b: Double) -> Double {
            let (ra, dec) = CelestialSphere.rightAscensionDeclination(
                of: CelestialSphere.equatorial(galacticLongitude: l * degree, galacticLatitude: b * degree))
            return map.light(rightAscension: ra, declination: dec)
        }
        let north = light(l: 0, b: 89), south = light(l: 0, b: -89)
        XCTAssertGreaterThan(light(l: 13, b: -1), 5 * max(north, south), "the Sagittarius cloud")
        for longitude in stride(from: 0.0, to: 360, by: 30) {
            // Just off the dust: 4° from the plane, either side.
            let plane = max(light(l: longitude, b: 4), light(l: longitude, b: -4))
            XCTAssertGreaterThan(plane, 1.5 * max(north, south), "l = \(longitude)°")
        }
    }

    /// It is drawn dim: the galaxy's brightest cloud under a tenth of
    /// white, the band under the faintest star's own peak, and the sky off
    /// the plane black. This is the number that answers "unnecessary
    /// contrast" (2026-10-24).
    func testTheGalaxyIsDrawnDimmerThanTheFaintestStar() throws {
        let map = try galaxyMap()
        let exposure = Sky.galaxyExposure
        func drawn(_ stored: Double) -> Double { stored / SkyDrawing.galaxyMapGain * exposure }
        let (ra, dec) = CelestialSphere.rightAscensionDeclination(
            of: CelestialSphere.equatorial(galacticLongitude: 13 * degree, galacticLatitude: -1 * degree))
        XCTAssertLessThan(drawn(map.light(rightAscension: ra, declination: dec)), 0.1)
        let (bandRA, bandDec) = CelestialSphere.rightAscensionDeclination(
            of: CelestialSphere.equatorial(galacticLongitude: 200 * degree, galacticLatitude: 3 * degree))
        XCTAssertLessThan(drawn(map.light(rightAscension: bandRA, declination: bandDec)),
                          StellarPhotometry.faintestPeak, "the winter Milky Way, by Orion")
        let (poleRA, poleDec) = CelestialSphere.rightAscensionDeclination(
            of: CelestialSphere.equatorial(galacticLongitude: 0, galacticLatitude: 89 * degree))
        XCTAssertLessThan(drawn(map.light(rightAscension: poleRA, declination: poleDec)), 0.003)
    }
}
