//
//  Sky.swift
//  Physics Playground — Shell
//
//  The real sky (2026-10-19): the 9,096 naked-eye stars of the Yale Bright
//  Star Catalogue at their true positions, each drawn in its own
//  blackbody colour and at a size and brightness set by its magnitude
//  (`PhysicsCore.StellarColour`, `StellarPhotometry`), over the near-black
//  of space, turned as a winter evening at 40° N with Orion's belt rising
//  ahead (`SkyOrientation.house`). The Milky Way's band was drawn behind
//  them until 2026-10-24 (owner: "unnecessary contrast").
//
//  Built once, off the main thread, at launch — beside the prop cache's
//  warm-up, which it never outlasts — and then only ever turned. Deep space
//  stands in it.
//

import CoreGraphics
import Foundation
import PhysicsCore
import RealityKit
import RenderKit
import simd
import UIKit

/// The sky's drawable parts, made once.
@MainActor
final class SkyResources {
    static private(set) var shared: SkyResources?
    private static var building: Task<SkyResources?, Never>?

    let starCount: Int
    let starMesh: MeshResource
    let starMaterial: UnlitMaterial
    let domeMesh: MeshResource
    /// The space between the stars, opaque: the sky IS the surroundings.
    let background: UnlitMaterial

    /// Stars on a sphere this far out — the retired Studio Mode's proven radius, past every
    /// lab and past Orbital Mechanics' 16 m shell — and the dark just behind.
    nonisolated static let starRadius: Float = 45
    nonisolated static let domeRadius: Float = 46

    private init(starCount: Int, starMesh: MeshResource, starMaterial: UnlitMaterial,
                 domeMesh: MeshResource, background: UnlitMaterial) {
        self.starCount = starCount
        self.starMesh = starMesh
        self.starMaterial = starMaterial
        self.domeMesh = domeMesh
        self.background = background
    }

    /// Builds the sky once; every later call returns the same one.
    static func prepare() async -> SkyResources? {
        if let shared { return shared }
        if building == nil { building = Task { await build() } }
        let made = await building?.value
        shared = made
        return made
    }

    private static func build() async -> SkyResources? {
        #if DEBUG
        let started = ContinuousClock.now
        #endif
        let drawing = await Task.detached(priority: .userInitiated) { SkyDrawing.draw() }.value
        guard let drawing,
              let colour = try? await TextureResource(
                image: drawing.atlasColour,
                options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)),
              let mask = try? await TextureResource(
                image: drawing.atlasMask,
                options: .init(semantic: .raw, mipmapsMode: .allocateAndGenerateAll)),
              let starMesh = StarField.mesh(drawing.geometry),
              let domeMesh = SkyDome.mesh(radius: domeRadius) else { return nil }

        var stars = UnlitMaterial()
        stars.color = .init(tint: .white, texture: .init(colour))
        stars.blending = .transparent(opacity: .init(scale: 1, texture: .init(mask)))
        stars.writesDepth = false

        let dark = SkyDrawing.background
        func byte(_ linear: Double) -> CGFloat { CGFloat(SkyDrawing.encode(linear)) / 255 }
        let background = Materials.unlit(UIColor(red: byte(dark.x), green: byte(dark.y),
                                                 blue: byte(dark.z), alpha: 1))

        #if DEBUG
        let seconds = (ContinuousClock.now - started) / .seconds(1)
        LaunchTrace.mark("sky built: \(drawing.geometry.vertices.count / 4) stars in "
                         + String(format: "%.2f", seconds) + " s")
        #endif
        return SkyResources(starCount: drawing.geometry.vertices.count / 4,
                            starMesh: starMesh, starMaterial: stars, domeMesh: domeMesh,
                            background: background)
    }
}

/// The sky as one entity.
enum Sky {
    /// The instant the sky stands for: a December evening. The stars do not
    /// move on any scale the app could show; the Sun's place, seen from
    /// Pluto's distance, is computed for this date.
    nonisolated static let epoch = MeanElements.julianDate(year: 2026, month: 12, day: 15)

    /// Eye height: the sky's centre, so a star's direction is its direction
    /// from the wearer's eyes, not their feet.
    static let centre = SIMD3<Float>(0, 1.5, 0)

    /// The sky turned into the room: the opaque surroundings. The stars take
    /// order `lastOrder` in `group`, so a caller can draw its own transparent
    /// parts after them.
    static func make(resources: SkyResources,
                     group: ModelSortGroup = ModelSortGroup(depthPass: nil)) -> Entity {
        let root = Entity()
        root.name = "sky"
        root.position = centre
        root.orientation = orientation

        let dome = ModelEntity(mesh: resources.domeMesh, materials: [resources.background])
        dome.name = "sky-dome"
        // Opaque and left out of the group, so it is drawn with the opaque
        // pass, first: sorted, it was drawn late, and any transparent part
        // that writes depth (Orbital's Sun glow) cut a hole through it to
        // whatever lay beyond.
        root.addChild(dome)

        let stars = ModelEntity(mesh: resources.starMesh, materials: [resources.starMaterial])
        stars.name = "sky-stars"
        stars.components.set(ModelSortGroupComponent(group: group, order: lastOrder))
        root.addChild(stars)
        return root
    }

    /// The sort order the stars take; a caller's parts come after it.
    static let lastOrder: Int32 = 1

    /// The house evening — or, for a still, the sky turned so a named target
    /// stands ahead 8° up — inside the simulator camera's frame, which ends about 12° up (`-skyLook orion|polaris|core|cygnus|zenith|sun`).
    static var orientation: simd_quatf {
        let house = simd_quatd(SkyOrientation.house.matrix)
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "skyLook"),
           let target = lookTarget(named: name) {
            let ahead = SIMD3<Double>(0, sin(8 * Double.pi / 180), -cos(8 * Double.pi / 180))
            let from = SkyOrientation.house.world(target)
            return single(simd_quatd(from: simd_normalize(from), to: ahead) * house)
        }
        #endif
        return single(house)
    }

    private static func single(_ q: simd_quatd) -> simd_quatf {
        simd_quatf(vector: SIMD4<Float>(q.vector))
    }

    #if DEBUG
    private static func lookTarget(named name: String) -> SIMD3<Double>? {
        let degree = Double.pi / 180
        switch name {
        case "orion": return CelestialSphere.equatorial(
            rightAscension: SkyOrientation.alnilam.rightAscension,
            declination: SkyOrientation.alnilam.declination)
        case "polaris": return CelestialSphere.equatorial(rightAscension: 37.9529 * degree,
                                                          declination: 89.2642 * degree)
        case "core": return CelestialSphere.equatorial(galacticLongitude: 0, galacticLatitude: 0)
        case "cygnus": return CelestialSphere.equatorial(rightAscension: 310.3580 * degree,
                                                         declination: 45.2803 * degree)
        case "zenith": return SkyOrientation.house.matrix.transpose * SIMD3(0, 1, 0)
        case "sun": return MeanElements.pluto.sunSeen(julianDate: epoch).direction
        default: return nil
        }
    }
    #endif
}

// MARK: - Drawing, off the main thread

nonisolated enum SkyDrawing {
    struct Drawing: @unchecked Sendable {
        var geometry: StarField.Geometry
        var atlasColour: CGImage
        var atlasMask: CGImage
    }

    /// The atlas: a 64-pixel cell per (temperature column, brightness row),
    /// 4-pixel gutters.
    static let cell = 64
    static let gutter = 4
    static let atlas = StarField.Atlas(columns: StellarPhotometry.temperatureColumns,
                                       rows: StellarPhotometry.brightnessRows,
                                       gutter: Float(gutter) / Float(cell))
    /// A star's quad half-size over its core's width (FWHM). The mask's core
    /// is exp(−(ρ/0.35)²), ρ = 1 at the quad's edge, so its FWHM is 0.583 of
    /// the half-size; 1/0.583 makes the drawn core exactly the photometric
    /// size, with room round it for the halo.
    static let quadOverCore = 1.715

    static func draw() -> Drawing? {
        guard let url = Bundle.main.url(forResource: "BrightStarCatalog", withExtension: "bin"),
              let data = try? Data(contentsOf: url),
              let catalog = try? StarCatalog.decode(data) else { return nil }
        let geometry = StarField.assemble(stars(catalog), radius: SkyResources.starRadius, atlas: atlas)
        guard let (colour, mask) = atlasImages() else { return nil }
        return Drawing(geometry: geometry, atlasColour: colour, atlasMask: mask)
    }

    /// Each catalogue star as a quad: its direction, its size, its cell.
    static func stars(_ catalog: [CatalogStar]) -> [StarField.Star] {
        catalog.map { star in
            let direction = CelestialSphere.equatorial(rightAscension: star.rightAscension,
                                                       declination: star.declination)
            let core = StellarPhotometry.angularSize(magnitude: star.magnitude)
            return StarField.Star(
                direction: SIMD3<Float>(direction),
                halfAngle: Float(core * quadOverCore),
                column: StellarPhotometry.column(
                    temperature: StellarColour.temperature(bMinusV: star.colourIndex)),
                row: StellarPhotometry.row(
                    brightness: StellarPhotometry.peakBrightness(magnitude: star.magnitude)))
        }
    }

    /// The atlas: a flat colour per column (a blackbody's, at the column's
    /// temperature) and a mask per cell — a soft core and a faint halo, its
    /// peak the row's brightness, zero in the gutters.
    static func atlasImages() -> (CGImage, CGImage)? {
        let columns = StellarPhotometry.temperatureColumns, rows = StellarPhotometry.brightnessRows
        let width = columns * cell, height = rows * cell
        var colour = [UInt8](repeating: 255, count: width * height * 4)
        var mask = [UInt8](repeating: 0, count: width * height)
        let usable = Double(cell / 2 - gutter)
        for column in 0..<columns {
            let c = StellarColour.displayColour(
                temperature: StellarPhotometry.temperature(column: column))
            let rgb = [c.x, c.y, c.z].map { UInt8((min(max($0, 0), 1) * 255).rounded()) }
            for row in 0..<rows {
                let peak = StellarPhotometry.brightness(row: row)
                for y in 0..<cell {
                    for x in 0..<cell {
                        let px = column * cell + x, py = row * cell + y
                        let i = py * width + px
                        colour[i * 4] = rgb[0]; colour[i * 4 + 1] = rgb[1]; colour[i * 4 + 2] = rgb[2]
                        let dx = Double(x) + 0.5 - Double(cell) / 2
                        let dy = Double(y) + 0.5 - Double(cell) / 2
                        let rho = (dx * dx + dy * dy).squareRoot() / usable
                        guard rho < 1 else { continue }
                        let core = exp(-pow(rho / 0.35, 2)), halo = 0.12 * exp(-pow(rho / 0.75, 2))
                        let edge = 1 - smoothstep(0.85, 1, rho)
                        mask[i] = UInt8((min(core + halo, 1) * peak * edge * 255).rounded())
                    }
                }
            }
        }
        guard let colourImage = image(rgba: colour, width: width, height: height),
              let maskImage = image(gray: mask, width: width, height: height) else { return nil }
        return (colourImage, maskImage)
    }

    /// The space between the stars: not quite black, in linear light.
    static let background = SIMD3<Double>(0.0035, 0.0040, 0.0070)

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Linear light → an sRGB byte.
    static func encode(_ c: Double) -> UInt8 {
        let x = min(max(c, 0), 1)
        let s = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        return UInt8((s * 255).rounded())
    }

    static func image(rgba pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    static func image(gray pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
