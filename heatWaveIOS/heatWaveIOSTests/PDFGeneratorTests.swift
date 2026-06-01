// PDFGeneratorTests.swift
// heatWaveIOSTests

import XCTest
@testable import heatWaveIOS

@MainActor
final class PDFGeneratorTests: XCTestCase {
    
    var generator: PDFGenerator!
    
    override func setUp() {
        super.setUp()
        generator = PDFGenerator()
    }
    
    override func tearDown() {
        // Clean up any test PDFs generated
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let files = try FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "pdf" {
                try FileManager.default.removeItem(at: file)
            }
        } catch {}
        super.tearDown()
    }
    
    func testGenerateThrowsOnEmptyHeatSheets() throws {
        XCTAssertThrowsError(try generator.generateHeatSheet([], to: "Test.pdf", meetTitle: "Test", meetDate: "2026")) { error in
            guard case PDFGeneratorError.noHeatSheets = error else {
                XCTFail("Expected noHeatSheets error")
                return
            }
        }
    }
    
    func testGenerateCreatesFileAndReturnsCorrectURL() throws {
        let event = Event(number: 1, name: "Test Event", distance: 50, stroke: "Free", entries: [], isRelay: false, gender: .female)
        let sheet = HeatSheet(event: event, lanes: 8, heats: 0, assignments: [])
        
        let filename = "OutputTest.pdf"
        let url = try generator.generateHeatSheet([sheet], to: filename, meetTitle: "Meet", meetDate: "Date")
        
        XCTAssertEqual(url.lastPathComponent, filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    
    func testOutputFileIsNonEmpty() throws {
        let event = Event(number: 1, name: "Test Event", distance: 50, stroke: "Free", entries: [], isRelay: false, gender: .female)
        let entry = EventEntry.individual(IndividualEntry(place: 1, swimmer: Swimmer(name: "A", age: nil, teamCode: "T"), seedTime: 60))
        let sheet = HeatSheet(event: event, lanes: 8, heats: 1, assignments: [LaneAssignment(entry: entry, heat: 1, lane: 4)])
        
        let url = try generator.generateHeatSheet([sheet], to: "NonEmptyTest.pdf", meetTitle: "Meet", meetDate: "Date")
        
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? UInt64 ?? 0
        XCTAssertGreaterThan(size, 0)
    }
    
    func testFormatTimeReturnsNTForInfinity() {
        XCTAssertEqual(generator.formatTime(.infinity), "NT")
    }
    
    func testFormatTimeReturnsMMSS() {
        XCTAssertEqual(generator.formatTime(150.55), "2:30.55")
        XCTAssertEqual(generator.formatTime(65.10), "1:05.10")
    }
    
    func testFormatTimeReturnsSS() {
        XCTAssertEqual(generator.formatTime(45.99), "45.99")
        XCTAssertEqual(generator.formatTime(9.05), "9.05")
    }
    
    func testGeneratorHandlesMultipleEventsAndHeatsWithoutCrashing() throws {
        var sheets: [HeatSheet] = []
        for i in 1...5 {
            let event = Event(number: i, name: "Event \(i)", distance: 100, stroke: "Fly", entries: [], isRelay: false, gender: .female)
            var assignments: [LaneAssignment] = []
            for j in 1...20 {
                let heat = (j / 8) + 1
                let lane = (j % 8) + 1
                let entry = EventEntry.individual(IndividualEntry(place: j, swimmer: Swimmer(name: "Swimmer \(j)", age: "12", teamCode: "TEAM"), seedTime: Double(j * 10)))
                assignments.append(LaneAssignment(entry: entry, heat: heat, lane: lane))
            }
            sheets.append(HeatSheet(event: event, lanes: 8, heats: 3, assignments: assignments))
        }
        
        let url = try generator.generateHeatSheet(sheets, to: "MultiEvent.pdf", meetTitle: "Big Meet", meetDate: "2026-05-01")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
