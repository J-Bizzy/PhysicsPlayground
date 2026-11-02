//
//  WordsAgreeTests.swift
//  PhysicsPlaygroundTests
//
//  Words and numbers agree (2026-11-02): one quantity is written one way
//  wherever it appears — on the part, on its ring's bead, in More, in a
//  formula. Each test puts two of those side by side for the same object
//  and asks for the same string.
//

import XCTest
import PhysicsCore
@testable import PhysicsPlayground

@MainActor
final class WordsAgreeTests: XCTestCase {

    private func readings(_ id: String, _ appModel: AppModel) -> [Reading] {
        ModuleCatalog.all(appModel: appModel).first { $0.id == id }!.readings()
    }

    private func row(_ name: String, in rows: [Reading],
                     file: StaticString = #filePath, line: UInt = #line) throws -> Reading {
        try XCTUnwrap(rows.first { $0.name == name }, "no \(name) in More",
                      file: file, line: line)
    }

    /// The whole reading as it reads: value, then unit when there is one.
    private func shown(_ reading: Reading) -> String {
        reading.unit.isEmpty ? reading.value : "\(reading.value) \(reading.unit)"
    }

    // MARK: Circuits

    /// A fuse's label is its bead's number at every rating it clicks into.
    /// At one decimal of its own, a 50 mA fuse was labelled "0.1 A".
    func testAFusesLabelIsItsBeadsNumber() {
        for rating in CircuitsModel.valueDetents(for: .fuse) {
            let fuse = CircuitsModel.Component(id: UUID(), kind: .fuse,
                                               position: .zero, value: rating)
            XCTAssertEqual(CircuitsRenderer.labelText(for: fuse),
                           CircuitsModel.formatValue(rating, for: .fuse))
        }
        let smallest = CircuitsModel.Component(id: UUID(), kind: .fuse,
                                               position: .zero, value: 0.05)
        XCTAssertEqual(CircuitsRenderer.labelText(for: smallest), "0.05 A")
    }

    /// More's voltage is the voltage its own formulas multiply, and Ohm's
    /// law divides by the resistance as the part is labelled — "4.7 kΩ",
    /// never "4700 Ω".
    func testMoresCircuitNumbersAreTheFormulasNumbers() throws {
        let appModel = AppModel()
        let model = appModel.circuitsModel
        model.loadPreset(.divider)
        let resistor = try XCTUnwrap(model.components.first { $0.kind == .resistor })
        model.setComponentValue(id: resistor.id, 4700)
        model.select(id: resistor.id)
        model.step(dt: 1.0 / 90.0)

        let rows = readings(CircuitsModule.id, appModel)
        let voltage = try row("Resistor voltage", in: rows)
        let power = try row("Resistor power", in: rows)
        XCTAssertTrue(try XCTUnwrap(power.formula).hasSuffix("× \(shown(voltage))"),
                      "More's voltage \(shown(voltage)) is not the one P = IV uses")
        let ohm = try XCTUnwrap(row("Resistor current", in: rows).formula)
        XCTAssertTrue(ohm.hasSuffix("÷ 4.7 kΩ"), ohm)
    }

    // MARK: Orbital Mechanics

    /// The star's mass in More is its bead's: "1.00 Sun".
    func testTheStarsMassReadsAsItsBeadDoes() throws {
        let appModel = AppModel()
        let model = appModel.orbitalMechanicsModel
        let star = try XCTUnwrap(model.primaryBody)
        let bead = PhysicsFormat.count(model.massInSuns(id: star.id),
                                       singular: "Sun", plural: "Suns", decimals: 2)
        XCTAssertEqual(shown(try row("Star mass", in: readings(OrbitalMechanicsModule.id, appModel))),
                       bead)
        XCTAssertEqual(bead, "1.00 Sun")
    }

    // MARK: Magnetism

    /// The selected magnet's moment in More is its track's number.
    func testAMagnetsMomentReadsAsItsTrackDoes() throws {
        let appModel = AppModel()
        let model = appModel.magnetismModel
        let magnet = try XCTUnwrap(model.magnets.first)
        model.select(id: magnet.id)
        let track = PhysicsFormat.measurement(magnet.strength, "A\u{00B7}m\u{00B2}", decimals: 1)
        XCTAssertEqual(shown(try row("Selected moment", in: readings(MagnetismModule.id, appModel))),
                       track)
    }

    // MARK: Electric Fields

    /// A charge in More reads in the µC its bead does, not in coulombs
    /// to the minus sixth.
    func testAChargeReadsInTheUnitsOfItsBead() throws {
        let appModel = AppModel()
        let model = appModel.electromagnetismModel
        let charge = try XCTUnwrap(model.charges.first { $0.isPositive })
        model.select(id: charge.id)
        let bead = PhysicsFormat.measurement(model.magnitudeMicroCoulombs(id: charge.id),
                                             "\u{00B5}C", decimals: 1)
        XCTAssertEqual(shown(try row("Selected charge", in: readings(ElectromagnetismModule.id, appModel))),
                       bead)
    }

    // MARK: Light & Optics

    /// With no walls to meet, the light that lands lands on the floor, and
    /// More says so rather than naming a room that is not there.
    func testLightWithNoWallsReachesTheFloor() {
        XCTAssertEqual(OpticsModule.landingName(LightTracer.Room(floorY: 0)),
                       "Light reaching the floor")
        let wall = RoomWalls.Wall(center: SIMD3(0, 1.5, -2), normal: SIMD3(0, 0, 1),
                                  uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 1, 0),
                                  halfU: 3, halfV: 1.5)
        XCTAssertEqual(OpticsModule.landingName(LightTracer.Room(walls: [wall], floorY: 0)),
                       "Light reaching the room")
    }
}
