// SwimmerSearchView.swift
// heatWaveIOS
//
// Minimum Deployment Target: iOS 16.0
//
// Hardware keyboard support:
//   Escape       — dismiss the sheet
//   Return/Enter — navigate to the first matching result
//   (Typing works on both software and Magic Keyboard without a focus delay)

import SwiftUI

// MARK: - Data types

struct SwimmerEventInfo: Identifiable, Hashable {
    var id: String { "\(eventNumber)-\(heat)-\(lane)" }
    let eventNumber: Int
    let eventName: String
    let gender: Gender
    let distance: Int
    let stroke: String
    let heat: Int
    let lane: Int
    let seedTime: TimeInterval
    let estimatedStart: TimeInterval
}

struct SwimmerSearchResult: Identifiable, Hashable {
    var id: String { "\(name)|\(team)" }
    let name: String
    let team: String
    let ageOrYear: String?
    let appearances: [SwimmerEventInfo]
}

// MARK: - SwimmerSearchView

struct SwimmerSearchView: View {
    
    let heatSheets: [HeatSheet]
    
    @State private var searchText: String = ""
    @State private var pushedResult: SwimmerSearchResult? = nil
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    
    // MARK: Swimmer index
    
    private var allResults: [SwimmerSearchResult] {
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
    
    private var filteredResults: [SwimmerSearchResult] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let lower = query.lowercased()
        return allResults
            .filter { $0.name.replacingOccurrences(of: ",", with: " ").lowercased().contains(lower) }
            .sorted { $0.name < $1.name }
    }
    
    private var queryIsEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                resultArea
            }
            .navigationTitle("Find Swimmer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                    // Escape key dismisses the sheet
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
            // Programmatic navigation when Return is pressed
            .navigationDestination(item: $pushedResult) { result in
                SwimmerDetailView(result: result)
            }
            .onAppear {
                // No delay needed — @FocusState works immediately for both
                // software keyboard and hardware Magic Keyboard.
                isSearchFocused = true
            }
        }
    }
    
    // MARK: Search bar
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("First or last name", text: $searchText)
                .focused($isSearchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            // Return/Enter → push first matching result
                .onSubmit {
                    if let first = filteredResults.first {
                        pushedResult = first
                    }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
    
    // MARK: Result area
    
    @ViewBuilder
    private var resultArea: some View {
        if queryIsEmpty {
            emptyPrompt
        } else if filteredResults.isEmpty {
            noResultsView
        } else {
            swimmerList
        }
    }
    
    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Search for a swimmer")
                .font(.title3.bold())
            Text("Type any part of a first or last name.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
    
    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No swimmer found")
                .font(.title3.bold())
            Text("\"\(searchText)\" didn't match any entry in the heat sheet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
    
    private var swimmerList: some View {
        List(filteredResults) { result in
            NavigationLink(destination: SwimmerDetailView(result: result)) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.name)
                            .font(.subheadline.bold())
                        HStack(spacing: 6) {
                            Text(result.team)
                            if let ay = result.ageOrYear, !ay.isEmpty {
                                Text("·")
                                Text(ay)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(result.appearances.count) event\(result.appearances.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - SwimmerDetailView

struct SwimmerDetailView: View {
    
    let result: SwimmerSearchResult
    
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.name)
                            .font(.headline)
                        HStack(spacing: 6) {
                            Text(result.team)
                            if let ay = result.ageOrYear, !ay.isEmpty {
                                Text("·")
                                Text(ay)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            
            Section("Schedule \u{2014} \(result.appearances.count) event\(result.appearances.count == 1 ? "" : "s")") {
                ForEach(result.appearances) { info in
                    eventRow(info)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Swimmer Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func eventRow(_ info: SwimmerEventInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Event \(info.eventNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Spacer()
                Text(formatTime(info.seedTime))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Text("\(info.gender.rawValue) \(info.distance)Y \(info.stroke)")
                .font(.subheadline.bold())
            HStack(spacing: 8) {
                Label("Heat \(info.heat)", systemImage: "heat.waves")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                Text("Lane \(info.lane)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .clipShape(Capsule())
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(formatDuration(info.estimatedStart))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        if time == .infinity { return "NT" }
        let mins = Int(time) / 60
        let secs = time.truncatingRemainder(dividingBy: 60)
        return mins > 0 ? String(format: "%d:%05.2f", mins, secs) : String(format: "%.2f", secs)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "< 1m" }
        let total = Int(seconds / 60)
        let h = total / 60, m = total % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }
}
