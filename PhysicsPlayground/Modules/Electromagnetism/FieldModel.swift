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

private extension Double {
    /// Guards divide-by-zero in display-only ratios.
    var replacingZero: Double { abs(self) < 1e-30 ? 1e-30 : self }
}

@MainActor
@Observable
final class FieldModel {
    // MARK: Sampling region
    // Immersive-space coordinates: origin is on the floor where the user
    // launched the space, +Y is up, -Z is straight ahead.

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

    /// The station's NOMINAL volume — where reset lays the dipole out
    /// and where the instruments take their clearance bearings
    /// (`FieldInstrumentLayout` keeps every collider `stationMargin`
    /// clear of this box, which is what makes pinch contention
    /// geometrically impossible).
    ///
    /// IT IS NOT A WALL ANY MORE. The drag clamps born in the merged
    /// E&M world — `clampToStation` on every `moveCharge` and
    /// `movePlate`, plus the escort mechanism that exempted a
    /// freshly-pulled charge until it first came inside — came out on
    /// 2026-08-03 at the owner's direction: this is a room-scale app,
    /// and an invisible box that stops a carried charge mid-air reads
    /// as broken. A hand meets only the floor now. What survives is a
    /// room-scale SAFETY bound on the free simulation, so a drifting
    /// charge settles in the room instead of sailing to infinity.
    /// The superseding entry is in DECISIONS.md, 2026-08-03.
    nonisolated static let regionHalfExtents = SIMD3<Double>(0.76, 1.20, 0.62)

    /// The free simulation's safety bounds — room-scale, never applied
    /// to a hand.
    nonisolated static let safetyHalfExtents = SIMD3<Double>(2.6, 1.6, 2.6)

    /// Clamps a FREE-drifting point into the room-scale safety box.
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
    /// The test charge's magnitude, C — bigger charge, bigger F = qE.
    var probeChargeMagnitude = FieldModel.defaultProbeCharge

    var probeCharge: Double {
        (probeIsPositive ? 1 : -1) * probeChargeMagnitude
    }

    // MARK: Display options
    var showLines = true

    // The Gauss flux meter — the carried bubble/disc, its clamps, its
    // memoised ∮E·dA — stood here until 2026-08-03, when the owner cut
    // it from the prototype. The pure math (`GaussSurface`) stays in
    // PhysicsCore with its tests; git history holds the rest.

    /// Clamps to `probeChargeRange`, so a hand that keeps pulling past the
    /// end of the bead's rail pins there instead of running off the scale.
    func setProbeMagnitude(_ coulombs: Double) {
        probeChargeMagnitude = min(max(coulombs, Self.probeChargeRange.lowerBound),
                                   Self.probeChargeRange.upperBound)
    }

    // MARK: Parallel-plate capacitor

    /// Two square plates bracketing the region: left (−x) positive,
    /// right (+x) negative, uniform E = V/d between them (fringing
    /// ignored, as every textbook does).
    var capacitorOn = false
    /// Plate voltage difference, V. kV-scale, like a real demo bench.
    var plateVoltage = 20_000.0
    /// Where the gap's midpoint sits — grab a plate to carry it.
    var capacitorCenter = SIMD3<Double>(0, 1.3, -1.0)
    /// Gap width, m — grab a plate and pull: E = V/d follows live.
    var plateSeparation = 0.44
    nonisolated static let plateSize = 0.5
    nonisolated static let plateVoltageRange = 2_000.0...40_000.0
    nonisolated static let plateSeparationRange = 0.15...1.0

    /// The gap's uniform field strength in kV/m, quantised to the tenth
    /// every surface displays — ONE arithmetic for the ΔV rail's E line
    /// and the readout card, so the two can never disagree.
    var plateFieldkVPerM: Double {
        ((plateVoltage / plateSeparation / 1000) * 10).rounded() / 10
    }

    /// Sets ΔV snapped to 500 V steps, clamped to the range. The rail
    /// writes through this so the displayed "%.0f kV" can never
    /// disagree with the model by sub-display noise — the bead lands on
    /// honest values (2026-08-06, the ΔV rail improvement pass).
    func setPlateVoltage(_ volts: Double) {
        let clamped = min(max(volts, Self.plateVoltageRange.lowerBound),
                          Self.plateVoltageRange.upperBound)
        plateVoltage = (clamped / 500).rounded() * 500
    }

    // MARK: Magnetic field

    /// A uniform B pointing straight UP fills the region; the probe
    /// then feels the full Lorentz force F = q(E + v×B) and curves.
    /// The tesla numbers are colossal because the probe is a 0.5 g,
    /// 10 nC ball — an electron (q/m ~10¹¹ larger) curves this hard in
    /// microtesla. The geometry is exact either way: r = mv/qB.
    var magneticFieldOn = false
    var magneticFieldTesla = 5e4
    nonisolated static let magneticFieldRange = 1e4...2e5
    /// The push dropProbe gives when B is on, so there's a v to curve.
    nonisolated static let magneticLaunchSpeed = 0.35

    // Electron mode — the probe as a genuine electron/positron, with
    // its own field range and a 10⁷× display clock — stood here until
    // 2026-08-03, when the owner removed it with the particle bank that
    // was its only door. The probe is always the charged ball now, and
    // its sign comes from which well mouth it was pulled from.

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

    /// Grabbing a plate: its own x changes the GAP (the other plate
    /// stays put), while its y/z carry the whole assembly.
    func movePlate(_ index: Int, toWorld world: SIMD3<Double>) {
        let fixedX = plateX(index == 0 ? 1 : 0)
        let pulled = index == 0 ? fixedX - world.x : world.x - fixedX
        let separation = min(max(pulled, Self.plateSeparationRange.lowerBound),
                             Self.plateSeparationRange.upperBound)
        plateSeparation = separation
        var center = capacitorCenter
        center.x = index == 0 ? fixedX - separation / 2 : fixedX + separation / 2
        // The floor is the one boundary a hand still meets: the plates
        // are half a metre tall and must not sink into it. The station
        // walls came off the drag paths on 2026-08-03 — carry the
        // capacitor anywhere in the room.
        center.y = max(world.y, Self.plateSize / 2 + 0.15)
        center.z = world.z
        capacitorCenter = center
    }

    /// The uniform field between the plates (zero outside them).
    func capacitorField(at point: SIMD3<Double>) -> SIMD3<Double> {
        guard capacitorOn else { return .zero }
        let offset = point - capacitorCenter
        guard abs(offset.x) < plateSeparation / 2,
              abs(offset.y) < Self.plateSize / 2,
              abs(offset.z) < Self.plateSize / 2 else { return .zero }
        // + plate on the −x side: E points +x, from + toward −.
        return SIMD3(plateVoltage / plateSeparation, 0, 0)
    }

    /// The full field the probe feels: point charges + plates.
    func fieldVector(at point: SIMD3<Double>) -> SIMD3<Double> {
        ElectricField.vector(at: point, dueTo: charges) + capacitorField(at: point)
    }

    /// Freezes the probe's flight and any free-charge drift.
    var isPaused = false

    // MARK: Free charges
    //
    // Stationary by default — the classic electrostatics exhibit, where
    // YOU are the thing that moves charges. Flip this on and the source
    // charges themselves respond to the net Coulomb force from every
    // other charge (plus the plates' field): opposites drift together
    // until they touch, likes shove each other apart — the same
    // overdamped force→velocity presentation the magnetism bench uses,
    // with the force direction exact and the speed capped.
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

        // Keep the flock from wandering off: drift stays within the
        // region the arrows sample, centred on the charges themselves.
        let centroid = charges.map(\.position).reduce(.zero, +) / Double(charges.count)
        // Cohesion, not a wall: the flock stays a flock rather than a
        // mutually-repelling pair racing to opposite ends of the room.
        // Widened 0.55 → 0.85 when the station walls came off the drag
        // paths (2026-08-03) — the room is the arena now.
        let bound = 0.85

        var next = charges.map(\.position)
        for j in charges.indices {
            let mover = charges[j]
            if mover.id == heldChargeID { continue }
            let others = charges.enumerated()
                .filter { $0.offset != j }
                .map(\.element)
            var field = SIMD3<Double>.zero
            if !others.isEmpty {
                field = ElectricField.vector(at: mover.position, dueTo: others)
            }
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
            // The centroid-relative bound keeps the FLOCK together; it
            // does not keep the flock in the room, because the centroid
            // drifts with it. The room-scale safety box is what stops a
            // mutually repelling pair drifting away forever — it is
            // metres out, so no hand or eye ever meets it.
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

    init() {
        charges = []
        reset()
        // Debug hook: `simctl launch … -emMagnetic 1` opens with the
        // uniform B field already on — the toggles can't be pinched
        // from the command line.
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "emMagnetic") {
            magneticFieldOn = true
        }
        if UserDefaults.standard.bool(forKey: "emProbe") {
            dropProbe()
        }
        // `-emFree 1`: free-charge mode with an opposite pair already
        // attracting, so the drift is screenshot-checkable from the CLI.
        if UserDefaults.standard.bool(forKey: "emFree") {
            addCharge(positive: false)
            chargesRespond = true
        }

        // Every control in this module is now an object standing in the
        // room, and `simctl` has no tap verb — so each apparatus needs a
        // way in from the command line or the migration cannot be
        // screenshot at all. The VALUE arguments matter as much as the
        // on/off ones: a rail whose bead sits at its default in every
        // picture proves nothing about the mapping behind it.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "emCap") { capacitorOn = true }
        if defaults.object(forKey: "emLines") != nil {
            showLines = defaults.bool(forKey: "emLines")
        }
        // `-emParticle plus|minus` — the probe's sign. The wells choose
        // it by hand; the CLI cannot pull from a well.
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

    /// Returns the module to its freshly-entered state: a DIPOLE.
    ///
    /// This used to open with a single positive charge, which is the
    /// least interesting field there is — straight rays to infinity,
    /// reading as a laser starburst rather than a field. A dipole is the
    /// picture everyone recognises (it is what the hub's own exhibit
    /// shows), it curves, it closes, and it fills the volume around the
    /// user.
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
        // THE SIXTH RESET DEFECT. `chargesRespond` is the "Free charges"
        // plate on the bank, and `reset()` restored the other four and
        // skipped this one — so switching the charges loose and pressing
        // Reset handed back a bench still drifting under a dark lamp.
        // Worse than the other five, because this flag has a SECOND
        // writer: `-emFree 1` sets it at launch, so it could be on with a
        // plate that Reset would never turn off. Found 2026-08-03.
        chargesRespond = false
        // An id a Reset can strand. `charges` is replaced wholesale
        // above, so anything still naming a charge by id is naming one
        // that no longer exists — a drag in flight at the moment Reset
        // lands would go on referring to it.
        heldChargeID = nil
        probe = nil
        probeStatus = .none
        probeTrail = []
        probeIsPositive = true
        showLines = true
        capacitorOn = false
        plateVoltage = 20_000
        capacitorCenter = samplingRegion.center
        plateSeparation = 0.44
        probeChargeMagnitude = Self.defaultProbeCharge
        magneticFieldOn = false
        magneticFieldTesla = 5e4
        isPaused = false
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
    //
    // The old pods all worked through "the selected charge", because a
    // pod floats somewhere else and has to be told what it is pointing
    // at. A Bloom IS on the object, so it says which one.

    /// Spawns a charge at a given point — at the fingertips, exactly.
    /// (An "escort" mechanism lived here while the station had drag
    /// walls: a charge born at a well outside them was exempt until it
    /// first came inside. The walls came off on 2026-08-03 and the
    /// escort went with them — there is nothing to be exempt from.)
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

    func removeSelectedCharge() {
        guard let id = selectedChargeID else { return }
        charges.removeAll { $0.id == id }
        selectedChargeID = charges.last?.id
    }

    func removeAllCharges() {
        charges.removeAll()
        selectedChargeID = nil
    }

    /// A dragged charge follows the hand exactly. The floor is the only
    /// boundary — the room-scale app has no invisible walls
    /// (owner, 2026-08-03).
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

    /// Where the test charge has been. A trajectory is a SHAPE, and this
    /// module's best moment is one you cannot see without it: throw the
    /// probe sideways with a uniform B on and it curves into a circle,
    /// r = mv/qB, closing exactly back on itself. Watching a dot go
    /// round tells you it went round. Watching it draw the circle tells
    /// you the circle is a circle — that it closes, that its radius is
    /// constant, that reversing the charge reverses the winding.
    /// Settable from the capsule extension, which rebuilds it on a
    /// scrub — otherwise the model alone appends to it.
    private(set) var probeTrail: [SIMD3<Double>] = []
    /// A point is laid down every this far along the path, so the trail
    /// samples DISTANCE rather than frames — a fast probe does not draw a
    /// sparser curve than a slow one.
    nonisolated static let probeTrailSpacing = 0.011
    /// How many points the trail remembers. At the spacing above that is
    /// about 2 m of path: comfortably more than one full cyclotron orbit
    /// at the default field, so the circle closes before its own tail
    /// disappears — which is the entire thing being demonstrated.
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

    /// Called when the user releases the probe.
    ///
    /// - Parameter flick: the hand's velocity at the moment of release,
    ///   m/s in model space. Only its DIRECTION is used; the speed is the
    ///   physics' own launch speed, because a cathode ray leaves its gun at
    ///   2×10⁶ m/s whatever your wrist was doing.
    ///
    /// Why this takes a flick at all, when the old panel button did not:
    /// with a magnetic field on, a probe released at REST has nothing for B
    /// to bend — F = qv×B is zero when v is zero, so it simply sits there.
    /// `dropProbe` handled that by pushing it sideways along +x, and the
    /// cyclotron demo (the classic Helmholtz e/m experiment, which this
    /// module gets genuinely right) depends on it. Replacing "press Drop"
    /// with "pull it out of a well and let go" would have silently deleted
    /// that demonstration, so the throw carries the aim instead — which is
    /// also better, because now you choose the direction and can watch the
    /// radius stay the same while the circle moves.
    func releaseProbe(flick: SIMD3<Double> = .zero) {
        guard probe != nil else { return }
        if magneticFieldOn {
            let speed = simd_length(flick)
            // Below a slow deliberate hand, treat it as a drop rather than
            // a throw and fall back to the old sideways push — releasing
            // "gently" must not mean releasing into a dead scene.
            let direction = speed > 0.05 ? flick / speed : SIMD3(1, 0, 0)
            probe?.velocity = direction * launchSpeed
        }
        probeStatus = .running
    }

    /// Advances the simulation by one frame. Substepped velocity Verlet, so
    /// accuracy doesn't ride on the display frame rate.
    /// One frame of this bench: the probe, then the free charges, then
    /// the recording. The two steppers each guard their own conditions
    /// and are still called directly by tests; this is the frame entry
    /// point, and the only place that records — the capsule must get one
    /// frame per rendered frame whether or not either stepper had work.
    func step(dt: Double) {
        guard !isPaused else { return }
        defer { recordCapsuleFrame(dt: min(dt, 1.0 / 30.0)) }
        stepProbe(dt: dt)
        stepFreeCharges(dt: dt)
    }

    func stepProbe(dt: Double) {
        guard !isPaused, probeStatus == .running, var state = probe,
              !charges.isEmpty || capacitorOn || magneticFieldOn else { return }

        // A stalled frame (app paused, debugger…) must not become one giant
        // physics leap.
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
        if hitPlate
            || charges.contains(where: { simd_distance($0.position, state.position) < Self.probeCaptureRadius }) {
            probeStatus = .captured
        } else if simd_distance(state.position, samplingRegion.center) > Self.probeEscapeDistance {
            // Off to infinity, as a real unbound charge would be.
            probeStatus = .escaped
        } else if state.position.y < Self.regionFloor {
            state.position.y = Self.regionFloor
            probeStatus = .captured
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
        /// |q v×B| on its own — zero unless the probe is MOVING across
        /// a field, which is the whole of what makes it magnetic.
        var magneticForce: Double    // N
        var acceleration: Double     // m/s²
        var speed: Double            // m/s
    }

    /// What the card says about the probe.
    ///
    /// THE CARD USED TO REPORT THE ELECTRIC FORCE WHILE THE HEADLINE
    /// DEMO WAS MAGNETIC. `stepProbe` pushes the probe with the full
    /// Lorentz force F = q(E + v×B) — correctly — and this computed
    /// `|q||E|` and called it the force. Switch Uniform B on with no
    /// charges in the room and the card read `Force 0.00 N` while the
    /// probe visibly circled in front of you at a = v²/r ≈ 0.35 m/s².
    /// The one number that could have explained the orbit said there
    /// was nothing happening.
    ///
    /// It reports BOTH TERMS SEPARATELY now, because the split is the
    /// lesson rather than a formatting choice: qE does not depend on
    /// motion and points along the field, q v×B vanishes when the probe
    /// stops and is always perpendicular to its path. Seeing the second
    /// one appear as the probe speeds up, and the first stay put, is
    /// what tells you why one field pushes and the other steers.
    var probeReadout: ProbeReadout? {
        guard let probe else { return nil }
        let electric = fieldVector(at: probe.position)
        let magnetic = simd_cross(probe.velocity, magneticField)
        let electricForce = probeQ * electric
        let magneticForce = probeQ * magnetic
        let net = electricForce + magneticForce
        return ProbeReadout(
            fieldMagnitude: simd_length(electric),
            // THE CAPACITOR COUNTS TOWARD THE POTENTIAL TOO. `fieldVector`
            // includes the plates and this did not, so the card could show
            // a large E beside `0.00 V` — the one thing a potential cannot
            // be. Between the plates the field is uniform, so the work per
            // coulomb from the centre is just −E·(r − centre).
            potential: ElectricField.potential(at: probe.position, dueTo: charges)
                + capacitorPotential(at: probe.position),
            forceMagnitude: simd_length(net),
            electricForce: simd_length(electricForce),
            magneticForce: simd_length(magneticForce),
            acceleration: simd_length(net) / probeM,
            speed: simd_length(probe.velocity)
        )
    }

    /// The plates' contribution to the potential, V, taking the
    /// capacitor's centre as the datum — the same convention
    /// `ElectricField.potential` uses for a point charge at infinity, in
    /// the only place a uniform field allows one.
    func capacitorPotential(at point: SIMD3<Double>) -> Double {
        let field = capacitorField(at: point)
        guard field != .zero else { return 0 }
        return -simd_dot(field, point - capacitorCenter)
    }

    // MARK: Selected-charge bindings for the charge's control ring

    var selectedMagnitudeMicroCoulombs: Double {
        get { selectedCharge?.magnitudeMicroCoulombs ?? 1 }
        set {
            // Through setMagnitude, so this binding clamps to
            // magnitudeRange exactly like the bloom's grip does — the
            // slider enforces the range visually, but the accessibility
            // adjustable path does not.
            guard let id = selectedChargeID else { return }
            setMagnitude(id: id, microCoulombs: newValue)
        }
    }

}

// MARK: - Time Capsule

extension FieldModel: TimeCapsuleRecording {
    /// The charges, the probe, and — the exception to the standing rule —
    /// the apparatus flags that CHANGE THE PHYSICS.
    ///
    /// Everywhere else the snapshot excludes what the observer chose. On
    /// this bench `capacitorOn`, `magneticFieldOn` and `chargesRespond`
    /// are not display layers: they decide the field the recorded motion
    /// happened in. A cyclotron circle scrubbed back into a room whose B
    /// is switched off would be a lie about what you watched, so they
    /// ride along with the plate geometry that sets E = V/d. `showLines`
    /// stays out, because a field line is drawn, not felt.
    ///
    /// `probeTrail` stays out and is rebuilt from the capsule, the way
    /// Gravity Lab's orbit trails are.
    struct CapsuleSnapshot: Equatable {
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
            magneticFieldOn: magneticFieldOn,
            magneticFieldTesla: magneticFieldTesla)
    }

    func restoreCapsuleSnapshot(_ snapshot: CapsuleSnapshot) {
        var restored = snapshot.charges
        // The hand's charge is the hand's: a restore never drags it out
        // of the fingers holding it.
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
        magneticFieldOn = snapshot.magneticFieldOn
        magneticFieldTesla = snapshot.magneticFieldTesla
        probeTrail = recordedProbeTrail(upTo: scrubTime)
        if let selectedChargeID,
           !charges.contains(where: { $0.id == selectedChargeID }) {
            self.selectedChargeID = nil
        }
    }

    /// The probe's recorded path, rebuilt under the live spacing and
    /// length rules — the trail a scrubbed room shows IS the recording.
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
