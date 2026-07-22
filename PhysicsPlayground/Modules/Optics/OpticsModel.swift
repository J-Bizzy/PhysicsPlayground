//
//  OpticsModel.swift
//  Physics Playground — Optics Studio
//
//  App state for one room with three light stations, separated by
//  DIRECTION so nothing ever stacks in view: the thin-lens BENCH dead
//  ahead (PhysicsCore RayOptics, paraxial-exact), the DISPERSION
//  station along the left wall (a real prism splitting white light —
//  Snell + Cauchy + TIR), and the REFRACTION corner on the right — a
//  hand-held laser pointer that always aims at a glass block, so
//  WHERE YOU CARRY IT is the angle of incidence. Waves live in the
//  Waves module; this room is all light.
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

    // MARK: - Dispersion station (the left wall)

    /// The station lives on the LEFT of the room, its trace plane
    /// facing the room center: local x runs INTO the room's depth
    /// (world −z), local y is up. Turn your head left and the whole
    /// experiment is in profile.
    nonisolated static let dispersionAnchor = SIMD3<Double>(-1.15, 1.32, -0.55)
    nonisolated static let prismSourceLocalX = -0.5
    nonisolated static let prismRotationRange = -20.0...15.0
    /// Seven wavelengths spanning violet to red, nm.
    nonisolated static let prismWavelengths: [Double] = [410, 445, 480, 520, 560, 610, 660]

    /// Starts at −6°: every wavelength clears the exit face (at 0°
    /// blue is ALREADY past its critical angle — the critical angle is
    /// wavelength-dependent — which is a great discovery but a
    /// confusing opening scene).
    var prismRotationDegrees = -6.0

    /// Station-local trace coordinates → the room.
    nonisolated static func dispersionWorld(_ local: SIMD2<Double>) -> SIMD3<Double> {
        SIMD3(dispersionAnchor.x,
              dispersionAnchor.y + local.y,
              dispersionAnchor.z - local.x)
    }

    var prismGeometry: Prism.Geometry {
        Prism.Geometry(
            apex: SIMD2(0, 0.15),
            apexAngle: .pi / 3,
            rotation: prismRotationDegrees * .pi / 180,
            sideLength: 0.26)
    }

    /// One traced polyline per wavelength, in station-local coords.
    var prismTraces: [(nanometers: Double, line: [SIMD2<Double>])] {
        let origin = SIMD2(Self.prismSourceLocalX, 0.0)
        let geometry = prismGeometry
        return Self.prismWavelengths.map { nanometers in
            (nanometers, Prism.trace(
                from: origin, direction: SIMD2(1, 0), geometry: geometry,
                index: Refraction.cauchyIndex(wavelengthNanometers: nanometers),
                escape: 0.5))
        }
    }

    /// Entry angles for the annotation: (incidence, refraction), rad.
    var prismEntryAngles: (incidence: Double, refraction: Double) {
        let incidence = abs(.pi / 6 - prismRotationDegrees * .pi / 180)
        let n = Refraction.cauchyIndex(wavelengthNanometers: 520)
        let refraction = asin(min(1, sin(incidence) / n))
        return (incidence, refraction)
    }

    /// True when any wavelength internally reflects instead of
    /// exiting through the far face — the pod names the moment.
    var prismShowsTIR: Bool {
        prismTraces.contains { $0.line.count > 4 }
    }

    // MARK: - Refraction corner (the right side)

    /// A glass block and a hand-held laser that ALWAYS aims at it:
    /// carrying the laser around the room IS the incidence-angle
    /// control. No sliders between your hand and Snell's law.
    nonisolated static let refractionAnchor = SIMD3<Double>(1.15, 1.3, -0.75)
    nonisolated static let blockHalfExtents = SIMD3<Double>(0.055, 0.16, 0.22)
    nonisolated static let blockIndexRange = 1.3...1.8

    var blockCenter = OpticsModel.refractionAnchor
    var laserPosition = SIMD3<Double>(0.7, 1.35, -0.25)
    var blockIndex = 1.5

    var laserAim: SIMD3<Double> {
        let offset = blockCenter - laserPosition
        let length = simd_length(offset)
        return length > 1e-6 ? offset / length : SIMD3(0, 0, -1)
    }

    /// The beam's whole path: laser → entry → (bounces) → out.
    var blockTrace: [SIMD3<Double>] {
        GlassBlock.trace(
            from: laserPosition, direction: laserAim,
            center: blockCenter, halfExtents: Self.blockHalfExtents,
            index: blockIndex, escape: 0.7)
    }

    /// Entry-point geometry for the in-room annotation.
    var blockEntry: (point: SIMD3<Double>, normal: SIMD3<Double>,
                     incidence: Double, refraction: Double)? {
        guard let hit = GlassBlock.entry(
            from: laserPosition, direction: laserAim,
            center: blockCenter, halfExtents: Self.blockHalfExtents) else { return nil }
        let cosine = max(-1, min(1, -simd_dot(laserAim, hit.normal)))
        let incidence = acos(cosine)
        let refraction = asin(min(1, sin(incidence) / blockIndex))
        return (hit.point, hit.normal, incidence, refraction)
    }

    /// The beam bounced inside at least once — the light-pipe moment.
    var blockShowsTIR: Bool { blockTrace.count > 4 }

    func moveLaser(toWorld position: SIMD3<Double>) {
        laserPosition = SIMD3(
            min(max(position.x, -0.4), 1.8),
            min(max(position.y, 0.6), 2.1),
            min(max(position.z, -1.9), 0.3))
    }

    func moveBlock(toWorld position: SIMD3<Double>) {
        blockCenter = SIMD3(
            min(max(position.x, 0.4), 1.7),
            min(max(position.y, 0.8), 1.9),
            min(max(position.z, -1.6), -0.3))
    }

        // MARK: Reset

    func reset() {
        elements = []
        selectedID = nil
        sourceMode = .parallel
        insightText = ""
        prismRotationDegrees = -6
        blockCenter = Self.refractionAnchor
        laserPosition = SIMD3(0.7, 1.35, -0.25)
        blockIndex = 1.5
        // The welcome scene: one converging lens focusing the beam.
        if let id = addElement(.convergingLens) {
            moveElement(id: id, toX: 0.0)
        }
        insightText = "Parallel rays meet at the focal point — drag the lens, slide its focal length, or switch to a point source and watch the thin-lens equation draw itself."
    }

    init() {
        reset()
    }
}
