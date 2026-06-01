// Models.swift
// heatWaveIOS
//
// Core data models for parsed swimming events and heat sheet generation.
//
// DESIGN NOTES:
//  - All models are Codable and Equatable.
//  - Gender is derived from event number parity (Odd = Female, Even = Male).
//  - Seed times are represented as TimeInterval, with NT (No Time) mapping to .infinity.

import Foundation

/// Represents the gender of the event participants.
enum Gender: String, Codable, Equatable {
    case female = "Female" // For girls/women
    case male = "Male" // For boys/men
}

/// Represents a swimmer.
struct Swimmer: Codable, Equatable {
    /// The name of the swimmer (e.g. "Smith, John").
    let name: String
    /// The age or eligibility year of the swimmer (e.g. "14", "SO"). Nil for relays.
    let age: String?
    /// The team code of the swimmer.
    let teamCode: String
}

/// Represents an individual swimmer's entry in an event.
struct IndividualEntry: Codable, Equatable, Identifiable {
    /// Unique identifier for SwiftUI Lists.
    var id: String { "\(place)-\(swimmer.name)" }
    /// The placement/ranking based on seed time.
    let place: Int
    /// The swimmer participating in the event.
    let swimmer: Swimmer
    /// The seed time in seconds. NT is TimeInterval.infinity.
    let seedTime: TimeInterval
}

/// Represents a relay team's entry in an event.
struct RelayEntry: Codable, Equatable, Identifiable {
    /// Unique identifier for SwiftUI Lists.
    var id: String { "\(place)-\(teamName)" }
    /// The placement/ranking based on seed time.
    let place: Int
    /// The team name and designation (e.g. "Tulsa Swim-OK A").
    let teamName: String
    /// The seed time in seconds. NT is TimeInterval.infinity.
    let seedTime: TimeInterval
}

/// Represents an entry in an event, which can be either an individual or a relay team.
enum EventEntry: Codable, Equatable {
    case individual(IndividualEntry)
    case relay(RelayEntry)
}

/// Represents a competitive swimming event.
struct Event: Codable, Equatable, Identifiable {
    /// Unique identifier for SwiftUI Lists (Event numbers are unique).
    var id: Int { number }
    /// The event number.
    let number: Int
    /// The descriptive name of the event (e.g. "10 & Under 200 Freestyle").
    let name: String
    /// The distance of the event (e.g. 200).
    let distance: Int
    /// The stroke of the event (e.g. "Freestyle").
    let stroke: String
    /// The list of entries in the event.
    var entries: [EventEntry]
    /// Whether the event is a relay.
    let isRelay: Bool
    
    /// The gender of the event participants.
    let gender: Gender
}

/// Represents a single heat within an event.
struct Heat: Codable, Equatable {
    /// The heat number.
    let number: Int
    /// The lane assignments for this heat.
    let assignments: [LaneAssignment]
}

/// Represents a swimmer or relay team assigned to a specific lane.
struct LaneAssignment: Codable, Equatable {
    /// The entry assigned to the lane.
    let entry: EventEntry
    /// The heat number.
    let heat: Int
    /// The lane number.
    let lane: Int
}

/// A complete heat sheet for an event.
struct HeatSheet: Codable, Equatable, Identifiable {
    /// Unique identifier for SwiftUI Lists.
    var id: Int { event.number }
    /// The event.
    let event: Event
    /// The total number of lanes available.
    let lanes: Int
    /// The total number of heats.
    let heats: Int
    /// The lane assignments.
    let assignments: [LaneAssignment]
}
