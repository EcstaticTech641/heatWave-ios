// PDFGenerator.swift
// heatWaveIOS
//
// Renders a complete heat sheet (array of HeatSheet objects from SeedingEngine)
// into a formatted PDF file on-device, saved to the user's document directory.
//
// TIMELINE ESTIMATOR:
//  Each event header now shows:
//    - "Est. Start: Xh Ym" — the running clock at the beginning of this event
//    - "Est. Duration: Ym Zs" — swim time + turnover for this event alone
//  A summary block at the very end of the PDF prints the total estimated meet duration.

import UIKit
import Foundation

// MARK: - PDFGeneratorError

enum PDFGeneratorError: LocalizedError {
    case noHeatSheets
    case fileWriteFailed(path: String)
    
    var errorDescription: String? {
        switch self {
        case .noHeatSheets:
            return "No heat sheets to generate."
        case .fileWriteFailed(let path):
            return "Failed to write the PDF to: \(path)"
        }
    }
}

// MARK: - PDFGenerator

/// Renders an array of `HeatSheet` objects into a formatted PDF file.
struct PDFGenerator {
    
    // MARK: - Configuration
    
    /// Page size in points. Default: US Letter (8.5 × 11 in).
    var pageSize: CGSize = CGSize(width: 612, height: 792)
    
    /// Inset from page edges for all content.
    var margin: CGFloat = 36
    
    // MARK: - Public API
    
    /// Renders `heatSheets` into a PDF and saves it to `.documentDirectory`.
    func generateHeatSheet(_ heatSheets: [HeatSheet], to filename: String, meetTitle: String, meetDate: String) throws -> URL {
        guard !heatSheets.isEmpty else { throw PDFGeneratorError.noHeatSheets }
        
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let data = renderer.pdfData { context in
            context.beginPage()
            var cursor: CGFloat = margin
            
            // Draw meet title
            let titleFont = UIFont.boldSystemFont(ofSize: 18)
            let titleStr = NSAttributedString(string: meetTitle, attributes: [.font: titleFont])
            titleStr.draw(at: CGPoint(x: margin, y: cursor))
            cursor += 24
            
            // Draw meet date
            if !meetDate.isEmpty {
                let dateStr = NSAttributedString(string: meetDate, attributes: [.font: UIFont.systemFont(ofSize: 12)])
                dateStr.draw(at: CGPoint(x: margin, y: cursor))
                cursor += 20
            }
            cursor += 10
            
            // Running clock: accumulates as we go event by event
            var runningClock: TimeInterval = 0
            
            for sheet in heatSheets {
                // Estimate header height + at least one heat. If not enough, new page.
                if cursor + 100 > pageSize.height - margin {
                    context.beginPage()
                    cursor = margin
                }
                
                drawEventHeader(sheet, estimatedStart: runningClock, context: context, cursor: &cursor)
                
                // Advance the running clock by this event's estimated duration
                runningClock += sheet.estimatedDuration
                
                // Group assignments by heat
                let heatDict = Dictionary(grouping: sheet.assignments, by: { $0.heat })
                let sortedHeats = heatDict.keys.sorted()
                
                for heatNum in sortedHeats {
                    if let assignments = heatDict[heatNum] {
                        let estimatedHeatHeight: CGFloat = 30 + CGFloat(assignments.count * 16)
                        if cursor + estimatedHeatHeight > pageSize.height - margin {
                            context.beginPage()
                            cursor = margin
                        }
                        drawHeat(assignments, heatNumber: heatNum, context: context, cursor: &cursor)
                    }
                }
                cursor += 20
            }
            
            // Grand total timeline block
            let totalDuration = heatSheets.reduce(0.0) { $0 + $1.estimatedDuration }
            if cursor + 60 > pageSize.height - margin {
                context.beginPage()
                cursor = margin
            }
            drawTimelineSummary(totalDuration: totalDuration, context: context, cursor: &cursor)
        }
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(filename)
        
        do {
            try data.write(to: url)
        } catch {
            throw PDFGeneratorError.fileWriteFailed(path: url.path)
        }
        
        return url
    }
    
    // MARK: - Internal Helpers
    
    /// Draws the event header block, including est. start time and est. event duration.
    private func drawEventHeader(_ sheet: HeatSheet,
                                 estimatedStart: TimeInterval,
                                 context: UIGraphicsPDFRendererContext,
                                 cursor: inout CGFloat) {
        let boldFont = UIFont.boldSystemFont(ofSize: 14)
        let regularFont = UIFont.systemFont(ofSize: 12)
        let timelineFont = UIFont.italicSystemFont(ofSize: 11)
        
        let headerText = "Event \(sheet.event.number): \(sheet.event.gender.rawValue) \(sheet.event.distance)Y \(sheet.event.stroke)"
        let subText = "Total Heats: \(sheet.heats) | Total Entries: \(sheet.assignments.count)"
        let startLabel = "Est. Start: \(formatDuration(estimatedStart))"
        let durationLabel = "Est. Event Duration: \(formatDuration(sheet.estimatedDuration))"
        let timelineText = "\(startLabel)   \(durationLabel)"
        
        NSAttributedString(string: headerText, attributes: [.font: boldFont])
            .draw(at: CGPoint(x: margin, y: cursor))
        cursor += 18
        
        NSAttributedString(string: subText, attributes: [.font: regularFont])
            .draw(at: CGPoint(x: margin, y: cursor))
        cursor += 16
        
        // Draw timeline estimate line in a muted style
        NSAttributedString(string: timelineText, attributes: [
            .font: timelineFont,
            .foregroundColor: UIColor.darkGray
        ]).draw(at: CGPoint(x: margin, y: cursor))
        cursor += 18
        
        // Thin separator rule under the header
        context.cgContext.move(to: CGPoint(x: margin, y: cursor))
        context.cgContext.addLine(to: CGPoint(x: pageSize.width - margin, y: cursor))
        context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
        context.cgContext.setLineWidth(0.5)
        context.cgContext.strokePath()
        cursor += 6
    }
    
    /// Draws one heat's lane assignments onto the current PDF page in a table format.
    private func drawHeat(_ assignments: [LaneAssignment],
                          heatNumber: Int,
                          context: UIGraphicsPDFRendererContext,
                          cursor: inout CGFloat) {
        let titleFont = UIFont.boldSystemFont(ofSize: 12)
        let font = UIFont.systemFont(ofSize: 12)
        
        NSAttributedString(string: "Heat \(heatNumber):", attributes: [.font: titleFont])
            .draw(at: CGPoint(x: margin, y: cursor))
        cursor += 16
        
        // Table headers
        let headers = ["Lane", "Name", "Team", "Seed Time"]
        let xOffsets: [CGFloat] = [margin, margin + 40, margin + 250, margin + 400]
        
        for (i, text) in headers.enumerated() {
            NSAttributedString(string: text, attributes: [.font: titleFont])
                .draw(at: CGPoint(x: xOffsets[i], y: cursor))
        }
        cursor += 16
        
        // Ruled line under headers
        context.cgContext.move(to: CGPoint(x: margin, y: cursor))
        context.cgContext.addLine(to: CGPoint(x: pageSize.width - margin, y: cursor))
        context.cgContext.setStrokeColor(UIColor.black.cgColor)
        context.cgContext.setLineWidth(0.5)
        context.cgContext.strokePath()
        cursor += 4
        
        // Row data
        for assignment in assignments {
            let laneStr = "\(assignment.lane)"
            var nameStr = ""
            var teamStr = ""
            var timeStr = ""
            
            switch assignment.entry {
            case .individual(let ind):
                nameStr = ind.swimmer.name
                if let age = ind.swimmer.age {
                    nameStr += " (Age \(age))"
                }
                teamStr = ind.swimmer.teamCode
                timeStr = formatTime(ind.seedTime)
            case .relay(let rel):
                nameStr = rel.teamName
                timeStr = formatTime(rel.seedTime)
            }
            
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            NSAttributedString(string: laneStr, attributes: attrs).draw(at: CGPoint(x: xOffsets[0], y: cursor))
            NSAttributedString(string: nameStr, attributes: attrs).draw(at: CGPoint(x: xOffsets[1], y: cursor))
            NSAttributedString(string: teamStr, attributes: attrs).draw(at: CGPoint(x: xOffsets[2], y: cursor))
            NSAttributedString(string: timeStr, attributes: attrs).draw(at: CGPoint(x: xOffsets[3], y: cursor))
            
            cursor += 16
        }
        cursor += 10
    }
    
    /// Draws the grand-total timeline summary block at the end of the PDF.
    private func drawTimelineSummary(totalDuration: TimeInterval,
                                     context: UIGraphicsPDFRendererContext,
                                     cursor: inout CGFloat) {
        let boldFont = UIFont.boldSystemFont(ofSize: 13)
        let regularFont = UIFont.systemFont(ofSize: 12)
        
        // Top rule
        context.cgContext.move(to: CGPoint(x: margin, y: cursor))
        context.cgContext.addLine(to: CGPoint(x: pageSize.width - margin, y: cursor))
        context.cgContext.setStrokeColor(UIColor.black.cgColor)
        context.cgContext.setLineWidth(1.0)
        context.cgContext.strokePath()
        cursor += 8
        
        NSAttributedString(string: "Meet Timeline Estimate", attributes: [.font: boldFont])
            .draw(at: CGPoint(x: margin, y: cursor))
        cursor += 18
        
        NSAttributedString(
            string: "Estimated Total Meet Duration: \(formatDuration(totalDuration))",
            attributes: [.font: regularFont]
        ).draw(at: CGPoint(x: margin, y: cursor))
        cursor += 16
        
        NSAttributedString(
            string: "Note: Estimate uses slowest timed seed per heat plus configured turnover time between heats.",
            attributes: [
                .font: UIFont.italicSystemFont(ofSize: 10),
                .foregroundColor: UIColor.darkGray
            ]
        ).draw(at: CGPoint(x: margin, y: cursor))
        cursor += 16
    }
    
    // MARK: - Formatters
    
    /// Formats a time interval (seconds) as "Xh Ym Zs" for timeline display.
    func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "0m" }
        let totalSecs = Int(seconds)
        let hours = totalSecs / 3600
        let minutes = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if secs > 0 && hours == 0 { parts.append("\(secs)s") }
        return parts.isEmpty ? "0m" : parts.joined(separator: " ")
    }
    
    /// Formats a seed time interval into a display string, treating .infinity as "NT".
    func formatTime(_ time: TimeInterval) -> String {
        if time == .infinity {
            return "NT"
        }
        let mins = Int(time) / 60
        let secs = time.truncatingRemainder(dividingBy: 60)
        
        if mins > 0 {
            return String(format: "%d:%05.2f", mins, secs)
        } else {
            return String(format: "%.2f", secs)
        }
    }
}
