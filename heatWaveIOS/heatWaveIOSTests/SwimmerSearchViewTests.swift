// SwimmerSearchViewTests.swift
// heatWaveIOSTests
//
// Unit tests for the data model logic that backs SwimmerSearchView and SwimmerDetailView.
// UI interactions (TextField, NavigationStack) are exercised manually; this file focuses
// on the pure data transformations that are safely testable without a host application.

import XCTest
@testable import heatWaveIOS

// MARK: - Helpers

private func makeIndividual(name: String, team: String, age: String? = nil, seedTime: TimeInterval = 60.0, place: Int = 1) -> EventEntry {
    .individual(IndividualEntry(place: place, swimmer: Swimmer(name: name, age: age, teamCode: team), seedTime: seedTime))
}

private func makeRelay(teamName: String, seedTime: TimeInterval = 200.0, place: Int = 1) -> EventEntry {
    .relay(RelayEntry(place: place, teamName: teamName, seedTime: seedTime))
}

private func makeEvent(number: Int, name: String = "50 Free", distance: Int = 50, stroke: String = "Freestyle", isRelay: Bool = false, gender: Gender = .female) -> Event {
    Event(number: number, name: name, distance: distance, stroke: stroke, entries: [], isRelay: isRelay, gender: gender)
}

// MARK: - SwimmerIndexTests

/// Tests the swimmer index built by SwimmerSearchView.allResults.
/// We replicate the indexing logic here to keep the tests pure Swift without needing
/// a live SwiftUI view.
final class SwimmerIndexTests: XCTestCase {

    // MARK: - Index building

    func testRelayEntriesAreExcluded() {
        // A heat sheet with only relay entries should produce zero swimmer results.
        let relayEvent = makeEvent(number: 1, isRelay: true)
        let assignment = LaneAssignment(entry: makeRelay(teamName: "Tulsa-OK A"), heat: 1, lane: 4)
        let sheet = HeatSheet(event: relayEvent, lanes: 8, heats: 1, assignments: [assignment], estimatedDuration: 200)

        let results = buildIndex(from: [sheet])
        XCTAssertTrue(results.isEmpty, "Relay entries must be excluded from swimmer search results")
    }

    func testIndividualEntryAppearsOnce() {
        let event = makeEvent(number: 1)
        let entry = makeIndividual(name: "Smith, Jane", team: "WAVE")
        let assignment = LaneAssignment(entry: entry, heat: 1, lane: 4)
        let sheet = HeatSheet(event: event, lanes: 8, heats: 1, assignments: [assignment], estimatedDuration: 150)

        let results = buildIndex(from: [sheet])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Smith, Jane")
        XCTAssertEqual(results[0].team, "WAVE")
    }

    func testSameSwimmerAcrossMultipleEventsHasSingleResult() {
        // Same swimmer in two different events should produce one result with two appearances.
        let e1 = makeEvent(number: 1, name: "50 Free", distance: 50)
        let e2 = makeEvent(number: 3, name: "100 Back", distance: 100, stroke: "Backstroke")

        let entry = makeIndividual(name: "Jones, Alex", team: "TIDE")
        let a1 = LaneAssignment(entry: entry, heat: 1, lane: 4)
        let a2 = LaneAssignment(entry: entry, heat: 1, lane: 5)

        let sheet1 = HeatSheet(event: e1, lanes: 8, heats: 1, assignments: [a1], estimatedDuration: 150)
        let sheet2 = HeatSheet(event: e2, lanes: 8, heats: 1, assignments: [a2], estimatedDuration: 180)

        let results = buildIndex(from: [sheet1, sheet2])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].appearances.count, 2)
    }

    func testDifferentSwimmersProduceSeparateResults() {
        let event = makeEvent(number: 1)
        let a1 = LaneAssignment(entry: makeIndividual(name: "Alpha, A", team: "T1"), heat: 1, lane: 4)
        let a2 = LaneAssignment(entry: makeIndividual(name: "Beta, B",  team: "T2"), heat: 1, lane: 5)
        let sheet = HeatSheet(event: event, lanes: 8, heats: 1, assignments: [a1, a2], estimatedDuration: 150)

        let results = buildIndex(from: [sheet])
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - Estimated start accumulation

    func testFirstEventHasZeroEstimatedStart() {
        let event = makeEvent(number: 1)
        let a = LaneAssignment(entry: makeIndividual(name: "A, B", team: "T"), heat: 1, lane: 4)
        let sheet = HeatSheet(event: event, lanes: 8, heats: 1, assignments: [a], estimatedDuration: 180)

        let results = buildIndex(from: [sheet])
        XCTAssertEqual(results[0].appearances[0].estimatedStart, 0.0, accuracy: 0.01)
    }

    func testSecondEventStartEqualsFirstEventDuration() {
        // Event 1 duration = 180 s → Event 2 should start at 180 s.
        let e1 = makeEvent(number: 1)
        let e2 = makeEvent(number: 2)
        let swimmer = makeIndividual(name: "A, B", team: "T")

        let s1 = HeatSheet(event: e1, lanes: 8, heats: 1,
                           assignments: [LaneAssignment(entry: swimmer, heat: 1, lane: 4)],
                           estimatedDuration: 180)
        let s2 = HeatSheet(event: e2, lanes: 8, heats: 1,
                           assignments: [LaneAssignment(entry: swimmer, heat: 1, lane: 5)],
                           estimatedDuration: 200)

        let results = buildIndex(from: [s1, s2])
        XCTAssertEqual(results.count, 1)
        let appearances = results[0].appearances.sorted { $0.estimatedStart < $1.estimatedStart }
        XCTAssertEqual(appearances[0].estimatedStart, 0.0,   accuracy: 0.01)
        XCTAssertEqual(appearances[1].estimatedStart, 180.0, accuracy: 0.01)
    }

    // MARK: - Filtering

    func testFilterMatchesFirstName() {
        let results = makeResults(names: ["Smith, Jane", "Jones, Alex"])
        let filtered = filter(results, query: "Jane")
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].name, "Smith, Jane")
    }

    func testFilterMatchesLastName() {
        let results = makeResults(names: ["Smith, Jane", "Jones, Alex"])
        let filtered = filter(results, query: "Jones")
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].name, "Jones, Alex")
    }

    func testFilterIsCaseInsensitive() {
        let results = makeResults(names: ["Smith, Jane"])
        XCTAssertEqual(filter(results, query: "smith").count, 1)
        XCTAssertEqual(filter(results, query: "SMITH").count, 1)
        XCTAssertEqual(filter(results, query: "SmItH").count, 1)
    }

    func testFilterIgnoresComma() {
        // "Smith Jane" (without comma) should still match "Smith, Jane"
        let results = makeResults(names: ["Smith, Jane"])
        let filtered = filter(results, query: "Smith Jane")
        XCTAssertEqual(filtered.count, 1)
    }

    func testEmptyQueryReturnsNoResults() {
        let results = makeResults(names: ["Smith, Jane", "Jones, Alex"])
        XCTAssertTrue(filter(results, query: "").isEmpty)
        XCTAssertTrue(filter(results, query: "   ").isEmpty)
    }

    func testNoMatchReturnsEmpty() {
        let results = makeResults(names: ["Smith, Jane"])
        XCTAssertTrue(filter(results, query: "zzznotaname").isEmpty)
    }

    func testFilterResultsAreSortedAlphabetically() {
        let results = makeResults(names: ["Zebra, Z", "Apple, A", "Mango, M"])
        let filtered = filter(results, query: "a")  // matches all three
        let names = filtered.map { $0.name }
        XCTAssertEqual(names, names.sorted())
    }

    // MARK: - SwimmerEventInfo content

    func testSwimmerEventInfoContainsCorrectFields() {
        let event = Event(number: 7, name: "200 Butterfly", distance: 200, stroke: "Butterfly",
                          entries: [], isRelay: false, gender: .male)
        let entry = makeIndividual(name: "Doe, John", team: "SWIM", age: "16", seedTime: 123.45)
        let assignment = LaneAssignment(entry: entry, heat: 2, lane: 6)
        let sheet = HeatSheet(event: event, lanes: 8, heats: 2, assignments: [assignment], estimatedDuration: 300)

        let results = buildIndex(from: [sheet])
        XCTAssertEqual(results.count, 1)
        let info = results[0].appearances[0]
        XCTAssertEqual(info.eventNumber, 7)
        XCTAssertEqual(info.heat, 2)
        XCTAssertEqual(info.lane, 6)
        XCTAssertEqual(info.seedTime, 123.45, accuracy: 0.001)
        XCTAssertEqual(info.stroke, "Butterfly")
    }

    func testAgeOrYearIsPropagated() {
        let event = makeEvent(number: 1)
        let entry = makeIndividual(name: "Kid, Young", team: "Y", age: "12")
        let assignment = LaneAssignment(entry: entry, heat: 1, lane: 4)
        let sheet = HeatSheet(event: event, lanes: 8, heats: 1, assignments: [assignment], estimatedDuration: 150)

        let results = buildIndex(from: [sheet])
        XCTAssertEqual(results[0].ageOrYear, "12")
    }
}

// MARK: - Pure data helpers (mirror SwimmerSearchView logic without SwiftUI)

private func buildIndex(from heatSheets: [HeatSheet]) -> [SwimmerSearchResult] {
    var index: [String: (name: String, team: String, age: String?, events: [SwimmerEventInfo])] = [:]
    var runningStart: TimeInterval = 0

    for sheet in heatSheets {
        let eventStart = runningStart
        runningStart += sheet.estimatedDuration

        for assignment in sheet.assignments {
            guard case .individual(let entry) = assignment.entry else { continue }
            let key = "\(entry.swimmer.name)|\(entry.swimmer.teamCode)"
            let info = SwimmerEventInfo(
                eventNumber: sheet.event.number,
                eventName: sheet.event.name,
                gender: sheet.event.gender,
                distance: sheet.event.distance,
                stroke: sheet.event.stroke,
                heat: assignment.heat,
                lane: assignment.lane,
                seedTime: entry.seedTime,
                estimatedStart: eventStart
            )
            if index[key] == nil {
                index[key] = (entry.swimmer.name, entry.swimmer.teamCode, entry.swimmer.age, [info])
            } else {
                index[key]!.events.append(info)
            }
        }
    }

    return index.values.map {
        SwimmerSearchResult(
            name: $0.name,
            team: $0.team,
            ageOrYear: $0.age,
            appearances: $0.events.sorted { $0.estimatedStart < $1.estimatedStart }
        )
    }
}

private func filter(_ results: [SwimmerSearchResult], query: String) -> [SwimmerSearchResult] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return [] }
    let lower = q.lowercased()
    return results
        .filter { $0.name.replacingOccurrences(of: ",", with: " ").lowercased().contains(lower) }
        .sorted { $0.name < $1.name }
}

private func makeResults(names: [String]) -> [SwimmerSearchResult] {
    names.map { name in
        SwimmerSearchResult(name: name, team: "T", ageOrYear: nil, appearances: [])
    }
}
