// SeedingEngineTests.swift
// heatWaveIOSTests
//
// XCTest coverage for SeedingEngine.

import XCTest
@testable import heatWaveIOS

final class SeedingEngineTests: XCTestCase {

    var engine: SeedingEngine!

    override func setUp() {
        super.setUp()
        engine = SeedingEngine()
    }

    // MARK: - Validation

    func testInvalidLaneCountThrows() throws {
        let event = Event(number: 1, name: "Test", distance: 50, stroke: "Free", entries: [], isRelay: false, gender: .female)
        XCTAssertThrowsError(try engine.seedEvent(event, lanes: 3)) { error in
            guard case SeedingError.invalidLaneCount(3) = error else {
                XCTFail("Expected invalidLaneCount error")
                return
            }
        }
        XCTAssertThrowsError(try engine.seedEvent(event, lanes: 11))
    }

    // MARK: - Center-Out Pattern

    func testCenterOutPattern8Lanes() throws {
        let pattern = engine.centerOutPattern(lanes: 8)
        XCTAssertEqual(pattern, [4, 5, 3, 6, 2, 7, 1, 8])
    }

    func testCenterOutPattern6Lanes() throws {
        let pattern = engine.centerOutPattern(lanes: 6)
        XCTAssertEqual(pattern, [3, 4, 2, 5, 1, 6])
    }
    
    func testCenterOutPattern10Lanes() throws {
        let pattern = engine.centerOutPattern(lanes: 10)
        XCTAssertEqual(pattern, [5, 6, 4, 7, 3, 8, 2, 9, 1, 10])
    }

    // MARK: - Sorting

    func testSortByTimePlacesNTSlowest() throws {
        let e1 = EventEntry.individual(IndividualEntry(place: 1, swimmer: Swimmer(name: "A", age: nil, teamCode: "T"), seedTime: 60.0))
        let e2 = EventEntry.individual(IndividualEntry(place: 2, swimmer: Swimmer(name: "B", age: nil, teamCode: "T"), seedTime: TimeInterval.infinity)) // NT
        let e3 = EventEntry.individual(IndividualEntry(place: 3, swimmer: Swimmer(name: "C", age: nil, teamCode: "T"), seedTime: 120.0))
        
        let sorted = engine.sortByTime([e1, e2, e3])
        
        // Should be descending: NT, 120.0, 60.0
        XCTAssertEqual(seedTime(for: sorted[0]), TimeInterval.infinity)
        XCTAssertEqual(seedTime(for: sorted[1]), 120.0)
        XCTAssertEqual(seedTime(for: sorted[2]), 60.0)
    }

    private func seedTime(for entry: EventEntry) -> TimeInterval {
        switch entry {
        case .individual(let e): return e.seedTime
        case .relay(let r): return r.seedTime
        }
    }

    // MARK: - Event Seeding

    func testEmptyEventReturnsEmptyHeatSheet() throws {
        let event = Event(number: 1, name: "Test", distance: 50, stroke: "Free", entries: [], isRelay: false, gender: .female)
        let sheet = try engine.seedEvent(event, lanes: 8)
        XCTAssertEqual(sheet.heats, 0)
        XCTAssertTrue(sheet.assignments.isEmpty)
    }

    func testFullEventHeatCount() throws {
        // 17 entries -> ceil(17/8) = 3 heats
        var entries: [EventEntry] = []
        for i in 1...17 {
            entries.append(.individual(IndividualEntry(place: i, swimmer: Swimmer(name: "S\(i)", age: nil, teamCode: "T"), seedTime: Double(i))))
        }
        let event = Event(number: 1, name: "Test", distance: 50, stroke: "Free", entries: entries, isRelay: false, gender: .female)
        let sheet = try engine.seedEvent(event, lanes: 8)
        XCTAssertEqual(sheet.heats, 3)
    }

    func testIncompleteFirstHeat() throws {
        // 10 entries in 8 lanes -> Heat 1 gets 2, Heat 2 gets 8
        var entries: [EventEntry] = []
        for i in 1...10 {
            // Give them times 10.0 down to 1.0
            entries.append(.individual(IndividualEntry(place: i, swimmer: Swimmer(name: "S\(i)", age: nil, teamCode: "T"), seedTime: Double(20 - i))))
        }
        let event = Event(number: 1, name: "Test", distance: 50, stroke: "Free", entries: entries, isRelay: false, gender: .female)
        let sheet = try engine.seedEvent(event, lanes: 8)
        
        let heat1 = sheet.assignments.filter { $0.heat == 1 }
        let heat2 = sheet.assignments.filter { $0.heat == 2 }
        
        XCTAssertEqual(heat1.count, 2)
        XCTAssertEqual(heat2.count, 8)
    }

    func testNTLandsInFirstHeat() throws {
        // 9 entries: 1 NT, 8 timed
        var entries: [EventEntry] = []
        entries.append(.individual(IndividualEntry(place: 1, swimmer: Swimmer(name: "NT Guy", age: nil, teamCode: "T"), seedTime: .infinity)))
        for i in 1...8 {
            entries.append(.individual(IndividualEntry(place: i+1, swimmer: Swimmer(name: "S\(i)", age: nil, teamCode: "T"), seedTime: Double(10 - i))))
        }
        
        let event = Event(number: 1, name: "Test", distance: 50, stroke: "Free", entries: entries, isRelay: false, gender: .female)
        let sheet = try engine.seedEvent(event, lanes: 8)
        
        // 9 entries in 8 lanes -> Heat 1 has 1 entry (the NT), Heat 2 has 8 entries.
        let heat1 = sheet.assignments.filter { $0.heat == 1 }
        XCTAssertEqual(heat1.count, 1)
        if case .individual(let ind) = heat1[0].entry {
            XCTAssertEqual(ind.seedTime, .infinity)
            XCTAssertEqual(ind.swimmer.name, "NT Guy")
        } else { XCTFail() }
    }

    func testCenterOutPlacementFastestInCenter() throws {
        // 3 entries in 1 heat. Lane pattern for 8 is [4, 5, 3, 6, 2, 7, 1, 8]
        // Sorted fastest first for the heat itself: S1 (fastest), S2, S3
        // S1 -> lane 4
        // S2 -> lane 5
        // S3 -> lane 3
        var entries: [EventEntry] = []
        entries.append(.individual(IndividualEntry(place: 1, swimmer: Swimmer(name: "Fastest", age: nil, teamCode: "T"), seedTime: 1.0)))
        entries.append(.individual(IndividualEntry(place: 2, swimmer: Swimmer(name: "Mid", age: nil, teamCode: "T"), seedTime: 2.0)))
        entries.append(.individual(IndividualEntry(place: 3, swimmer: Swimmer(name: "Slowest", age: nil, teamCode: "T"), seedTime: 3.0)))
        
        let event = Event(number: 1, name: "Test", distance: 50, stroke: "Free", entries: entries, isRelay: false, gender: .female)
        let sheet = try engine.seedEvent(event, lanes: 8)
        
        let heat1 = sheet.assignments
        // Assignments should be sorted by heat/lane: lane 3, 4, 5
        XCTAssertEqual(heat1[0].lane, 3)
        if case .individual(let ind) = heat1[0].entry { XCTAssertEqual(ind.swimmer.name, "Slowest") }
        
        XCTAssertEqual(heat1[1].lane, 4)
        if case .individual(let ind) = heat1[1].entry { XCTAssertEqual(ind.swimmer.name, "Fastest") }
        
        XCTAssertEqual(heat1[2].lane, 5)
        if case .individual(let ind) = heat1[2].entry { XCTAssertEqual(ind.swimmer.name, "Mid") }
    }
}
