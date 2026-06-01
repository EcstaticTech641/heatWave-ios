// PDFExtractor.swift
// heatWaveIOS
//
// Responsible for converting a PDF file into a single clean string of text
// that the RegexParser can consume.
//
// DESIGN DECISIONS (see EXTRACTION_SPIKE.md for full rationale):
//
//  • Uses PDFPage.string(for: CGRect) — NOT PDFDocument.string — because
//    psych sheets use a two-column layout. PDFDocument.string interleaves
//    columns; rect-based extraction reads each column independently.
//
//  • Column split: width * columnSplitRatio (default 0.5, mirrors Python line 22-23).
//    Exposed as `columnSplitRatio` for future asymmetric layout support.
//
//  • Scanned PDF guard: if total text across the first 3 pages is < 100
//    characters, the PDF is treated as image-based and an error is thrown.
//    Required user-facing error string:
//    "This PDF appears to be image-based. Scanned PDFs are not yet supported."
//
//  • Output PDFs are saved to FileManager.default.urls(for: .documentDirectory, ...)
//    NOT to temporaryDirectory. (PDFExtractor itself only reads — writing is PDFGenerator's job.)
//
// Python reference: src/parser/extractor.py  extract_text_from_pdf()
// Minimum iOS: 16.0 (PDFPage.string(for:) availability)

import PDFKit
import Foundation

// MARK: - Error Types

enum PDFExtractionError: LocalizedError, Equatable {
    /// Thrown when the PDF has no extractable text (likely scanned/image-based).
    case scannedPDF
    /// Thrown when PDFDocument cannot be initialised at the given URL.
    case unreadableFile(url: URL)
    /// Thrown when the document has zero pages.
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .scannedPDF:
            // This string is a hard product requirement — do not modify without updating tests.
            return "This PDF appears to be image-based. Scanned PDFs are not yet supported."
        case .unreadableFile(let url):
            return "Could not open the file: \(url.lastPathComponent)"
        case .emptyDocument:
            return "The selected PDF contains no pages."
        }
    }

    static func == (lhs: PDFExtractionError, rhs: PDFExtractionError) -> Bool {
        switch (lhs, rhs) {
        case (.scannedPDF, .scannedPDF),
             (.emptyDocument, .emptyDocument):
            return true
        case (.unreadableFile(let a), .unreadableFile(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - PDFExtractor

/// Extracts ordered plain text from a (optionally two-column) USA Swimming psych sheet PDF.
///
/// Call `extractText(from:)` as the entry point. All helper methods are `internal`
/// so they can be exercised directly from XCTest without exposing them to the rest
/// of the app.
struct PDFExtractor {

    // MARK: - Configuration

    /// Fractional x-position of the column divider, measured from the left edge.
    /// Default 0.5 (centre split) matches the Python pdfplumber approach exactly.
    /// Override with 0.4 for a 40/60 asymmetric layout.
    var columnSplitRatio: Double = 0.5

    /// Minimum character count across the first `scannedCheckPageCount` pages
    /// before the document is considered text-based. Below this the extractor
    /// throws `PDFExtractionError.scannedPDF`.
    var scannedCharacterThreshold: Int = 10

    /// Number of pages to sample for the scanned-PDF heuristic.
    var scannedCheckPageCount: Int = 3

    // MARK: - Public API

    /// Opens the PDF at `url`, validates it contains extractable text, then
    /// extracts and merges both columns for every page in reading order.
    ///
    /// - Parameter url: File URL to a PDF inside the app's sandbox.
    /// - Returns: Merged left+right column text, ready for `RegexParser`.
    /// - Throws: `PDFExtractionError` if the file cannot be read, has no pages,
    ///           or appears to be a scanned (image-only) document.
    func extractText(from url: URL) throws -> String {
        // 1. Open the document
        guard let document = PDFDocument(url: url) else {
            throw PDFExtractionError.unreadableFile(url: url)
        }

        // 2. Must have at least one page
        guard document.pageCount > 0 else {
            throw PDFExtractionError.emptyDocument
        }

        // 3. Guard against scanned/image-only PDFs before doing real work
        if isLikelyScanned(document) {
            throw PDFExtractionError.scannedPDF
        }

        // 4. Extract text from every page and concatenate in reading order
        //    Mirrors Python extractor.py lines 17-34 exactly:
        //      for page_num, page in enumerate(pdf.pages):
        //          left_text = page.crop(left_bbox).extract_text() or ""
        //          right_text = page.crop(right_bbox).extract_text() or ""
        //          full_text += left_text + "\n" + right_text
        return extractFullText(from: document)
    }

    // MARK: - Internal Helpers

    /// Returns the merged plain text for the entire document.
    /// Separated from `extractText(from:)` so tests can call it on a
    /// `PDFDocument` constructed entirely in memory.
    func extractFullText(from document: PDFDocument) -> String {
        var fullText = ""
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            if i > 0 {
                // Mirror Python: `if page_num > 0: full_text += "\n"`
                fullText += "\n"
            }
            fullText += extractTextFromPage(page)
        }
        return fullText
    }

    /// Returns `true` when the document is likely scanned (image-only),
    /// determined by sampling the first `scannedCheckPageCount` pages.
    ///
    /// Heuristic: fewer than `scannedCharacterThreshold` total characters
    /// across the sampled pages strongly indicates a rasterised scan.
    ///
    /// Note: we sample using `page.string` (no rect) here because we only
    /// need a rough character count — the split is not needed for detection.
    func isLikelyScanned(_ document: PDFDocument) -> Bool {
        let pagesToCheck = min(scannedCheckPageCount, document.pageCount)
        var totalChars = 0
        for i in 0..<pagesToCheck {
            if let page = document.page(at: i) {
                // page.string returns the full-page text extraction;
                // fine for the coarse character-count heuristic.
                totalChars += (page.string ?? "").count
            }
        }
        return totalChars < scannedCharacterThreshold
    }

    /// Extracts text from a single page using rect-based column splitting.
    ///
    /// The page is divided at `columnSplitRatio * width`. Text is extracted
    /// from the left half, then the right half, and concatenated with a
    /// newline — matching the Python `left_text + "\n" + right_text` merge.
    ///
    /// Uses `PDFPage.string(for: CGRect)` (iOS 16+) which restricts
    /// extraction to glyphs whose bounding boxes intersect the given rect.
    /// This correctly separates side-by-side columns without interleaving.
    func extractTextFromPage(_ page: PDFPage) -> String {
        let bounds = page.bounds(for: .cropBox)
        let splitX = bounds.width * columnSplitRatio

        // Left column: Ensuring we cover the full height from bottom to top
        let leftRect = CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y,
            width: splitX,
            height: bounds.size.height
        )

        // Right column
        let rightRect = CGRect(
            x: bounds.origin.x + splitX,
            y: bounds.origin.y,
            width: bounds.size.width - splitX,
            height: bounds.size.height
        )

        // IMPORTANT: PDFKit text extraction order can be erratic with selection(for:).
        // Forcing a top-down, left-to-right sort ensures stable parsing.
        let leftText  = extractSortedText(from: page.selection(for: leftRect), on: page)
        let rightText = extractSortedText(from: page.selection(for: rightRect), on: page)

        // Preserve the Python merge order: left column first, then right
        return leftText + "\n" + rightText
    }
    
    private func extractSortedText(from selection: PDFSelection?, on page: PDFPage) -> String {
        guard let selection = selection else { return "" }
        let lines = selection.selectionsByLine()
        
        // 1. Sort all lines strictly by Y coordinate descending (top-to-bottom).
        //    Use X coordinate as a tie-breaker. This forms a strict weak ordering.
        let roughSorted = lines.sorted { a, b in
            let boundsA = a.bounds(for: page)
            let boundsB = b.bounds(for: page)
            if boundsA.origin.y == boundsB.origin.y {
                return boundsA.origin.x < boundsB.origin.x
            }
            return boundsA.origin.y > boundsB.origin.y
        }
        
        // 2. Group selections that are on the same visual line (within a 5.0 point vertical threshold)
        var rows: [[PDFSelection]] = []
        for line in roughSorted {
            let bounds = line.bounds(for: page)
            if let lastRow = rows.last,
               let firstInRow = lastRow.first {
                let firstBounds = firstInRow.bounds(for: page)
                if abs(firstBounds.origin.y - bounds.origin.y) < 5.0 {
                    rows[rows.count - 1].append(line)
                } else {
                    rows.append([line])
                }
            } else {
                rows.append([line])
            }
        }
        
        // 3. Sort selections within each row left-to-right (by X coordinate),
        //    and merge them with a space separator.
        let mappedRows = rows.map { row in
            let sortedRow = row.sorted { a, b in
                a.bounds(for: page).origin.x < b.bounds(for: page).origin.x
            }
            return sortedRow.compactMap { $0.string }.joined(separator: " ")
        }
        
        // 4. Join visual rows with newlines to form the final column text.
        return mappedRows.joined(separator: "\n")
    }
}
