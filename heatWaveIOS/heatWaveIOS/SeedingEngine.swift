// SeedingEngine.swift
// heatWaveIOS
//
// Applies USA Swimming preliminary seeding rules to a list of parsed events,
// producing heat and lane assignments for the PDF generator.
//
// TIMELINE ESTIMATOR:
//  estimatedDuration per HeatSheet = Σ(slowest timed seed in each heat) + (heats × turnoverTime)
//  Heats where every entry is NT use `ntFallbackTime` (default 120 s / 2:00.00).
//  turnoverTime covers the gap between the last swimmer touching the wall and
//  the starter's signal for the next heat (warm-up clear, check-in, etc.).

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
    
    // MARK: - Configuration
    
    /// Seconds added per heat to model check-in, clear-deck, and start procedure.
    /// Default: 120 s (2 minutes). ContentView exposes this as `turnoverMinutes` (stepper, 1–15 min).
    var turnoverTime: TimeInterval = 120
    
    /// Fallback swim time (seconds) used when every entry in a heat is NT.
    /// Default: 120 s (2:00.00) — a conservative middle-distance estimate.
    var ntFallbackTime: TimeInterval = 120
    
    // MARK: - Public API
    
    /// Seeds a single event and returns a complete HeatSheet, including timeline estimate.
    func seedEvent(_ event: Event, lanes: Int = 8) throws -> HeatSheet {
        guard lanes >= 4 && lanes <= 10 else {
            throw SeedingError.invalidLaneCount(lanes)
        }
        
        if event.entries.isEmpty {
            return HeatSheet(event: event, lanes: lanes, heats: 0, assignments: [], estimatedDuration: 0)
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
                startIdx = 0
                endIdx = remainder
            } else {
                if remainder > 0 && sortedEntries.count % lanes != 0 {
                    startIdx = remainder + (heatNum - 2) * lanes
                } else {
                    startIdx = (heatNum - 1) * lanes
                }
                endIdx = startIdx + lanes
            }
            
            let heatSlice = sortedEntries[startIdx..<endIdx]
            let heatEntries = Array(heatSlice.reversed())
            
            for (position, entry) in heatEntries.enumerated() {
                let lane = lanePattern[position]
                assignments.append(LaneAssignment(entry: entry, heat: heatNum, lane: lane))
            }
        }
        
        assignments.sort {
            if $0.heat != $1.heat { return $0.heat < $1.heat }
            return $0.lane < $1.lane
        }
        
        // MARK: Timeline estimation
        // Group assignments by heat and find the slowest timed entry per heat.
        let byHeat = Dictionary(grouping: assignments, by: { $0.heat })
        var swimTotal: TimeInterval = 0
        for heatNum in 1...numHeats {
            let heatAssignments = byHeat[heatNum] ?? []
            let times = heatAssignments.map { seedTimeForEntry($0.entry) }.filter { $0.isFinite }
            let slowest = times.max() ?? ntFallbackTime
            swimTotal += slowest
        }
        let estimatedDuration = swimTotal + Double(numHeats) * turnoverTime
        
        return HeatSheet(
            event: event,
            lanes: lanes,
            heats: numHeats,
            assignments: assignments,
            estimatedDuration: estimatedDuration
        )
    }
    
    /// Seeds all events and returns them in document order.
    func seedAllEvents(_ events: [Event], lanes: Int = 8) throws -> [HeatSheet] {
        return try events.map { try seedEvent($0, lanes: lanes) }
    }
    
    // MARK: - Internal Helpers
    
    func sortByTime(_ entries: [EventEntry]) -> [EventEntry] {
        return entries.sorted {
            seedTimeForEntry($0) > seedTimeForEntry($1)
        }
    }
    
    func seedTimeForEntry(_ entry: EventEntry) -> TimeInterval {
        switch entry {
        case .individual(let ind): return ind.seedTime
        case .relay(let rel): return rel.seedTime
        }
    }
    
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
