// SeedingEngine.swift
// heatWaveIOS
//
// Applies USA Swimming preliminary seeding rules to a list of parsed events,
// producing heat and lane assignments for the PDF generator.

import Foundation

enum SeedingError: LocalizedError {
    case invalidLaneCount(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidLaneCount(let count):
            return "Invalid lane count: \(count). Must be between 4 and 10."
        }
    }
}

/// Converts parsed events into lane-assigned heat sheets using USA Swimming rules.
struct SeedingEngine {

    // MARK: - Public API

    /// Seeds a single event and returns a complete HeatSheet.
    ///
    /// - Parameters:
    ///   - event: An `Event` with all entries populated.
    ///   - lanes: Number of lanes in the pool (default: 8).
    /// - Returns: A `HeatSheet` with heat/lane assignments sorted by (heat, lane).
    /// - Throws: `SeedingError` if lane count is invalid.
    func seedEvent(_ event: Event, lanes: Int = 8) throws -> HeatSheet {
        guard lanes >= 4 && lanes <= 10 else {
            throw SeedingError.invalidLaneCount(lanes)
        }
        
        if event.entries.isEmpty {
            return HeatSheet(event: event, lanes: lanes, heats: 0, assignments: [])
        }
        
        // Slowest to fastest
        let sortedEntries = sortByTime(event.entries)
        
        let numHeats = Int(ceil(Double(sortedEntries.count) / Double(lanes)))
        let lanePattern = centerOutPattern(lanes: lanes)
        
        var assignments: [LaneAssignment] = []
        var remainder = sortedEntries.count % lanes
        if remainder == 0 {
            remainder = lanes
        }
        
        for heatNum in 1...numHeats {
            let startIdx: Int
            let endIdx: Int
            
            if remainder > 0 && heatNum == 1 {
                // First heat: partial (with empty lanes)
                startIdx = 0
                endIdx = remainder
            } else {
                // Other heats: full
                if remainder > 0 && sortedEntries.count % lanes != 0 {
                    startIdx = remainder + (heatNum - 2) * lanes
                } else {
                    startIdx = (heatNum - 1) * lanes
                }
                endIdx = startIdx + lanes
            }
            
            let heatSlice = sortedEntries[startIdx..<endIdx]
            
            // Reverse to put fastest first in heat for center-out placement
            let heatEntries = Array(heatSlice.reversed())
            
            for (position, entry) in heatEntries.enumerated() {
                let lane = lanePattern[position]
                assignments.append(LaneAssignment(entry: entry, heat: heatNum, lane: lane))
            }
        }
        
        // Sort assignments by heat then lane for output
        assignments.sort {
            if $0.heat != $1.heat { return $0.heat < $1.heat }
            return $0.lane < $1.lane
        }
        
        return HeatSheet(
            event: event,
            lanes: lanes,
            heats: numHeats,
            assignments: assignments
        )
    }

    /// Seeds all events in a psych sheet in document order.
    ///
    /// - Parameters:
    ///   - events: Array of `Event` objects from RegexParser.
    ///   - lanes: Number of lanes (applied to all events).
    /// - Returns: Array of `HeatSheet` objects in event order.
    func seedAllEvents(_ events: [Event], lanes: Int = 8) throws -> [HeatSheet] {
        return try events.map { try seedEvent($0, lanes: lanes) }
    }

    // MARK: - Internal Helpers

    /// Returns entries sorted slowest-first (NT at the very beginning).
    ///
    /// - Parameter entries: Unsorted event entries.
    func sortByTime(_ entries: [EventEntry]) -> [EventEntry] {
        return entries.sorted {
            let time1 = seedTime(for: $0)
            let time2 = seedTime(for: $1)
            // Sort descending: slower (larger time) first.
            // TimeInterval.infinity (NT) will naturally be placed at the start.
            return time1 > time2
        }
    }
    
    private func seedTime(for entry: EventEntry) -> TimeInterval {
        switch entry {
        case .individual(let ind): return ind.seedTime
        case .relay(let rel): return rel.seedTime
        }
    }

    /// Generates the center-out lane assignment pattern for a given lane count.
    ///
    /// For 8 lanes: [4, 5, 3, 6, 2, 7, 1, 8]
    /// For 6 lanes: [3, 4, 2, 5, 1, 6]
    ///
    /// - Parameter lanes: Number of lanes in the pool.
    /// - Returns: Lane numbers in center-out placement order (position 0 = fastest in heat).
    func centerOutPattern(lanes: Int) -> [Int] {
        if lanes <= 0 { return [] }
        var result: [Int] = []
        var left = lanes / 2
        var right = left + 1
        
        for _ in 0..<lanes {
            if left >= 1 && result.count < lanes {
                result.append(left)
                left -= 1
            }
            if right <= lanes && result.count < lanes {
                result.append(right)
                right += 1
            }
        }
        
        return Array(result.prefix(lanes))
    }
}
