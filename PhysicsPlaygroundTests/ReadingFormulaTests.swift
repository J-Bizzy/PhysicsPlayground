//
//  ReadingFormulaTests.swift
//  PhysicsPlaygroundTests
//
//  The equations in More › Values. Every lab shows the law behind its
//  numbers somewhere; every formula is an equation and no reading's name
//  is one (they moved out of the names); the live numbers in a formula are
//  the numbers the reading shows, so the substitution is the computation;
//  and the subscript marks typeset without losing a character.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class ReadingFormulaTests: XCTestCase {

    // MARK: Typesetting

    func testSubscriptMarksSplitIntoRuns() {
        XCTAssertEqual(Formula.runs("mg = ½ρC_DAv²"), [
            .init(text: "mg = ½ρC", isSubscript: false),
            .init(text: "D", isSubscript: true),
            .init(text: "Av²", isSubscript: false),
        ])
        XCTAssertEqual(Formula.runs("ε = IR + V_{LED}(I)").map(\.text), ["ε = IR + V", "LED", "(I)"])
        XCTAssertEqual(Formula.runs("ε = IR + V_{LED}(I)").map(\.isSubscript), [false, true, false])
        XCTAssertEqual(Formula.plain("δ_{min} = 2A"), "δmin = 2A")
        XCTAssertEqual(Formula.plain("T = 2π√(L/g)"), "T = 2π√(L/g)")
    }

    /// A line breaks between clauses and before the numbers, never inside
    /// a term.
    func testAFormulaBreaksOnlyWhereAReaderWould() {
        let nb = "\u{00A0}"
        XCTAssertEqual(Formula.breakable("δ = 2 arcsin(n sin(A/2)) − A = 2 arcsin(1.79 sin 30°) − 60°"),
                       "δ\(nb)=\(nb)2\(nb)arcsin(n\(nb)sin(A/2))\(nb)−\(nb)A"
                       + " =\(nb)2\(nb)arcsin(1.79\(nb)sin\(nb)30°)\(nb)−\(nb)60°")
        XCTAssertEqual(Formula.breakable("R = ρL/A, L = 1407 m of copper"),
                       "R\(nb)=\(nb)ρL/A, L\(nb)=\(nb)1407\(nb)m\(nb)of\(nb)copper")
        XCTAssertEqual(Formula.breakable("E = −∇V"), "E\(nb)=\(nb)−∇V")
    }

    /// No formula leans on Unicode's ᵢ or ᵣ, which a fallback font sets
    /// apart from their letter: the house marks set them in the same face.
    func testNoFormulaUsesAFallbackSubscript() throws {
        for (id, states) in try stagedReadings() {
            for formula in states.flatMap({ $0 }).compactMap(\.formula) {
                XCTAssertFalse(formula.contains("ᵢ") || formula.contains("ᵣ"), "\(id): \(formula)")
            }
        }
    }

    /// A stray mark is text, not a lost character.
    func testAStrayMarkIsKeptAsText() {
        XCTAssertEqual(Formula.plain("x_"), "x_")
        XCTAssertEqual(Formula.plain("a_{b = c"), "a_{b = c")
    }

    // MARK: Every lab

    /// Each lab's readings in the states that light up its laws: a test
    /// charge, a coil, every optical piece, a coupled pair, air on and off.
    private func stagedReadings() throws -> [String: [[Reading]]] {
        let appModel = AppModel()
        func readings(_ id: String) throws -> [Reading] {
            try XCTUnwrap(ModuleCatalog.descriptor(id: id, appModel: appModel)).readings()
        }
        var staged: [String: [[Reading]]] = [:]
        func record(_ id: String) throws { staged[id, default: []].append(try readings(id)) }

        try record("electrostatics")
        let field = appModel.electromagnetismModel
        field.dropProbe()
        field.magneticFieldOn = true
        field.showEquipotentials = true
        try record("electrostatics")

        let magnetism = appModel.magnetismModel
        if let magnet = magnetism.magnets.first { magnetism.select(id: magnet.id) }
        try record("magnetism")
        let coil = try XCTUnwrap(magnetism.addCoil(at: SIMD3(0.3, 1.3, -0.6)))
        magnetism.select(id: coil)
        try record("magnetism")

        let optics = appModel.opticsModel
        optics.select(id: OpticsModel.laserID)
        try record("optics")
        for kind in OpticsModel.Kind.allCases {
            let id = try optics.pieces.first { $0.kind == kind }?.id
                ?? XCTUnwrap(optics.addPiece(kind, at: SIMD3(0.2, 1.2, -0.8)))
            optics.select(id: id)
            try record("optics")
        }

        let pendulums = appModel.pendulumsModel
        if let first = pendulums.pendulums.first { pendulums.select(id: first.id) }
        try record("pendulums")
        XCTAssertTrue(pendulums.addCoupledPair())
        if let coupled = pendulums.pendulums.first(where: { pendulums.partner(of: $0.id) != nil }) {
            pendulums.select(id: coupled.id)
        }
        try record("pendulums")

        let kinematics = appModel.kinematicsModel
        kinematics.airResistance = false
        try record("kinematics")
        kinematics.airResistance = true
        try record("kinematics")

        let orbits = appModel.orbitalMechanicsModel
        if let planet = orbits.bodies.first(where: { $0.id != orbits.primaryBody?.id }) {
            orbits.select(id: planet.id)
        }
        try record("gravitylab")

        let circuits = appModel.circuitsModel
        for component in circuits.components {
            circuits.select(id: component.id)
            try record("circuits")
        }
        if circuits.components.isEmpty { try record("circuits") }
        return staged
    }

    /// Every formula is an equation, and no name is one: the law lives
    /// under the number, never in its label.
    func testEveryFormulaIsAnEquationAndNoNameIsOne() throws {
        for (id, states) in try stagedReadings() {
            for row in states.flatMap({ $0 }) {
                XCTAssertFalse(row.name.contains("="), "\(id): “\(row.name)” is a formula in a name")
                XCTAssertFalse(row.name.contains("√"), "\(id): “\(row.name)” is a formula in a name")
                if let formula = row.formula {
                    XCTAssertTrue(formula.contains("="), "\(id): “\(formula)” is not an equation")
                }
            }
        }
    }

    /// Every lab shows at least one of its laws, and none writes the same
    /// law twice in one panel.
    func testEveryLabShowsALawOnce() throws {
        let staged = try stagedReadings()
        for id in ModuleCatalog.allIDs {
            let states = try XCTUnwrap(staged[id], "\(id) was not staged")
            XCTAssertTrue(states.flatMap { $0 }.contains { $0.formula != nil },
                          "\(id) shows no law in More")
            for rows in states {
                let formulas = rows.compactMap(\.formula)
                XCTAssertEqual(Set(formulas).count, formulas.count, "\(id) writes a law twice")
            }
        }
    }

    // MARK: The numbers in a formula are the numbers shown

    /// T = 2π√(L/g), evaluated from the very strings the formula shows,
    /// is the period the reading shows, to its last digit.
    func testThePeriodIsItsOwnSubstitution() throws {
        let appModel = AppModel()
        let model = appModel.pendulumsModel
        let simple = try XCTUnwrap(model.pendulums.first { $0.kind == .simple })
        model.select(id: simple.id)
        let row = try XCTUnwrap(PendulumsModule.readings(appModel: appModel).first { $0.name == "Period" })
        let formula = try XCTUnwrap(row.formula)
        let length = PhysicsFormat.fixed(simple.length, decimals: 3)
        let g = PhysicsFormat.fixed(model.gravity, decimals: 2)
        XCTAssertTrue(formula.hasSuffix("2π√(\(length) m ÷ \(g) m/s²)"), formula)
        let evaluated = 2 * Double.pi * (try XCTUnwrap(Double(length)) / XCTUnwrap(Double(g))).squareRoot()
        XCTAssertEqual(try XCTUnwrap(Double(row.value)), evaluated, accuracy: 0.0015)
    }

    /// R = v² sin 2θ / g is the drag-free range of the aim as it stands;
    /// in air the terminal speed sorts the balls the way they fly.
    func testProjectilesShowTheirClosedForms() throws {
        let appModel = AppModel()
        let model = appModel.kinematicsModel
        model.airResistance = false
        model.setAim(elevationDegrees: 30, azimuthDegrees: 0)
        model.launchSpeed = 8
        let range = try XCTUnwrap(KinematicsModule.lawReadings(model).first)
        XCTAssertEqual(try XCTUnwrap(Double(range.value)),
                       64 * sin(60 * Double.pi / 180) / model.gravity, accuracy: 0.005)
        XCTAssertTrue(try XCTUnwrap(range.formula).contains("sin 60.0°"))

        model.airResistance = true
        model.kind = .tableTennisBall
        let light = try XCTUnwrap(Double(try XCTUnwrap(KinematicsModule.lawReadings(model).first).value))
        model.kind = .cannonball
        let heavy = try XCTUnwrap(Double(try XCTUnwrap(KinematicsModule.lawReadings(model).first).value))
        XCTAssertLessThan(light, 15, "a table tennis ball tops out at walking-into-wind speeds")
        XCTAssertGreaterThan(heavy, 10 * light)
    }

    /// P = IV holds for every part on the bench exactly as the solver
    /// reports it, which is what lets the formula claim it for all of them;
    /// Ohm's law is claimed only for a plain resistance.
    func testCircuitsClaimOnlyTheLawsTheirPartsObey() throws {
        let appModel = AppModel()
        let model = appModel.circuitsModel
        for component in model.components {
            guard let readout = model.readouts[component.id] else { continue }
            XCTAssertEqual(readout.watts, readout.amps * readout.volts,
                           accuracy: 1e-9 * max(1, abs(readout.watts)))
            let ohm = CircuitsModule.ohm(component, volts: "0")
            switch component.kind {
            case .resistor where !component.failed, .bulb: XCTAssertNotNil(ohm)
            default: XCTAssertNil(ohm, "\(component.kind) does not obey V = IR")
            }
        }
    }
}
