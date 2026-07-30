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

    /// How far anything belonging to this apparatus may get from
    /// `regionCenter` — the station's walls.
    ///
    /// This bench had no lateral limit at all until it became the
    /// middle seat of the E&M world: `moveCharge` and
    /// `moveGaussSurface` clamped only `y`, so a charge could be
    /// dragged to the far side of the room. Alone in a room that cost
    /// nothing. With a circuit bench 1.4 m to the left and a magnetic
    /// field 1.33 m to the right, an unclamped drag ends up inside a
    /// neighbour's apparatus, which is the exact silent failure
    /// co-presence exists to make impossible.
    ///
    /// Kept in step with `EMStationLayout.halfExtents(.charges)` by
    /// `EMStationLayoutTests`; the layout may not promise a footprint
    /// the model does not enforce.
    nonisolated static let regionHalfExtents = SIMD3<Double>(0.62, 1.20, 0.62)

    /// Clamps a point into the station, keeping `inset` of clearance on
    /// every side so a thing WITH SIZE — a plate, a Gauss sphere —
    /// stays inside rather than merely having its centre inside.
    nonisolated static func clampToStation(
        _ point: SIMD3<Double>, inset: SIMD3<Double> = .zero
    ) -> SIMD3<Double> {
        let half = simd_max(regionHalfExtents - simd_abs(inset),
                            SIMD3(repeating: 0.01))
        var clamped = simd_clamp(point, regionCenter - half, regionCenter + half)
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

    // MARK: Gauss surface — the flux meter you carry

    /// A surface you hold in the field and move through it, reading the
    /// flux ∮E·dA through it live.
    ///
    /// This is the one idea in electrostatics that a page genuinely
    /// cannot show, because showing it means moving a surface through a
    /// field and watching the number respond. As a BUBBLE (closed) it is
    /// Gauss's law itself: whatever shape the field is in and wherever
    /// the outside charges sit, the flux is exactly Q_enclosed/ε₀ — put
    /// a charge inside and the number jumps, take it out and it returns
    /// to zero, and no amount of waving it about changes that.
    var gaussSurfaceOn = false
    enum GaussSurfaceKind: String, CaseIterable, Identifiable {
        /// An open disc: flux depends on where and how it's tilted.
        case disc
        /// A closed bubble: flux is Q_enclosed/ε₀ and nothing else.
        case bubble
        var id: String { rawValue }
        var displayName: String { self == .disc ? "Disc" : "Bubble" }
    }
    var gaussSurfaceKind: GaussSurfaceKind = .bubble
    var gaussSurfaceCenter = SIMD3<Double>(0, 1.35, -0.55)
    /// The disc's facing direction (ignored by the bubble).
    var gaussSurfaceNormal = SIMD3<Double>(0, 0, 1)
    var gaussSurfaceRadius = 0.22
    /// Capped just under the station's half-width (0.62) so the bubble
    /// still has somewhere to move once it is inset by its own radius.
    nonisolated static let gaussRadiusRange = 0.08...0.55

    /// Measure by LOOKING: the Gauss surface rides the head ray, so
    /// turning to face part of the field carries the flux meter there
    /// without reaching for it. Head direction, not eye gaze — visionOS
    /// never hands an app the eyes, and the UI says as much.
    var lookToPlace = false
    var lookReach = 1.0
    nonisolated static let lookReachRange = 0.4...2.0

    /// The charge region as a clip box, so a look ray that misses the
    /// experiment moves nothing rather than parking the meter in a wall.
    var lookRegion: RoomBox {
        let region = samplingRegion
        return RoomBox(center: region.center, halfExtents: region.extents / 2)
    }

    func moveGaussSurface(to point: SIMD3<Double>) {
        // Inset by the surface's own radius: the flux meter is a metre-
        // wide sphere at full size, and a centre that is merely inside
        // the station still puts half the bubble in the circuit bench.
        // Moving it near a wall therefore stops early rather than
        // shrinking it — the radius is a measurement, not a decoration.
        gaussSurfaceCenter = Self.clampToStation(
            point, inset: SIMD3(repeating: gaussSurfaceRadius))
    }

    /// Everything the flux integral depends on. If none of it moved,
    /// neither did the answer.
    private struct GaussInputs: Equatable {
        var kind: GaussSurfaceKind
        var center: SIMD3<Double>
        var normal: SIMD3<Double>
        var radius: Double
        var charges: [PointCharge]
    }

    /// Deliberately outside observation: this is a memo of a value that
    /// is already derived from observed state, and registering writes to
    /// it during a read would invalidate views that only read the flux.
    @ObservationIgnored private var gaussCache: (inputs: GaussInputs, flux: Double)?

    /// Live flux through the surface, N·m²/C.
    ///
    /// The closed bubble integrates over 900 sample points, against every
    /// charge — and this is read once by the renderer and again by two
    /// labels in the controls pod, EVERY FRAME, whether or not anything
    /// moved. Memoising on the inputs makes a still surface free and
    /// leaves a moving one costing exactly what it did before. The
    /// physics is untouched: same integral, same sample count, same
    /// answer, just not recomputed for a scene that did not change.
    var gaussFlux: Double {
        let inputs = GaussInputs(kind: gaussSurfaceKind,
                                 center: gaussSurfaceCenter,
                                 normal: gaussSurfaceNormal,
                                 radius: gaussSurfaceRadius,
                                 charges: charges)
        if let cache = gaussCache, cache.inputs == inputs { return cache.flux }

        let flux: Double
        switch gaussSurfaceKind {
        case .disc:
            flux = GaussSurface.flux(
                throughDiscAt: gaussSurfaceCenter, normal: gaussSurfaceNormal,
                radius: gaussSurfaceRadius, charges: charges)
        case .bubble:
            flux = GaussSurface.flux(
                throughSphereAt: gaussSurfaceCenter, radius: gaussSurfaceRadius,
                charges: charges, samples: 900)
        }
        gaussCache = (inputs, flux)
        return flux
    }

    /// Charge strictly inside the bubble (nil for the open disc, where
    /// "enclosed" has no meaning).
    var gaussEnclosedCharge: Double? {
        guard gaussSurfaceKind == .bubble else { return nil }
        return GaussSurface.enclosedCharge(
            inSphereAt: gaussSurfaceCenter, radius: gaussSurfaceRadius, charges: charges)
    }

    /// What Gauss's law says the bubble's flux must be — shown beside the
    /// measured value so the two can be watched agreeing.
    var gaussPredictedFlux: Double? {
        guard gaussSurfaceKind == .bubble else { return nil }
        return GaussSurface.predictedFlux(
            inSphereAt: gaussSurfaceCenter, radius: gaussSurfaceRadius, charges: charges)
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

    // MARK: Electron mode

    /// The probe becomes a genuine electron (or positron, via the
    /// polarity picker): q = e, m = mₑ, launched at a cathode-ray
    /// 2×10⁶ m/s. Now REALISTIC fields curve it — a tenth of a
    /// millitesla bends it into an 11 cm circle, exactly the classic
    /// Helmholtz-coil e/m experiment. Time is compressed for display
    /// (1 s shows 0.1 µs, disclosed): the physics stays SI-exact.
    var electronMode = false
    nonisolated static let electronCharge = 1.602176634e-19
    nonisolated static let electronMass = 9.1093837015e-31
    nonisolated static let electronLaunchSpeed = 2e6
    nonisolated static let electronTimeScale = 1e-7
    nonisolated static let electronFieldRange = 2e-5...5e-4
    /// Electron-mode B remembered separately from ball-mode B.
    var electronFieldTesla = 1e-4

    /// Mode-aware signed charge and mass.
    var probeQ: Double {
        let magnitude = electronMode ? Self.electronCharge : probeChargeMagnitude
        return (probeIsPositive ? 1 : -1) * magnitude
    }
    var probeM: Double { electronMode ? Self.electronMass : Self.probeMass }
    var launchSpeed: Double {
        electronMode ? Self.electronLaunchSpeed : Self.magneticLaunchSpeed
    }

    var magneticField: SIMD3<Double> {
        guard magneticFieldOn else { return .zero }
        return SIMD3(0, electronMode ? electronFieldTesla : magneticFieldTesla, 0)
    }

    /// Cyclotron radius at the launch speed, m (mode-aware).
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
        center.y = max(world.y, Self.plateSize / 2 + 0.15)
        center.z = world.z
        // The assembly is separation wide in x and a plate tall and deep
        // in y/z, so it is clamped by its own half-size. At the widest
        // gap (1.0 m against a 1.24 m station) that leaves the capacitor
        // roughly centred, which is where a capacitor belongs — but the
        // full separation range survives, which is the range that
        // teaches E = V/d.
        capacitorCenter = Self.clampToStation(
            center,
            inset: SIMD3(separation / 2, Self.plateSize / 2, Self.plateSize / 2))
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
        // Narrowed from regionExtent * 0.55 (0.715) when this bench
        // became the middle seat of a three-station world: a flock that
        // may spread 1.43 m does not fit a 1.24 m station.
        let bound = 0.55

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
            // drifts with it. The station clamp is what stops a mutually
            // repelling pair walking into the circuit bench over a
            // minute of drift.
            next[j] = Self.clampToStation(
                position, inset: SIMD3(repeating: Self.chargeContact))
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
        // uniform B field (and electron mode) already on — the toggles
        // can't be pinched from the command line.
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "emMagnetic") {
            magneticFieldOn = true
            electronMode = true
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
        probe = nil
        probeStatus = .none
        probeIsPositive = true
        showLines = true
        capacitorOn = false
        plateVoltage = 20_000
        capacitorCenter = samplingRegion.center
        plateSeparation = 0.44
        probeChargeMagnitude = Self.defaultProbeCharge
        magneticFieldOn = false
        magneticFieldTesla = 5e4
        electronMode = false
        electronFieldTesla = 1e-4
        gaussSurfaceOn = false
        lookToPlace = false
        lookReach = 1.0
        gaussSurfaceKind = .bubble
        gaussSurfaceCenter = SIMD3(0, 1.35, -0.55)
        gaussSurfaceNormal = SIMD3(0, 0, 1)
        gaussSurfaceRadius = 0.22
        isPaused = false
        placementIndex = 2
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

    /// Spawns a charge at a given point.
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

    func moveCharge(id: UUID, to position: SIMD3<Double>) {
        guard let index = charges.firstIndex(where: { $0.id == id }) else { return }
        // Inset by the charge's own contact radius so the sphere stays
        // inside its station, not just its centre.
        charges[index].position = Self.clampToStation(
            position, inset: SIMD3(repeating: Self.chargeContact))
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
        if magneticFieldOn || electronMode {
            // A sideways push so there's a velocity for B to bend.
            state.velocity = SIMD3(launchSpeed, 0, 0)
        }
        probe = state
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
        guard !isPaused, probeStatus == .running, var state = probe,
              !charges.isEmpty || capacitorOn || magneticFieldOn else { return }

        // A stalled frame (app paused, debugger…) must not become one giant
        // physics leap.
        let frameDt = min(dt, 1.0 / 30.0)
        let simDt = frameDt * (electronMode ? Self.electronTimeScale : 1)
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
        let fieldMagnitude = simd_length(fieldVector(at: probe.position))
        let force = abs(probeQ) * fieldMagnitude
        return ProbeReadout(
            fieldMagnitude: fieldMagnitude,
            potential: ElectricField.potential(at: probe.position, dueTo: charges),
            forceMagnitude: force,
            acceleration: force / probeM,
            speed: simd_length(probe.velocity)
        )
    }

    // MARK: Selected-charge bindings for the control panels

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
