//
//  AppSettingsTests.swift
//  PhysicsPlaygroundTests
//
//  The settings model: every preference survives a relaunch (a fresh
//  AppSettings reads back what the last one wrote), the master volume
//  actually reaches the sound engine, and the two reset actions clear
//  exactly what they claim to.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class AppSettingsTests: XCTestCase {

    private static let keys = [
        "settings.reduceMotion", "settings.masterVolume",
        "settings.ambientAudio", "settings.arcDistance",
        "settings.arcHeight", "settings.seenHints",
    ]

    private func clearKeys() {
        for key in Self.keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    override func setUp() {
        super.setUp()
        clearKeys()
    }

    override func tearDown() {
        clearKeys()
        SoundPalette.masterVolume = 1
        super.tearDown()
    }

    func testDefaultsOnFirstLaunch() {
        let settings = AppSettings()
        XCTAssertFalse(settings.reduceMotion)
        XCTAssertEqual(settings.masterVolume, 1.0)
        XCTAssertTrue(settings.ambientAudio)
        XCTAssertEqual(settings.arcDistance, 2.0)
        XCTAssertEqual(settings.arcHeight, 1.4)
        XCTAssertTrue(settings.seenHints.isEmpty)
    }

    func testEveryPreferenceSurvivesRelaunch() {
        let settings = AppSettings()
        settings.reduceMotion = true
        settings.masterVolume = 0.4
        settings.ambientAudio = false
        settings.arcDistance = 2.6
        settings.arcHeight = 1.1
        settings.markHintSeen("circuits")
        settings.markHintSeen("waves")

        // A second instance is a relaunch: nothing but UserDefaults
        // connects the two.
        let relaunched = AppSettings()
        XCTAssertTrue(relaunched.reduceMotion)
        XCTAssertEqual(relaunched.masterVolume, 0.4)
        XCTAssertFalse(relaunched.ambientAudio)
        XCTAssertEqual(relaunched.arcDistance, 2.6)
        XCTAssertEqual(relaunched.arcHeight, 1.1)
        XCTAssertTrue(relaunched.hasSeenHint("circuits"))
        XCTAssertTrue(relaunched.hasSeenHint("waves"))
        XCTAssertFalse(relaunched.hasSeenHint("pendulums"))
    }

    func testMasterVolumeReachesTheSoundEngine() {
        let settings = AppSettings()
        settings.masterVolume = 0.3
        XCTAssertEqual(SoundPalette.masterVolume, 0.3,
                       "the slider must reach the engine live, not on next hub visit")

        // And a relaunch restores it without any surface's help.
        SoundPalette.masterVolume = 1
        _ = AppSettings()
        XCTAssertEqual(SoundPalette.masterVolume, 0.3)
    }

    func testResetOnboardingTipsShowsEveryHintAgain() {
        let settings = AppSettings()
        settings.markHintSeen("circuits")

        settings.resetOnboardingTips()

        XCTAssertFalse(settings.hasSeenHint("circuits"))
        let relaunched = AppSettings()
        XCTAssertTrue(relaunched.seenHints.isEmpty, "the reset persists")
    }

    func testExperimentResetWipesProgressAndStreak() {
        UserDefaults.standard.removeObject(forKey: ExperimentProgress.key)
        UserDefaults.standard.removeObject(forKey: "streak.count")
        UserDefaults.standard.removeObject(forKey: "streak.lastDay")

        let progress = ExperimentProgress()
        progress.complete("test.reset")
        XCTAssertFalse(progress.completed.isEmpty)
        XCTAssertEqual(progress.streak, 1)

        progress.resetAll()
        XCTAssertTrue(progress.completed.isEmpty)
        XCTAssertEqual(progress.streak, 0)

        // A relaunch starts truly clean.
        let relaunched = ExperimentProgress()
        XCTAssertTrue(relaunched.completed.isEmpty)
        XCTAssertEqual(relaunched.streak, 0)
    }
}
