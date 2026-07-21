//
//  OpticsModel.swift
//  Physics Playground — Waves & Optics Studio
//
//  App state for the studio's two areas. The OPTICS BENCH: a laser
//  firing a fan of rays through lenses and mirrors (PhysicsCore
//  RayOptics, paraxial-exact) plus a dispersion station where white
//  light meets a REAL prism (PhysicsCore Prism — Snell at real faces,
//  Cauchy dispersion, TIR). The WAVE LAB: emitters whose crests
//  expand from their emission points (EmissionTrail — Doppler for
//  free), a walkable interference lattice, and a room-scale double
//  slit whose fringes come from the exact screen formula.
//

import Foundation
import Observation
import PhysicsCore
import simd

@MainActor
@Observable
final class OpticsModel {
    // MARK: Bench layout

    /// Bench center in the room; the optical axis runs along world X,
    /// rays fan in the vertical (XY) plane.
    nonisolated static let center = SIMD3<Double>(0, 1.35, -0.9)
    nonisolated static let railHalf = 0.75
    nonisolated static let sourceX = -0.65
    nonisolated static let elementBudget = 6
    nonisolated static let focalRange = 0.1...0.6

    // MARK: Elements

    enum ElementKind: String, CaseIterable, Codable {
        case convergingLens, divergingLens, mirror, screen

        var displayName: String {
            switch self {
            case .convergingLens: "Converging lens"
            case .divergingLens: "Diverging lens"
            case .mirror: "Mirror"
            case .screen: "Screen"
            }
        }
    }

    struct Element: Identifiable, Equatable {
        let id: UUID
        let kind: ElementKind
        var x: Double
        /// Lenses only: focal length magnitude, m.
        var focal: Double = 0.25

        var benchElement: RayOptics.BenchElement {
            switch kind {
            case .convergingLens: .lens(x: x, focalLength: focal)
            case .divergingLens: .lens(x: x, focalLength: -focal)
            case .mirror: .mirror(x: x)
            case .screen: .screen(x: x)
            }
        }
    }

    private(set) var elements: [Element] = []
    private(set) var selectedID: UUID?

    var selected: Element? { elements.first { $0.id == selectedID } }

    // MARK: Source

    enum SourceMode: String, CaseIterable {
        case parallel, point
    }
    var sourceMode: SourceMode = .parallel
    nonisolated static let rayCount = 7

    // MARK: Insight

    private(set) var insightText = ""

    // MARK: Editing

    @discardableResult
    func addElement(_ kind: ElementKind) -> UUID? {
        guard elements.count < Self.elementBudget else { return nil }
        // Drop new elements at successive free spots to the right.
        let x = ([Self.sourceX + 0.35] + elements.map { $0.x + 0.3 }).max() ?? 0
        let element = Element(id: UUID(), kind: kind,
                              x: min(x, Self.railHalf - 0.05))
        elements.append(element)
        selectedID = element.id
        switch kind {
        case .convergingLens:
            insightText = "A converging lens bends every ray toward the axis by y/f — parallel rays meet at the focal point; a point source images at 1/f = 1/dₒ + 1/dᵢ. Drag the lens and watch the crossing obey."
        case .divergingLens:
            insightText = "A diverging lens fans rays outward — they never meet, but traced backward they appear to come from a virtual focus on the source side."
        case .mirror:
            insightText = "The flat mirror folds the bench: rays head back left at equal angles. Put a lens in the return path for a two-pass system."
        case .screen:
            insightText = "The screen absorbs whatever reaches it — slide it to the ray crossing and the image lands in sharp focus."
        }
        return element.id
    }

    func removeSelected() {
        guard let selectedID else { return }
        elements.removeAll { $0.id == selectedID }
        self.selectedID = elements.last?.id
    }

    func select(id: UUID) {
        guard elements.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func moveElement(id: UUID, toX x: Double) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        elements[index].x = min(max(x, Self.sourceX + 0.1), Self.railHalf - 0.02)
    }

    func setFocal(id: UUID, _ focal: Double) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        elements[index].focal = min(max(focal, Self.focalRange.lowerBound),
                                    Self.focalRange.upperBound)
    }

    // MARK: The trace

    /// All ray polylines in bench coordinates (x along the axis, y up).
    var tracedRays: [[SIMD2<Double>]] {
        let bench = elements.map(\.benchElement)
        let bounds = (Self.sourceX)...(Self.railHalf)
        var rays: [RayOptics.BenchRay] = []
        switch sourceMode {
        case .parallel:
            for index in 0..<Self.rayCount {
                let y = -0.12 + 0.24 * Double(index) / Double(Self.rayCount - 1)
                rays.append(RayOptics.BenchRay(x: Self.sourceX, y: y, slope: 0))
            }
        case .point:
            for index in 0..<Self.rayCount {
                let slope = -0.28 + 0.56 * Double(index) / Double(Self.rayCount - 1)
                rays.append(RayOptics.BenchRay(x: Self.sourceX, y: 0, slope: slope))
            }
        }
        return rays.map {
            RayOptics.trace($0, elements: bench, bounds: bounds)
        }
    }

    /// The full 3D light bundle: a circular beam or a cone of rays,
    /// traced through ideal elements in world coordinates. This is the
    /// rendered light — the 2D tracedRays stays as the exactly-tested
    /// paraxial reference.
    var tracedRays3D: [[SIMD3<Double>]] {
        let elements3D = elements.map { element -> RayOptics3D.Element in
            let kind: RayOptics3D.Element.Kind
            switch element.kind {
            case .convergingLens: kind = .lens(focalLength: element.focal)
            case .divergingLens: kind = .lens(focalLength: -element.focal)
            case .mirror: kind = .mirror
            case .screen: kind = .screen
            }
            return RayOptics3D.Element(
                x: Self.center.x + element.x, kind: kind, apertureRadius: 0.17)
        }
        let bounds = (Self.center.x + Self.sourceX)...(Self.center.x + Self.railHalf)
        let rays: [RayOptics3D.Ray]
        switch sourceMode {
        case .parallel:
            rays = RayOptics3D.parallelBeam(
                fromX: Self.center.x + Self.sourceX, center: Self.center,
                radius: 0.13, rings: 3, spokes: 8)
        case .point:
            rays = RayOptics3D.pointCone(
                from: SIMD3(Self.center.x + Self.sourceX, Self.center.y, Self.center.z),
                halfAngle: 0.26, rings: 3, spokes: 8)
        }
        return RayOptics3D.trace(
            rays: rays, elements: elements3D, axisCenter: Self.center, bounds: bounds)
    }

    /// The light landing on the nearest screen: its centroid and blur
    /// radius. Slide the screen through focus and this disc collapses
    /// to a point, then blooms again — depth of focus made touchable.
    var screenSpot: (center: SIMD3<Double>, radius: Double)? {
        let screens = elements.filter { $0.kind == .screen }
        guard !screens.isEmpty else { return nil }
        let screenXs = Set(screens.map { Self.center.x + $0.x })
        var hits: [SIMD3<Double>] = []
        for line in tracedRays3D {
            guard let end = line.last,
                  screenXs.contains(where: { abs($0 - end.x) < 1e-6 }) else { continue }
            hits.append(end)
        }
        guard hits.count >= 2 else { return nil }
        let centroid = hits.reduce(SIMD3<Double>.zero, +) / Double(hits.count)
        let radius = hits.map { simd_distance($0, centroid) }.max() ?? 0
        return (centroid, max(radius, 0.004))
    }

    /// Thin-lens prediction for the FIRST lens: (image x, di, dₒ, m) —
    /// nil when there's no lens or the image is at infinity.
    var imagePrediction: (x: Double, imageDistance: Double, objectDistance: Double, magnification: Double)? {
        guard sourceMode == .point,
              let lens = elements
                .filter({ $0.kind == .convergingLens || $0.kind == .divergingLens })
                .min(by: { $0.x < $1.x })
        else { return nil }
        let objectDistance = lens.x - Self.sourceX
        let focal = lens.kind == .convergingLens ? lens.focal : -lens.focal
        guard abs(objectDistance - focal) > 1e-6 else { return nil }
        let imageDistance = RayOptics.imageDistance(
            objectDistance: objectDistance, focalLength: focal)
        return (lens.x + imageDistance, imageDistance, objectDistance,
                RayOptics.magnification(objectDistance: objectDistance,
                                        imageDistance: imageDistance))
    }

    // MARK: - Studio areas

    enum StudioArea: String, CaseIterable {
        case optics, waveLab
    }
    var area: StudioArea = .optics {
        didSet {
            guard area != oldValue else { return }
            insightText = area == .waveLab
                ? "Every glowing shell is a crest expanding from where it was BORN. Grab an emitter and glide it: crests bunch ahead and stretch behind — the Doppler effect, live."
                : "The beam is live — drag lenses along the rail. Below the bench, white light meets a real prism: rotate it and watch the spectrum fan."
        }
    }

    // MARK: - Prism & dispersion station (optics area)

    /// The station sits below the bench; its trace lives in the
    /// vertical x–y plane at this z.
    nonisolated static let prismStationCenter = SIMD3<Double>(-0.35, 1.62, -1.05)
    nonisolated static let prismSourceX = -1.0
    nonisolated static let prismRotationRange = -20.0...15.0
    /// Seven wavelengths spanning violet to red, nm.
    nonisolated static let prismWavelengths: [Double] = [410, 445, 480, 520, 560, 610, 660]

    var prismRotationDegrees = 0.0

    var prismGeometry: Prism.Geometry {
        Prism.Geometry(
            apex: SIMD2(Self.prismStationCenter.x, Self.prismStationCenter.y + 0.16),
            apexAngle: .pi / 3,
            rotation: prismRotationDegrees * .pi / 180,
            sideLength: 0.26)
    }

    /// One traced polyline per wavelength, in station-plane coords.
    var prismTraces: [(nanometers: Double, line: [SIMD2<Double>])] {
        let origin = SIMD2(Self.prismSourceX, Self.prismStationCenter.y)
        let geometry = prismGeometry
        return Self.prismWavelengths.map { nanometers in
            (nanometers, Prism.trace(
                from: origin, direction: SIMD2(1, 0), geometry: geometry,
                index: Refraction.cauchyIndex(wavelengthNanometers: nanometers)))
        }
    }

    /// Entry angles for the annotation: (incidence, refraction), rad —
    /// straight from Snell at the entry face for the middle wavelength.
    var prismEntryAngles: (incidence: Double, refraction: Double) {
        let incidence = abs(.pi / 6 - prismRotationDegrees * .pi / 180)
        let n = Refraction.cauchyIndex(wavelengthNanometers: 520)
        let refraction = asin(min(1, sin(incidence) / n))
        return (incidence, refraction)
    }

    /// True when any wavelength internally reflects instead of exiting
    /// through the far face — the pod names the moment.
    var prismShowsTIR: Bool {
        prismTraces.contains { $0.line.count > 4 }
    }

    // MARK: - Wave Lab

    nonisolated static let labCenter = SIMD3<Double>(0, 1.3, -0.85)
    nonisolated static let labHalfExtent = 0.8
    nonisolated static let emitterBudget = 4
    nonisolated static let labFrequencyRange = 0.5...4.5
    nonisolated static let labSpeedRange = 0.25...0.75
    nonisolated static let shellBudgetPerSource = 10

    struct LabEmitter: Identifiable, Equatable {
        let id: UUID
        var position: SIMD3<Double>
    }

    private(set) var emitters: [LabEmitter] = []
    private(set) var selectedEmitterID: UUID?
    var selectedEmitter: LabEmitter? { emitters.first { $0.id == selectedEmitterID } }

    var labFrequency = 1.1 {
        didSet {
            for id in trails.keys { trails[id]?.period = 1 / labFrequency }
            rigTrail.period = 1 / labFrequency
        }
    }
    var labWaveSpeed = 0.45
    var labPaused = false
    var labSlowMotion = false
    private(set) var labTime = 0.0
    var labWavelength: Double { labWaveSpeed / labFrequency }

    private var trails: [UUID: EmissionTrail] = [:]
    private var rigTrail = EmissionTrail(period: 1 / 1.1, capacity: 10)

    /// Advances the lab clock: crests are emitted at the emitters'
    /// CURRENT positions, so dragging a source is the Doppler demo.
    func stepLab(dt: Double) {
        guard area == .waveLab, !labPaused else { return }
        advanceLab(by: dt * (labSlowMotion ? 0.25 : 1))
    }

    /// One 90 Hz frame while paused — freeze the room, nudge time.
    func stepLabOneFrame() {
        labPaused = true
        advanceLab(by: 1.0 / 90.0)
    }

    private func advanceLab(by dt: Double) {
        labTime += dt
        if slitRigOn {
            rigTrail.advance(to: labTime, sourcePosition: Self.labCenter + Self.rigSourceOffset)
        } else {
            for emitter in emitters {
                var trail = trails[emitter.id]
                    ?? EmissionTrail(period: 1 / labFrequency,
                                     capacity: Self.shellBudgetPerSource)
                trail.advance(to: labTime, sourcePosition: emitter.position)
                trails[emitter.id] = trail
            }
        }
    }

    /// Every live crest in the room right now.
    func labShells() -> [(center: SIMD3<Double>, radius: Double)] {
        let source = slitRigOn ? [rigTrail] : emitters.compactMap { trails[$0.id] }
        return source.flatMap { $0.shells(at: labTime, speed: labWaveSpeed) }
            .filter { $0.radius < 1.7 }
    }

    /// Sources for the interference lattice. With the rig on, the two
    /// SLITS are the sources — Huygens' principle, literally.
    var labWaveSources: [WaveSource] {
        if slitRigOn {
            let slits = slitCenters
            return [WaveSource(position: slits.a), WaveSource(position: slits.b)]
        }
        return emitters.map { WaveSource(position: $0.position) }
    }

    @discardableResult
    func addEmitter(at position: SIMD3<Double>? = nil) -> UUID? {
        guard emitters.count < Self.emitterBudget else { return nil }
        let spot = position ?? Self.labCenter
            + SIMD3(Double(emitters.count) * 0.3 - 0.3, 0.05, 0.1)
        let emitter = LabEmitter(id: UUID(), position: clampToLab(spot))
        emitters.append(emitter)
        selectedEmitterID = emitter.id
        insightText = emitters.count >= 2
            ? "Two emitters, one medium: where crests meet crests the field doubles; where crest meets trough, silence. Walk the bright and dead zones."
            : "One emitter, expanding shells — each crest is one period of the wave, one wavelength apart."
        return emitter.id
    }

    func duplicateSelectedEmitter() {
        guard let selected = selectedEmitter else { return }
        addEmitter(at: selected.position + SIMD3(0.25, 0, 0))
    }

    func removeSelectedEmitter() {
        guard let selectedEmitterID else { return }
        emitters.removeAll { $0.id == selectedEmitterID }
        trails[selectedEmitterID] = nil
        self.selectedEmitterID = emitters.last?.id
    }

    func selectEmitter(id: UUID) {
        guard emitters.contains(where: { $0.id == id }) else { return }
        selectedEmitterID = id
    }

    func moveEmitter(id: UUID, toWorld position: SIMD3<Double>) {
        guard let index = emitters.firstIndex(where: { $0.id == id }) else { return }
        emitters[index].position = clampToLab(position)
    }

    private func clampToLab(_ p: SIMD3<Double>) -> SIMD3<Double> {
        let c = Self.labCenter
        let h = Self.labHalfExtent
        return SIMD3(min(max(p.x, c.x - h), c.x + h),
                     min(max(p.y, max(c.y - h, 0.35)), c.y + h),
                     min(max(p.z, c.z - h), c.z + h))
    }

    // MARK: - Double-slit rig (wave lab)

    nonisolated static let rigSourceOffset = SIMD3<Double>(-0.75, 0, 0)
    nonisolated static let slitSeparationRange = 0.1...0.3
    nonisolated static let slitWidthRange = 0.02...0.08

    var slitRigOn = false {
        didSet {
            guard slitRigOn != oldValue else { return }
            rigTrail.reset()
            // Fringes are λL/d apart: room-scale slits need the short
            // end of the lab's wavelength range to show several.
            if slitRigOn, labFrequency < 3.5 { labFrequency = 4.0 }
            insightText = slitRigOn
                ? "Crests hit the barrier; only the two slits get through — and each slit becomes a new source (Huygens). Where their paths differ by whole wavelengths, bright. Half, dark. Walk between the fringes."
                : "Free emitters again — place them anywhere in the room."
        }
    }
    var slitSeparation = 0.2
    var slitWidth = 0.04
    var showFringeRays = false
    /// Barrier and screen x, relative to the lab center.
    var rigBarrierX = -0.15
    var rigScreenX = 0.55

    var slitCenters: (a: SIMD3<Double>, b: SIMD3<Double>) {
        let c = Self.labCenter
        return (SIMD3(c.x + rigBarrierX, c.y + slitSeparation / 2, c.z),
                SIMD3(c.x + rigBarrierX, c.y - slitSeparation / 2, c.z))
    }

    var fringeDistance: Double { max(rigScreenX - rigBarrierX, 0.15) }

    var fringeSpacing: Double {
        DoubleSlit.fringeSpacing(distance: fringeDistance,
                                 separation: slitSeparation,
                                 wavelength: labWavelength)
    }

    func fringeIntensity(y: Double) -> Double {
        DoubleSlit.intensity(y: y, distance: fringeDistance,
                             separation: slitSeparation,
                             slitWidth: slitWidth, wavelength: labWavelength)
    }

    func fringeMaxima(count: Int) -> [Double] {
        DoubleSlit.brightFringes(distance: fringeDistance,
                                 separation: slitSeparation,
                                 wavelength: labWavelength, count: count)
    }

    func moveBarrier(toWorldX x: Double) {
        rigBarrierX = min(max(x - Self.labCenter.x, -0.35), rigScreenX - 0.2)
    }

    func moveScreen(toWorldX x: Double) {
        rigScreenX = min(max(x - Self.labCenter.x, rigBarrierX + 0.2), 0.8)
    }

    // MARK: Reset

    func reset() {
        elements = []
        selectedID = nil
        sourceMode = .parallel
        insightText = ""
        area = .optics
        prismRotationDegrees = 0
        emitters = []
        trails = [:]
        rigTrail.reset()
        selectedEmitterID = nil
        labTime = 0
        labFrequency = 1.1
        labWaveSpeed = 0.45
        labPaused = false
        labSlowMotion = false
        slitRigOn = false
        slitSeparation = 0.2
        slitWidth = 0.04
        showFringeRays = false
        rigBarrierX = -0.15
        rigScreenX = 0.55
        addEmitter()
        // The welcome scene: one converging lens focusing the beam.
        if let id = addElement(.convergingLens) {
            moveElement(id: id, toX: 0.0)
        }
        insightText = "Parallel rays meet at the focal point — drag the lens, slide its focal length, or switch to a point source and watch the thin-lens equation draw itself."
    }

    init() {
        reset()
        #if DEBUG
        // Debug launches: -studioArea waveLab, -studioSlit 1.
        if UserDefaults.standard.string(forKey: "studioArea") == "waveLab" {
            area = .waveLab
        }
        if UserDefaults.standard.bool(forKey: "studioSlit") {
            area = .waveLab
            slitRigOn = true
        }
        #endif
    }
}
