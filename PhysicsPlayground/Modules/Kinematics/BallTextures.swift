//
//  BallTextures.swift
//  Physics Playground — Kinematics module
//
//  Procedural ball textures — no bundled assets: a seamed basketball,
//  a dimple-speckled golf ball, a scuffed iron cannonball. Generated
//  once (512×256 equirectangular CGContext), cached, applied by the
//  renderer as they arrive via the `version` counter.
//

import Foundation
import CoreGraphics
import UIKit
import RealityKit

@MainActor
enum BallTextures {
    private static var cache: [String: TextureResource] = [:]
    private(set) static var version = 0
    private static var warmed = false

    static func texture(for projectileName: String) -> TextureResource? {
        cache[projectileName]
    }

    static func warmUp() {
        guard !warmed else { return }
        warmed = true
        Task {
            for name in ["Basketball", "Golf ball", "Cannonball", "Table-tennis ball", "Custom ball"] {
                guard cache[name] == nil, let image = draw(name) else { continue }
                if let resource = try? await TextureResource(
                    image: image, options: .init(semantic: .color)) {
                    cache[name] = resource
                    version += 1
                }
            }
        }
    }

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

        switch name {
        case "Basketball":
            fill(0.85, 0.4, 0.13)
            context.setStrokeColor(CGColor(red: 0.1, green: 0.08, blue: 0.07, alpha: 1))
            context.setLineWidth(5)
            // Four meridian seams + the equator.
            for fraction in [0.0, 0.25, 0.5, 0.75] {
                context.move(to: CGPoint(x: w * fraction, y: 0))
                context.addLine(to: CGPoint(x: w * fraction, y: h))
            }
            context.move(to: CGPoint(x: 0, y: h / 2))
            context.addLine(to: CGPoint(x: w, y: h / 2))
            context.strokePath()
            // The two curved side seams.
            for offset in [0.32, 0.68] {
                context.move(to: CGPoint(x: 0, y: h * offset))
                for step in 0...64 {
                    let x = w * CGFloat(step) / 64
                    let y = h * offset + sin(CGFloat(step) / 64 * 4 * .pi) * h * 0.09
                    context.addLine(to: CGPoint(x: x, y: y))
                }
                context.strokePath()
            }
            // Pebble grain.
            for _ in 0..<600 {
                let v = CGFloat.random(in: -0.05...0.05)
                context.setFillColor(CGColor(red: 0.85 + v, green: 0.4 + v, blue: 0.13, alpha: 0.5))
                context.fillEllipse(in: CGRect(x: .random(in: 0...w), y: .random(in: 0...h),
                                               width: 2.4, height: 2.4))
            }
        case "Golf ball":
            fill(0.95, 0.95, 0.93)
            // Dimples in a loose hex-ish scatter.
            context.setFillColor(CGColor(red: 0.8, green: 0.8, blue: 0.79, alpha: 0.9))
            for row in 0..<12 {
                for column in 0..<24 {
                    let x = w * CGFloat(column) / 24 + (row % 2 == 0 ? 0 : w / 48)
                    let y = h * CGFloat(row) / 12 + h / 24
                    context.fillEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
                }
            }
        case "Cannonball":
            fill(0.16, 0.16, 0.17)
            for _ in 0..<250 {
                let v = CGFloat.random(in: 0.1...0.3)
                context.setFillColor(CGColor(red: v, green: v, blue: v + 0.02, alpha: 0.6))
                context.fillEllipse(in: CGRect(x: .random(in: 0...w), y: .random(in: 0...h),
                                               width: .random(in: 2...9), height: .random(in: 1...4)))
            }
        case "Table-tennis ball":
            fill(0.97, 0.96, 0.9)
            context.setStrokeColor(CGColor(red: 0.85, green: 0.83, blue: 0.75, alpha: 1))
            context.setLineWidth(2)
            context.move(to: CGPoint(x: 0, y: h * 0.5))
            context.addLine(to: CGPoint(x: w, y: h * 0.5))
            context.strokePath()
        default: // Custom ball
            fill(0.22, 0.55, 0.55)
            for _ in 0..<220 {
                let v = CGFloat.random(in: -0.08...0.08)
                context.setFillColor(CGColor(red: 0.22 + v, green: 0.55 + v, blue: 0.55 + v, alpha: 0.5))
                context.fillEllipse(in: CGRect(x: .random(in: 0...w), y: .random(in: 0...h),
                                               width: .random(in: 3...8), height: .random(in: 3...8)))
            }
        }

        return context.makeImage()
    }
}
