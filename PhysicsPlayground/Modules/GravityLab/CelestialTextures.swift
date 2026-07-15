//
//  CelestialTextures.swift
//  Physics Playground — Gravity Lab module
//
//  Procedurally generated equirectangular textures for every body — no
//  bundled assets. Banded Jupiter with its red spot, a blotchy blue
//  Earth with polar caps and cloud streaks, cratered Mercury and Moon,
//  Mars with dark maria, granulated Sun. Generated once off the main
//  path (512×256 CGContext each), cached, and applied by the renderer
//  as they arrive (the `version` counter tells it to refresh).
//

import Foundation
import CoreGraphics
import UIKit
import RealityKit

@MainActor
enum CelestialTextures {
    private static var cache: [String: TextureResource] = [:]
    /// Bumped as each texture finishes loading; renderers re-apply
    /// materials when they see it change.
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
            let names = ["Sun", "Mercury", "Venus", "Earth", "Moon",
                         "Mars", "Jupiter", "Asteroid", "Custom", "Satellite"]
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
            fill(0.55, 0.53, 0.5)
            craters(count: 46, base: 0.55)
        case "Venus":
            fill(0.87, 0.76, 0.55)
            for band in 0..<26 {
                let y = h * CGFloat(band) / 26 + .random(in: -6...6)
                let v = CGFloat.random(in: -0.06...0.06)
                context.setFillColor(CGColor(red: 0.87 + v, green: 0.75 + v, blue: 0.5 + v, alpha: 0.5))
                context.fill(CGRect(x: 0, y: y, width: w, height: .random(in: 5...14)))
            }
        case "Earth":
            fill(0.16, 0.35, 0.62)
            // Continent splotches: clusters of overlapping green-brown blobs.
            for _ in 0..<15 {
                let cx = CGFloat.random(in: 0...w), cy = CGFloat.random(in: h * 0.18...h * 0.82)
                for _ in 0..<9 {
                    let green = CGFloat.random(in: 0.32...0.48)
                    blob(x: cx + .random(in: -34...34), y: cy + .random(in: -20...20),
                         radius: .random(in: 8...22), green * 0.8, green, green * 0.45, alpha: 0.9)
                }
            }
            // Polar caps and cloud streaks.
            context.setFillColor(CGColor(red: 0.95, green: 0.96, blue: 1.0, alpha: 0.95))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.07))
            context.fill(CGRect(x: 0, y: h * 0.93, width: w, height: h * 0.07))
            for _ in 0..<16 {
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
                context.fillEllipse(in: CGRect(x: .random(in: -20...w), y: .random(in: 0...h),
                                               width: .random(in: 40...110), height: .random(in: 5...12)))
            }
        case "Moon":
            fill(0.68, 0.67, 0.65)
            craters(count: 40, base: 0.66)
        case "Mars":
            fill(0.78, 0.42, 0.26)
            for _ in 0..<12 {
                blob(x: .random(in: 0...w), y: .random(in: h * 0.2...h * 0.8),
                     radius: .random(in: 12...34), 0.5, 0.26, 0.17, alpha: 0.55)
            }
            context.setFillColor(CGColor(red: 0.96, green: 0.94, blue: 0.9, alpha: 0.95))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.05))
            context.fill(CGRect(x: 0, y: h * 0.95, width: w, height: h * 0.05))
        case "Jupiter":
            fill(0.83, 0.72, 0.55)
            let bands: [(CGFloat, CGFloat, CGFloat)] = [
                (0.9, 0.83, 0.68), (0.72, 0.55, 0.4), (0.87, 0.79, 0.63),
                (0.65, 0.48, 0.36), (0.9, 0.84, 0.7), (0.7, 0.55, 0.42),
                (0.86, 0.78, 0.6), (0.68, 0.5, 0.38), (0.88, 0.82, 0.66),
            ]
            let bandHeight = h / CGFloat(bands.count)
            for (index, band) in bands.enumerated() {
                context.setFillColor(CGColor(red: band.0, green: band.1, blue: band.2, alpha: 1))
                context.fill(CGRect(x: 0, y: CGFloat(index) * bandHeight,
                                    width: w, height: bandHeight + 1))
                // Soften edges with a wandering overlay.
                for _ in 0..<10 {
                    blob(x: .random(in: 0...w),
                         y: CGFloat(index) * bandHeight + .random(in: -4...4),
                         radius: .random(in: 6...14), band.0, band.1, band.2, alpha: 0.4)
                }
            }
            // The Great Red Spot.
            context.setFillColor(CGColor(red: 0.72, green: 0.3, blue: 0.2, alpha: 0.95))
            context.fillEllipse(in: CGRect(x: w * 0.6, y: h * 0.6, width: 60, height: 30))
        case "Asteroid":
            fill(0.42, 0.4, 0.38)
            craters(count: 30, base: 0.42)
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
