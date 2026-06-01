// RegexParser.swift

// heatWaveIOS

//

// Parses the plain-text output of PDFExtractor into structured Swift data models.



import Foundation



/// Parses psych sheet plain text into an array of Event models.

struct RegexParser {

   

    /// Enable this to print classification traces during development

    var isDebugTraceEnabled: Bool = false



    // MARK: - Types

   

    enum LineType {

        case eventHeader(Event)

        case eventContinuation

        case individualEntry(IndividualEntry)

        case relayEntry(RelayEntry)

        case skip

        case unknown

    }



    // MARK: - Public API



    /// Main entry point. Takes the full merged column text from PDFExtractor

    /// and returns all parsed events with their entries.

    func parseEvents(from text: String) throws -> [Event] {

        if isDebugTraceEnabled {

            print("=== RAW TEXT FIRST 500 CHARS ===")

            print(String(text.prefix(500)))

            print("=== END RAW TEXT ===")

        }

       

        var events: [Event] = []

        var currentEvent: Event?

       

        let lines = text.components(separatedBy: .newlines)

        for line in lines {

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty { continue }

           

            let type = classifyLine(trimmed, currentEvent: currentEvent)

           

            if isDebugTraceEnabled {

                print("Trace [\(type)]: \(trimmed)")

            }

           

            switch type {

            case .eventHeader(let header):

                if let current = currentEvent {

                    if current.number == header.number && current.name == header.name {

                        // Continuation header with same name/number - ignore and keep current

                        continue

                    }

                    events.append(current)

                }

                currentEvent = header

               

            case .eventContinuation:

                continue

               

            case .individualEntry(let entry):

                currentEvent?.entries.append(.individual(entry))

               

            case .relayEntry(let entry):

                currentEvent?.entries.append(.relay(entry))

               

            case .skip:

                continue

               

            case .unknown:

                if isDebugTraceEnabled {

                    print("⚠️ UNKNOWN LINE: \(trimmed)")

                }

                continue

            }

        }

       

        if let current = currentEvent {

            events.append(current)

        }

       

        if isDebugTraceEnabled {

            print("=== PARSE RESULT: \(events.count) events ===")

            for e in events {

                print("Event \(e.number): \(e.entries.count) entries")

            }

        }

       

        return events

    }



    // MARK: - Internal Parsers



    /// Parses a single event header line.

    func parseEventHeader(line: String) -> Event? {

        // Explicitly reject continuation headers

        if line.contains("...") { return nil }

       

        let parts = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        guard parts.count >= 3, parts[0].uppercased() == "EVENT" else { return nil }

       

        let eventNumStr = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: ":"))

        guard let eventNum = Int(eventNumStr) else { return nil }

       

        let genders = ["GIRLS", "BOYS", "WOMEN", "MEN", "FEMALE", "MALE"]

        var genderIdx = -1

        var genderEnum: Gender = .male

        for (i, part) in parts.enumerated() {

            let p = part.uppercased()

            if i >= 2 && genders.contains(p) {

                genderIdx = i

                if ["GIRLS", "WOMEN", "FEMALE"].contains(p) {

                    genderEnum = .female

                }

                break

            }

        }

        if genderIdx == -1 { return nil }

       

        let commonDistances = [25, 50, 100, 200, 400, 500, 800, 1000, 1500, 1650]

        var distance = 0

        var distanceIdx = -1

       

        // Search backwards from the end to find the distance

        for i in stride(from: parts.count - 1, to: genderIdx, by: -1) {

            if let val = Int(parts[i]) {

                var isDist = commonDistances.contains(val)

                if !isDist {

                    let window = (i+1..<min(i+4, parts.count)).map { parts[$0].uppercased() }

                    if window.contains(where: { ["YARD","YARDS","LC","SC","METER","METERS","Y","M"].contains($0) }) {

                        isDist = true

                    }

                }

                if isDist {

                    distance = val

                    distanceIdx = i

                    break

                }

            }

        }

       

        if distance == 0 { return nil }

       

        var strokeParts: [String] = []

        for i in (distanceIdx + 1)..<parts.count {

            let p = parts[i]

            if ["YARD", "YARDS", "METER", "METERS", "LC", "SC", "LCM", "SCY", "SCM"].contains(p.uppercased()) { continue }

            strokeParts.append(p)

        }

        let stroke = strokeParts.joined(separator: " ")

       

        var ageGroup = ""

        if distanceIdx > genderIdx + 1 {

            ageGroup = parts[(genderIdx + 1)..<distanceIdx].joined(separator: " ")

        }

       

        let eventName = ageGroup.isEmpty ? "\(distance) \(stroke)" : "\(ageGroup) \(distance) \(stroke)"

        let isRelay = eventName.uppercased().contains("RELAY")

       

        return Event(

            number: eventNum,

            name: eventName,

            distance: distance,

            stroke: stroke,

            entries: [],

            isRelay: isRelay,

            gender: genderEnum

        )

    }



    /// Parses a single individual swimmer entry line.

    func parseIndividualEntry(line: String) -> IndividualEntry? {
        // Use whitespacesAndNewlines to strip invisible \r characters from PDFKit
        let parts = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard parts.count >= 3 else { return nil } // place, name, time at least
        guard let place = Int(parts[0]) else { return nil }

        // Find seed time scanning from end. No strict $ anchor: survives "1:03.39Y" or trailing whitespace.
        var timeIdx = -1
        let timePattern = #/^[Xx]?(\d+:)?\d{1,2}\.\d{2}/#
        for i in stride(from: parts.count - 1, through: 1, by: -1) {
            let p = parts[i].uppercased()
            if p.hasPrefix("NT") || p.firstMatch(of: timePattern) != nil {
                timeIdx = i
                break
            }
        }

        if timeIdx == -1 { return nil }
        let seedTime = parseSeedTime(parts[timeIdx])

        // Find Age/Year. Usually a 1-2 digit number or FR/SO/JR/SR.
        var ageIdx = -1
        var textAgeIdx = -1
        for i in 1..<parts.count {
            if i == timeIdx { continue }
            let p = parts[i].uppercased()
            if p.firstMatch(of: #/^(\d{1,2})$/#) != nil {
                ageIdx = i
                break
            } else if textAgeIdx == -1 && p.firstMatch(of: #/^(SO|FR|JR|SR)$/#) != nil {
                textAgeIdx = i
            }
        }
        
        if ageIdx == -1 {
            ageIdx = textAgeIdx
        }

        let age = ageIdx != -1 ? parts[ageIdx] : nil

        // Name starts at index 1 and goes up to the first found component (ageIdx or timeIdx).
        let firstComponentIdx = [ageIdx, timeIdx].filter { $0 > 0 }.min() ?? parts.count
        let name = parts[1..<firstComponentIdx].joined(separator: " ")

        // Team is everything after the name that isn't age or time.
        var teamParts: [String] = []
        for i in 1..<parts.count {
            if i == ageIdx || i == timeIdx { continue }
            if i < firstComponentIdx { continue } // already part of name
            teamParts.append(parts[i])
        }

        // Remove standard code if last team part looks like one (but preserve middle initials).
        if teamParts.count > 1, let last = teamParts.last {
            if last.uppercased().firstMatch(of: #/^[A-Z]{1,3}$/#) != nil && !["SO","FR","JR","SR"].contains(last.uppercased()) {
                teamParts.removeLast()
            }
        }

        let teamCode = teamParts.joined(separator: " ")

        // DEBUG TRACE — set isDebugTraceEnabled = true to see token-level detail
        if isDebugTraceEnabled {
            print("  ENTRY parts=\(parts) timeIdx=\(timeIdx) ageIdx=\(ageIdx) name='\(name)' team='\(teamCode)'")
        }

        let swimmer = Swimmer(name: name, age: age, teamCode: teamCode)
        return IndividualEntry(place: place, swimmer: swimmer, seedTime: seedTime)
    }



    /// Parses a single relay team entry line.

    func parseRelayEntry(line: String) -> RelayEntry? {
        // Use whitespacesAndNewlines to strip invisible \r characters from PDFKit
        let parts = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        guard parts.count >= 3 else { return nil }

        guard let place = Int(parts[0]) else { return nil }

       

        var timeIdx = -1

        let timePattern = #/^[Xx]?(\d+:)?\d{1,2}\.\d{2}/#

        for i in stride(from: parts.count - 1, through: 1, by: -1) {

            let p = parts[i].uppercased()

            if p.hasPrefix("NT") || p.firstMatch(of: timePattern) != nil {

                timeIdx = i

                break

            }

        }

       

        if timeIdx == -1 { return nil }

        let seedTime = parseSeedTime(parts[timeIdx])

       

        // Team name is everything except place and time

        var teamParts: [String] = []

        for i in 1..<parts.count {

            if i == timeIdx { continue }

            teamParts.append(parts[i])

        }

        let teamName = teamParts.joined(separator: " ")

       

        return RelayEntry(place: place, teamName: teamName, seedTime: seedTime)

    }



    /// Normalises a seed time string to TimeInterval.

    func parseSeedTime(_ raw: String) -> TimeInterval {

        var trimmed = raw.trimmingCharacters(in: .whitespaces).uppercased()

       

        // Remove trailing course indicators

        for suffix in ["Y", "L", "S", "B"] {

            if trimmed.hasSuffix(suffix) {

                trimmed.removeLast()

                break

            }

        }

       

        if trimmed.hasPrefix("X") { trimmed.removeFirst() }

        if trimmed.hasPrefix("NT") { return TimeInterval.infinity }

       

        // MM:SS.XX

        if let match = trimmed.firstMatch(of: #/^(\d+):(\d{2})\.(\d{2})$/#) {

            let min = Double(match.1) ?? 0

            let sec = Double(match.2) ?? 0

            let frac = Double(match.3) ?? 0

            return (min * 60) + sec + (frac / 100)

        }

       

        // MM:SS

        if let match = trimmed.firstMatch(of: #/^(\d+):(\d{2})$/#) {

            let min = Double(match.1) ?? 0

            let sec = Double(match.2) ?? 0

            return (min * 60) + sec

        }

       

        // SS.XX

        if let match = trimmed.firstMatch(of: #/^(\d+)\.(\d{2})$/#) {

            let sec = Double(match.1) ?? 0

            let frac = Double(match.2) ?? 0

            return sec + (frac / 100)

        }

       

        return TimeInterval.infinity

    }



    // MARK: - Skip Line Check



    func isSkipLine(_ line: String) -> Bool {

        let skips = [

            "Name Age Team Seed Time",

            "Name Age Team",

            "Team Relay Seed Time",

            "Team Relay Seed",

            "Seed Time",

            "HY-TEK",

            "Elig. Year",

            "Std Seed",

            "Psych Sheet"

        ]

        return skips.contains(where: { line.contains($0) })

    }



    // MARK: - Debug Trace Helper



    /// Classifies a line based on strict, mutually exclusive rules.

    func classifyLine(_ line: String, currentEvent: Event?) -> LineType {

        // 1. Check for skips first (page headers, column headers)

        if isSkipLine(line) { return .skip }

       

        // 2. Check for event continuation explicitly

        if line.hasPrefix("Event ") && line.contains("...") {

            return .eventContinuation

        }

       

        // 3. Try to parse as an Event Header

        if let header = parseEventHeader(line: line) {

            return .eventHeader(header)

        }

       

        // 4. Try to parse as an entry (requires an active event context)

        if let event = currentEvent {

            if event.isRelay {

                if let relay = parseRelayEntry(line: line) {

                    return .relayEntry(relay)

                }

            } else {

                if let individual = parseIndividualEntry(line: line) {

                    return .individualEntry(individual)

                }

            }

        }

       

        // 5. If nothing matched, it's unknown

        return .unknown

    }

}