//
//  OpticsBeamLayout.swift
//  Physics Playground — Light & Optics
//
//  From a trace to what is drawn. Pure functions, so they are tested on
//  numbers.
//
//  Light of several wavelengths travelling the same line is one white
//  beam, not thirteen coloured cylinders fighting for the same pixels: a
//  stretch every colour shares is merged, its colour the sum of theirs.
//  Where a prism has pulled them apart they are drawn apart, each in its
//  own colour. The same for where light lands: one white spot where the
//  whole spectrum arrives together, a rainbow where it arrives fanned.
//
//  How strong a stroke is drawn is its power relative to the strongest
//  light of its wavelength — a weak reflection is faint because it carries
//  four per cent of the beam, not because it was decided to look faint.
//

import Foundation
import PhysicsCore
import RenderKit
import simd

enum OpticsBeamLayout {
    struct Stroke: Equatable {
        var a: SIMD3<Float>
        var b: SIMD3<Float>
        /// Linear RGB, brightest channel 1 — the sum of its wavelengths.
        var color: SIMD3<Double>
        /// 0…1: the power relative to its wavelength's strongest light.
        var strength: Double
        /// Whether it runs through glass.
        var inGlass: Bool
        /// Whether it met nothing, so the drawing fades it out rather than
        /// ending it where the tracer stopped following.
        var fadesOut = false
    }

    struct Spot: Equatable {
        var point: SIMD3<Float>
        var normal: SIMD3<Float>
        var color: SIMD3<Double>
        var strength: Double
    }

    /// The strongest power each wavelength reaches anywhere in the trace —
    /// the light as it left its source.
    static func peaks(_ segments: [LightTracer.Segment]) -> [Double: Double] {
        var peak: [Double: Double] = [:]
        for segment in segments {
            peak[segment.nanometers] = max(peak[segment.nanometers] ?? 0, segment.power)
        }
        return peak
    }

    private struct LineKey: Hashable {
        let a: SIMD3<Int64>, b: SIMD3<Int64>
        init(_ a: SIMD3<Double>, _ b: SIMD3<Double>, grid: Double) {
            self.a = SIMD3<Int64>(a / grid, rounding: .toNearestOrEven)
            self.b = SIMD3<Int64>(b / grid, rounding: .toNearestOrEven)
        }
    }

    /// Every segment as a stroke, with the stretches several wavelengths
    /// share merged into one.
    static func strokes(_ trace: LightTracer.Result, faintest: Double = 0.02) -> [Stroke] {
        let peak = peaks(trace.segments)
        var order: [LineKey] = []
        var groups: [LineKey: (segment: LightTracer.Segment, color: SIMD3<Double>, strength: Double)] = [:]
        for segment in trace.segments {
            guard simd_distance(segment.a, segment.b) > 1e-5 else { continue }
            let strength = segment.power / max(peak[segment.nanometers] ?? segment.power, 1e-12)
            guard strength >= faintest else { continue }
            let key = LineKey(segment.a, segment.b, grid: 1e-4)
            let tint = Spectrum.xyz(nanometers: segment.nanometers) * strength
            if var group = groups[key] {
                group.color += tint
                group.strength = max(group.strength, strength)
                groups[key] = group
            } else {
                order.append(key)
                groups[key] = (segment, tint, strength)
            }
        }
        return order.compactMap { key in
            guard let group = groups[key] else { return nil }
            return Stroke(a: SIMD3<Float>(group.segment.a), b: SIMD3<Float>(group.segment.b),
                          color: Spectrum.linearRGB(xyz: group.color),
                          strength: group.strength, inGlass: group.segment.inside != nil,
                          fadesOut: group.segment.escapes)
        }
    }

    /// Where the light lands, with the spots the whole spectrum shares
    /// merged into one.
    static func spots(_ trace: LightTracer.Result, faintest: Double = 0.02) -> [Spot] {
        let peak = peaks(trace.segments)
        var order: [SIMD3<Int64>] = []
        var groups: [SIMD3<Int64>: (landing: LightTracer.Landing, color: SIMD3<Double>, strength: Double)] = [:]
        for landing in trace.landings {
            let strength = landing.power / max(peak[landing.nanometers] ?? landing.power, 1e-12)
            guard strength >= faintest else { continue }
            let key = SIMD3<Int64>(landing.point / 1e-3, rounding: .toNearestOrEven)
            let tint = Spectrum.xyz(nanometers: landing.nanometers) * strength
            if var group = groups[key] {
                group.color += tint
                group.strength = max(group.strength, strength)
                groups[key] = group
            } else {
                order.append(key)
                groups[key] = (landing, tint, strength)
            }
        }
        return order.compactMap { key in
            guard let group = groups[key] else { return nil }
            return Spot(point: SIMD3<Float>(group.landing.point),
                        normal: SIMD3<Float>(group.landing.normal),
                        color: Spectrum.linearRGB(xyz: group.color),
                        strength: group.strength)
        }
    }

    /// A strength as one of four drawn levels, so the materials a beam can
    /// wear stay a handful rather than one per power.
    static func level(_ strength: Double) -> Float {
        switch strength {
        case 0.5...: 1
        case 0.15...: 0.6
        case 0.05...: 0.35
        default: 0.18
        }
    }
}
