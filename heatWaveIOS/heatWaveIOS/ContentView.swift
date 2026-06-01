// ContentView.swift
// heatWaveIOS
//
// Minimum Deployment Target: iOS 16.0
//
// Compilation Checklist (Ensure all these files are in the same flat heatWaveIOS directory in Xcode):
// - App.swift
// - ContentView.swift
// - DocumentPicker.swift
// - Models.swift
// - PDFExtractor.swift
// - PDFGenerator.swift
// - RegexParser.swift
// - SeedingEngine.swift
// - ShareSheet.swift
//
// Root view driving the UI state and wiring the processing pipeline.

import SwiftUI
import PDFKit

// MARK: - ProcessingState

enum ProcessingState: Equatable {
    case idle
    case loading(String)
    case preview([Event])
    case done(url: URL, entryCount: Int, heatCount: Int)
    case error(String)
    
    static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.loading(let a), .loading(let b)): return a == b
        case (.preview(let a), .preview(let b)): return a == b
        case (.done(let u1, let c1, let h1), .done(let u2, let c2, let h2)):
            return u1 == u2 && c1 == c2 && h1 == h2
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
    
    // Meet settings with sensible defaults
    @State private var meetTitle: String = "Meet"
    @State private var meetDate: String = ""
    @State private var lanes: Int = 8
    
    // Services
    let extractor = PDFExtractor()
    let parser = RegexParser()
    let engine = SeedingEngine()
    let generator = PDFGenerator()
    
    var body: some View {
        NavigationStack {
            VStack {
                if case .preview = state {
                    // Custom header for preview state to maximize space
                } else {
                    Spacer()
                    // App logo / title area
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.orange)
                        Text("heatWave")
                            .font(.largeTitle.bold())
                        Text("Psych Sheet → Heat Sheet")
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
                    case .done(let url, let entries, let heats):
                        successView(outputURL: url, entryCount: entries, heatCount: heats)
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
                if case .done(let url, _, _) = state {
                    ShareSheet(items: [url])
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
    }

    private func progressView(label: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
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
                    TextField("Meet Date (Optional)", text: $meetDate)
                    Stepper("Lanes: \(lanes)", value: $lanes, in: 4...10)
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
        }
    }

    private func successView(outputURL: URL, entryCount: Int, heatCount: Int) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Heat Sheet Ready")
                .font(.title2.bold())
                
            Text("\(heatCount) Heats | \(entryCount) Total Entries")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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

            Button("Start Over") {
                state = .idle
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
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
        state = .loading("Extracting text…")
        
        Task(priority: .userInitiated) {
            do {
                let text = try extractor.extractText(from: url)
                
                await MainActor.run { state = .loading("Parsing events…") }
                let events = try parser.parseEvents(from: text)
                
                await MainActor.run {
                    state = .preview(events)
                }
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
        state = .loading("Seeding heats…")
        
        Task(priority: .userInitiated) {
            do {
                let heatSheets = try engine.seedAllEvents(events, lanes: lanes)
                
                await MainActor.run { state = .loading("Generating PDF…") }
                
                let filename = "HeatSheet_\(meetTitle.replacingOccurrences(of: " ", with: "_")).pdf"
                let url = try generator.generateHeatSheet(heatSheets, to: filename, meetTitle: meetTitle, meetDate: meetDate)
                
                let totalEntries = heatSheets.reduce(0) { $0 + $1.assignments.count }
                let totalHeats = heatSheets.reduce(0) { $0 + $1.heats }
                
                await MainActor.run {
                    state = .done(url: url, entryCount: totalEntries, heatCount: totalHeats)
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
}
