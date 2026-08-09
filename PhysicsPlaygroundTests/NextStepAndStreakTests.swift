//
//  NextStepAndStreakTests.swift
//  PhysicsPlaygroundTests
//
//  THE TWO READOUTS THAT LIE, from goal §3.1.
//
//  Both were harmless while nobody could see them. The experiments strip
//  lived in a catalog hidden whenever the gallery was open, so a wrong
//  "next step" and a stale streak were wrong in private. On 2026-08-08
//  they moved into a window with a button on the Gallery bar — which
//  means this commit surfaced two lies rather than fixing them, and
//  these are the fix.
//
//  1. `nextStep` walked `ModuleCatalog` in declaration order and
//     returned the first unfinished experiment in the first module,
//     forever, to everybody. A user standing in Pendulums was told
//     "Opposites attract — Electric Fields". The one line whose entire
//     job is to say what to do next pointed at a different room.
//     `AppModel.lastPlayed(_:)` had a writer and no reader the whole
//     time.
//
//  2. The streak was `UserDefaults.integer(forKey:)` and nothing else.
//     `recordStreakDay` breaks it correctly — but only when you next
//     complete something, so between Tuesday and Friday the app went on
//     claiming the streak that had already ended. A counter you cannot
//     break is not a reason to come back.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class NextStepAndStreakTests: XCTestCase {

    /// Marks a lab as played the way the app does — `lastPlayed` is
    /// written by `recordVisit`, which fires when `activeModuleID` is
    /// set. There is no public setter, and that is correct: a visit is
    /// something that HAPPENS, not something a caller declares.
    private func visit(_ id: String, in appModel: AppModel) {
        appModel.activeModuleID = id
        appModel.activeModuleID = nil
    }

    /// `lastPlayed` and the streak both live in `UserDefaults`, which
    /// outlives a test case — so a run of this file leaks visits from
    /// one test into the next. `testTheOpenLabIsRecommendedFirst` opens
    /// every lab in turn, which stamps a timestamp on all six, and the
    /// tie-order test then had no untouched module left to check.
    /// Caught by that test failing, which is the right way round.
    private func clearHistory(_ appModel: AppModel) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "streak.count")
        defaults.removeObject(forKey: "streak.lastDay")
        for module in ModuleCatalog.all(appModel: appModel) {
            defaults.removeObject(forKey: "lastPlayed.\(module.id)")
        }
    }

    override func setUp() {
        super.setUp()
        clearHistory(AppModel())
    }

    override func tearDown() {
        clearHistory(AppModel())
        super.tearDown()
    }

    // MARK: Where to go next

    /// THE LAB YOU ARE STANDING IN COMES FIRST. Anything else is the
    /// app telling you to leave the room you just entered.
    func testTheOpenLabIsRecommendedFirst() {
        let appModel = AppModel()
        for module in ModuleCatalog.all(appModel: appModel) {
            appModel.activeModuleID = module.id
            let order = ExperimentCatalog.modulesByRecency(appModel: appModel)
            XCTAssertEqual(order.first?.id, module.id, """
                standing in \(module.title), the next step was sought in \
                \(order.first?.title ?? "nothing") first.
                """)
        }
    }

    /// …and with no lab open, the most recently played one leads.
    func testTheMostRecentlyPlayedLabLeads() throws {
        let appModel = AppModel()
        appModel.activeModuleID = nil
        let catalog = ModuleCatalog.all(appModel: appModel)
        // Pick a module that is NOT first in catalog order, so passing
        // cannot be an accident of the old behaviour.
        let target = try XCTUnwrap(catalog.dropFirst().last)
        visit(target.id, in: appModel)

        let order = ExperimentCatalog.modulesByRecency(appModel: appModel)
        XCTAssertEqual(order.first?.id, target.id, """
            \(target.title) was played most recently and \
            \(order.first?.title ?? "nothing") was recommended instead — this \
            is the catalog-order bug returning.
            """)
    }

    /// A lab never opened sorts LAST, not first: the line is for
    /// continuing what you were doing, and catalog order breaks ties so
    /// a brand-new user still gets a stable answer.
    func testUntouchedLabsSortAfterPlayedOnesAndTiesAreStable() throws {
        let appModel = AppModel()
        appModel.activeModuleID = nil
        let catalog = ModuleCatalog.all(appModel: appModel)
        let played = try XCTUnwrap(catalog.last)
        visit(played.id, in: appModel)

        let order = ExperimentCatalog.modulesByRecency(appModel: appModel)
        XCTAssertEqual(order.first?.id, played.id)
        // The untouched remainder keeps catalog order behind it.
        let rest = order.dropFirst().map(\.id)
        let expected = catalog.map(\.id).filter { $0 != played.id }
        XCTAssertEqual(rest, expected)
    }

    // MARK: The streak

    /// A STREAK MUST BE ABLE TO BREAK. Last completion on Tuesday, read
    /// on Friday: zero, not four.
    func testAStreakWhoseLastDayHasPassedIsGone() {
        UserDefaults.standard.set(4, forKey: "streak.count")
        UserDefaults.standard.set(
            Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
            forKey: "streak.lastDay")

        XCTAssertEqual(ExperimentProgress().streak, 0, """
            a streak whose last day was three days ago survived a relaunch — \
            the app is claiming a run the user did not have.
            """)
    }

    /// Yesterday still counts: the day is not over until it is.
    func testYesterdayStillCounts() {
        UserDefaults.standard.set(4, forKey: "streak.count")
        UserDefaults.standard.set(
            Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            forKey: "streak.lastDay")
        XCTAssertEqual(ExperimentProgress().streak, 4)
    }

    /// …and so does today.
    func testTodayCounts() {
        UserDefaults.standard.set(2, forKey: "streak.count")
        UserDefaults.standard.set(Date(), forKey: "streak.lastDay")
        XCTAssertEqual(ExperimentProgress().streak, 2)
    }

    /// A stored count with no recorded day is not a streak. This is the
    /// shape a half-written preference leaves behind, and believing it
    /// would resurrect a number from a version that stored it
    /// differently.
    func testACountWithNoDayIsNotAStreak() {
        UserDefaults.standard.set(7, forKey: "streak.count")
        UserDefaults.standard.removeObject(forKey: "streak.lastDay")
        XCTAssertEqual(ExperimentProgress().streak, 0)
    }
}
