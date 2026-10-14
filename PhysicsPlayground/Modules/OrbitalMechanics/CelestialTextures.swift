//
//  CelestialTextures.swift
//  Procedural equirectangular textures for every body — generated once off the main path, cached,
//  applied as they arrive via `version`. Each base fill is the body's `celestialUI` colour, so the
//  sphere and the trail behind it are one colour by construction.
//

import Foundation
import CoreGraphics
import UIKit
import RealityKit

@MainActor
enum CelestialTextures {
    private static var cache: [String: TextureResource] = [:]
    /// Bumped as each texture finishes loading; renderers re-apply materials on change.
    private(set) static var version = 0
    private static var warmed = false

    static func texture(for bodyName: String) -> TextureResource? {
        cache[key(for: bodyName)]
    }

    private static func key(for name: String) -> String {
        if name.hasPrefix("Sun") { return "Sun" }
        if name.hasPrefix("Custom") { return "Custom" }
        return name
    }

    static func warmUp() {
        guard !warmed else { return }
        warmed = true
        Task {
            let names = ["Sun", "Mercury", "Venus", "Earth", "Moon", "Mars", "Jupiter",
                         "Saturn", "Uranus", "Neptune", "Asteroid", "Comet", "Custom", "Satellite"]
            for name in names {
                guard cache[name] == nil, let image = draw(name) else { continue }
                if let resource = try? await TextureResource(
                    image: image, options: .init(semantic: .color)) {
                    cache[name] = resource
                    version += 1
                }
            }
        }
    }

    // MARK: Drawing

    private static let width = 512
    private static let height = 256

    private static func draw(_ name: String) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let w = CGFloat(width), h = CGFloat(height)

        func fill(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
            context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        /// The body's own colour from the one table, as the ground everything else is drawn on.
        func base() -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            DesignTokens.Palette.celestialUI(name).getRed(&r, green: &g, blue: &b, alpha: &a)
            fill(r, g, b)
            return (r, g, b)
        }
        func blob(x: CGFloat, y: CGFloat, radius: CGFloat,
                  _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, alpha: CGFloat) {
            context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: alpha))
            context.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                           width: radius * 2, height: radius * 2))
        }
        func speckle(count: Int, radius: ClosedRange<CGFloat>, brightness: ClosedRange<CGFloat>, alpha: CGFloat) {
            for _ in 0..<count {
                let v = CGFloat.random(in: brightness)
                blob(x: .random(in: 0...w), y: .random(in: 0...h),
                     radius: .random(in: radius), v, v, v, alpha: alpha)
            }
        }
        func craters(count: Int, base: CGFloat) {
            for _ in 0..<count {
                let x = CGFloat.random(in: 0...w), y = CGFloat.random(in: 0...h)
                let radius = CGFloat.random(in: 3...16)
                blob(x: x, y: y, radius: radius, base - 0.14, base - 0.14, base - 0.13, alpha: 0.8)
                blob(x: x - radius * 0.25, y: y + radius * 0.25, radius: radius * 0.75,
                     base + 0.08, base + 0.08, base + 0.09, alpha: 0.5)
            }
        }

        switch key(for: name) {
        case "Sun":
            fill(1.0, 0.78, 0.35)
            for _ in 0..<420 {
                let v = CGFloat.random(in: -0.12...0.1)
                blob(x: .random(in: 0...w), y: .random(in: 0...h),
                     radius: .random(in: 3...10), 1.0 + v, 0.75 + v, 0.3 + v * 0.5, alpha: 0.5)
            }
        case "Mercury":
            let ground = base()
            craters(count: 46, base: ground.r)
        case "Venus":
            let ground = base()
            for band in 0..<26 {
                let y = h * CGFloat(band) / 26 + .random(in: -6...6)
                let v = CGFloat.random(in: -0.06...0.06)
                context.setFillColor(CGColor(red: ground.r + v, green: ground.g + v,
                                             blue: ground.b + v, alpha: 0.5))
                context.fill(CGRect(x: 0, y: y, width: w, height: .random(in: 5...14)))
            }
        case "Earth":
            _ = base()
            for _ in 0..<15 {
                let cx = CGFloat.random(in: 0...w), cy = CGFloat.random(in: h * 0.18...h * 0.82)
                for _ in 0..<9 {
                    let green = CGFloat.random(in: 0.32...0.48)
                    blob(x: cx + .random(in: -34...34), y: cy + .random(in: -20...20),
                         radius: .random(in: 8...22), green * 0.8, green, green * 0.45, alpha: 0.9)
                }
            }
            context.setFillColor(CGColor(red: 0.95, green: 0.96, blue: 1.0, alpha: 0.95))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.07))
            context.fill(CGRect(x: 0, y: h * 0.93, width: w, height: h * 0.07))
            for _ in 0..<16 {
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
                context.fillEllipse(in: CGRect(x: .random(in: -20...w), y: .random(in: 0...h),
                                               width: .random(in: 40...110), height: .random(in: 5...12)))
            }
        case "Moon":
            let ground = base()
            craters(count: 40, base: ground.r)
        case "Mars":
            _ = base()
            for _ in 0..<12 {
                blob(x: .random(in: 0...w), y: .random(in: h * 0.2...h * 0.8),
                     radius: .random(in: 12...34), 0.5, 0.26, 0.17, alpha: 0.55)
            }
            context.setFillColor(CGColor(red: 0.96, green: 0.94, blue: 0.9, alpha: 0.95))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.05))
            context.fill(CGRect(x: 0, y: h * 0.95, width: w, height: h * 0.05))
        case "Jupiter":
            let ground = base()
            // Bands lighter and darker than the ground by turns, so the average stays the table's colour.
            let shades: [CGFloat] = [0.10, -0.08, 0.07, -0.12, 0.10, -0.07, 0.06, -0.10, 0.08]
            let bandHeight = h / CGFloat(shades.count)
            for (index, shade) in shades.enumerated() {
                let band = (ground.r + shade, ground.g + shade * 1.1, ground.b + shade * 1.2)
                context.setFillColor(CGColor(red: band.0, green: band.1, blue: band.2, alpha: 1))
                context.fill(CGRect(x: 0, y: CGFloat(index) * bandHeight,
                                    width: w, height: bandHeight + 1))
                for _ in 0..<10 {
                    blob(x: .random(in: 0...w),
                         y: CGFloat(index) * bandHeight + .random(in: -4...4),
                         radius: .random(in: 6...14), band.0, band.1, band.2, alpha: 0.4)
                }
            }
            context.setFillColor(CGColor(red: 0.72, green: 0.3, blue: 0.2, alpha: 0.95))
            context.fillEllipse(in: CGRect(x: w * 0.6, y: h * 0.6, width: 60, height: 30))
        case "Saturn":
            // Pale gold with faint bands. No ring geometry: a ring mesh is a feature, not a texture.
            let ground = base()
            for band in 0..<18 {
                let shade = CGFloat.random(in: -0.05...0.04)
                context.setFillColor(CGColor(red: ground.r + shade, green: ground.g + shade,
                                             blue: ground.b + shade * 0.6, alpha: 0.7))
                context.fill(CGRect(x: 0, y: h * CGFloat(band) / 18, width: w,
                                    height: h / 18 + 1))
            }
        case "Uranus":
            // Near-featureless cyan, one faint band and a polar hood.
            let ground = base()
            context.setFillColor(CGColor(red: ground.r - 0.04, green: ground.g - 0.02,
                                         blue: ground.b, alpha: 0.6))
            context.fill(CGRect(x: 0, y: h * 0.44, width: w, height: h * 0.12))
            context.setFillColor(CGColor(red: ground.r + 0.06, green: ground.g + 0.04,
                                         blue: ground.b + 0.03, alpha: 0.6))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.14))
        case "Neptune":
            // Deep blue, a dark storm and white methane streaks.
            let ground = base()
            for band in 0..<8 {
                let shade = CGFloat.random(in: -0.06...0.05)
                context.setFillColor(CGColor(red: ground.r + shade * 0.5, green: ground.g + shade,
                                             blue: ground.b + shade * 0.3, alpha: 0.6))
                context.fill(CGRect(x: 0, y: h * CGFloat(band) / 8, width: w, height: h / 8 + 1))
            }
            context.setFillColor(CGColor(red: ground.r - 0.1, green: ground.g - 0.12,
                                         blue: ground.b - 0.2, alpha: 0.9))
            context.fillEllipse(in: CGRect(x: w * 0.3, y: h * 0.55, width: 70, height: 34))
            for _ in 0..<6 {
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
                context.fillEllipse(in: CGRect(x: .random(in: -20...w), y: .random(in: h * 0.2...h * 0.5),
                                               width: .random(in: 40...90), height: .random(in: 4...9)))
            }
        case "Comet":
            // Dirty ice: grey-white with darker speckle.
            _ = base()
            speckle(count: 220, radius: 1...4, brightness: 0.55...0.8, alpha: 0.5)
        case "Asteroid":
            let ground = base()
            craters(count: 30, base: ground.r)
            speckle(count: 150, radius: 1...3, brightness: 0.3...0.55, alpha: 0.6)
        case "Satellite":
            fill(0.8, 0.8, 0.82)
            speckle(count: 60, radius: 1...4, brightness: 0.5...0.9, alpha: 0.7)
        default: // Custom
            fill(0.25, 0.6, 0.6)
            speckle(count: 200, radius: 2...6, brightness: 0.45...0.75, alpha: 0.35)
        }

        return context.makeImage()
    }
}
