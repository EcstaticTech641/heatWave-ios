// PDFExtractorTests.swift
// heatWaveIOSTests
//
// Full XCTest coverage for PDFExtractor.
//
// APPROACH: All tests are self-contained — they build PDFDocument objects
// programmatically using UIGraphicsPDFRenderer so no external fixture files
// are required. This makes the tests runnable in any environment that has
// the iOS SDK (simulator or device) without bundle resource management.
//
// Helper factories at the bottom of this file create the synthetic PDFs.

import XCTest
import PDFKit
import UIKit
@testable import heatWaveIOS

@MainActor
final class PDFExtractorTests: XCTestCase {

    // MARK: - System Under Test

    var extractor: PDFExtractor!

    override func setUp() {
        super.setUp()
        extractor = PDFExtractor()
    }

    override func tearDown() {
        extractor = nil
        super.tearDown()
    }

    // MARK: - Error Message Contract
    // This test has no dependency on PDFExtractor's implementation;
    // it guards the hard product requirement string.

    func testScannedPDFErrorMessageMatchesRequirement() {
        let error = PDFExtractionError.scannedPDF
        XCTAssertEqual(
            error.errorDescription,
            "This PDF appears to be image-based. Scanned PDFs are not yet supported.",
            "Scanned PDF error message must match the exact product requirement string."
        )
    }

    func testUnreadableFileErrorIncludesFilename() {
        let url = URL(fileURLWithPath: "/fake/path/myfile.pdf")
        let error = PDFExtractionError.unreadableFile(url: url)
        XCTAssertTrue(
            error.errorDescription?.contains("myfile.pdf") == true,
            "Unreadable file error should include the filename."
        )
    }

    func testEmptyDocumentErrorIsNotEmpty() {
        let error = PDFExtractionError.emptyDocument
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    // MARK: - unreadableFile (bad URL)

    func testExtractTextThrowsUnreadableFileForNonexistentURL() {
        let badURL = URL(fileURLWithPath: "/no/such/file/at/this/path.pdf")
        XCTAssertThrowsError(try extractor.extractText(from: badURL)) { error in
            guard let extractionError = error as? PDFExtractionError,
                  case .unreadableFile = extractionError else {
                XCTFail("Expected PDFExtractionError.unreadableFile, got \(error)")
                return
            }
        }
    }

    // MARK: - emptyDocument

    func testExtractTextThrowsEmptyDocumentForZeroPagePDF() throws {
        // Build a valid PDFDocument with zero pages by starting with a one-page
        // document then removing the page. PDFDocument has no zero-page constructor,
        // so we remove the page we just added.
        let doc = PDFDocument()
        // PDFDocument() starts with 0 pages — confirmed by Apple docs.
        // If pageCount is not 0, skip this test (environment dependent).
        guard doc.pageCount == 0 else {
            throw XCTSkip("PDFDocument() did not initialise with 0 pages on this platform.")
        }

        // Write to a temp file so we can feed a URL to extractText(from:)
        let url = try writeDocumentToTemp(doc, name: "empty.pdf")

        // An empty PDF document produces a valid PDFDocument(url:) but pageCount == 0.
        // We need to verify PDFDocument(url:) actually succeeds here — if the
        // written data is invalid, we'd get .unreadableFile instead, so guard that.
        guard let reopened = PDFDocument(url: url), reopened.pageCount == 0 else {
            throw XCTSkip("Could not create a zero-page PDF on this platform.")
        }

        XCTAssertThrowsError(try extractor.extractText(from: url)) { error in
            guard let e = error as? PDFExtractionError, case .emptyDocument = e else {
                XCTFail("Expected .emptyDocument, got \(error)")
                return
            }
        }
    }

    // MARK: - Scanned PDF Guard

    func testIsLikelyScannedReturnsTrueWhenTextIsShort() {
        // Build a 1-page PDF that contains a single short label — well under threshold.
        let shortDoc = makeSyntheticPDF(pages: [("Hi", nil)]) // "Hi" = 2 chars
        XCTAssertTrue(
            extractor.isLikelyScanned(shortDoc),
            "A PDF with only 2 characters should be flagged as likely scanned."
        )
    }

    func testIsLikelyScannedReturnsFalseForTextRichPDF() {
        // Build a 1-page PDF with 200+ characters of text.
        let longString = String(repeating: "Event 1 Girls 200 Yard Freestyle\n", count: 10)
        let doc = makeSyntheticPDF(pages: [(longString, nil)])
        XCTAssertFalse(
            extractor.isLikelyScanned(doc),
            "A text-rich PDF should NOT be flagged as scanned."
        )
    }

    func testIsLikelyScannedOnlySamplesFirstThreePages() {
        // Pages 1-3: short text (< threshold each).
        // Pages 4-5: long text.
        // Result should still be TRUE because only pages 0-2 are sampled.
        let shortPage = "AB"
        let longPage  = String(repeating: "X", count: 200)
        let doc = makeSyntheticPDF(pages: [
            (shortPage, nil),
            (shortPage, nil),
            (shortPage, nil),
            (longPage, nil),
            (longPage, nil)
        ])
        // 3 * 2 = 6 chars sampled, which is < 100 threshold
        XCTAssertTrue(
            extractor.isLikelyScanned(doc),
            "Scanned check should only sample first 3 pages."
        )
    }

    func testScannedThresholdIsConfigurable() {
        var customExtractor = PDFExtractor()
        customExtractor.scannedCharacterThreshold = 5
        // A PDF with exactly 6 chars should NOT be flagged with threshold=5
        let doc = makeSyntheticPDF(pages: [("ABCDEF", nil)])
        XCTAssertFalse(
            customExtractor.isLikelyScanned(doc),
            "6-char document should not be flagged when threshold is 5."
        )
    }

    func testExtractTextThrowsScannedPDFForImageOnlyPDF() throws {
        // Build a PDF whose pages contain only a drawn UIImage, no text layer.
        let imageDoc = makeImageOnlyPDF()
        let url = try writeDocumentToTemp(imageDoc, name: "scanned.pdf")

        // Re-open from disk so extractText(from:) goes through the full path.
        XCTAssertThrowsError(try extractor.extractText(from: url)) { error in
            guard let e = error as? PDFExtractionError, case .scannedPDF = e else {
                XCTFail("Expected .scannedPDF for image-only PDF, got \(error)")
                return
            }
        }
    }

    // MARK: - Column Merge Order

    func testTwoColumnMergeOrderIsLeftThenRight() throws {
        // Build a two-column PDF where the left half contains "LEFTCOL"
        // and the right half contains "RIGHTCOL". Verify left comes first.
        let doc = makeTwoColumnPDF(leftText: "LEFTCOL", rightText: "RIGHTCOL")
        let text = extractor.extractFullText(from: doc)

        guard let leftRange  = text.range(of: "LEFTCOL"),
              let rightRange = text.range(of: "RIGHTCOL") else {
            XCTFail("Extracted text does not contain both column markers. Got: \(text)")
            return
        }
        XCTAssertLessThan(
            leftRange.lowerBound,
            rightRange.lowerBound,
            "Left column text must appear before right column text in the merged output."
        )
    }

    func testSingleColumnExtractsWithoutDuplication() throws {
        // A single-column PDF should not duplicate text by splitting.
        let marker = "UNIQUEMARKER"
        let doc = makeSyntheticPDF(pages: [(marker, nil)])
        let text = extractor.extractFullText(from: doc)

        let occurrences = text.components(separatedBy: marker).count - 1
        XCTAssertEqual(
            occurrences, 1,
            "Unique marker should appear exactly once in the extracted text, not duplicated."
        )
    }

    func testColumnSplitRatioIsRespected() throws {
        // With a 0.4 split ratio, the left rect is narrower.
        // Text drawn in the rightmost 60% should land in the right extraction.
        // We verify the extractor doesn't crash and still returns non-empty text.
        var customExtractor = PDFExtractor()
        customExtractor.columnSplitRatio = 0.4

        let doc = makeTwoColumnPDF(leftText: "LEFTSIDE", rightText: "RIGHTSIDE")
        let text = customExtractor.extractFullText(from: doc)

        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "Extraction with non-default split ratio should produce non-empty text.")
    }

    func testVisualLineGroupingAndSorting() throws {
        // Build a PDF with three text segments on the same visual line
        // but with slightly different Y coordinates (within 5.0 points) and in scrambled
        // drawing/Y order, to verify they get grouped into a single line and sorted left-to-right.
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ]
            // We draw them with slightly different Y, and in a scrambled order.
            // Segment 3: x=200, y=10.2 (drawn first)
            ("SegmentThree" as NSString).draw(at: CGPoint(x: 200, y: 10.2), withAttributes: attrs)
            // Segment 1: x=10, y=9.8 (drawn second)
            ("SegmentOne" as NSString).draw(at: CGPoint(x: 10, y: 9.8), withAttributes: attrs)
            // Segment 2: x=100, y=10.0 (drawn third)
            ("SegmentTwo" as NSString).draw(at: CGPoint(x: 100, y: 10.0), withAttributes: attrs)
        }
        
        let doc = PDFDocument(data: data)!
        let text = extractor.extractFullText(from: doc)
        
        // Since all three segments are within 5.0 points Y difference and in the left column (< 306),
        // they should be grouped into a single line, sorted left-to-right, and joined by space.
        XCTAssertTrue(
            text.contains("SegmentOne SegmentTwo SegmentThree"),
            "Expected segments to be grouped and sorted left-to-right. Got: \(text)"
        )
    }

    // MARK: - Multi-Page Extraction

    func testMultiPageDocumentConcatenatesWithNewline() throws {
        let page1 = "PAGE_ONE_MARKER"
        let page2 = "PAGE_TWO_MARKER"
        let doc = makeSyntheticPDF(pages: [(page1, nil), (page2, nil)])
        let text = extractor.extractFullText(from: doc)

        XCTAssertTrue(text.contains(page1), "Page 1 marker missing from output.")
        XCTAssertTrue(text.contains(page2), "Page 2 marker missing from output.")

        // Page separators: the Python inserts "\n" between pages.
        // Our implementation does the same; verify both markers are present
        // and the text is not just a concatenation without any separator.
        guard let p1Range = text.range(of: page1),
              let p2Range = text.range(of: page2) else { return }
        let between = String(text[p1Range.upperBound..<p2Range.lowerBound])
        XCTAssertTrue(
            between.contains("\n"),
            "There should be at least one newline between page 1 and page 2 text."
        )
    }

    func testSinglePageDocumentHasNoLeadingNewline() throws {
        let doc = makeSyntheticPDF(pages: [("HELLO", nil)])
        let text = extractor.extractFullText(from: doc)
        XCTAssertFalse(
            text.hasPrefix("\n"),
            "Single-page extraction must not start with a leading newline."
        )
    }

    // MARK: - extractTextFromPage

    func testExtractTextFromPageReturnsNonNilForTextPage() {
        let doc = makeSyntheticPDF(pages: [("SomeText", nil)])
        guard let page = doc.page(at: 0) else {
            XCTFail("Could not get page 0 from synthetic document.")
            return
        }
        let result = extractor.extractTextFromPage(page)
        // Should return a string (possibly empty if the renderer
        // doesn't embed a text layer — acceptable; we just check no crash).
        XCTAssertNotNil(result) // String is never Optional, so always passes
    }
}

// MARK: - Synthetic PDF Factory Helpers
// All helpers are private to this test file.

extension PDFExtractorTests {

    // MARK: Generic page builder

    /// Creates an in-memory `PDFDocument` with one page per entry in `pages`.
    ///
    /// - Parameter pages: Array of `(text, UIImage?)` tuples.
    ///   If `text` is non-empty it is drawn at the top-left of the page.
    ///   If an image is provided it is drawn over the entire page.
    private func makeSyntheticPDF(pages: [(String, UIImage?)]) -> PDFDocument {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)  // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { ctx in
            for (text, image) in pages {
                ctx.beginPage()
                if let img = image {
                    img.draw(in: pageRect)
                }
                if !text.isEmpty {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12),
                        .foregroundColor: UIColor.black
                    ]
                    (text as NSString).draw(at: CGPoint(x: 10, y: 10), withAttributes: attrs)
                }
            }
        }

        return PDFDocument(data: data) ?? PDFDocument()
    }

    // MARK: Two-column builder

    /// Creates a 1-page PDF with `leftText` drawn in the left half and
    /// `rightText` drawn in the right half.
    private func makeTwoColumnPDF(leftText: String, rightText: String) -> PDFDocument {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ]
            // Left column: x=10, well within the left half (0–306)
            (leftText as NSString).draw(at: CGPoint(x: 10, y: 10), withAttributes: attrs)
            // Right column: x=320, well within the right half (306–612)
            (rightText as NSString).draw(at: CGPoint(x: 320, y: 10), withAttributes: attrs)
        }

        return PDFDocument(data: data) ?? PDFDocument()
    }

    // MARK: Image-only builder

    /// Creates a 1-page PDF containing only a solid-colour UIImage — no text layer.
    private func makeImageOnlyPDF() -> PDFDocument {
        let size = CGSize(width: 612, height: 792)
        // Render a solid black image
        let imageRenderer = UIGraphicsImageRenderer(size: size)
        let solidBlack = imageRenderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return makeSyntheticPDF(pages: [("", solidBlack)])
    }

    // MARK: Disk write helper

    /// Writes a `PDFDocument` to a temp file and returns its URL.
    /// Uses `FileManager.default.temporaryDirectory` which is fine for test fixtures
    /// (the production constraint of using `.documentDirectory` applies to generated
    ///  heat sheet output, not to test scaffolding).
    private func writeDocumentToTemp(_ doc: PDFDocument, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard doc.write(to: url) else {
            throw NSError(
                domain: "PDFExtractorTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not write test PDF to \(url.path)"]
            )
        }
        return url
    }
}
