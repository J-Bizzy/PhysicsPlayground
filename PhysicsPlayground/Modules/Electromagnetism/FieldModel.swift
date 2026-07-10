//
//  FieldModel.swift
//  Physics Playground — Electromagnetism module
//
//  The single source of truth for app state, shared between the SwiftUI
//  control window, the in-space panels, and the immersive scene. It owns the
//  charges and probe (physics domain) plus UI state like selection.
//
//  @Observable means SwiftUI views — and the renderer's observation loop —
//  automatically re-run when any property they read changes.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class FieldModel {
    // MARK: Sampling region
    // Immersive-space coordinates: origin is on the floor where the user
    // launched the space, +Y is up, -Z is straight ahead.

    /// Where the field visualization lives when there are no charges, and
    /// where the first charge spawns: chest height, a meter in front.
    nonisolated static let regionCenter = SIMD3<Double>(0, 1.3, -1.0)
    nonisolated static let regionExtent = 0.9
    nonisolated static let pointsPerAxis = 7
    /// Margin added around the charges' bounding box.
    nonisolated static let regionMargin = 0.35
    /// Sample points never go below this height (no arrows in the floor).
    nonisolated static let regionFloor = 0.05

    nonisolated static let defaultMagnitude = 1e-6  // 1 µC
    nonisolated static let floorClearance = 0.15    // charges can't be dragged below this height

    // MARK: Probe (test charge) constants — real SI values, sized so the
    // acceleration is a visible ~0.1–2 m/s² at tabletop distances.
    nonisolated static let probeChargeMagnitude = 1e-8              // 10 nC
    nonisolated static let probeMass = 5e-4                         // 0.5 g
    /// Probe freezes when it gets this close to a source charge ("captured").
    nonisolated static let probeCaptureRadius = 0.045
    /// …or this far from the region center ("escaped to infinity").
    nonisolated static let probeEscapeDistance = 2.0

    /// The box the arrows sample, following the charges wherever they go.
    nonisolated struct SamplingRegion: Equatable {
        var center: SIMD3<Double>
        var extents: SIMD3<Double>
    }

    // MARK: Charges
    var charges: [PointCharge]

    /// The charge the sliders edit — the last one added or grabbed.
    var selectedChargeID: UUID?

    // MARK: Probe state
    enum ProbeStatus: Equatable {
        case none, running, held, captured, escaped
    }
    var probe: TestChargeDynamics.ProbeState?
    var probeStatus: ProbeStatus = .none
    /// Polarity of the test charge — flippable live, even mid-flight.
    var probeIsPositive = true

    /// Signed probe charge in Coulombs.
    var probeCharge: Double {
        (probeIsPositive ? 1 : -1) * Self.probeChargeMagnitude
    }

    // MARK: Display options
    var showArrows = true
    var showLines = true
    var showEquipotentials = true

    /// Counts placements so each new charge lands at a different spot.
    private var placementIndex = 1

    init() {
        charges = []
        reset()
    }

    /// Returns the module to its freshly-entered state: one positive charge
    /// at the home center, no probe, all display layers on. Wired to the
    /// shell's Reset button through the module descriptor.
    func reset() {
        let first = PointCharge(position: Self.regionCenter, charge: Self.defaultMagnitude)
        charges = [first]
        selectedChargeID = first.id
        probe = nil
        probeStatus = .none
        probeIsPositive = true
        showArrows = true
        showLines = true
        showEquipotentials = true
        placementIndex = 1
    }

    var selectedCharge: PointCharge? {
        charges.first { $0.id == selectedChargeID }
    }

    // MARK: Region

    /// Bounding box of all charges, inflated by the margin, never smaller
    /// than the default cube, and clamped out of the floor. Derived state:
    /// moving a charge moves the region, and the observation loop repositions
    /// the arrows automatically.
    var samplingRegion: SamplingRegion {
        guard let first = charges.first else {
            return SamplingRegion(
                center: Self.regionCenter,
                extents: SIMD3(repeating: Self.regionExtent)
            )
        }
        var lower = first.position
        var upper = first.position
        for charge in charges.dropFirst() {
            lower = simd_min(lower, charge.position)
            upper = simd_max(upper, charge.position)
        }
        lower -= SIMD3(repeating: Self.regionMargin)
        upper += SIMD3(repeating: Self.regionMargin)

        // Grow to the minimum cube, symmetrically around the charges.
        let deficit = simd_max(SIMD3(repeating: Self.regionExtent) - (upper - lower), .zero)
        lower -= deficit / 2
        upper += deficit / 2

        // Keep arrows out of the floor.
        lower.y = max(lower.y, Self.regionFloor)
        upper.y = max(upper.y, lower.y + Self.regionExtent / 2)

        return SamplingRegion(center: (lower + upper) / 2, extents: upper - lower)
    }

    /// The current uniform grid of sample points inside `samplingRegion`.
    var samplePoints: [SIMD3<Double>] {
        let region = samplingRegion
        let n = Self.pointsPerAxis
        let spacing = region.extents / Double(n - 1)
        let origin = region.center - region.extents / 2
        var points: [SIMD3<Double>] = []
        points.reserveCapacity(n * n * n)
        for i in 0..<n {
            for j in 0..<n {
                for k in 0..<n {
                    points.append(origin + spacing * SIMD3<Double>(Double(i), Double(j), Double(k)))
                }
            }
        }
        return points
    }

    // MARK: Charge mutations

    /// Adds a charge near the region center, walking around a ring (golden
    /// angle) so successive charges don't stack on top of each other.
    func addCharge(positive: Bool) {
        let angle = Double(placementIndex) * 2.399963
        let ringRadius = 0.22
        let center = samplingRegion.center
        let offset = SIMD3<Double>(cos(angle) * ringRadius, sin(angle) * 0.08, sin(angle) * ringRadius)
        let charge = PointCharge(
            position: center + offset,
            charge: (positive ? 1 : -1) * Self.defaultMagnitude
        )
        charges.append(charge)
        selectedChargeID = charge.id
        placementIndex += 1
    }

    func removeSelectedCharge() {
        guard let id = selectedChargeID else { return }
        charges.removeAll { $0.id == id }
        selectedChargeID = charges.last?.id
    }

    func removeAllCharges() {
        charges.removeAll()
        selectedChargeID = nil
    }

    func moveCharge(id: UUID, to position: SIMD3<Double>) {
        guard let index = charges.firstIndex(where: { $0.id == id }) else { return }
        var clamped = position
        clamped.y = max(clamped.y, Self.floorClearance)
        charges[index].position = clamped
    }

    func select(id: UUID) {
        guard charges.contains(where: { $0.id == id }) else { return }
        selectedChargeID = id
    }

    // MARK: Probe lifecycle

    /// Drops (or re-drops) the test charge slightly above and beside the
    /// region center, at rest, and starts the simulation.
    func dropProbe() {
        let center = samplingRegion.center
        probe = TestChargeDynamics.ProbeState(position: center + SIMD3(0.12, 0.24, 0))
        probeStatus = .running
    }

    func removeProbe() {
        probe = nil
        probeStatus = .none
    }

    /// Called while the user drags the probe: it follows the hand with no
    /// momentum, and the simulation waits.
    func holdProbe(at position: SIMD3<Double>) {
        var clamped = position
        clamped.y = max(clamped.y, Self.floorClearance)
        probe = TestChargeDynamics.ProbeState(position: clamped)
        probeStatus = .held
    }

    /// Called when the user releases the probe: resume from rest there.
    func releaseProbe() {
        guard probe != nil else { return }
        probeStatus = .running
    }

    /// Advances the simulation by one frame. Substepped velocity Verlet, so
    /// accuracy doesn't ride on the display frame rate.
    func stepProbe(dt: Double) {
        guard probeStatus == .running, var state = probe, !charges.isEmpty else { return }

        // A stalled frame (app paused, debugger…) must not become one giant
        // physics leap.
        let frameDt = min(dt, 1.0 / 30.0)
        state = TestChargeDynamics.step(
            state,
            chargeToMassRatio: probeCharge / Self.probeMass,
            dt: frameDt,
            substeps: 4
        ) { [charges] point in
            ElectricField.vector(at: point, dueTo: charges)
        }

        // Landed on a source charge: field lines end here, and so does the ride.
        if charges.contains(where: { simd_distance($0.position, state.position) < Self.probeCaptureRadius }) {
            probeStatus = .captured
        } else if simd_distance(state.position, samplingRegion.center) > Self.probeEscapeDistance {
            // Off to infinity, as a real unbound charge would be.
            probeStatus = .escaped
        } else if state.position.y < Self.regionFloor {
            state.position.y = Self.regionFloor
            probeStatus = .captured
        }
        probe = state
    }

    /// Live physics numbers at the probe's location, for the stats panel.
    struct ProbeReadout {
        var fieldMagnitude: Double   // N/C
        var potential: Double        // V
        var forceMagnitude: Double   // N
        var acceleration: Double     // m/s²
        var speed: Double            // m/s
    }

    var probeReadout: ProbeReadout? {
        guard let probe else { return nil }
        let fieldMagnitude = ElectricField.magnitude(at: probe.position, dueTo: charges)
        let force = Self.probeChargeMagnitude * fieldMagnitude
        return ProbeReadout(
            fieldMagnitude: fieldMagnitude,
            potential: ElectricField.potential(at: probe.position, dueTo: charges),
            forceMagnitude: force,
            acceleration: force / Self.probeMass,
            speed: simd_length(probe.velocity)
        )
    }

    // MARK: Selected-charge bindings for the control panels

    var selectedMagnitudeMicroCoulombs: Double {
        get { selectedCharge?.magnitudeMicroCoulombs ?? 1 }
        set {
            guard let index = charges.firstIndex(where: { $0.id == selectedChargeID }) else { return }
            let sign: Double = charges[index].isPositive ? 1 : -1
            charges[index].charge = sign * newValue * 1e-6
        }
    }

    var selectedIsPositive: Bool {
        get { selectedCharge?.isPositive ?? true }
        set {
            guard let index = charges.firstIndex(where: { $0.id == selectedChargeID }) else { return }
            charges[index].charge = (newValue ? 1 : -1) * abs(charges[index].charge)
        }
    }

    /// Offset of the selected charge from the fixed home center, for the
    /// fallback position sliders.
    var selectedOffset: SIMD3<Double> {
        get { (selectedCharge?.position ?? Self.regionCenter) - Self.regionCenter }
        set {
            guard let id = selectedChargeID else { return }
            moveCharge(id: id, to: Self.regionCenter + newValue)
        }
    }
}
