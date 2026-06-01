// RegexParserTests.swift
// heatWaveIOSTests
//
// XCTest coverage for RegexParser.

import XCTest
@testable import heatWaveIOS

final class RegexParserTests: XCTestCase {

    var parser: RegexParser!

    override func setUp() {
        super.setUp()
        parser = RegexParser()
    }

    // MARK: - Event Header Parsing

    func testStandardEventHeader() throws {
        // "Event 1 Girls 10 & Under 200 Yard Freestyle"
        let result = parser.parseEventHeader(line: "Event 1 Girls 10 & Under 200 Yard Freestyle")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.number, 1)
        XCTAssertEqual(result?.gender, .female)
        XCTAssertEqual(result?.distance, 200)
        XCTAssertEqual(result?.stroke, "Freestyle")
        XCTAssertEqual(result?.name, "10 & Under 200 Freestyle")
    }

    func testEventHeaderWithColonSuffix() throws {
        // "Event 2: Boys 10 & Under 200 Yard Freestyle"
        let result = parser.parseEventHeader(line: "Event 2: Boys 10 & Under 200 Yard Freestyle")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.number, 2)
        XCTAssertEqual(result?.gender, .male)
    }

    func testContinuationEventHeaderIsIgnored() throws {
        // "Event 4 ...(Boys 12 & Under 100 LC Meter Freestyle)"
        let result = parser.parseEventHeader(line: "Event 4 ...(Boys 12 & Under 100 LC Meter Freestyle)")
        XCTAssertNil(result, "Continuation headers should be ignored")
    }

    func testExactCopiedEventHeaders() throws {
        // Exact copies from Hy-Tek sheets
        let e1 = parser.parseEventHeader(line: "Event 3 Girls 12 & Under 100 LC Meter Freestyle")
        XCTAssertEqual(e1?.number, 3)
        XCTAssertEqual(e1?.distance, 100)
        XCTAssertEqual(e1?.stroke, "Freestyle")
        
        let e2 = parser.parseEventHeader(line: "Event 5 Boys 12 & Under 100 LC Meter Freestyle")
        XCTAssertEqual(e2?.number, 5)
        XCTAssertEqual(e2?.gender, .male)
    }

    func testCollegiateEventHeader() throws {
        // "Event 12 Women 200 Yard Backstroke"
        let result = parser.parseEventHeader(line: "Event 12 Women 200 Yard Backstroke")
        XCTAssertNotNil(result)
        // The parser now respects the explicit "Women" text over the odd/even rule
        XCTAssertEqual(result?.gender, .female)
        XCTAssertEqual(result?.distance, 200)
        XCTAssertEqual(result?.stroke, "Backstroke")
        XCTAssertEqual(result?.name, "200 Backstroke")
    }

    func testNonHeaderLineReturnsNil() throws {
        // "1 Smith, John 14 Tulsa Swim-OK 2:41.23" → parseEventHeader → nil
        let result = parser.parseEventHeader(line: "1 Smith, John 14 Tulsa Swim-OK 2:41.23")
        XCTAssertNil(result, "Non-header line should not parse as an event header")
    }

    // MARK: - Individual Entry Parsing

    func testStandardIndividualEntry() throws {
        // "1 Mitchell, Braylin R 12 SSC-OK 1:03.39"
        let result = parser.parseIndividualEntry(line: "1 Mitchell, Braylin R 12 SSC-OK 1:03.39")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.place, 1)
        XCTAssertEqual(result?.swimmer.name, "Mitchell, Braylin R")
        XCTAssertEqual(result?.swimmer.age, "12")
        XCTAssertEqual(result?.swimmer.teamCode, "SSC-OK")
        XCTAssertEqual(result?.seedTime, 63.39) // 1*60 + 3.39
    }

    func testCollegiateEntryWithYearCode() throws {
        // "1 Cox, Jillian SO Texas QS 15:32.75"
        let result = parser.parseIndividualEntry(line: "1 Cox, Jillian SO Texas QS 15:32.75")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.swimmer.age, "SO")
        XCTAssertEqual(result?.swimmer.teamCode, "Texas")
        XCTAssertEqual(result?.seedTime, 932.75) // 15*60 + 32.75
    }

    func testEntryWithNT() throws {
        // "8 Jones, Bob 12 Tulsa Swim-OK NT"
        let result = parser.parseIndividualEntry(line: "8 Jones, Bob 12 Tulsa Swim-OK NT")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.seedTime, TimeInterval.infinity)
    }

    func testEntryWithStandardCode() throws {
        // "2 Smith, Anna 15 Club Team A 1:05.44"
        let result = parser.parseIndividualEntry(line: "2 Smith, Anna 15 Club Team A 1:05.44")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.swimmer.teamCode, "Club Team")
        XCTAssertEqual(result?.seedTime, 65.44)
    }

    func testEntryWithExhibitionTime() throws {
        // "4 Doe, Jane 14 Team-OK X28.50"
        let result = parser.parseIndividualEntry(line: "4 Doe, Jane 14 Team-OK X28.50")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.seedTime, 28.50)
    }

    // MARK: - Relay Entry Parsing

    func testStandardRelayEntry() throws {
        // "1 KMS-OK A 2:12.03"
        let result = parser.parseRelayEntry(line: "1 KMS-OK A 2:12.03")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.place, 1)
        XCTAssertEqual(result?.teamName, "KMS-OK A")
        XCTAssertEqual(result?.seedTime, 132.03) // 2*60 + 12.03
    }

    func testRelayEntryWithNT() throws {
        // "12 ST-OK A NT"
        let result = parser.parseRelayEntry(line: "12 ST-OK A NT")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.teamName, "ST-OK A")
        XCTAssertEqual(result?.seedTime, TimeInterval.infinity)
    }

    func testExactRelayRow() throws {
        // Real text: "1 KMS-OK A 2:12.03"
        let result = parser.parseRelayEntry(line: "1 KMS-OK A 2:12.03")
        XCTAssertEqual(result?.place, 1)
        XCTAssertEqual(result?.seedTime, 132.03)
    }

    // MARK: - Seed Time Normalisation

    func testNTNormalisesCorrectly() throws {
        XCTAssertEqual(parser.parseSeedTime("NT"), TimeInterval.infinity)
    }

    func testPartialTimeGetsDecimalAppended() throws {
        XCTAssertEqual(parser.parseSeedTime("2:41"), 161.0)
    }
    
    func testSecondsTimeGetsParsed() throws {
        XCTAssertEqual(parser.parseSeedTime("28.50"), 28.50)
    }

    func testAllKnownTimeFormats() throws {
        XCTAssertEqual(parser.parseSeedTime("1:03.39"), 63.39)
        XCTAssertEqual(parser.parseSeedTime("X28.50"), 28.50)
        XCTAssertEqual(parser.parseSeedTime("NT"), TimeInterval.infinity)
        XCTAssertEqual(parser.parseSeedTime("58.2Y"), 58.2)
        XCTAssertEqual(parser.parseSeedTime("15:32.75"), 932.75)
    }

    // MARK: - Skip Line Detection

    func testSkipLinesAreIgnored() throws {
        XCTAssertTrue(parser.isSkipLine("Name Age Team Seed Time"))
        XCTAssertTrue(parser.isSkipLine("Team Relay Seed Time"))
        XCTAssertTrue(parser.isSkipLine("King Marlin Swim Club HY-TEK's MEET MANAGER..."))
        XCTAssertFalse(parser.isSkipLine("1 Mitchell, Braylin R 12 SSC-OK 1:03.39"))
    }

    func testExactHyTekPageHeadersAreIgnored() throws {
        XCTAssertTrue(parser.isSkipLine("King Marlin Swim Club HY-TEK's MEET MANAGER 7.0 - 2:20 PM 4/28/2026 Page 1"))
        XCTAssertTrue(parser.isSkipLine("2026 KMSC Spring Twister - 5/2/2026 to 5/3/2026"))
        XCTAssertTrue(parser.isSkipLine("2026 King Marlin Spring Twister"))
        XCTAssertTrue(parser.isSkipLine("Psych Sheet"))
    }

    // MARK: - Full Text Parse Integration

    func testParsesMultipleEventsInOrder() throws {
        let text = """
        Event 1 Girls 10 & Under 200 Yard Freestyle
        Name Age Team Seed Time
        1 Meek, Keaston 10 Bartlesville Spl-OK 2:42.05
        2 Smith, Anna 10 Club Team 2:45.00
        
        Event 2 Boys 10 & Under 200 Yard Freestyle
        Name Age Team Seed Time
        1 Jones, Bob 10 Tulsa Swim-OK NT
        
        Event 3 Girls 11-12 200 Yard Freestyle Relay
        Team Relay Seed
        1 King Marlin Swim-OK A 2:13.43
        """
        
        let events = try parser.parseEvents(from: text)
        XCTAssertEqual(events.count, 3)
        
        let event1 = events[0]
        XCTAssertEqual(event1.number, 1)
        XCTAssertFalse(event1.isRelay)
        XCTAssertEqual(event1.entries.count, 2)
        if case .individual(let e1) = event1.entries[0] {
            XCTAssertEqual(e1.swimmer.name, "Meek, Keaston")
        } else { XCTFail() }
        
        let event2 = events[1]
        XCTAssertEqual(event2.number, 2)
        XCTAssertEqual(event2.entries.count, 1)
        if case .individual(let e2) = event2.entries[0] {
            XCTAssertEqual(e2.seedTime, TimeInterval.infinity)
        } else { XCTFail() }
        
        let event3 = events[2]
        XCTAssertEqual(event3.number, 3)
        XCTAssertTrue(event3.isRelay)
        XCTAssertEqual(event3.entries.count, 1)
        if case .relay(let r1) = event3.entries[0] {
            XCTAssertEqual(r1.teamName, "King Marlin Swim-OK A")
            XCTAssertEqual(r1.seedTime, 133.43)
        } else { XCTFail() }
    }

    func testRealHyTekPsychSheetData() throws {
        let text = """
        King Marlin Swim Club HY-TEK's MEET MANAGER 7.0 - 2:20 PM 4/28/2026 Page 1
        2026 KMSC Spring Twister - 5/2/2026 to 5/3/2026
        2026 King Marlin Spring Twister
        Psych Sheet
        Event 3 Girls 12 & Under 100 LC Meter Freestyle
        Name Age Team Seed Time
        1 Mitchell, Braylin R 12 SSC-OK 1:03.39
        34 Moffitt, Lexi M 9 AESC-OK NT
        Event 4 ...(Boys 12 & Under 100 LC Meter Freestyle)
        Event 5 Boys 12 & Under 100 LC Meter Freestyle
        Team Relay Seed Time
        1 KMS-OK A 2:12.03
        12 ST-OK A NT
        """

        let events = try parser.parseEvents(from: text)
        
        // We expect Event 3 and Event 5
        XCTAssertEqual(events.count, 2, "Should parse exactly two events")
        
        let event3 = events[0]
        XCTAssertEqual(event3.number, 3)
        XCTAssertEqual(event3.name, "12 & Under 100 LC Freestyle")
        XCTAssertFalse(event3.isRelay)
        XCTAssertEqual(event3.entries.count, 2)
        
        if case .individual(let e1) = event3.entries[0] {
            XCTAssertEqual(e1.swimmer.name, "Mitchell, Braylin R")
            XCTAssertEqual(e1.swimmer.age, "12")
            XCTAssertEqual(e1.seedTime, 63.39)
        } else { XCTFail() }
        
        if case .individual(let e2) = event3.entries[1] {
            XCTAssertEqual(e2.swimmer.name, "Moffitt, Lexi M")
            XCTAssertEqual(e2.seedTime, TimeInterval.infinity)
        } else { XCTFail() }
        
        let event5 = events[1]
        XCTAssertEqual(event5.number, 5)
        XCTAssertEqual(event5.entries.count, 2)
        XCTAssertTrue(event5.isRelay)
        
        if case .relay(let r1) = event5.entries[0] {
            XCTAssertEqual(r1.teamName, "KMS-OK A")
            XCTAssertEqual(r1.seedTime, 132.03)
        } else { XCTFail() }
        
        if case .relay(let r2) = event5.entries[1] {
            XCTAssertEqual(r2.teamName, "ST-OK A")
            XCTAssertEqual(r2.seedTime, TimeInterval.infinity)
        } else { XCTFail() }
    }

    func testDuplicateHeaderWithoutDotsPreservesEntries() throws {
        let text = """
        Event 1 Girls 10 & Under 200 Yard Freestyle
        Name Age Team Seed Time
        1 Meek, Keaston 10 Bartlesville Spl-OK 2:42.05
        Event 1 Girls 10 & Under 200 Yard Freestyle
        2 Smith, Anna 10 Club Team 2:45.00
        """
        let events = try parser.parseEvents(from: text)
        XCTAssertEqual(events.count, 1)
        let event = events[0]
        XCTAssertEqual(event.number, 1)
        XCTAssertEqual(event.entries.count, 2, "Duplicate event header should not wipe out previous entries.")
    }

    func testCarriageReturnHandlingInHeader() throws {
        let line = "Event 1 Girls 10 & Under 200 Yard Freestyle\r"
        let result = parser.parseEventHeader(line: line)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.stroke, "Freestyle", "Stroke should not contain trailing carriage returns.")
    }
}

