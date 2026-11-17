//
//  Sky.swift
//  Physics Playground — Shell
//
//  The real sky (2026-10-19): the 9,096 naked-eye stars of the Yale Bright
//  Star Catalogue at their true positions, each drawn in its own
//  blackbody colour and at a size and brightness set by its magnitude
//  (`PhysicsCore.StellarColour`, `StellarPhotometry`), turned as a winter
//  evening at 40° N with Orion's belt rising ahead (`SkyOrientation.house`).
//
//  Since 2026-11-13 a faint star is a dim point and a bright one a
//  brilliant one in the eye's own glare (the sky had been 8,000 equal
//  dots), and behind them is the light of every star too faint to draw:
//  NASA's Deep Star Maps 2020, Gaia's 1.7 billion stars summed
//  (`Tools/galaxymap.swift` → `Sky/GalaxyMap.heic`) — the Milky Way's
//  star clouds and dust lanes, the Magellanic Clouds, Andromeda, each
//  where and as it is. It is measured light, drawn dim; the smooth model
//  band drawn here until 2026-10-24 (owner: "unnecessary contrast") was
//  neither. Without the map's file the dome is the near-black it was.
//
//  Built once, off the main thread, at launch — beside the prop cache's
//  warm-up, which it never outlasts — and then only ever turned. Deep space
//  stands in it.
//

import CoreGraphics
import Foundation
import ImageIO
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
    /// The light of the stars too faint to draw one by one, opaque — or nil
    /// when the map is not in the bundle, and the dome is `background`.
    let galaxy: UnlitMaterial?

    /// Stars on a sphere this far out — the retired Studio Mode's proven radius, past every
    /// lab and past Orbital Mechanics' 16 m shell — and the dark just behind.
    nonisolated static let starRadius: Float = 45
    nonisolated static let domeRadius: Float = 46

    private init(starCount: Int, starMesh: MeshResource, starMaterial: UnlitMaterial,
                 domeMesh: MeshResource, background: UnlitMaterial, galaxy: UnlitMaterial?) {
        self.starCount = starCount
        self.starMesh = starMesh
        self.starMaterial = starMaterial
        self.domeMesh = domeMesh
        self.background = background
        self.galaxy = galaxy
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

        // The galaxy: the map's light times one number. A tint is a colour,
        // so the linear factor goes in encoded.
        var galaxy: UnlitMaterial?
        let exposure = Sky.galaxyExposure
        if exposure > 0, let map = drawing.galaxyMap,
           let texture = try? await TextureResource(
            image: map, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)) {
            let tint = CGFloat(SkyDrawing.encode(min(exposure / SkyDrawing.galaxyMapGain, 1))) / 255
            var material = UnlitMaterial()
            material.color = .init(tint: UIColor(white: tint, alpha: 1), texture: .init(texture))
            galaxy = material
        }

        #if DEBUG
        let seconds = (ContinuousClock.now - started) / .seconds(1)
        LaunchTrace.mark("sky built: \(drawing.starCount) stars"
                         + (galaxy == nil ? "" : " and the galaxy") + " in "
                         + String(format: "%.2f", seconds) + " s")
        #endif
        return SkyResources(starCount: drawing.starCount,
                            starMesh: starMesh, starMaterial: stars, domeMesh: domeMesh,
                            background: background, galaxy: galaxy)
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

        let dome = ModelEntity(mesh: resources.domeMesh,
                               materials: [resources.galaxy ?? resources.background])
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

    /// How bright the galaxy is drawn: the map's linear light times this.
    /// At 0.25 the brightest star cloud (M24, 0.30 in the map) is drawn at
    /// 0.075 of white and the band between a hundredth and a fortieth —
    /// under the faintest star's own peak (0.05), as a glow no star in it
    /// can be picked out of should be — and the sky off the plane at a
    /// thousandth: black. `-skyGalaxy <exposure>` sets it for a still; 0
    /// draws the plain dome.
    nonisolated static var galaxyExposure: Double {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "skyGalaxy") != nil {
            return max(UserDefaults.standard.double(forKey: "skyGalaxy"), 0)
        }
        #endif
        return 0.25
    }

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
        var starCount: Int
        var galaxyMap: CGImage?
    }

    /// The atlas: a 64-pixel cell per (temperature column, row), 4-pixel
    /// gutters. The first rows are a star's core, one per brightness; the
    /// rows after them are a bright star's glare, one per level.
    static let cell = 64
    static let gutter = 4
    static let atlas = StarField.Atlas(columns: StellarPhotometry.temperatureColumns,
                                       rows: StellarPhotometry.brightnessRows
                                           + StellarPhotometry.glareRows,
                                       gutter: Float(gutter) / Float(cell))
    /// The glare's width at half its level, as a share of its radius: the
    /// sprite is level / (1 + (ρ/0.3)²), brought to nothing at its edge.
    static let glareCore = 0.3
    /// A star's quad half-size over its core's width (FWHM). The mask's core
    /// is exp(−(ρ/0.35)²), ρ = 1 at the quad's edge, so its FWHM is 0.583 of
    /// the half-size; 1/0.583 makes the drawn core exactly the photometric
    /// size, with room round it for the halo.
    static let quadOverCore = 1.715

    static func draw() -> Drawing? {
        guard let url = Bundle.main.url(forResource: "BrightStarCatalog", withExtension: "bin"),
              let data = try? Data(contentsOf: url),
              let catalog = try? StarCatalog.decode(data) else { return nil }
        let geometry = StarField.assemble(glares(catalog) + stars(catalog),
                                          radius: SkyResources.starRadius, atlas: atlas)
        guard let (colour, mask) = atlasImages() else { return nil }
        return Drawing(geometry: geometry, atlasColour: colour, atlasMask: mask,
                       starCount: catalog.count, galaxyMap: galaxyMap())
    }

    /// The map's file, and the gain `Tools/galaxymap.swift` wrote it with.
    static let galaxyMapName = "GalaxyMap"
    static let galaxyMapGain = 2.0

    /// The galaxy's map from the bundle, or nil when it is not there.
    static func galaxyMap() -> CGImage? {
        guard let url = Bundle.main.url(forResource: galaxyMapName, withExtension: "heic"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Where the dome draws the sky toward (α, δ): the map's texture
    /// coordinate there (`RenderKit.SkyDome`), u along right ascension and
    /// v up from the south pole.
    static func galaxyCoordinate(rightAscension: Double, declination: Double) -> SIMD2<Double> {
        SIMD2(rightAscension / (2 * .pi), declination / .pi + 0.5)
    }

    private static func cell(of star: CatalogStar) -> (direction: SIMD3<Float>, column: Int) {
        (SIMD3<Float>(CelestialSphere.equatorial(rightAscension: star.rightAscension,
                                                 declination: star.declination)),
         StellarPhotometry.column(temperature: StellarColour.temperature(bMinusV: star.colourIndex)))
    }

    /// Each catalogue star as a quad: its direction, its size, its cell —
    /// faintest first, so a bright star is drawn over its faint neighbours.
    static func stars(_ catalog: [CatalogStar]) -> [StarField.Star] {
        catalog.sorted { $0.magnitude > $1.magnitude }.map { star in
            let (direction, column) = cell(of: star)
            let core = StellarPhotometry.angularSize(magnitude: star.magnitude)
            return StarField.Star(
                direction: direction,
                halfAngle: Float(core * quadOverCore),
                column: column,
                row: StellarPhotometry.row(
                    brightness: StellarPhotometry.peakBrightness(magnitude: star.magnitude)))
        }
    }

    /// The glare of each star bright enough to show one, as a quad out to
    /// its radius in the star's own colour. Drawn before the stars, so
    /// every core lies over every glare.
    static func glares(_ catalog: [CatalogStar]) -> [StarField.Star] {
        catalog.sorted { $0.magnitude > $1.magnitude }.compactMap { star in
            guard let glare = StellarPhotometry.glare(magnitude: star.magnitude) else { return nil }
            let (direction, column) = cell(of: star)
            return StarField.Star(
                direction: direction,
                halfAngle: Float(glare.radius),
                column: column,
                row: StellarPhotometry.brightnessRows
                    + StellarPhotometry.glareRow(level: glare.level))
        }
    }

    /// The atlas: a colour per cell (a blackbody's, at the column's
    /// temperature) and a mask per cell, zero in the gutters. A core's cell
    /// is the full colour under a soft core and a faint halo whose peak is
    /// the row's brightness. A glare's cell carries its level in the COLOUR
    /// and its shape alone in the mask, dithered: eight bits of opacity
    /// across a veil this faint would otherwise draw rings.
    static func atlasImages() -> (CGImage, CGImage)? {
        let columns = StellarPhotometry.temperatureColumns
        let coreRows = StellarPhotometry.brightnessRows
        let rows = coreRows + StellarPhotometry.glareRows
        let width = columns * cell, height = rows * cell
        var colour = [UInt8](repeating: 255, count: width * height * 4)
        var mask = [UInt8](repeating: 0, count: width * height)
        let usable = Double(cell / 2 - gutter)
        for column in 0..<columns {
            let c = StellarColour.displayColour(
                temperature: StellarPhotometry.temperature(column: column))
            for row in 0..<rows {
                let isGlare = row >= coreRows
                // A glare's colour is the star's, dimmed to its level in
                // linear light.
                let level = isGlare ? StellarPhotometry.glareLevel(row: row - coreRows) : 1
                let rgb = [c.x, c.y, c.z].map { encode(decode($0) * level) }
                let peak = isGlare ? 1 : StellarPhotometry.brightness(row: row)
                for y in 0..<cell {
                    for x in 0..<cell {
                        let px = column * cell + x, py = row * cell + y
                        let i = py * width + px
                        colour[i * 4] = rgb[0]; colour[i * 4 + 1] = rgb[1]; colour[i * 4 + 2] = rgb[2]
                        let dx = Double(x) + 0.5 - Double(cell) / 2
                        let dy = Double(y) + 0.5 - Double(cell) / 2
                        let rho = (dx * dx + dy * dy).squareRoot() / usable
                        guard rho < 1 else { continue }
                        if isGlare {
                            let shape = glareShape(rho)
                            mask[i] = UInt8(min(max((shape * 255 + dither(px, py)).rounded(), 0), 255))
                        } else {
                            let core = exp(-pow(rho / 0.35, 2)), halo = 0.12 * exp(-pow(rho / 0.75, 2))
                            let edge = 1 - smoothstep(0.85, 1, rho)
                            mask[i] = UInt8((min(core + halo, 1) * peak * edge * 255).rounded())
                        }
                    }
                }
            }
        }
        guard let colourImage = image(rgba: colour, width: width, height: height),
              let maskImage = image(gray: mask, width: width, height: height) else { return nil }
        return (colourImage, maskImage)
    }

    /// A glare's opacity at ρ (1 at the quad's edge): 1 / (1 + (ρ/0.3)²)
    /// — the eye's 1/θ² veil, finite at the star — times (1 − ρ²)², which
    /// brings it and its slope to nothing at the edge.
    static func glareShape(_ rho: Double) -> Double {
        guard rho < 1 else { return 0 }
        let window = (1 - rho * rho) * (1 - rho * rho)
        return window / (1 + (rho / glareCore) * (rho / glareCore))
    }

    /// A fixed ±½ level of noise per pixel, so a slow ramp rounds to a mix
    /// of two neighbouring levels and not to a step.
    static func dither(_ x: Int, _ y: Int) -> Double {
        let h = sin(Double(x) * 127.1 + Double(y) * 311.7) * 43758.5453
        return h - h.rounded(.down) - 0.5
    }

    /// The space between the stars: not quite black, in linear light.
    static let background = SIMD3<Double>(0.0035, 0.0040, 0.0070)

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// An sRGB value, 0…1 → linear light.
    static func decode(_ s: Double) -> Double {
        s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
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
