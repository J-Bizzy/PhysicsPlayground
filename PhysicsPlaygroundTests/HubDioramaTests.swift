//
//  HubDioramaTests.swift
//  PhysicsPlaygroundTests
//
//  The home's dioramas are the labs in miniature, so their motion is held
//  to the labs' physics: the cradle swings at the exact large-amplitude
//  period of the lab's 0.55 m cables and hands the swing across; the prism
//  sends violet further than red, onto its screen; the coil's LED lights
//  both colours and is dark when the magnet stops; the orrery keeps
//  Kepler's third law and solves Kepler's equation; and every lab's stage
//  is the same size in its portal, which is what makes them one set. In the
//  home nothing frames them and nothing stands under them: each floats,
//  scaled to one footprint at one height with its name under it, turning
//  slowly.
//

import XCTest
import PhysicsCore
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class HubDioramaTests: XCTestCase {

    // MARK: The cradle

    /// T = 4√(L/g)·K(sin(θ₀/2)), the complete elliptic integral by the
    /// arithmetic–geometric mean: the large-amplitude period, about 2 %
    /// longer than 2π√(L/g) at 0.55 rad.
    func testTheCradleSwingsAtTheExactLargeAmplitudePeriod() {
        let swing = HubVignettes.cradleSwing
        let k = sin(swing.amplitude / 2)
        var a = 1.0, b = (1 - k * k).squareRoot()
        for _ in 0..<12 { (a, b) = ((a + b) / 2, (a * b).squareRoot()) }
        let K = Double.pi / (2 * a)
        let exact = 4 * (0.55 / 9.81).squareRoot() * K
        XCTAssertEqual(swing.period, exact, accuracy: exact * 1e-4)
        XCTAssertGreaterThan(swing.period, 2 * .pi * (0.55 / 9.81).squareRoot() * 1.015)
    }

    /// Released on the left, at rest on the bottom, out on the right, and
    /// back — each end ball still while the other moves.
    func testTheCradleHandsTheSwingAcross() {
        let swing = HubVignettes.cradleSwing
        let q = swing.quarter
        let start = swing.cradle(at: 0)
        XCTAssertEqual(start.left, -swing.amplitude, accuracy: 1e-9)
        XCTAssertEqual(start.right, 0)
        XCTAssertEqual(swing.cradle(at: q).left, 0, accuracy: 1e-3)
        XCTAssertEqual(swing.cradle(at: 2 * q).right, swing.amplitude, accuracy: 1e-3)
        for step in 0..<200 {
            let ends = swing.cradle(at: Double(step) * swing.period / 200)
            XCTAssertTrue(ends.left == 0 || ends.right == 0, "both end balls moved at once")
            XCTAssertLessThanOrEqual(ends.left, 0)
            XCTAssertGreaterThanOrEqual(ends.right, 0)
        }
    }

    /// The miniature is the lab's opening cradle: five bobs one diameter
    /// apart, each one cable length below its collar, the end one released
    /// from the lab's angle — and no frame, because the lab has none.
    func testTheCradleIsTheLabsOwnCradle() throws {
        let built = HubVignettes.cradleDiorama()
        built.animate(0)
        let radius = Float(PendulumsModel.cradleBobRadius)
        let length = Float(PendulumsModel.cradleCableLength)
        var collars: [Entity] = []
        for index in 0..<5 {
            let collar = try XCTUnwrap(built.entity.findEntity(named: "cradle-collar-\(index)"))
            let bob = try XCTUnwrap(built.entity.findEntity(named: "cradle-bob-\(index)"))
            // Collar and bob share the bench, so this is the lab's metres.
            XCTAssertEqual(simd_distance(collar.position, bob.position), length, accuracy: 1e-5)
            collars.append(collar)
            if index == 0 {
                let hang = bob.position - collar.position
                XCTAssertEqual(Double(atan2(hang.x, -hang.y)), -PendulumsModel.cradleRelease, accuracy: 1e-4)
            }
        }
        for (a, b) in zip(collars, collars.dropFirst()) {
            XCTAssertEqual(b.position.x - a.position.x, 2 * radius, accuracy: 1e-6)
        }
        XCTAssertNil(built.entity.findEntity(named: "HubCradle"))
    }

    // MARK: The circuit

    /// The miniature is the circuit the lab opens on: every part where the
    /// lab stands it relative to the battery, on the lab's own axis.
    func testTheCircuitIsTheLabsStarterLoop() throws {
        let built = HubVignettes.circuitsDiorama()
        let model = CircuitsModel()
        let battery = try XCTUnwrap(model.components.first { $0.kind == .battery })
        let batteryEntity = try XCTUnwrap(built.entity.findEntity(named: "circuit-\(battery.kind)"))
        XCTAssertEqual(model.components.count, CircuitsModel.starterParts.count)
        XCTAssertEqual(model.wires.count, CircuitsModel.starterWires.count)
        for component in model.components {
            let entity = try XCTUnwrap(built.entity.findEntity(named: "circuit-\(component.kind)"))
            let expected = SIMD3<Float>(component.position - battery.position)
            XCTAssertLessThan(simd_distance(entity.position - batteryEntity.position, expected), 1e-5,
                              "\(component.kind) does not stand where the lab stands it")
        }
    }

    // MARK: The prism

    /// White light at least deviation: violet turned further than red, the
    /// fan a few degrees wide, and both ends of it on the screen.
    func testTheSpectrumFallsInOrderOnTheScreen() throws {
        let bench = HubVignettes.OpticsBench.shared
        let prism = OpticalElement(
            position: bench.prismCentre, orientation: simd_quatd(angle: 0, axis: SIMD3(0, 0, 1)),
            shape: .prism(apexAngle: OpticsModel.prismApex, side: OpticsModel.prismSide,
                          length: OpticsModel.prismHeight),
            glass: HubVignettes.dioramaGlass)
        func landing(_ nm: Double) throws -> SIMD3<Double> {
            let trace = LightTracer.trace(
                [.init(origin: bench.start, direction: bench.incoming, nanometers: nm)],
                elements: [prism], room: LightTracer.Room(maxSegment: 0.4),
                options: .init(followsPartialReflections: false))
            let out = try XCTUnwrap(trace.segments.last { $0.inside == nil && $0.direction.y < 0 })
            let t = simd_dot(bench.screenPoint - out.a, bench.screenNormal)
                / simd_dot(out.b - out.a, bench.screenNormal)
            return out.a + (out.b - out.a) * t
        }
        let violet = try landing(420), red = try landing(660)
        XCTAssertLessThan(violet.y, red.y, "violet should be bent further, toward the base")
        for hit in [violet, red] {
            XCTAssertLessThan(simd_distance(hit, bench.screenPoint), 0.05, "the light missed the screen")
        }
    }

    // MARK: The coil

    /// One stroke lights both colours — one going in, the other coming out —
    /// and the LED is dark where the magnet turns round and stands still.
    func testTheCoilLightsBothWaysAndIsDarkAtRest() {
        let levels = HubVignettes.coilLEDLevels
        XCTAssertGreaterThanOrEqual(levels.max() ?? 0, 3, "the red LED never plainly lit")
        XCTAssertLessThanOrEqual(levels.min() ?? 0, -3, "the green LED never plainly lit")
        // sin(2πt/P) turns at a quarter and three quarters of the stroke.
        for phase in [0.25, 0.75] {
            XCTAssertEqual(levels[Int(phase * Double(levels.count))], 0,
                           "lit while the magnet stood still at \(phase)")
        }
    }

    // MARK: The orrery

    /// T² = a³ in years and AU: the table's real periods and axes agree.
    func testTheOrreryKeepsKeplersThirdLaw() {
        for planet in HubVignettes.orreryPlanets {
            XCTAssertEqual(planet.period * planet.period / (planet.a * planet.a * planet.a), 1,
                           accuracy: 0.002, planet.name)
        }
    }

    /// The true anomaly it places a planet by satisfies Kepler's equation.
    func testTheTrueAnomalySolvesKeplersEquation() {
        let e = 0.2056
        for mean in stride(from: 0.1, to: 6.2, by: 0.37) {
            let nu = HubVignettes.trueAnomaly(meanAnomaly: mean, eccentricity: e)
            let E = 2 * atan(sqrt((1 - e) / (1 + e)) * tan(nu / 2))
            var back = E - e * sin(E)
            if back < 0 { back += 2 * .pi }
            XCTAssertEqual(back, mean, accuracy: 1e-9)
        }
    }

    // MARK: The set

    /// Every lab's stage is the same size in its portal, whatever stands on
    /// it: the one thing that makes seven exhibits a row. Nothing is drawn
    /// there, so it is measured by where it puts its radius.
    func testEveryStageIsTheSameSizeInItsPortal() throws {
        var widths: [String: Float] = [:]
        for id in ModuleCatalog.allIDs {
            let built = HubVignettes.make(for: id)
            let stage = try XCTUnwrap(built.entity.findEntity(named: HubVignettes.stageName),
                                      "\(id) stands on no stage")
            widths[id] = simd_distance(stage.convert(position: .zero, to: built.entity),
                                       stage.convert(position: [HubVignettes.stageRadius, 0, 0],
                                                     to: built.entity))
        }
        let reference = try XCTUnwrap(widths.values.first)
        for (id, width) in widths {
            XCTAssertEqual(width, reference, accuracy: reference * 0.002, "\(id)'s stage differs")
        }
    }

    // MARK: The home

    private func home() -> HubScene {
        let scene = HubScene()
        scene.openingAlreadyPlayed = true
        scene.build(modules: ModuleCatalog.all(appModel: AppModel()))
        return scene
    }

    /// Every lab is scaled to a footprint of `PortalLayout.footprintRadius`
    /// whose centre and tilt are the layout's — one size, one height, and
    /// the row is the frame.
    func testEveryLabFillsOneFootprintAtOneHeight() throws {
        let scene = home()
        let layout = PortalLayout.portals(count: scene.portalIDs.count)
        for (id, slot) in zip(scene.portalIDs, layout) {
            let anchor = try XCTUnwrap(scene.portal(id))
            let stage = try XCTUnwrap(anchor.findEntity(named: HubVignettes.stageName),
                                      "\(id) has no footprint")
            let centre = stage.convert(position: .zero, to: nil)
            let edge = stage.convert(position: [HubVignettes.stageRadius, 0, 0], to: nil)
            XCTAssertEqual(simd_distance(centre, edge), Float(PortalLayout.footprintRadius),
                           accuracy: 1e-4, "\(id) is another size")
            let expected = SIMD3<Float>(PortalLayout.footprintCentre(of: slot))
            XCTAssertLessThan(simd_distance(centre, expected), 1e-4,
                              "\(id) floats somewhere else")
            // Tipped toward the wearer by the tilt.
            let tilt = PortalLayout.footprintTilt
            let normal = SIMD3<Float>(SIMD3<Double>(0, cos(tilt), 0) + slot.toward * sin(tilt))
            XCTAssertGreaterThan(simd_dot(stage.convert(direction: [0, 1, 0], to: nil), normal),
                                 1 - 1e-5, "\(id) is tipped another way")
        }
    }

    /// Nothing frames a lab and nothing stands under it: no glass pane, no
    /// ring, no plinth — the stage is a point, nothing drawn.
    func testNothingFramesALabOrStandsUnderIt() throws {
        let scene = home()
        for id in scene.portalIDs {
            let anchor = try XCTUnwrap(scene.portal(id))
            for name in ["portal-pane", "portal-rim", HubScene.vignetteSquareName] {
                XCTAssertNil(anchor.findEntity(named: name), "\(id) still has a \(name)")
            }
            let stage = try XCTUnwrap(anchor.findEntity(named: HubVignettes.stageName))
            XCTAssertTrue(stage.children.isEmpty, "\(id) stands on something")
            XCTAssertNil(stage.components[ModelComponent.self], "\(id) stands on something")
        }
        XCTAssertNil(PropCache.prototype(named: "HubStage"), "the plinth is still in the bundle")
    }

    /// A lab's name hangs under it, clear of it, and every name on one row.
    func testTheNamesHangUnderTheirLabsInOneRow() throws {
        let scene = home()
        var rows: [Float] = []
        for id in scene.portalIDs {
            let anchor = try XCTUnwrap(scene.portal(id))
            let body = try XCTUnwrap(anchor.findEntity(named: "portal-body"))
            let label = try XCTUnwrap(anchor.findEntity(named: "portal-label-extent"))
            let lab = body.visualBounds(relativeTo: anchor)
            let name = label.visualBounds(relativeTo: anchor)
            XCTAssertLessThan(name.max.y, lab.min.y, "\(id)'s name overlaps it")
            XCTAssertGreaterThan(name.max.y, lab.min.y - 0.08, "\(id)'s name hangs far below it")
            rows.append(name.max.y)
        }
        XCTAssertLessThan((rows.max() ?? 0) - (rows.min() ?? 0), 1e-4, "the names are not one row")
    }

    /// The turn starts from rest, builds without a jump, and never passes
    /// ±12° — a turntable easing back and forth, not a spin.
    func testTheLabsTurnGentlyFromRest() {
        for phase in [0.0, 0.73, 2.19, 4.38] {
            XCTAssertEqual(HubScene.swayAngle(elapsed: -1, phase: phase), 0)
            XCTAssertEqual(HubScene.swayAngle(elapsed: 0, phase: phase), 0, accuracy: 1e-6)
            var previous: Float = 0
            for step in 1...3000 {
                let angle = HubScene.swayAngle(elapsed: Double(step) / 90, phase: phase)
                XCTAssertLessThanOrEqual(abs(angle), 0.21 + 1e-6)
                XCTAssertLessThan(abs(angle - previous), 0.004,
                                  "the turn jumped at \(Double(step) / 90) s")
                previous = angle
            }
        }
    }
}
