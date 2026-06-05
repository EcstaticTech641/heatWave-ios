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

    // MARK: - Timeline Estimator

    /// All entries are timed. estimatedDuration = slowest seed + (heats × turnover).
    func testEstimatedDurationAllTimed() throws {
        // 3 entries, 8-lane pool → 1 heat
        // Slowest = 30.0 s. Turnover default = 120 s.
        // Expected: 30.0 + 1 * 120 = 150.0 s
        let entries: [EventEntry] = [
            .individual(IndividualEntry(place: 1, swimmer: Swimmer(name: "A", age: nil, teamCode: "T"), seedTime: 25.0)),
            .individual(IndividualEntry(place: 2, swimmer: Swimmer(name: "B", age: nil, teamCode: "T"), seedTime: 28.0)),
            .individual(IndividualEntry(place: 3, swimmer: Swimmer(name: "C", age: nil, teamCode: "T"), seedTime: 30.0)),
        ]
        let event = Event(number: 1, name: "Test", distance: 50, stroke: "Free", entries: entries, isRelay: false, gender: .female)
        let sheet = try engine.seedEvent(event, lanes: 8)
        XCTAssertEqual(sheet.estimatedDuration, 150.0, accuracy: 0.01)
    }

    /// All entries NT → fallback used per heat.
    func testEstimatedDurationNTFallback() throws {
        // 2 NT entries → 1 heat, all NT → fallback = 120 s, turnover = 120 s
        // Expected: 120 + 1 * 120 = 240.0 s
        let entries: [EventEntry] = [
            .individual(IndividualEntry(place: 1, swimmer: Swimmer(name: "A", age: nil, teamCode: "T"), seedTime: .infinity)),
            .individual(IndividualEntry(place: 2, swimmer: Swimmer(name: "B", age: nil, teamCode: "T"), seedTime: .infinity)),
        ]
        let event = Event(number: 1, name: "Test", distance: 50, stroke: "Free", entries: entries, isRelay: false, gender: .female)
        let sheet = try engine.seedEvent(event, lanes: 8)
        // ntFallbackTime = 120, turnoverTime = 120 → 120 + 120 = 240
        XCTAssertEqual(sheet.estimatedDuration, 240.0, accuracy: 0.01)
    }

    /// Multi-heat event: each heat contributes its slowest timed seed.
    func testEstimatedDurationMultiHeat() throws {
        // 9 entries: 1 NT (heat 1) + 8 timed (heat 2, slowest = 9.0 s)
        // Heat 1: all NT → fallback 120 s
        // Heat 2: slowest = 9.0 s
        // turnoverTime = 120, heats = 2 → duration = 120 + 9 + 2*120 = 369 s
        var entries: [EventEntry] = [
            .individual(IndividualEntry(place: 1, swimmer: Swimmer(name: "NT", age: nil, teamCode: "T"), seedTime: .infinity))
        ]
        for i in 1...8 {
            entries.append(.individual(IndividualEntry(place: i+1, swimmer: Swimmer(name: "S\(i)", age: nil, teamCode: "T"), seedTime: Double(i))))
        }
        let event = Event(number: 2, name: "Test", distance: 100, stroke: "Free", entries: entries, isRelay: false, gender: .male)
        let sheet = try engine.seedEvent(event, lanes: 8)
        // Heat 1 has only the NT → fallback 120 s; Heat 2 slowest timed = 8.0 s
        XCTAssertEqual(sheet.heats, 2)
        // Duration = 120 (NT heat fallback) + 8.0 (heat2 slowest) + 2 * 120 (turnover)
        XCTAssertEqual(sheet.estimatedDuration, 368.0, accuracy: 0.01)
    }

    /// turnoverTime can be overridden before seeding.
    func testCustomTurnoverTimeIsRespected() throws {
        engine.turnoverTime = 180   // 3 minutes
        let entries: [EventEntry] = [
            .individual(IndividualEntry(place: 1, swimmer: Swimmer(name: "A", age: nil, teamCode: "T"), seedTime: 60.0)),
        ]
        let event = Event(number: 1, name: "Test", distance: 100, stroke: "Back", entries: entries, isRelay: false, gender: .female)
        let sheet = try engine.seedEvent(event, lanes: 8)
        // 1 heat, slowest = 60.0, turnover = 180 → 240 s
        XCTAssertEqual(sheet.estimatedDuration, 240.0, accuracy: 0.01)
    }
}
