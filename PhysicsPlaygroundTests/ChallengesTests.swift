//
//  ChallengesTests.swift
//  PhysicsPlaygroundTests
//
//  The challenge layer: progress persists and predicates read the
//  live models truthfully.
//

import XCTest
import simd
@testable import PhysicsPlayground

@MainActor
final class ChallengesTests: XCTestCase {

    func testProgressPersistsAndCompletesOnce() {
        UserDefaults.standard.removeObject(forKey: ChallengeProgress.key)
        let progress = ChallengeProgress()
        XCTAssertTrue(progress.complete("test.a"), "first completion counts")
        XCTAssertFalse(progress.complete("test.a"), "repeat is a no-op")
        let reloaded = ChallengeProgress()
        XCTAssertTrue(reloaded.completed.contains("test.a"))
        UserDefaults.standard.removeObject(forKey: ChallengeProgress.key)
    }

    func testCircuitChallengePredicateReadsTheModel() {
        let appModel = AppModel()
        let entries = ChallengeCatalog.challenges(for: "circuits", appModel: appModel)
        let charged = entries.first { $0.challenge.id == "circuits.charged" }!
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
}
