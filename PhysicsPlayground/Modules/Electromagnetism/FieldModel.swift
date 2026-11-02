//
//  FieldModel.swift
//  Physics Playground — Electromagnetism module
//
//  Single source of truth: the charges and probe (physics) plus UI state
//  like selection, shared between the SwiftUI window and the immersive scene.
//  @Observable: views and the renderer's observation loop re-run on change.
//

import Foundation
import Observation
import PhysicsCore
import simd

private extension Double {
    /// Guards divide-by-zero in display-only ratios.
    var replacingZero: Double { abs(self) < 1e-30 ? 1e-30 : self }
}

@MainActor
@Observable
final class FieldModel {
    // MARK: Sampling region
    // Immersive-space coordinates: origin on the floor where the user
    // launched the space, +Y up, −Z ahead.

    /// Where the field visualization lives when there are no charges, and
    /// where the first charge spawns: chest height, just ahead. The
    /// region follows the charges, so dragging them apart spreads the
    /// field across the whole room.
    nonisolated static let regionCenter = SIMD3<Double>(0, 1.35, -0.9)
    nonisolated static let regionExtent = 1.3
    nonisolated static let pointsPerAxis = 7
    /// Margin added around the charges' bounding box.
    nonisolated static let regionMargin = 0.45
    /// Sample points never go below this height (no arrows in the floor).
    nonisolated static let regionFloor = 0.05

    /// The station's nominal volume: where reset lays the dipole out and
    /// where the instruments take their clearance bearings
    /// (`FieldInstrumentLayout` keeps every collider `stationMargin` clear
    /// of it). Not a wall; the free simulation's safety bound is separate.
    nonisolated static let regionHalfExtents = SIMD3<Double>(0.76, 1.20, 0.62)

    /// The free simulation's safety bounds — room-scale, never applied
    /// to a hand.
    nonisolated static let safetyHalfExtents = SIMD3<Double>(2.6, 1.6, 2.6)

    /// Clamps a free-drifting point into the room-scale safety box.
    nonisolated static func clampToRoomSafety(
        _ point: SIMD3<Double>
    ) -> SIMD3<Double> {
        var clamped = simd_clamp(point,
                                 regionCenter - safetyHalfExtents,
                                 regionCenter + safetyHalfExtents)
        clamped.y = max(clamped.y, floorClearance)
        return clamped
    }

    nonisolated static let defaultMagnitude = 1e-6  // 1 µC
    nonisolated static let floorClearance = 0.15    // charges can't be dragged below this height

    // MARK: Probe (test charge) constants — real SI values, sized so the
    // acceleration is a visible ~0.1–2 m/s² at tabletop distances.
    nonisolated static let defaultProbeCharge = 1e-8                // 10 nC
    nonisolated static let probeChargeRange = 1e-9...5e-8           // 1…50 nC
    /// The round values the test charge's bead clicks into, C.
    nonisolated static let probeChargeDetents = [1e-9, 2e-9, 5e-9, 1e-8, 2e-8, 5e-8]
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
    nonisolated enum ProbeStatus: Equatable {
        case none, running, held, captured, escaped
    }
    var probe: TestChargeDynamics.ProbeState?
    var probeStatus: ProbeStatus = .none
    /// Polarity of the test charge — flippable live, even mid-flight.
    var probeIsPositive = true

    /// The test charge's magnitude, C — bigger charge, bigger F = qE.
    var probeChargeMagnitude = FieldModel.defaultProbeCharge

    var probeCharge: Double {
        (probeIsPositive ? 1 : -1) * probeChargeMagnitude
    }

    // MARK: Display options
    var showLines = true
    /// The equipotential surfaces: off until asked for, so the room opens on
    /// the lines alone.
    var showEquipotentials = false

    /// Surfaces of equal potential at equal steps of voltage, so where they
    /// crowd the field is strong. The step is a round 1-2-5 number of volts,
    /// a quarter of the potential just outside the strongest charge's ball;
    /// three surfaces round each sign of charge — two, three and four steps
    /// out, the crowded inner ones, since the one-step surface is the
    /// largest and so the dearest to draw (2026-10-16) — and the 0 V
    /// surface when both signs are here.
    /// Point charges only: the capacitor's potential is a line integral per
    /// point, too dear for a grid, and its gap has its own field lines.
    nonisolated static func equipotentialLevels(_ charges: [PointCharge])
        -> (step: Double, levels: [Double]) {
        guard let strongest = charges.map({ abs($0.charge) }).max(), strongest > 0 else {
            return (0, [])
        }
        let near = ElectricField.k * strongest / 0.08
        let step = roundStep(near / 4)
        var levels: [Double] = []
        let hasPositive = charges.contains { $0.charge > 0 }
        let hasNegative = charges.contains { $0.charge < 0 }
        for index in 2...4 {
            if hasPositive { levels.append(Double(index) * step) }
            if hasNegative { levels.append(-Double(index) * step) }
        }
        if hasPositive && hasNegative { levels.append(0) }
        return (step, levels)
    }

    /// The largest 1, 2 or 5 times a power of ten not above `value`.
    nonisolated static func roundStep(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        let power = pow(10, floor(log10(value)))
        let mantissa = value / power
        let nice: Double = mantissa >= 5 ? 5 : mantissa >= 2 ? 2 : 1
        return nice * power
    }

    /// Clamps to `probeChargeRange`, so a hand that keeps pulling past the
    /// end of the bead's rail pins there instead of running off the scale.
    func setProbeMagnitude(_ coulombs: Double) {
        probeChargeMagnitude = min(max(coulombs, Self.probeChargeRange.lowerBound),
                                   Self.probeChargeRange.upperBound)
    }

    // MARK: Parallel-plate capacitor

    /// Two square plates bracketing the region: left (−x) positive, right
    /// (+x) negative — real finite plates (`PlateField.Capacitor`), so the
    /// field fringes, and the plate charge is calibrated so the line
    /// integral across the gap equals the set ΔV.
    var capacitorOn = false
    /// Plate voltage difference, V. kV-scale, like a real demo bench.
    var plateVoltage = 20_000.0
    /// Where the gap's midpoint sits — grab a plate to carry it.
    var capacitorCenter = SIMD3<Double>(0, 1.3, -1.0)
    /// Gap width, m — grab a plate and pull; the calibration follows.
    var plateSeparation = 0.44
    /// How far the dielectric slab is slid in, 0 (parked clear of the −z
    /// edge) … 1 (covering the plate): C rises toward κ·C₀ and the plate
    /// charge visibly crowds under the slab.
    var dielectricCoverage = 0.0
    nonisolated static let plateSize = 0.5
    nonisolated static let plateVoltageRange = 2_000.0...40_000.0
    nonisolated static let plateSeparationRange = 0.15...1.0
    /// Soda-lime glass, the slab a demo bench actually has.
    nonisolated static let dielectricConstant = 4.7

    /// The calibrated plates, rebuilt only when an input moves.
    /// `@ObservationIgnored`: a cache written during a tracked read would
    /// re-arm the observation loop forever.
    @ObservationIgnored private var cachedCapacitor: PlateField.Capacitor?
    var capacitor: PlateField.Capacitor? {
        guard capacitorOn else { return nil }
        if let cached = cachedCapacitor,
           cached.center == capacitorCenter,
           cached.separation == plateSeparation,
           cached.voltage == plateVoltage,
           cached.dielectricCoverage == dielectricCoverage {
            return cached
        }
        let built = PlateField.Capacitor.calibrated(
            center: capacitorCenter, separation: plateSeparation,
            plateSize: Self.plateSize, voltage: plateVoltage,
            dielectricConstant: Self.dielectricConstant,
            dielectricCoverage: dielectricCoverage)
        cachedCapacitor = built
        return built
    }

    /// The measured centre field in kV/m, quantised to the tenth — one
    /// arithmetic for the ΔV rail's E line and the readout card. Honestly
    /// below V/d.
    var plateFieldkVPerM: Double {
        let field = capacitor.map { $0.field(at: capacitorCenter).x }
            ?? plateVoltage / plateSeparation
        return ((field / 1000) * 10).rounded() / 10
    }

    /// Sets ΔV snapped to 500 V steps, clamped to the range — so the displayed
    /// "%.0f kV" can never disagree with the model by sub-display noise.
    func setPlateVoltage(_ volts: Double) {
        let clamped = min(max(volts, Self.plateVoltageRange.lowerBound),
                          Self.plateVoltageRange.upperBound)
        plateVoltage = (clamped / 500).rounded() * 500
    }

    // MARK: Magnetic field

    /// A uniform B pointing straight up fills the region; the probe feels
    /// the full Lorentz force and curves. The tesla numbers are colossal
    /// because the probe is a 0.5 g, 10 nC ball; the geometry is exact
    /// either way: r = mv/qB.
    var magneticFieldOn = false
    var magneticFieldTesla = 5e4
    nonisolated static let magneticFieldRange = 1e4...2e5
    /// The push dropProbe gives when B is on, so there's a v to curve.
    nonisolated static let magneticLaunchSpeed = 0.35

    /// Signed charge and mass of the probe.
    var probeQ: Double {
        (probeIsPositive ? 1 : -1) * probeChargeMagnitude
    }
    var probeM: Double { Self.probeMass }
    var launchSpeed: Double { Self.magneticLaunchSpeed }

    var magneticField: SIMD3<Double> {
        guard magneticFieldOn else { return .zero }
        return SIMD3(0, magneticFieldTesla, 0)
    }

    /// Cyclotron radius at the launch speed, m.
    var cyclotronRadius: Double {
        probeM * launchSpeed / (abs(probeQ) * simd_length(magneticField).replacingZero)
    }

    /// A plate's world x (0 = the + plate on the −x side).
    func plateX(_ index: Int) -> Double {
        capacitorCenter.x + (index == 0 ? -plateSeparation : plateSeparation) / 2
    }

    /// Grabbing a plate: its own x changes the gap (the other plate
    /// stays put), while its y/z carry the whole assembly.
    func movePlate(_ index: Int, toWorld world: SIMD3<Double>) {
        let fixedX = plateX(index == 0 ? 1 : 0)
        let pulled = index == 0 ? fixedX - world.x : world.x - fixedX
        let separation = min(max(pulled, Self.plateSeparationRange.lowerBound),
                             Self.plateSeparationRange.upperBound)
        plateSeparation = separation
        var center = capacitorCenter
        center.x = index == 0 ? fixedX - separation / 2 : fixedX + separation / 2
        // The floor is the one boundary a hand still meets: the plates are
        // half a metre tall and must not sink into it.
        center.y = max(world.y, Self.plateSize / 2 + 0.15)
        center.z = world.z
        capacitorCenter = center
    }

    /// The plates' field anywhere — between them, in the fringe past
    /// their edges, behind them. The κ scaling inside the slab is the
    /// capacitor's own.
    func capacitorField(at point: SIMD3<Double>) -> SIMD3<Double> {
        capacitor?.field(at: point) ?? .zero
    }

    /// Where the slab's centre sits, for the hand and the renderer:
    /// parked flush against the plates' −z edge at coverage 0, fully
    /// between them at 1.
    var dielectricSlabCenter: SIMD3<Double> {
        capacitorCenter + SIMD3(0, 0, -(1 - dielectricCoverage) * Self.plateSize)
    }

    /// Sliding the slab: only the z of the hand matters, mapped onto
    /// the coverage — the slab rides the capacitor's frame on the
    /// other two axes.
    func moveDielectric(toWorld world: SIMD3<Double>) {
        dielectricCoverage = min(max(
            1 - (capacitorCenter.z - world.z) / Self.plateSize, 0), 1)
    }

    /// Fires the probe crosswise through the gap — the CRT deflection demo:
    /// a parabola between the plates, the bend following the probe's sign.
    /// Entry is on the +z side, where the slab is not parked.
    func launchProbeThroughGap() {
        guard capacitorOn else { return }
        var state = TestChargeDynamics.ProbeState(
            position: capacitorCenter + SIMD3(0, 0, Self.plateSize / 2 + 0.18))
        state.velocity = SIMD3(0, 0, -Self.deflectionLaunchSpeed)
        probe = state
        probeStatus = .running
        emitSound(.whoosh, at: state.position, volume: 0.3)
        // Each shot is its own flight — else the new trail's first point
        // bridges back to where the last parabola ended.
        probeTrail = []
    }

    /// Fast enough to cross before drifting into a plate at full ΔV,
    /// slow enough that the parabola is unmistakable.
    nonisolated static let deflectionLaunchSpeed = 0.9

    /// The full field the probe feels: point charges + plates.
    func fieldVector(at point: SIMD3<Double>) -> SIMD3<Double> {
        ElectricField.vector(at: point, dueTo: charges) + capacitorField(at: point)
    }

    /// Freezes the probe's flight and any free-charge drift.
    var isPaused = false

    // MARK: Free charges
    // Stationary by default. On, the source charges respond to the net
    // Coulomb force (plus the plates') by the same overdamped
    // force→velocity law the magnetism bench uses.
    var chargesRespond = false
    /// The charge pinned under the user's hand — it follows the drag,
    /// never the drift, while everything else reacts to it live.
    var heldChargeID: UUID?

    // MARK: Time Capsule

    @ObservationIgnored var capsule = TimeCapsule<CapsuleSnapshot>()
    @ObservationIgnored var capsuleClock = 0.0
    var scrubTime: Double?
    var scrubNonce = 0

    nonisolated static let chargeDriftGain = 3.0     // m/s per newton, overdamped
    nonisolated static let chargeMaxSpeed = 0.4      // m/s cap
    /// Two charge spheres touch at this centre distance (m); the drift
    /// can't push them closer, which also keeps 1/r² finite.
    nonisolated static let chargeContact = 0.075

    /// One frame of overdamped Coulomb drift for the source charges.
    func stepFreeCharges(dt: Double) {
        guard chargesRespond, !isPaused, charges.count > 1 || capacitorOn else { return }
        let h = min(dt, 1.0 / 30.0)

        let centroid = charges.map(\.position).reduce(.zero, +) / Double(charges.count)
        // Cohesion, not a wall: the flock stays a flock rather than a
        // mutually-repelling pair racing to opposite ends of the room.
        let bound = 0.85

        var next = charges.map(\.position)
        for j in charges.indices {
            let mover = charges[j]
            if mover.id == heldChargeID { continue }
            var field = ElectricField.vector(
                at: mover.position, dueTo: charges, excluding: j)
            field += capacitorField(at: mover.position)
            let force = mover.charge * field
            var velocity = Self.chargeDriftGain * force
            let speed = simd_length(velocity)
            guard speed > 1e-12 else { continue }
            if speed > Self.chargeMaxSpeed {
                velocity *= Self.chargeMaxSpeed / speed
            }
            var position = mover.position + velocity * h
            position = simd_clamp(position,
                                  centroid - SIMD3(repeating: bound),
                                  centroid + SIMD3(repeating: bound))
            // The centroid-relative bound holds the flock together; the
            // room-scale safety box (metres out) stops it drifting to infinity.
            next[j] = Self.clampToRoomSafety(position)
        }

        // Contact: spheres can touch but never interpenetrate (which also
        // keeps the 1/r² forces finite). Pairs push apart symmetrically;
        // a held charge is immovable and its partner takes the full push.
        for _ in 0..<2 {
            for a in next.indices {
                for b in (a + 1)..<next.count {
                    let offset = next[b] - next[a]
                    let distance = simd_length(offset)
                    guard distance < Self.chargeContact, distance > 1e-9 else { continue }
                    let push = (Self.chargeContact - distance) / 2
                    let direction = offset / distance
                    let aHeld = charges[a].id == heldChargeID
                    let bHeld = charges[b].id == heldChargeID
                    if aHeld && bHeld { continue }
                    if aHeld { next[b] += direction * push * 2 }
                    else if bHeld { next[a] -= direction * push * 2 }
                    else { next[a] -= direction * push; next[b] += direction * push }
                }
            }
        }
        for j in charges.indices where charges[j].position != next[j] {
            charges[j].position = next[j]
        }
    }

    /// Counts placements so each new charge lands at a different spot.
    private var placementIndex = 1

    // MARK: Sound events (the renderer plays them spatially)

    private(set) var soundEvent: SpatialSoundEvent?
    @ObservationIgnored private var soundCounter = 0

    private func emitSound(_ kind: SoundPalette.Sound, at position: SIMD3<Double>, volume: Double) {
        soundCounter += 1
        soundEvent = SpatialSoundEvent(id: soundCounter, kind: kind,
                                       position: position, volume: volume)
    }

    /// Two charges, either way round.
    nonisolated struct ChargePair: Hashable {
        let first: UUID
        let second: UUID

        init(_ a: UUID, _ b: UUID) {
            (first, second) = a.uuidString < b.uuidString ? (a, b) : (b, a)
        }
    }

    /// The pairs touching after the last frame, so a clack sounds when two
    /// first meet and not on every frame they stay together.
    @ObservationIgnored private(set) var touchingPairs: Set<ChargePair> = []

    /// Every pair of charges within a hair of contact.
    nonisolated static func contacts(_ charges: [PointCharge]) -> Set<ChargePair> {
        var touching = Set<ChargePair>()
        for a in charges.indices {
            for b in charges.indices where b > a
                && simd_distance(charges[a].position, charges[b].position) <= chargeContact + 0.002 {
                touching.insert(ChargePair(charges[a].id, charges[b].id))
            }
        }
        return touching
    }

    /// A clack when two free charges first touch, louder the faster they
    /// closed: the spheres meeting, steel-bright and brief.
    private func soundContacts(before: [PointCharge], dt: Double) {
        let now = Self.contacts(charges)
        defer { touchingPairs = now }
        guard chargesRespond, dt > 0 else { return }
        for pair in now.subtracting(touchingPairs) {
            guard let a = charges.first(where: { $0.id == pair.first }),
                  let b = charges.first(where: { $0.id == pair.second }) else { continue }
            var was = Self.chargeContact
            if let oldA = before.first(where: { $0.id == pair.first }),
               let oldB = before.first(where: { $0.id == pair.second }) {
                was = simd_distance(oldA.position, oldB.position)
            }
            let closing = max(0, was - simd_distance(a.position, b.position)) / dt
            emitSound(.clack, at: (a.position + b.position) / 2,
                      volume: 0.1 + 0.3 * min(closing / Self.chargeMaxSpeed, 1))
        }
    }

    init() {
        charges = []
        reset()
        // Debug hooks: the room's controls are objects and `simctl` has no
        // tap verb, so each apparatus and value needs a launch argument.
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "emMagnetic") {
            magneticFieldOn = true
        }
        if UserDefaults.standard.bool(forKey: "emProbe") {
            dropProbe()
        }
        // `-emFree 1`: free-charge mode with an opposite pair attracting.
        if UserDefaults.standard.bool(forKey: "emFree") {
            addCharge(positive: false)
            chargesRespond = true
        }

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "emCap") { capacitorOn = true }
        if defaults.object(forKey: "emLines") != nil {
            showLines = defaults.bool(forKey: "emLines")
        }
        // `-emShells 1` lights the equipotential surfaces.
        if defaults.bool(forKey: "emShells") { showEquipotentials = true }
        // `-emParticle plus|minus` — the probe's sign.
        if let particle = defaults.string(forKey: "emParticle") {
            probeIsPositive = particle == "plus"
        }
        let volts = defaults.double(forKey: "emVolts")
        if volts > 0 {
            plateVoltage = min(max(volts, Self.plateVoltageRange.lowerBound),
                               Self.plateVoltageRange.upperBound)
        }
        let tesla = defaults.double(forKey: "emTesla")
        if tesla > 0 {
            magneticFieldTesla = min(max(tesla, Self.magneticFieldRange.lowerBound),
                                     Self.magneticFieldRange.upperBound)
        }
        let probeCharge = defaults.double(forKey: "emProbeCharge")
        if probeCharge > 0 { setProbeMagnitude(probeCharge) }
        #endif
    }

    /// Returns the module to its freshly-entered state: a dipole — the
    /// recognisable field that curves, closes and fills the volume.
    func reset() {
        let separation = 0.26
        let positive = PointCharge(
            position: Self.regionCenter + SIMD3(-separation, 0, 0),
            charge: Self.defaultMagnitude)
        let negative = PointCharge(
            position: Self.regionCenter + SIMD3(separation, 0, 0),
            charge: -Self.defaultMagnitude)
        charges = [positive, negative]
        selectedChargeID = positive.id
        // `chargesRespond` must reset too: it is the "Free charges" plate and
        // has a second writer (`-emFree 1`), so it can be on with no visible
        // control turning it off. (`ResetCoverageTests` covers this.)
        chargesRespond = false
        // `charges` is replaced wholesale above, so an id naming an old charge
        // (a drag in flight when Reset lands) must be cleared.
        heldChargeID = nil
        probe = nil
        probeStatus = .none
        probeTrail = []
        probeIsPositive = true
        showLines = true
        showEquipotentials = false
        capacitorOn = false
        plateVoltage = 20_000
        capacitorCenter = samplingRegion.center
        plateSeparation = 0.44
        dielectricCoverage = 0
        probeChargeMagnitude = Self.defaultProbeCharge
        magneticFieldOn = false
        magneticFieldTesla = 5e4
        isPaused = false
        touchingPairs = []
        placementIndex = 2
        clearCapsule()
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

    // MARK: Per-charge edits — what the Bloom calls

    /// Spawns a charge at a given point — at the fingertips, exactly.
    @discardableResult
    func addCharge(positive: Bool, at position: SIMD3<Double>) -> UUID {
        var clamped = position
        clamped.y = max(clamped.y, Self.floorClearance)
        let charge = PointCharge(
            position: clamped,
            charge: (positive ? 1 : -1) * Self.defaultMagnitude)
        charges.append(charge)
        selectedChargeID = charge.id
        return charge.id
    }

    /// Turns a charge over: the same magnitude, the other sign. What the
    /// ring's Flip does, so one well makes both kinds.
    func flipCharge(id: UUID) {
        guard let index = charges.firstIndex(where: { $0.id == id }) else { return }
        charges[index].charge = -charges[index].charge
    }

    func removeCharge(id: UUID) {
        charges.removeAll { $0.id == id }
        if selectedChargeID == id { selectedChargeID = charges.last?.id }
    }

    /// Sets one charge's magnitude in microcoulombs, sign preserved.
    func setMagnitude(id: UUID, microCoulombs: Double) {
        guard let index = charges.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(microCoulombs, Self.magnitudeRange.lowerBound),
                          Self.magnitudeRange.upperBound)
        let sign: Double = charges[index].charge < 0 ? -1 : 1
        charges[index].charge = sign * clamped * 1e-6
    }

    func magnitudeMicroCoulombs(id: UUID) -> Double {
        guard let charge = charges.first(where: { $0.id == id }) else { return 1 }
        return abs(charge.charge) * 1e6
    }

    nonisolated static let magnitudeRange = 0.2...6.0
    /// The round values a charge's bead clicks into, µC.
    nonisolated static let magnitudeDetents = [0.5, 1, 2, 3, 4, 5, 6]

    func removeSelectedCharge() {
        guard let id = selectedChargeID else { return }
        charges.removeAll { $0.id == id }
        selectedChargeID = charges.last?.id
    }

    func removeAllCharges() {
        charges.removeAll()
        selectedChargeID = nil
    }

    /// What the Clear plate promises: an empty room. Everything the wearer
    /// placed goes (including the probe); the toggles stay, because a layer
    /// switch is a setting, not a placed object.
    func clearEverything() {
        removeAllCharges()
        removeProbe()
    }

    /// A dragged charge follows the hand exactly; the floor is the only boundary.
    func moveCharge(id: UUID, to position: SIMD3<Double>) {
        guard let index = charges.firstIndex(where: { $0.id == id }) else { return }
        var next = position
        next.y = max(next.y, Self.floorClearance)
        charges[index].position = next
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
        var state = TestChargeDynamics.ProbeState(position: center + SIMD3(0.12, 0.24, 0))
        if magneticFieldOn {
            // A sideways push so there's a velocity for B to bend.
            state.velocity = SIMD3(launchSpeed, 0, 0)
        }
        probe = state
        probeStatus = .running
    }

    func removeProbe() {
        probe = nil
        probeStatus = .none
        probeTrail = []
    }

    // MARK: The trail — the shape of the path, kept

    /// Where the test charge has been — the cyclotron circle cannot be read
    /// without it. Settable from the capsule extension, which rebuilds it
    /// on a scrub.
    private(set) var probeTrail: [SIMD3<Double>] = []
    /// A point every this far along the path — the trail samples distance,
    /// not frames, so a fast probe draws no sparser than a slow one.
    nonisolated static let probeTrailSpacing = 0.011
    /// Points the trail remembers — ~2 m of path, more than one cyclotron
    /// orbit, so the circle closes before its tail disappears.
    nonisolated static let probeTrailLength = 190

    /// Called while the user drags the probe: it follows the hand with no
    /// momentum, and the simulation waits.
    func holdProbe(at position: SIMD3<Double>) {
        var clamped = position
        clamped.y = max(clamped.y, Self.floorClearance)
        probe = TestChargeDynamics.ProbeState(position: clamped)
        probeStatus = .held
        // A hand on the probe ends the flight the trail was drawing.
        probeTrail = []
    }

    /// Called when the user releases the probe. `flick` is the hand's
    /// velocity at release; only its direction is used, since with B on a
    /// probe released at rest has nothing for B to bend.
    func releaseProbe(flick: SIMD3<Double> = .zero) {
        guard probe != nil else { return }
        if magneticFieldOn {
            let speed = simd_length(flick)
            // Below a slow deliberate hand, fall back to a sideways push —
            // releasing gently must not mean releasing into a dead scene.
            let direction = speed > 0.05 ? flick / speed : SIMD3(1, 0, 0)
            probe?.velocity = direction * launchSpeed
            if let position = probe?.position {
                emitSound(.whoosh, at: position, volume: 0.3)
            }
        }
        probeStatus = .running
    }

    /// Lets go of whatever a hand holds — a charge, the test charge — at
    /// rest where it is. Leaving the lab mid-drag never delivers the
    /// gesture's end: a charge left held never moves freely again, and a
    /// held probe never runs.
    func releaseAll() {
        heldChargeID = nil
        if probeStatus == .held { probeStatus = .running }
    }

    /// One frame of this bench: the probe, then the free charges, then the
    /// recording — the only place that records, one frame per rendered
    /// frame.
    func step(dt: Double) {
        guard !isPaused else { return }
        defer { recordCapsuleFrame(dt: min(dt, 1.0 / 30.0)) }
        stepProbe(dt: dt)
        let before = charges
        stepFreeCharges(dt: dt)
        soundContacts(before: before, dt: min(dt, 1.0 / 30.0))
    }

    func stepProbe(dt: Double) {
        guard !isPaused, probeStatus == .running, var state = probe,
              !charges.isEmpty || capacitorOn || magneticFieldOn else { return }

        // A stalled frame must not become one giant physics leap.
        let simDt = min(dt, 1.0 / 30.0)
        state = TestChargeDynamics.stepLorentz(
            state,
            chargeToMassRatio: probeQ / probeM,
            dt: simDt,
            substeps: 4,
            electricField: { point in self.fieldVector(at: point) },
            magneticField: magneticField
        )

        // Landed on a source charge or a capacitor plate: ride over.
        let plateOffset = state.position - capacitorCenter
        let hitPlate = capacitorOn
            && abs(plateOffset.x) >= plateSeparation / 2 - 0.01
            && abs(plateOffset.x) < plateSeparation / 2 + 0.06
            && abs(plateOffset.y) < Self.plateSize / 2
            && abs(plateOffset.z) < Self.plateSize / 2
        // A landing sounds once, as it happens, louder the faster it came:
        // glass meeting glass on a charge or a plate, a soft body on the
        // floor. Leaving for infinity is silent.
        let impact = 0.15 + 0.3 * min(simd_length(state.velocity) / 2, 1)
        if hitPlate
            || charges.contains(where: { simd_distance($0.position, state.position) < Self.probeCaptureRadius }) {
            probeStatus = .captured
            emitSound(.pop, at: state.position, volume: impact)
        } else if simd_distance(state.position, samplingRegion.center) > Self.probeEscapeDistance {
            // Off to infinity, as a real unbound charge would be.
            probeStatus = .escaped
        } else if state.position.y < Self.regionFloor {
            state.position.y = Self.regionFloor
            probeStatus = .captured
            emitSound(.thud, at: state.position, volume: impact)
        }
        probe = state
        recordTrail(at: state.position)
    }

    private func recordTrail(at point: SIMD3<Double>) {
        if let last = probeTrail.last,
           simd_distance(last, point) < Self.probeTrailSpacing { return }
        probeTrail.append(point)
        if probeTrail.count > Self.probeTrailLength {
            probeTrail.removeFirst(probeTrail.count - Self.probeTrailLength)
        }
    }

    /// Live physics numbers at the probe's location, for the stats panel.
    struct ProbeReadout {
        var fieldMagnitude: Double   // N/C
        var potential: Double        // V
        /// |q(E + v×B)| — the force actually pushing the probe.
        var forceMagnitude: Double   // N
        /// |qE| on its own.
        var electricForce: Double    // N
        /// |q v×B| on its own — zero unless the probe is moving across
        /// a field, which is the whole of what makes it magnetic.
        var magneticForce: Double    // N
        var acceleration: Double     // m/s²
        var speed: Double            // m/s
    }

    /// What the card says about the probe: both force terms separately,
    /// because the split is the lesson (qE is motion-independent and along
    /// the field; q v×B vanishes at rest and is perpendicular to the path).
    var probeReadout: ProbeReadout? {
        guard let probe else { return nil }
        let electric = fieldVector(at: probe.position)
        let magnetic = simd_cross(probe.velocity, magneticField)
        let electricForce = probeQ * electric
        let magneticForce = probeQ * magnetic
        let net = electricForce + magneticForce
        return ProbeReadout(
            fieldMagnitude: simd_length(electric),
            // The capacitor counts toward the potential too — else the card
            // shows a large E beside 0.00 V, which a potential cannot be.
            potential: ElectricField.potential(at: probe.position, dueTo: charges)
                + capacitorPotential(at: probe.position),
            forceMagnitude: simd_length(net),
            electricForce: simd_length(electricForce),
            magneticForce: simd_length(magneticForce),
            acceleration: simd_length(net) / probeM,
            speed: simd_length(probe.velocity)
        )
    }

    /// The plates' contribution to the potential, V, datum at the capacitor's
    /// centre — integrated along the real field, so it means something in the
    /// fringe.
    func capacitorPotential(at point: SIMD3<Double>) -> Double {
        capacitor?.potential(at: point) ?? 0
    }

    // MARK: Selected-charge bindings for the charge's control ring

    var selectedMagnitudeMicroCoulombs: Double {
        get { selectedCharge?.magnitudeMicroCoulombs ?? 1 }
        set {
            // Through setMagnitude, so this binding clamps to magnitudeRange
            // like the bloom's grip does (the accessibility path needs it).
            guard let id = selectedChargeID else { return }
            setMagnitude(id: id, microCoulombs: newValue)
        }
    }

}

// MARK: - Time Capsule

extension FieldModel: TimeCapsuleRecording {
    /// The charges, the probe, and the apparatus flags that change the
    /// physics (`capacitorOn`, `magneticFieldOn`, `chargesRespond`);
    /// `showLines` stays out, and `probeTrail` is rebuilt from the capsule.
    nonisolated struct CapsuleSnapshot: Equatable {
        var charges: [PointCharge]
        var probe: TestChargeDynamics.ProbeState?
        var probeStatus: ProbeStatus
        var probeIsPositive: Bool
        var probeChargeMagnitude: Double
        var chargesRespond: Bool
        var capacitorOn: Bool
        var plateVoltage: Double
        var plateSeparation: Double
        var capacitorCenter: SIMD3<Double>
        var dielectricCoverage: Double
        var magneticFieldOn: Bool
        var magneticFieldTesla: Double
    }

    func captureCapsuleSnapshot() -> CapsuleSnapshot {
        CapsuleSnapshot(
            charges: charges, probe: probe, probeStatus: probeStatus,
            probeIsPositive: probeIsPositive,
            probeChargeMagnitude: probeChargeMagnitude,
            chargesRespond: chargesRespond, capacitorOn: capacitorOn,
            plateVoltage: plateVoltage, plateSeparation: plateSeparation,
            capacitorCenter: capacitorCenter,
            dielectricCoverage: dielectricCoverage,
            magneticFieldOn: magneticFieldOn,
            magneticFieldTesla: magneticFieldTesla)
    }

    func restoreCapsuleSnapshot(_ snapshot: CapsuleSnapshot) {
        var restored = snapshot.charges
        // A restore never drags the held charge out of the fingers holding it.
        if let heldChargeID,
           let live = charges.first(where: { $0.id == heldChargeID }) {
            if let index = restored.firstIndex(where: { $0.id == heldChargeID }) {
                restored[index] = live
            } else {
                restored.append(live)
            }
        }
        charges = restored
        probe = snapshot.probe
        probeStatus = snapshot.probeStatus
        probeIsPositive = snapshot.probeIsPositive
        probeChargeMagnitude = snapshot.probeChargeMagnitude
        chargesRespond = snapshot.chargesRespond
        capacitorOn = snapshot.capacitorOn
        plateVoltage = snapshot.plateVoltage
        plateSeparation = snapshot.plateSeparation
        capacitorCenter = snapshot.capacitorCenter
        dielectricCoverage = snapshot.dielectricCoverage
        magneticFieldOn = snapshot.magneticFieldOn
        magneticFieldTesla = snapshot.magneticFieldTesla
        probeTrail = recordedProbeTrail(upTo: scrubTime)
        if let selectedChargeID,
           !charges.contains(where: { $0.id == selectedChargeID }) {
            self.selectedChargeID = nil
        }
        // A pair the restore left touching has already met: resuming must
        // not clack it again.
        touchingPairs = Self.contacts(charges)
    }

    /// The probe's recorded path, rebuilt under the live spacing and
    /// length rules — the trail a scrubbed room shows is the recording.
    private func recordedProbeTrail(upTo time: Double?) -> [SIMD3<Double>] {
        guard let time, let span = capsule.span else { return [] }
        var trail: [SIMD3<Double>] = []
        for frame in capsule.frames(in: span.lowerBound...time) {
            guard let probe = frame.snapshot.probe else { continue }
            if let last = trail.last,
               simd_distance(last, probe.position) < Self.probeTrailSpacing {
                continue
            }
            trail.append(probe.position)
        }
        if trail.count > Self.probeTrailLength {
            trail.removeFirst(trail.count - Self.probeTrailLength)
        }
        return trail
    }

    /// The probe's recorded flight, for the walkable tube.
    func capsuleRecordedPaths(stride: Int = 4) -> [[SIMD3<Float>]] {
        guard scrubTime != nil, let span = capsule.span else { return [] }
        var path: [SIMD3<Float>] = []
        for frame in capsule.frames(in: span, stride: stride) {
            guard let probe = frame.snapshot.probe else { continue }
            let point = SIMD3<Float>(probe.position)
            if let last = path.last, simd_distance(last, point) < 0.004 { continue }
            path.append(point)
        }
        return path.count >= 2 ? [path] : []
    }
}
