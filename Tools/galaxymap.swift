//
//  galaxymap.swift
//  Physics Playground — Tools
//
//  The light between the naked-eye stars: NASA's Deep Star Maps 2020
//  (NASA/Goddard Space Flight Center Scientific Visualization Studio; Gaia
//  DR2: ESA/Gaia/DPAC — https://svs.gsfc.nasa.gov/4851/), the "milkyway"
//  map, which plots Gaia's stars with the Hipparcos and Tycho stars (those
//  brighter than magnitude 11.5) left out. The app draws the bright stars
//  itself, one by one, from the Yale catalogue; this is everything fainter,
//  summed: the Milky Way's star clouds and dust lanes, both Magellanic
//  Clouds, Andromeda.
//
//      swiftc -O Tools/galaxymap.swift -o <dir>/galaxymap
//      <dir>/galaxymap <dir>/milkyway_2020_4k.exr PhysicsPlayground/Sky/GalaxyMap.heic
//
//  Input:  milkyway_2020_4k.exr (36,436,668 bytes; SHA-256
//          2eb802d6e68d170b410f766c7fec07f7518619f6b6708fdc81e9302d93e74fdb
//          as downloaded on 2026-11-13). 4096 × 2048, linear light, plate
//          carrée in ICRF/J2000 right ascension and declination, centred on
//          0h with right ascension increasing to the LEFT, north at the top.
//  Output: the same light as an 8-bit sRGB image, turned to the sky dome's
//          own layout (`RenderKit.SkyDome`): column x is right ascension
//          2π (x + ½) / width, increasing to the RIGHT, row 0 the north
//          celestial pole: a flip and a half-turn of whole columns. Two
//          things are done to the light, both stated:
//            • it is smoothed over 6′ (`blur`, below), the same angle in
//              every direction on the sphere. Stars this faint cannot be
//              told apart by eye — their sum is a glow — and the map holds
//              11 pixels to the degree where the headset shows 34, so its
//              pixel-to-pixel grain would be drawn three times its size,
//              and near the poles, where a row of 4,096 pixels is a small
//              circle, as streaks. The dust lanes are degrees across and
//              keep their shape;
//            • one gain (`gain`) so the eight bits are spent on the galaxy
//              and not on headroom. How bright the app then draws it is
//              the app's number (`Sky.galaxyExposure`).
//
//  Only the converted file and this script are committed, never the raw map.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The map's linear values times this, clipped at 1, before encoding. The
/// map's brightest star cloud (the Sagittarius cloud, M24) averages 0.30
/// and 99.9 % of its pixels are under 0.40; ×2 keeps both inside the range.
let gain: Float = 2

/// The smoothing, as a Gaussian's standard deviation in the map's own
/// pixels along declination (1.15 px of 5.27′ is 6′) — and that same angle
/// along right ascension, which is 1.15 / cos δ pixels of a row.
let blur: Float = 1.15

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else { fail("usage: galaxymap <milkyway_2020_4k.exr> <out.heic>") }
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let destinationURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read the map") }
let width = image.width, height = image.height
guard width == 2 * height else { fail("not a plate carrée map: \(width) × \(height)") }

// The map as linear floats.
var linear = [Float](repeating: 0, count: width * height * 4)
linear.withUnsafeMutableBytes { raw in
    let info = CGBitmapInfo.byteOrder32Little.rawValue | CGBitmapInfo.floatComponents.rawValue
        | CGImageAlphaInfo.noneSkipLast.rawValue
    guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                  bitsPerComponent: 32, bytesPerRow: width * 16,
                                  space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                                  bitmapInfo: info) else { fail("no float context") }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
}

// Smooth along declination: one Gaussian for every column.
func kernel(_ sigma: Float) -> [Float] {
    let radius = max(Int((3 * sigma).rounded(.up)), 1)
    var weights = (-radius...radius).map { expf(-Float($0 * $0) / (2 * sigma * sigma)) }
    let total = weights.reduce(0, +)
    weights = weights.map { $0 / total }
    return weights
}
do {
    let weights = kernel(blur), radius = weights.count / 2
    var smoothed = linear
    for y in 0..<height {
        for x in 0..<width {
            var sum = SIMD3<Float>.zero
            for k in -radius...radius {
                let i = (min(max(y + k, 0), height - 1) * width + x) * 4
                sum += weights[k + radius] * SIMD3(linear[i], linear[i + 1], linear[i + 2])
            }
            let o = (y * width + x) * 4
            smoothed[o] = sum.x; smoothed[o + 1] = sum.y; smoothed[o + 2] = sum.z
        }
    }
    linear = smoothed
}

// Smooth along right ascension, round the sky, by the same ANGLE: a row at
// declination δ is a circle cos δ as long, so its Gaussian is 1/cos δ as
// wide in pixels. Wide ones (near a pole) are three running means of the
// width that gives the same variance, which is a Gaussian to within a few
// per cent at a cost that does not grow with the width.
do {
    var row = [SIMD3<Float>](repeating: .zero, count: width)
    var scratch = row
    for y in 0..<height {
        let declination = (0.5 - (Float(y) + 0.5) / Float(height)) * .pi
        let sigma = min(blur / max(cos(declination), 1e-4), Float(width) / 4)
        for x in 0..<width {
            let i = (y * width + x) * 4
            row[x] = SIMD3(linear[i], linear[i + 1], linear[i + 2])
        }
        if sigma <= 12 {
            let weights = kernel(sigma), radius = weights.count / 2
            for x in 0..<width {
                var sum = SIMD3<Float>.zero
                for k in -radius...radius {
                    sum += weights[k + radius] * row[((x + k) % width + width) % width]
                }
                scratch[x] = sum
            }
            row = scratch
        } else {
            // Three running means of half-width r: variance 3 · ((2r + 1)² − 1) / 12 = σ².
            let half = min(max(Int(((4 * sigma * sigma + 1).squareRoot() - 1) / 2), 1), width / 2 - 1)
            let span = Float(2 * half + 1)
            for _ in 0..<3 {
                var sum = SIMD3<Float>.zero
                for k in -half...half { sum += row[((k % width) + width) % width] }
                for x in 0..<width {
                    scratch[x] = sum / span
                    sum += row[(x + half + 1) % width] - row[((x - half) % width + width) % width]
                }
                row = scratch
            }
        }
        for x in 0..<width {
            let o = (y * width + x) * 4
            linear[o] = row[x].x; linear[o + 1] = row[x].y; linear[o + 2] = row[x].z
        }
    }
}

/// Linear light → an sRGB byte.
func encode(_ value: Float) -> UInt8 {
    let x = min(max(value, 0), 1)
    let s = x <= 0.0031308 ? 12.92 * x : 1.055 * powf(x, 1 / 2.4) - 0.055
    return UInt8((s * 255).rounded())
}

// Column x of the output is right ascension 2π (x + ½) / W. The map's
// column X is right ascension 2π (½ − (X + ½) / W); so X = W/2 − x − 1.
var pixels = [UInt8](repeating: 255, count: width * height * 4)
for y in 0..<height {
    for x in 0..<width {
        let from = ((width / 2 - x - 1) % width + width) % width
        let i = (y * width + from) * 4, o = (y * width + x) * 4
        pixels[o] = encode(linear[i] * gain)
        pixels[o + 1] = encode(linear[i + 1] * gain)
        pixels[o + 2] = encode(linear[i + 2] * gain)
    }
}

guard let provider = CGDataProvider(data: Data(pixels) as CFData),
      let output = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: true,
                           intent: .defaultIntent),
      let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL,
                                                        UTType.heic.identifier as CFString, 1, nil)
else { fail("cannot write the image") }
CGImageDestinationAddImage(destination, output,
                           [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fail("cannot write \(destinationURL.path)") }
print("\(width) × \(height) → \(destinationURL.lastPathComponent)")
