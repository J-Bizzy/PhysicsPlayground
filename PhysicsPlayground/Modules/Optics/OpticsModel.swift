//
//  OpticsModel.swift
//  Physics Playground — Ray Optics module
//
//  App state for the optical bench: a laser source firing a fan of
//  rays down a rail, through lenses and off mirrors the user places
//  and drags. The trace comes from PhysicsCore's RayOptics — paraxial-
//  exact, so the image marker sits precisely where the thin-lens
//  equation says it must.
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

    // MARK: Reset

    func reset() {
        elements = []
        selectedID = nil
        sourceMode = .parallel
        insightText = ""
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
