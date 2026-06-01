// PDFGenerator.swift
// heatWaveIOS
//
// Renders a complete heat sheet (array of HeatSheet objects from SeedingEngine)
// into a formatted PDF file on-device, saved to the user's document directory.

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
    ///
    /// - Parameters:
    ///   - heatSheets: Ordered array of `HeatSheet` from SeedingEngine.
    ///   - filename: The name of the output PDF file.
    ///   - meetTitle: Title of the meet to display at the top.
    ///   - meetDate: Date of the meet to display below the title.
    /// - Returns: The URL of the saved PDF file.
    /// - Throws: `PDFGeneratorError` if no heat sheets are provided or writing fails.
    func generateHeatSheet(_ heatSheets: [HeatSheet], to filename: String, meetTitle: String, meetDate: String) throws -> URL {
        guard !heatSheets.isEmpty else { throw PDFGeneratorError.noHeatSheets }
        
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let data = renderer.pdfData { context in
            context.beginPage()
            var cursor: CGFloat = margin
            
            // Draw meet title
            let titleFont = UIFont.boldSystemFont(ofSize: 18)
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont]
            let titleStr = NSAttributedString(string: meetTitle, attributes: titleAttrs)
            titleStr.draw(at: CGPoint(x: margin, y: cursor))
            cursor += 24
            
            // Draw meet date
            if !meetDate.isEmpty {
                let dateStr = NSAttributedString(string: meetDate, attributes: [.font: UIFont.systemFont(ofSize: 12)])
                dateStr.draw(at: CGPoint(x: margin, y: cursor))
                cursor += 20
            }
            cursor += 10
            
            for sheet in heatSheets {
                // Estimate header height + at least one heat. If not enough, new page.
                if cursor + 100 > pageSize.height - margin {
                    context.beginPage()
                    cursor = margin
                }
                
                drawEventHeader(sheet, context: context, cursor: &cursor)
                
                // Group assignments by heat
                let heatDict = Dictionary(grouping: sheet.assignments, by: { $0.heat })
                let sortedHeats = heatDict.keys.sorted()
                
                for heatNum in sortedHeats {
                    if let assignments = heatDict[heatNum] {
                        // 30pts for heat header + 16pts per row
                        let estimatedHeatHeight: CGFloat = 30 + CGFloat(assignments.count * 16)
                        if cursor + estimatedHeatHeight > pageSize.height - margin {
                            context.beginPage()
                            cursor = margin
                        }
                        drawHeat(assignments, heatNumber: heatNum, context: context, cursor: &cursor)
                    }
                }
                cursor += 20 // Extra space between events
            }
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

    /// Draws the event header block onto the current PDF page.
    private func drawEventHeader(_ sheet: HeatSheet,
                                 context: UIGraphicsPDFRendererContext,
                                 cursor: inout CGFloat) {
        let font = UIFont.boldSystemFont(ofSize: 14)
        let headerText = "Event \(sheet.event.number): \(sheet.event.gender.rawValue) \(sheet.event.distance)Y \(sheet.event.stroke)"
        let subText = "Total Heats: \(sheet.heats) | Total Entries: \(sheet.assignments.count)"
        
        let headerAttr = NSAttributedString(string: headerText, attributes: [.font: font])
        headerAttr.draw(at: CGPoint(x: margin, y: cursor))
        cursor += 18
        
        let subAttr = NSAttributedString(string: subText, attributes: [.font: UIFont.systemFont(ofSize: 12)])
        subAttr.draw(at: CGPoint(x: margin, y: cursor))
        cursor += 20
    }

    /// Draws one heat's lane assignments onto the current PDF page in a table format.
    private func drawHeat(_ assignments: [LaneAssignment],
                          heatNumber: Int,
                          context: UIGraphicsPDFRendererContext,
                          cursor: inout CGFloat) {
        let titleFont = UIFont.boldSystemFont(ofSize: 12)
        let font = UIFont.systemFont(ofSize: 12)
        
        let heatTitle = NSAttributedString(string: "Heat \(heatNumber):", attributes: [.font: titleFont])
        heatTitle.draw(at: CGPoint(x: margin, y: cursor))
        cursor += 16
        
        // Draw table headers
        let headers = ["Lane", "Name", "Team", "Seed Time"]
        let xOffsets: [CGFloat] = [margin, margin + 40, margin + 250, margin + 400]
        
        for (i, text) in headers.enumerated() {
            let attr = NSAttributedString(string: text, attributes: [.font: titleFont])
            attr.draw(at: CGPoint(x: xOffsets[i], y: cursor))
        }
        cursor += 16
        
        // Draw ruled line
        context.cgContext.move(to: CGPoint(x: margin, y: cursor))
        context.cgContext.addLine(to: CGPoint(x: pageSize.width - margin, y: cursor))
        context.cgContext.setStrokeColor(UIColor.black.cgColor)
        context.cgContext.setLineWidth(0.5)
        context.cgContext.strokePath()
        cursor += 4
        
        // Draw assignments rows
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
            
            let rowAttrs: [NSAttributedString.Key: Any] = [.font: font]
            
            NSAttributedString(string: laneStr, attributes: rowAttrs).draw(at: CGPoint(x: xOffsets[0], y: cursor))
            NSAttributedString(string: nameStr, attributes: rowAttrs).draw(at: CGPoint(x: xOffsets[1], y: cursor))
            NSAttributedString(string: teamStr, attributes: rowAttrs).draw(at: CGPoint(x: xOffsets[2], y: cursor))
            NSAttributedString(string: timeStr, attributes: rowAttrs).draw(at: CGPoint(x: xOffsets[3], y: cursor))
            
            cursor += 16
        }
        cursor += 10
    }
    
    /// Formats a time interval into a string, treating .infinity as "NT".
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
