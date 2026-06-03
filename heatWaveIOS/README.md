# heatWaveIOS Project

iOS companion application to the heatWave psych sheet processor.

- Native, offline-capable SwiftUI application.
- Converts USA Swimming psych sheet PDFs to formatted heat sheet PDFs entirely on-device.
- Minimum deployment target: iOS 16.

---

## Project Structure

```
heatWaveIOS/
├── EXTRACTION_SPIKE.md          # PDF column extraction strategy (read first)
├── heatWaveIOS/                 # Swift source files
│   ├── App.swift                # Main entry point
│   ├── ContentView.swift        # Root view and ProcessingState enumeration
│   ├── DocumentPicker.swift     # UIDocumentPickerViewController wrapper
│   ├── PDFExtractor.swift       # Phase 2: PDF text extraction (rect-based)
│   ├── RegexParser.swift        # Phase 3: text to data models
│   ├── SeedingEngine.swift      # Phase 4: seeding rules and heat assignment
│   └── PDFGenerator.swift       # Phase 4: UIGraphicsPDFRenderer output
└── heatWaveIOSTests/
    ├── PDFExtractorTests.swift
    ├── RegexParserTests.swift
    └── SeedingEngineTests.swift
```

---

## Reference Implementation

The Python source in the project root's `src/` directory is the reference implementation and source of truth for all business logic.

| Python File | Swift Counterpart |
|---|---|
| `src/parser/extractor.py` | `PDFExtractor.swift` + `RegexParser.swift` |
| `src/models/schemas.py` | Data models inside `RegexParser.swift` / `Models.swift` |
| `src/seeding/seeder.py` | `SeedingEngine.swift` |

---

## Implementation Phases

| Phase | Focus | Status |
|---|---|---|
| 1 | UI Shell and scaffolding | Complete |
| 2 | File I/O and PDF text extraction | Next |
| 3 | Regex parser (port from Python) | Pending |
| 4 | Seeding engine and PDF generation | Pending |
| 5 | Polish and Xcode migration | Pending |

---

## Xcode Setup (Phase 5)

When migrating to Xcode:
1. Create a new **iOS App** project in Xcode (SwiftUI lifecycle, minimum iOS 16).
2. Drag all files from `heatWaveIOS/heatWaveIOS/` into the Xcode source group.
3. Drag all files from `heatWaveIOS/heatWaveIOSTests/` into the test target.
4. No third-party dependencies are required — all frameworks used are Apple system frameworks.

---

## Key Constraints

- Use `PDFPage.string(for: CGRect)` for column-aware extraction (see EXTRACTION_SPIKE.md).
- Save output PDFs to `.documentDirectory` — do not use `.temporaryDirectory`.
- Surface scanned-PDF errors with the exact message: "This PDF appears to be image-based. Scanned PDFs are not yet supported."
- Every core Swift file must have a corresponding XCTest file.
