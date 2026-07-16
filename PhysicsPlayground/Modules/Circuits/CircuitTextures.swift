//
//  CircuitTextures.swift
//  Physics Playground — Circuits module
//
//  Procedural resistor textures with the REAL 4-band color code: adjust
//  a resistor's value and its bands repaint to what you'd read on the
//  physical part (two digits, multiplier, gold tolerance). Cached per
//  code; a version counter tells the renderer when fresh ones land.
//

import Foundation
import CoreGraphics
import PhysicsCore
import UIKit
import RealityKit

@MainActor
enum CircuitTextures {
    private static var cache: [String: TextureResource] = [:]
    private static var pending: Set<String> = []
    private(set) static var version = 0

    /// The standard digit colors, 0–9.
    private static let bandColors: [(CGFloat, CGFloat, CGFloat)] = [
        (0.05, 0.05, 0.05),  // black
        (0.45, 0.26, 0.13),  // brown
        (0.82, 0.12, 0.1),   // red
        (0.95, 0.5, 0.1),    // orange
        (0.95, 0.85, 0.2),   // yellow
        (0.15, 0.6, 0.25),   // green
        (0.15, 0.3, 0.85),   // blue
        (0.55, 0.25, 0.7),   // violet
        (0.55, 0.55, 0.55),  // gray
        (0.96, 0.96, 0.96),  // white
    ]

    static func resistorTexture(ohms: Double) -> TextureResource? {
        guard let code = CircuitSolver.colorBands(ohms: ohms) else { return nil }
        let key = "\(code.digit1)-\(code.digit2)-\(code.multiplier)"
        if let cached = cache[key] { return cached }
        if !pending.contains(key) {
            pending.insert(key)
            Task {
                if let image = draw(code),
                   let resource = try? await TextureResource(
                    image: image, options: .init(semantic: .color)) {
                    cache[key] = resource
                    version += 1
                }
            }
        }
        return nil
    }

    private static func draw(_ code: (digit1: Int, digit2: Int, multiplier: Int)) -> CGImage? {
        let size = 128
        guard let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let s = CGFloat(size)

        // The classic tan body.
        context.setFillColor(CGColor(red: 0.85, green: 0.72, blue: 0.55, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: s, height: s))

        // Bands ring the cylinder: horizontal stripes in texture space.
        func band(at fraction: CGFloat, color: (CGFloat, CGFloat, CGFloat)) {
            context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
            context.fill(CGRect(x: 0, y: s * fraction - 6, width: s, height: 12))
        }
        band(at: 0.22, color: bandColors[min(code.digit1, 9)])
        band(at: 0.38, color: bandColors[min(code.digit2, 9)])
        band(at: 0.54, color: bandColors[min(code.multiplier, 9)])
        band(at: 0.78, color: (0.82, 0.66, 0.22))  // gold tolerance

        return context.makeImage()
    }
}
