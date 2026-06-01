# heatWaveIOS Project

iOS companion to the heatWave psych sheet processor.

- **100% native, offline-capable SwiftUI app**
- Converts USA Swimming psych sheet PDFs → formatted heat sheet PDFs, entirely on-device
- Minimum deployment target: **iOS 16**
- No backend required for MVP

---

## Project Structure

```
heatWaveIOS/
├── EXTRACTION_SPIKE.md          ← PDF column extraction strategy (read first)
├── heatWaveIOS/                 ← Swift source files
│   ├── App.swift                ← @main entry point
│   ├── ContentView.swift        ← Root view + ProcessingState enum
│   ├── DocumentPicker.swift     ← UIDocumentPickerViewController wrapper
│   ├── PDFExtractor.swift       ← Phase 2: PDF text extraction (rect-based)
│   ├── RegexParser.swift        ← Phase 3: text → data models
│   ├── SeedingEngine.swift      ← Phase 4: seeding rules + heat assignment
│   └── PDFGenerator.swift       ← Phase 4: UIGraphicsPDFRenderer output
└── heatWaveIOSTests/
    ├── PDFExtractorTests.swift
    ├── RegexParserTests.swift
    └── SeedingEngineTests.swift
```

## Reference Implementation

The Python source in `../src/` is the **source of truth** for business logic.

| Python file | Swift counterpart |
|---|---|
| `src/parser/extractor.py` | `PDFExtractor.swift` + `RegexParser.swift` |
| `src/models/schemas.py` | Data models inside `RegexParser.swift` |
| `src/seeding/seeder.py` | `SeedingEngine.swift` |

## Implementation Phases

| Phase | Focus | Status |
|---|---|---|
| 1 | UI Shell + scaffolding | ✅ Complete |
| 2 | File I/O + PDF text extraction | 🔲 Next |
| 3 | Regex parser (port from Python) | 🔲 Pending |
| 4 | Seeding engine + PDF generation | 🔲 Pending |
| 5 | Polish + Xcode migration | 🔲 Pending |

## Xcode Setup (Phase 5)

When migrating to Xcode:
1. Create a new **iOS App** project in Xcode (SwiftUI lifecycle, minimum iOS 16)
2. Drag all files from `heatWaveIOS/` into the Xcode source group
3. Drag all files from `heatWaveIOSTests/` into the test target
4. No third-party dependencies required — all frameworks are Apple system frameworks

## Key Constraints

- Use `PDFPage.string(for: CGRect)` for column-aware extraction (see EXTRACTION_SPIKE.md)
- Save output PDFs to `.documentDirectory` — **never** `.temporaryDirectory`
- Surface scanned-PDF error with the exact message: "This PDF appears to be image-based. Scanned PDFs are not yet supported."
- Every core Swift file must have a corresponding XCTest file
