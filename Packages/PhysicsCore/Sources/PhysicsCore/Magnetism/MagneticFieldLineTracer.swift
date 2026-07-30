//
//  MagneticFieldLineTracer.swift
//  PhysicsCore — Magnetism
//
//  Magnetic field lines are streamlines of B. Unlike electric lines they
//  form CLOSED LOOPS (no monopoles): a line leaving the north pole curves
//  back to the south. So each seed is traced BOTH ways along B and the two
//  halves joined into one continuous loop. The RK4 integration is Math's
//  shared StreamlineTracer; this file owns only the magnetism policy.
//

import Foundation
import simd

public enum MagneticFieldLineTracer {
    public struct Config: Sendable {
        public var stepSize = 0.01
        public var maxSteps = 260
        /// Seeds start this far from the magnet centre…
        public var seedRadius = 0.06
        /// …and a line ends when it comes this close to any magnet centre.
        public var terminationRadius = 0.05
        public var boundsCenter: SIMD3<Double> = .zero
        public var boundsRadius = 1.1
        public var seedsPerMagnet = 12

        public init() {}

        var streamlineConfig: StreamlineTracer.Config {
            var config = StreamlineTracer.Config()
            config.stepSize = stepSize
            config.maxSteps = maxSteps
            config.stopRadius = terminationRadius
            config.boundsCenter = boundsCenter
            config.boundsRadius = boundsRadius
            return config
        }
    }

    /// Traces looping field lines for the given magnets. Each returned line
    /// is a polyline spaced ~stepSize apart.
    /// The both-ways trace and the splice are
    /// `StreamlineTracer.loopedLines`, shared with the electric tracer;
    /// what stays here is the magnetism policy — every magnet seeds the
    /// same number of lines, because a dipole moment has no equivalent of
    /// the charge-density rule that scales the electric bundle.
    public static func trace(magnets: [BarMagnet], config: Config) -> [[SIMD3<Double>]] {
        guard !magnets.isEmpty else { return [] }
        return StreamlineTracer.loopedLines(
            from: magnets.map {
                StreamlineTracer.Seeded(position: $0.position,
                                        seeds: config.seedsPerMagnet)
            },
            seedRadius: config.seedRadius,
            stopCenters: magnets.map(\.position),
            config: config.streamlineConfig,
            field: { MagneticField.vector(at: $0, dueTo: magnets) })
    }
}
