//
//  ExperimentsTests.swift
//  PhysicsPlaygroundTests
//
//  The experiments layer: progress persists and completes exactly once,
//  and the predicates read the live models truthfully — verified by
//  driving a model into the goal state and watching the predicate flip.
//

import XCTest
import simd
@testable import PhysicsPlayground

@MainActor
final class ExperimentsTests: XCTestCase {

    func testProgressPersistsAndCompletesOnce() {
        UserDefaults.standard.removeObject(forKey: ExperimentProgress.key)
        let progress = ExperimentProgress()
        XCTAssertTrue(progress.complete("test.a"), "first completion counts")
        XCTAssertFalse(progress.complete("test.a"), "repeat is a no-op")
        let reloaded = ExperimentProgress()
        XCTAssertTrue(reloaded.completed.contains("test.a"))
        UserDefaults.standard.removeObject(forKey: ExperimentProgress.key)
    }

    func testCircuitExperimentPredicateReadsTheModel() {
        let appModel = AppModel()
        let entries = ExperimentCatalog.experiments(for: "circuits", appModel: appModel)
        let charged = entries.first { $0.experiment.id == "circuits.charged" }!
        XCTAssertFalse(charged.isMet(), "nothing charged on the starter loop")

        // A capacitor across the battery, run for a while: predicate flips.
        let model = appModel.circuitsModel
        model.clearBench()
        model.add(.battery)
        model.add(.capacitor)
        let battery = model.components[0]
        let capacitor = model.components[1]
        model.tapTerminal(.init(componentID: battery.id, end: 0))
        model.tapTerminal(.init(componentID: capacitor.id, end: 0))
        model.tapTerminal(.init(componentID: capacitor.id, end: 1))
        model.tapTerminal(.init(componentID: battery.id, end: 1))
        for _ in 0..<400 { model.step(dt: 1.0 / 30.0) }
        XCTAssertTrue(charged.isMet(), "an 8.9 V capacitor satisfies Full tank")
    }

    func testFieldExperimentSeesTheDipole() {
        let appModel = AppModel()
        let entries = ExperimentCatalog.experiments(for: "electrostatics", appModel: appModel)
        let dipole = entries.first { $0.experiment.id == "field.dipole" }!

        let model = appModel.electromagnetismModel
        model.charges.removeAll()
        XCTAssertFalse(dipole.isMet(), "an empty field is no dipole")
        model.addCharge(positive: true)
        XCTAssertFalse(dipole.isMet(), "one polarity is still no dipole")
        model.addCharge(positive: false)
        XCTAssertTrue(dipole.isMet(), "a positive and a negative make a dipole")
    }

    func testEveryModuleOffersExperiments() {
        let appModel = AppModel()
        for module in ModuleCatalog.all(appModel: appModel) {
            let entries = ExperimentCatalog.experiments(for: module.id, appModel: appModel)
            XCTAssertFalse(entries.isEmpty,
                           "\(module.id) should offer at least one experiment")
        }
        // The floor tracks the BENCHED catalog. Folding modules into
        // worlds moves experiments between entries but never deletes
        // one, so this floor only ever falls when a module is ARCHIVED
        // — as Wind Tunnel was on 2026-07-30, taking its two with it.
        XCTAssertGreaterThanOrEqual(ExperimentCatalog.total(appModel: appModel), 16)
    }

    // MARK: The steps must describe the app that exists

    /// No experiment may tell you to do something "in this window".
    ///
    /// Six of them did, and every one became a lie on 2026-08-01 when
    /// the module window became a title bar: "Tap Twin suns in this
    /// window", "Turn on True electron speed in this window's Flow
    /// section". The controls they named are plates and petals in the
    /// room now.
    ///
    /// This is cheap to re-break — the strings are prose, nothing
    /// compiles against them, and the panel they referred to is gone, so
    /// nobody writing a new experiment would even see the old shape.
    /// The project's recurring defect is authored content that quietly
    /// stops matching the app; this is the check for that.
    @MainActor
    func testNoExperimentStepPointsAtTheWindowPanel() {
        let appModel = AppModel()
        for module in ModuleCatalog.all(appModel: appModel) {
            for entry in ExperimentCatalog.experiments(for: module.id,
                                                       appModel: appModel) {
                let step = entry.experiment.step.lowercased()
                for phrase in ["this window", "the panel", "control panel"] {
                    XCTAssertFalse(step.contains(phrase), """
                        \(module.id)/\(entry.experiment.id) says "\(phrase)": \
                        "\(entry.experiment.step)"

                        There is no window panel. Name the instrument in the \
                        room instead — the plate, the rail, the disc, the \
                        petal, the well.
                        """)
                }
            }
        }
    }
}
