# Technical Implementation Summary: iOS-Centric Architecture

This document outlines the technical architecture of the `heatWave-ios` application. It highlights the mapping between the Python reference implementation and the native SwiftUI Swift modules, detailing the algorithms and rules governing extraction, parsing, seeding, and PDF generation.

---

## Core System Architecture

The application is structured into four distinct layers. These layers are implemented in Python for reference/testing and in Swift for native, offline execution on iOS devices:

```
[PDF Input] 
    │
    ▼
1. Extraction Layer ──► Splits two-column pages into independent reading zones
    │
    ▼
2. Parsing Layer    ──► Extracts events and entries via regular expressions
    │
    ▼
3. Seeding Layer    ──► Assigns heats and center-out lanes (USA Swimming rules)
    │
    ▼
4. Generation Layer ──► Renders the printable heat sheet PDF
```

---

## Component Mappings

| Component | Python Reference Class/Module | iOS Native Swift Class | Implementation Details |
|---|---|---|---|
| **Data Models** | `src/models/schemas.py` | `Models.swift` | Defines structures for Swimmer, Entry, RelayEntry, Event, Assignment, and HeatSheet. |
| **PDF Extraction** | `src/parser/extractor.py` (`extract_text_from_pdf`) | `PDFExtractor.swift` | Crops page widths to split columns and avoid interleaved text. |
| **Data Parsing** | `src/parser/extractor.py` (`parse_events_from_text`) | `RegexParser.swift` | Iterates over lines to match event headers and entry patterns. |
| **Seeding Engine** | `src/seeding/seeder.py` | `SeedingEngine.swift` | Orders entries, sets heat counts, and maps lanes. |
| **PDF Renderer** | `src/core/pdf_generator.py` | `PDFGenerator.swift` | Employs Core Graphics / UIKit rendering on iOS. |

---

## Technical Specifications by Phase

### 1. PDF Text Extraction
- **Problem:** Standard PDF text readers extract characters line-by-line across the entire page, resulting in interleaved text when reading two-column psych sheets.
- **Reference Solution:** Uses `pdfplumber` to crop the page into left and right bounding boxes (`width / 2`), extract text from each independently, and merge them.
- **iOS Implementation:** Employs Apple's `PDFKit` framework. Using `PDFPage.string(for: CGRect)`, the extractor defines two bounding boxes:
  - Left Column Rect: `[x: 0, y: 0, width: page_width / 2, height: page_height]`
  - Right Column Rect: `[x: page_width / 2, y: 0, width: page_width / 2, height: page_height]`
  The text from both rectangles is extracted and merged. This is supported in iOS 16+.

### 2. Regular Expression Parsing
- **Patterns:** Regex rules detect event boundaries (such as `#1 Girls 10 & Under 50 Yard Freestyle`) and swimmer lines (e.g., `1 Smith, Jane 10 BSS-FL 28.50`).
- **Data Schemas:** Validates that ages are numeric, seed times are in standard swim formats (e.g., `MM:SS.XX`, `SS.XX`, or `NT` for No Time), and relay teams are grouped.
- **Robustness:** Handles names with multiple spaces, varied team abbreviations, and spacing tolerances across different meet management software exports.

### 3. USA Swimming Seeding Rules
- **Seeding Order:** Entries are sorted from fastest to slowest.
- **Lane Placement Pattern:** Centers the fastest swimmers. For standard 8-lane pools, the assignment order is:
  - Lane 4: 1st seed in heat
  - Lane 5: 2nd seed in heat
  - Lane 3: 3rd seed in heat
  - Lane 6: 4th seed in heat
  - Lane 2: 5th seed in heat
  - Lane 7: 6th seed in heat
  - Lane 1: 7th seed in heat
  - Lane 8: 8th seed in heat
- **Heat Allocation:** The total number of heats is computed by dividing the number of entries by the pool lane count. The seeding engine balances the remaining entries to prevent single-swimmer heats.

### 4. PDF Heat Sheet Generation
- **Reference PDF Output:** Built using `ReportLab`, producing structured tabular PDFs.
- **iOS PDF Output:** Uses `UIGraphicsPDFRenderer` to render vectors and text onto a print-ready canvas. Font selection utilizes native iOS system fonts (Helvetica/San Francisco) to guarantee consistent rendering.

---

## Performance and Constraints

- **On-Device Execution:** No external APIs or web backend servers are involved. All processing occurs locally on the iOS device.
- **File I/O:** Generated PDFs are stored within the app's secure `.documentDirectory` to comply with iOS security policies.
- **Scanned PDF Guard:** The extraction pipeline checks the character count of the first three pages of any uploaded document. If fewer than 100 characters are found, the process aborts with the following error:
  `"This PDF appears to be image-based. Scanned PDFs are not yet supported."`
