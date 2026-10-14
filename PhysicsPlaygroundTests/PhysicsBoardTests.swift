//
//  PhysicsBoardTests.swift
//  PhysicsPlaygroundTests
//
//  The Physics box: every module's dials read and write its model within
//  range, the board stands one rail per dial within reach and clear of
//  every flank instrument in every lab, it folds and unfolds with the
//  flag, and Electric Fields' rows carry the test charge's physics while
//  one is in the room.
//

import XCTest
import RealityKit
import PhysicsCore
import RenderKit
import simd
@testable import PhysicsPlayground

@MainActor
final class PhysicsBoardTests: XCTestCase {

    private func descriptors() -> [ModuleDescriptor] {
        ModuleCatalog.all(appModel: AppModel())
    }

    /// Writing what was read changes nothing; writing past the range lands
    /// on its end; writing inside the range lands exactly there.
    func testEveryDialReadsAndWritesItsModelWithinRange() {
        for module in descriptors() {
            for dial in module.adjustables {
                let before = dial.read()
                dial.write(before)
                XCTAssertEqual(dial.read(), before, accuracy: 1e-9,
                               "\(module.id).\(dial.id): writing the read value moved it")
                dial.write(dial.range.upperBound + 1)
                XCTAssertEqual(dial.read(), dial.range.upperBound, accuracy: 1e-6,
                               "\(module.id).\(dial.id): a write past the top was not clamped")
                let middle = (dial.range.lowerBound + dial.range.upperBound) / 2
                dial.write(middle)
                XCTAssertEqual(dial.read(), middle, accuracy: 1e-6 * max(1, abs(middle)),
                               "\(module.id).\(dial.id): a write inside the range did not land")
                dial.write(before)
            }
        }
    }

    /// The labs that let you set a field or a constant have dials; the
    /// ones whose values live on their parts do not.
    func testTheDialsAreWhereTheQuantitiesAre() {
        let byID = Dictionary(uniqueKeysWithValues: descriptors().map { ($0.id, $0) })
        XCTAssertEqual(byID["electrostatics"]?.adjustables.map(\.id),
                       ["plateVoltage", "uniformB"])
        XCTAssertEqual(byID["magnetism"]?.adjustables.map(\.id), ["moment"])
        XCTAssertEqual(byID["kinematics"]?.adjustables.map(\.id), ["gravity", "wind"])
        XCTAssertEqual(byID["gravitylab"]?.adjustables.map(\.id),
                       ["gravitationalConstant", "sunMass"])
        XCTAssertEqual(byID["circuits"]?.adjustables.count, 0)
        XCTAssertEqual(byID["pendulums"]?.adjustables.count, 0)
    }

    /// One rail per dial, in a column beside the card, every one within
    /// reach from where the box stands.
    func testTheBoardStandsOneRailPerDialWithinReach() {
        let viewer = SIMD3<Float>(InstrumentClearance.viewer)
        for module in descriptors() {
            let board = PhysicsBoard(module: module)
            XCTAssertEqual(board.rails.count, module.adjustables.count, module.id)
            for (index, rail) in board.rails.enumerated() {
                let expected = PhysicsBoard.railColumn - SIMD3(0, Float(index) * PhysicsBoard.railPitch, 0)
                XCTAssertEqual(rail.root.position, expected)
                for end in [Float(-1), 1] {
                    let world = PhysicsBoard.home + rail.root.position
                        + SIMD3(end * Float(PhysicsBoard.railLength) / 2, 0, 0)
                    XCTAssertLessThanOrEqual(Double(simd_length(world - viewer)),
                                             InstrumentClearance.maximumReach,
                                             "\(module.id) rail \(index) is out of reach")
                }
            }
        }
        let card = PhysicsBoard.home
        XCTAssertLessThanOrEqual(Double(simd_length(card - viewer)),
                                 InstrumentClearance.maximumReach)
    }

    /// Every module's flank instruments and the volume a hand builds in,
    /// from the constants the modules place them with. Electric Fields'
    /// station is not here: it is 1.5 × 2.4 × 1.2 m and covers every
    /// reachable point on the flank, and the box is folded until asked.
    private var furniture: [StationBox] {
        let bank = SIMD3<Double>(0.15, 0.20, 0.15)
        let column = SIMD3<Double>(0.15, 0.157, 0.05)
        let verb = SIMD3<Double>(0.13, 0.10, 0.08)
        let rail = SIMD3<Double>(0.16, 0.05, 0.07)
        func box(_ center: SIMD3<Float>, _ half: SIMD3<Double>) -> StationBox {
            StationBox(center: SIMD3<Double>(center), halfExtents: half)
        }
        var boxes = (FieldInstrumentLayout.leftRail.boxes + FieldInstrumentLayout.foreRail.boxes).map(\.box)
        boxes += [
            box(MagnetismSpaceView.bankAnchor, bank),
            box(CircuitsSpaceView.viewsColumnAnchor, column),
            StationBox(center: CircuitsModel.buildCenter, halfExtents: CircuitsModel.buildHalfExtents),
            box(OrbitalMechanicsSpaceView.showColumnAnchor, column),
            box(OrbitalMechanicsSpaceView.clockAnchor + SIMD3(0, 0.13, 0), verb),
            box(OrbitalMechanicsSpaceView.verbAnchor, verb),
            box(PendulumsSpaceView.bankAnchor, bank),
            StationBox(center: PendulumsModel.defaultPivot, halfExtents: SIMD3(0.40, 0.06, 0.12)),
            box(KinematicsSpaceView.bankAnchor, bank),
            box(KinematicsSpaceView.wellAnchor, SIMD3(repeating: 0.10)),
            box(KinematicsSpaceView.hoopWellAnchor, SIMD3(repeating: 0.10)),
            box(KinematicsSpaceView.worldsAnchor, SIMD3(0.15, 0.10, 0.15)),
            box(KinematicsSpaceView.gravityCenter, rail),
        ]
        return boxes
    }

    /// Every module's rails stand clear of every instrument and every
    /// build volume in every lab, box against box: a rail a hand reaches
    /// through a bank for is a rail that shields the bank. The box is one
    /// shape for six labs, so a dial added to any module is measured
    /// against all of them.
    func testTheRailsClearEveryFlankInstrument() {
        // Half the length plus the bead, the value bubble above, the name under.
        let railHalf = SIMD3<Double>(PhysicsBoard.railLength / 2 + 0.02, 0.065, 0.04)
        let furniture = furniture
        XCTAssertGreaterThan(furniture.count, 12, "the furniture list walked nothing")
        let railCount = descriptors().map(\.adjustables.count).max() ?? 0
        XCTAssertGreaterThan(railCount, 0)
        for index in 0..<railCount {
            let center = PhysicsBoard.home + PhysicsBoard.railColumn
                - SIMD3(0, Float(index) * PhysicsBoard.railPitch, 0)
            let rail = StationBox(center: SIMD3<Double>(center), halfExtents: railHalf)
            for piece in furniture where !rail.isSeparated(from: piece) {
                XCTFail("Physics box rail \(index) at \(center) stands in the instrument at \(piece.center)")
            }
        }
    }

    /// Folded until asked, unfolded when asked, folded again after.
    func testTheBoardFoldsWithItsFlag() {
        let module = descriptors().first { $0.id == "kinematics" }!
        let board = PhysicsBoard(module: module)
        XCTAssertFalse(board.root.isEnabled, "the box opened unasked")
        board.isOpen = true
        for _ in 0..<60 { board.update(dt: 1 / 90, viewer: [0, 1.5, 0], placement: .zero) }
        XCTAssertTrue(board.root.isEnabled)
        XCTAssertEqual(board.openness, 1, accuracy: 1e-3)
        XCTAssertEqual(board.unfold.scale.x, 1, accuracy: 1e-3)
        board.isOpen = false
        for _ in 0..<60 { board.update(dt: 1 / 90, viewer: [0, 1.5, 0], placement: .zero) }
        XCTAssertFalse(board.root.isEnabled)
    }

    /// The box follows the lab placement, like every shell instrument.
    func testTheBoardFollowsTheLabPlacement() {
        let module = descriptors().first { $0.id == "kinematics" }!
        let board = PhysicsBoard(module: module)
        board.isOpen = true
        board.update(dt: 1 / 90, viewer: nil, placement: [0.3, 0, -0.2])
        XCTAssertEqual(board.root.position, PhysicsBoard.home + SIMD3(0.3, 0, -0.2))
    }

    /// A drag on a rail's own entity sets the model; a drag elsewhere is
    /// refused.
    func testADragOnARailSetsItsQuantity() {
        let appModel = AppModel()
        let module = ModuleCatalog.descriptor(id: "kinematics", appModel: appModel)!
        let board = PhysicsBoard(module: module)
        board.isOpen = true
        for _ in 0..<60 { board.update(dt: 1 / 90, viewer: nil, placement: .zero) }
        let rail = board.rails[0]
        // The rail's far right end, in the board's frame, is the top of the range.
        let end = PhysicsBoard.home + rail.root.position + SIMD3(Float(PhysicsBoard.railLength) / 2, 0, 0)
        XCTAssertTrue(board.handleDrag(entity: rail.root, handWorld: SIMD3<Double>(end)))
        XCTAssertEqual(appModel.kinematicsModel.gravity, KinematicsModel.gravityRange.upperBound,
                       accuracy: 0.05)
        board.endDrag()
        XCTAssertFalse(board.handleDrag(entity: Entity(), handWorld: .zero))
        appModel.kinematicsModel.gravity = 9.81
    }

    /// Electric Fields' numbers carry the test charge's own physics while
    /// one is in the room, and not before.
    func testFieldRowsCarryTheTestChargeWhileOneIsOut() {
        let appModel = AppModel()
        let module = ModuleCatalog.descriptor(id: "electrostatics", appModel: appModel)!
        XCTAssertFalse(module.readings().contains { $0.name == "E at charge" })
        appModel.electromagnetismModel.dropProbe()
        let rows = module.readings()
        for name in ["Test charge q", "E at charge", "Potential", "Force qE", "Speed"] {
            XCTAssertTrue(rows.contains { $0.name == name }, "missing \(name)")
        }
    }

    /// Circuit Workshop's card stays card-sized: the bench and the selected
    /// part, not every part on the bench.
    func testCircuitsBoxRowsAreCardSized() {
        let appModel = AppModel()
        let module = ModuleCatalog.descriptor(id: "circuits", appModel: appModel)!
        let rows = module.readings()
        XCTAssertLessThanOrEqual(rows.count, 2 + 2 * 3)
        XCTAssertEqual(rows.first?.name, "Components")
    }
}
