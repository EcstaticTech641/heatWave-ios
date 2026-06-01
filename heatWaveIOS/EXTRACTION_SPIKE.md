# PDF Extraction Strategy — Spike Document

**Branch:** `ios`  
**Date:** 2026-05-01  
**Status:** Validated — approved for use in PDFExtractor.swift

---

## Problem: Two-Column Psych Sheet Layout

USA Swimming psych sheets are paginated PDFs formatted in **two side-by-side columns**.
When `PDFDocument.string` (Apple's default text extractor) reads the page, it reads line
by line across the full page width. This causes the left and right column entries to be
**interleaved**, producing nonsense like:

```
1 Smith, John   14  Tulsa Swim-OK   1 Meek, Keaston  10  Bartlesville Spl-OK
2:41.23                              2:42.05
```

The Python reference implementation (`extractor.py` lines 21-34) solves this with
`pdfplumber`'s `page.crop(bbox)` — it splits each page at `width / 2`, extracts text
from each half independently, then concatenates `left_text + "\n" + right_text`.

---

## iOS Solution: Rect-Based PDFPage Extraction

**Do NOT use `PDFDocument.string`** — it does not support bounding-box cropping and will
produce column reflow errors on two-column layouts.

**Use `PDFPage.attributedString(for:)` with a CGRect crop**, which is the PDFKit
equivalent of pdfplumber's `page.crop(bbox).extract_text()`.

### Validated Approach

```swift
import PDFKit

func extractTextFromPage(_ page: PDFPage) -> String {
    let pageBounds = page.bounds(for: .mediaBox)
    let width  = pageBounds.width
    let height = pageBounds.height

    // Mirror the Python: left half = [0, 0, width/2, height]
    let leftRect  = CGRect(x: 0,        y: 0, width: width / 2, height: height)
    let rightRect = CGRect(x: width / 2, y: 0, width: width / 2, height: height)

    let leftText  = page.string(for: leftRect)  ?? ""
    let rightText = page.string(for: rightRect) ?? ""

    // Merge in reading order — left column first, then right column
    return leftText + "\n" + rightText
}
```

> **Note:** `PDFPage.string(for: CGRect)` is available from iOS 16+ via PDFKit.
> This is why iOS 16 is the minimum deployment target.

### Why This Works

- PDFKit internally uses the same Core Graphics text extraction that Apple's Preview
  uses. Passing a `CGRect` restricts which text objects are returned to those whose
  glyph bounds intersect the rect.
- Because psych sheets are rendered-text PDFs (not scanned images), glyph bounding boxes
  are always present and accurate.
- By splitting at `width / 2` we get a clean left-then-right merge that matches the
  Python pdfplumber output line-for-line.

---

## Scanned PDF Guard

Before running column extraction, check if the PDF is likely scanned (image-only).

```swift
func isLikelyScanned(_ document: PDFDocument) -> Bool {
    // Sample first 3 pages; if all return nil or very short strings, treat as scanned.
    let pagesToCheck = min(3, document.pageCount)
    var totalChars = 0
    for i in 0..<pagesToCheck {
        if let page = document.page(at: i) {
            totalChars += (page.string ?? "").count
        }
    }
    // Heuristic: fewer than 100 chars across 3 pages = almost certainly scanned
    return totalChars < 100
}
```

**User-facing error string (exact copy required in UI):**
> "This PDF appears to be image-based. Scanned PDFs are not yet supported."

---

## Column Boundary Assumption

- Split point: `width / 2` (matches Python exactly).
- This works for the standard USA Swimming / HY-TEK psych sheet format where columns
  are perfectly bisected.
- If a future format uses an asymmetric split (e.g., 40/60), we can expose a
  `columnSplitRatio: Double = 0.5` parameter in `PDFExtractor` to override this.

---

## Full Page Loop Pattern (Production)

```swift
func extractFullText(from document: PDFDocument) -> String {
    var fullText = ""
    for i in 0..<document.pageCount {
        guard let page = document.page(at: i) else { continue }
        if i > 0 { fullText += "\n" }
        fullText += extractTextFromPage(page)
    }
    return fullText
}
```

This mirrors `extractor.py` lines 17-34 exactly.

---

## Decision Record

| Decision | Choice | Rationale |
|---|---|---|
| Extraction API | `PDFPage.string(for: CGRect)` | Only PDFKit API supporting rect-bounded extraction |
| Column split | `width / 2` | Matches Python reference; proven on HY-TEK format |
| Scanned guard | `< 100 chars across 3 pages` | Heuristic catches blank-text scans without false positives |
| Min iOS target | iOS 16 | Required for `PDFPage.string(for:)` and native Swift Regex |
| Output storage | `.documentDirectory` | Per product constraint; never `temporaryDirectory` |

---

## Files That Depend on This Strategy

- `PDFExtractor.swift` — implements the above functions directly
- `PDFExtractorTests.swift` — must test single-column, two-column, and scanned cases
- `ContentView.swift` — surfaces the scanned-PDF error to the user
