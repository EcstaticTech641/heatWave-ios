// ContentView.swift
// heatWaveIOS
//
// Minimum Deployment Target: iOS 16.0
//
// Hardware keyboard shortcuts (iPad + Magic Keyboard):
//   Cmd+O        — Import Psych Sheet (O for Open)
//   Cmd+Return   — Generate Heat Sheet
//   Cmd+S        — Share PDF
//   Cmd+F        — Find Swimmer
//   Cmd+R        — Start Over (R for Reset)
//   Escape       — Dismiss sheets (handled inside each sheet)

import SwiftUI
import PDFKit

// MARK: - ProcessingState

enum ProcessingState: Equatable {
    case idle
    case loading(String)
    case preview([Event])
    case done(url: URL, entryCount: Int, heatCount: Int, meetDuration: TimeInterval, heatSheets: [HeatSheet])
    case error(String)
    
    static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.loading(let a), .loading(let b)): return a == b
        case (.preview(let a), .preview(let b)): return a == b
        case (.done(let u1, let c1, let h1, let d1, _), .done(let u2, let c2, let h2, let d2, _)):
            return u1 == u2 && c1 == c2 && h1 == h2 && d1 == d2
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @State private var state: ProcessingState = .idle
    @State private var isPickerPresented: Bool = false
    @State private var isSharePresented: Bool = false
    @State private var isSwimmerSearchPresented: Bool = false
    
    @State private var meetTitle: String = "Meet"
    @State private var meetDate: String = ""
    @State private var lanes: Int = 8
    /// Gap between heats in minutes. 2 min suits most short-course yards meets.
    @State private var turnoverMinutes: Int = 2
    
    let extractor = PDFExtractor()
    let parser = RegexParser()
    let generator = PDFGenerator()
    
    var body: some View {
        NavigationStack {
            VStack {
                if case .preview = state {
                } else {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.orange)
                        Text("heatWave")
                            .font(.largeTitle.bold())
                        Text("Psych Sheet \u{2192} Heat Sheet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                
                Group {
                    switch state {
                    case .idle:
                        idleView
                    case .loading(let msg):
                        progressView(label: msg)
                    case .preview(let events):
                        previewView(events: events)
                    case .done(let url, let entries, let heats, let duration, let heatSheets):
                        successView(
                            outputURL: url,
                            entryCount: entries,
                            heatCount: heats,
                            meetDuration: duration,
                            heatSheets: heatSheets
                        )
                    case .error(let msg):
                        errorView(message: msg)
                    }
                }
                
                if case .preview = state {} else { Spacer() }
            }
            .padding()
            .navigationTitle(casePreviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isPickerPresented) {
                DocumentPicker(allowedTypes: ["com.adobe.pdf"]) { url in
                    processPDF(at: url)
                }
            }
            .sheet(isPresented: $isSharePresented) {
                if case .done(let url, _, _, _, _) = state {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $isSwimmerSearchPresented) {
                if case .done(_, _, _, _, let heatSheets) = state {
                    SwimmerSearchView(heatSheets: heatSheets)
                }
            }
        }
    }
    
    var casePreviewTitle: String {
        if case .preview = state { return "Configure Meet" }
        return ""
    }
    
    // MARK: - Sub-views
    
    private var idleView: some View {
        Button {
            isPickerPresented = true
        } label: {
            Label("Import Psych Sheet", systemImage: "doc.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        // Cmd+O — standard "open file" shortcut
        .keyboardShortcut("o", modifiers: .command)
    }
    
    private func progressView(label: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.4)
            Text(label)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
    
    private func previewView(events: [Event]) -> some View {
        VStack(spacing: 20) {
            Form {
                Section("Meet Settings") {
                    TextField("Meet Title", text: $meetTitle)
                        .submitLabel(.next)
                    TextField("Meet Date (Optional)", text: $meetDate)
                        .submitLabel(.done)
                    Stepper("Lanes: \(lanes)", value: $lanes, in: 4...10)
                    VStack(alignment: .leading, spacing: 4) {
                        Stepper("Heat gap: \(turnoverMinutes) min", value: $turnoverMinutes, in: 1...15)
                        Text("Time between heats: check-in, clear deck, and start signal. Typical SCY meet: 2\u{2013}3 min.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Parsed Events (\(events.count))") {
                    List(events) { event in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Event \(event.number): \(event.name)")
                                    .font(.subheadline.bold())
                                Text("\(event.gender.rawValue) \(event.distance)Y \(event.stroke)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(event.entries.count) entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Button {
                generateHeatSheet(events: events)
            } label: {
                Label("Generate Heat Sheet", systemImage: "bolt.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            // Cmd+Return — natural "confirm/go" shortcut
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
    
    private func successView(
        outputURL: URL,
        entryCount: Int,
        heatCount: Int,
        meetDuration: TimeInterval,
        heatSheets: [HeatSheet]
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            
            Text("Heat Sheet Ready")
                .font(.title2.bold())
            
            Text("\(heatCount) Heats | \(entryCount) Total Entries")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 6) {
                Label("Estimated Meet Duration", systemImage: "clock")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(formatDuration(meetDuration))
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
                Text("Slowest seed per heat + \(turnoverMinutes) min gap between heats")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Button {
                isSharePresented = true
            } label: {
                Label("Share PDF", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            // Cmd+S — standard "save/share" shortcut
            .keyboardShortcut("s", modifiers: .command)
            
            Button {
                isSwimmerSearchPresented = true
            } label: {
                Label("Find Swimmer", systemImage: "person.text.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            // Cmd+F — standard "find" shortcut
            .keyboardShortcut("f", modifiers: .command)
            
            Button("Start Over") {
                state = .idle
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            // Cmd+R — reset
            .keyboardShortcut("r", modifiers: .command)
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
            Text("Processing Error")
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try Again") {
                state = .idle
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    // MARK: - Pipeline
    
    private func processPDF(at url: URL) {
        state = .loading("Extracting text\u{2026}")
        Task(priority: .userInitiated) {
            do {
                let text = try extractor.extractText(from: url)
                await MainActor.run { state = .loading("Parsing events\u{2026}") }
                let events = try parser.parseEvents(from: text)
                await MainActor.run { state = .preview(events) }
            } catch let error as PDFExtractionError {
                let msg: String
                switch error {
                case .scannedPDF:
                    msg = "This PDF appears to be image-based. Scanned PDFs are not yet supported."
                case .emptyDocument:
                    msg = "The PDF appears to be empty or corrupted."
                default:
                    msg = "Something went wrong: \(error.localizedDescription)"
                }
                await MainActor.run { state = .error(msg) }
            } catch {
                await MainActor.run { state = .error("Something went wrong: \(error.localizedDescription)") }
            }
        }
    }
    
    private func generateHeatSheet(events: [Event]) {
        state = .loading("Seeding heats\u{2026}")
        let turnoverSeconds = TimeInterval(turnoverMinutes) * 60
        Task(priority: .userInitiated) {
            do {
                var engine = SeedingEngine()
                engine.turnoverTime = turnoverSeconds
                let heatSheets = try engine.seedAllEvents(events, lanes: lanes)
                await MainActor.run { state = .loading("Generating PDF\u{2026}") }
                let filename = "HeatSheet_\(meetTitle.replacingOccurrences(of: " ", with: "_")).pdf"
                let url = try generator.generateHeatSheet(
                    heatSheets,
                    to: filename,
                    meetTitle: meetTitle,
                    meetDate: meetDate
                )
                let totalEntries  = heatSheets.reduce(0)   { $0 + $1.assignments.count }
                let totalHeats    = heatSheets.reduce(0)   { $0 + $1.heats }
                let totalDuration = heatSheets.reduce(0.0) { $0 + $1.estimatedDuration }
                await MainActor.run {
                    state = .done(
                        url: url,
                        entryCount: totalEntries,
                        heatCount: totalHeats,
                        meetDuration: totalDuration,
                        heatSheets: heatSheets
                    )
                }
            } catch let error as SeedingError {
                let msg: String
                if case .invalidLaneCount = error {
                    msg = "Invalid lane count. Please enter a value between 4 and 10."
                } else {
                    msg = "Something went wrong: \(error.localizedDescription)"
                }
                await MainActor.run { state = .error(msg) }
            } catch {
                await MainActor.run { state = .error("Something went wrong: \(error.localizedDescription)") }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}
