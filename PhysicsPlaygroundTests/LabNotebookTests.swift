//
//  LabNotebookTests.swift
//  PhysicsPlaygroundTests
//
//  The notebook: entries persist across launches, the capacity cap
//  holds, exports carry every reading, and CSV escaping survives the
//  fields a student will actually type.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class LabNotebookTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: LabNotebook.key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LabNotebook.key)
        super.tearDown()
    }

    func testRecordPersistsAcrossRelaunch() {
        let notebook = LabNotebook()
        notebook.record(moduleID: "waves", moduleTitle: "Wave Interference",
                        title: "Observation 1",
                        readings: [.init("λ", "0.33", "m")])

        let relaunched = LabNotebook()
        XCTAssertEqual(relaunched.entries.count, 1)
        XCTAssertEqual(relaunched.entries[0].moduleTitle, "Wave Interference")
        XCTAssertEqual(relaunched.entries[0].readings[0].value, "0.33")
    }

    func testNewestFirstAndCapacityCap() {
        let notebook = LabNotebook()
        for index in 0..<(LabNotebook.capacity + 25) {
            notebook.record(moduleID: "m", moduleTitle: "M",
                            title: "Observation \(index)",
                            readings: [.init("n", "\(index)")])
        }
        XCTAssertEqual(notebook.entries.count, LabNotebook.capacity)
        XCTAssertEqual(notebook.entries.first?.title,
                       "Observation \(LabNotebook.capacity + 24)",
                       "newest first; the oldest fell off the end")
    }

    func testRemoveAndClear() {
        let notebook = LabNotebook()
        let kept = notebook.record(moduleID: "a", moduleTitle: "A",
                                   title: "Keep", readings: [.init("x", "1")])
        let dropped = notebook.record(moduleID: "a", moduleTitle: "A",
                                      title: "Drop", readings: [.init("x", "2")])
        notebook.remove(dropped.id)
        XCTAssertEqual(notebook.entries.map(\.id), [kept.id])

        notebook.clear()
        XCTAssertTrue(notebook.entries.isEmpty)
        XCTAssertTrue(LabNotebook().entries.isEmpty, "the clear persists")
    }

    func testCSVEscapesCommasAndQuotes() {
        let notebook = LabNotebook()
        notebook.record(moduleID: "c", moduleTitle: "Circuit, Workshop",
                        title: "The \"big\" run",
                        readings: [.init("V", "9.0", "V")])
        let csv = notebook.csv
        XCTAssertTrue(csv.contains("\"Circuit, Workshop\""),
                      "comma-bearing field is quoted")
        XCTAssertTrue(csv.contains("\"The \"\"big\"\" run\""),
                      "quotes are doubled inside a quoted field")
        XCTAssertTrue(csv.hasPrefix("timestamp,module,observation,quantity,value,unit"))
    }

    func testMarkdownGroupsByModule() {
        let notebook = LabNotebook()
        notebook.record(moduleID: "waves", moduleTitle: "Wave Interference",
                        title: "Observation 1", readings: [.init("λ", "0.33", "m")])
        notebook.record(moduleID: "pendulums", moduleTitle: "Pendulums",
                        title: "Observation 1", readings: [.init("T", "1.79", "s")])
        let markdown = notebook.markdown
        XCTAssertTrue(markdown.contains("## Pendulums"))
        XCTAssertTrue(markdown.contains("## Wave Interference"))
        XCTAssertTrue(markdown.contains("| λ | 0.33 | m |"))
    }

    func testCaptureThroughAppModel() {
        let appModel = AppModel()
        XCTAssertFalse(appModel.captureNotebookEntry(),
                       "no active module — nothing to capture")

        appModel.go(to: "electrostatics")
        XCTAssertTrue(appModel.captureNotebookEntry())
        XCTAssertEqual(appModel.notebook.entries.count, 1)
        XCTAssertEqual(appModel.notebook.entries[0].moduleID, "electrostatics")
        XCTAssertEqual(appModel.notebook.entries[0].title, "Observation 1")

        XCTAssertTrue(appModel.captureNotebookEntry())
        XCTAssertEqual(appModel.notebook.entries[0].title, "Observation 2",
                       "observation numbering counts per module")
    }
}
