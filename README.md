# heatWave-ios (v0.1.0-alpha.1)

`heatWave-ios` is a 100% native, offline-capable SwiftUI application for iOS and iPadOS designed to transform USA Swimming psych sheets (entry lists) into professionally formatted, seeded heat sheets (meet programs). 

All text extraction, entry parsing, center-out heat seeding, timeline estimation, and PDF rendering are performed **entirely on-device**.

---

## 🔒 Core Invariants & Privacy Disclaimers

* **100% Offline / Zero Telemetry:** `heatWave-ios` includes zero network SDKs, zero telemetry framework calls (`URLSession`, `Alamofire`, `Firebase`), and zero remote analytics. All parsing and PDF rendering take place in sandbox memory.
* **Zero-PII / Local Storage Only:** Swimmer names, ages, team codes, and imported PDF documents never leave the local device sandbox. Generated PDFs are written directly to `.documentDirectory` for user sharing.
* **Honest Scanned-PDF Handling:** `heatWave-ios` requires text-based vector PDFs (standard output from Hy-Tek, Meet Maestro, TeamUnify, etc.). Image-only or rasterized scanned PDFs trigger an immediate user error message:
  > *"This PDF appears to be image-based. Scanned PDFs are not yet supported."*

---

## ✨ Key Capabilities

* **On-Device Two-Column PDF Extraction (`PDFExtractor.swift`):** Resolves column interleaving in USA Swimming psych sheets using `PDFPage.string(for: CGRect)` with visual row Y/X sorting heuristics.
* **USA Swimming Seeding Engine (`SeedingEngine.swift`):** Applies standard preliminary center-out lane assignment (e.g. 8-lane pattern: `4 → 5 → 3 → 6 → 2 → 7 → 1 → 8`), placing `NT` (No Time) entries in early heats.
* **Timeline Estimator:** Computes event start times and total meet duration by calculating $\sum(\text{slowest timed seed per heat}) + (\text{numHeats} \times \text{turnoverTime})$. Configurable heat turnover gap (1–15 minutes).
* **Find Swimmer Lookup (`SwimmerSearchView.swift`):** Allows coaches to instantly search swimmers by name to view their personal schedule (event, heat, lane, seed time, estimated start time).
* **iPad Magic Keyboard Shortcuts:** Full hardware keyboard navigation (`Cmd+O`, `Cmd+Return`, `Cmd+S`, `Cmd+F`, `Cmd+R`, `Escape`, `Return`).
* **Native PDF Renderer (`PDFGenerator.swift`):** Uses `UIGraphicsPDFRenderer` to produce crisp, print-ready US Letter heat sheet PDFs with event header timelines and grand total timeline summaries.

---

## ⌨️ Hardware Keyboard Shortcuts

| Shortcut | Context | Action |
| :--- | :--- | :--- |
| `Cmd + O` | Main View | Import Psych Sheet PDF |
| `Cmd + Return` | Configure Screen | Generate Seeded Heat Sheet |
| `Cmd + S` | Success Screen | Share / Print Heat Sheet PDF |
| `Cmd + F` | Success Screen | Open Find Swimmer Search Sheet |
| `Cmd + R` | Any Screen | Reset / Start Over |
| `Escape` | Sheets | Dismiss active sheet |
| `Return` | Find Swimmer | Jump directly to first matching swimmer |

---

## 📁 Repository Structure

```
heatWave-ios/
└── heatWaveIOS/
    ├── EXTRACTION_SPIKE.md          # PDF column extraction technical specification
    ├── README.md                    # iOS target documentation
    ├── README_XCODE.md              # Xcode setup guide
    ├── heatWaveIOS/                 # Primary Swift App Source Target (10 files)
    │   ├── App.swift                # @main SwiftUI App entry point
    │   ├── ContentView.swift        # Primary state machine, main UI & keyboard shortcuts
    │   ├── DocumentPicker.swift     # UIDocumentPickerViewController wrapper
    │   ├── Models.swift             # Codable data structures (Event, Entry, HeatSheet, Swimmer)
    │   ├── PDFExtractor.swift       # Bounding-box text extraction engine (iOS 16+)
    │   ├── PDFGenerator.swift       # UIGraphicsPDFRenderer heat sheet PDF generator
    │   ├── RegexParser.swift        # Plain-text line classifier & entry parser
    │   ├── SeedingEngine.swift      # USA Swimming center-out seeding & timeline estimator
    │   ├── ShareSheet.swift         # UIActivityViewController wrapper
    │   └── SwimmerSearchView.swift  # Find Swimmer lookup sheet and detail views
    └── heatWaveIOSTests/            # Complete XCTest Suite (5 files)
        ├── PDFExtractorTests.swift  # Synthetic PDF extraction tests
        ├── PDFGeneratorTests.swift  # PDF generation & layout tests
        ├── RegexParserTests.swift   # Text parsing & regex token tests
        ├── SeedingEngineTests.swift # USA Swimming seeding & timeline tests
        └── SwimmerSearchViewTests.swift # Swimmer search & indexing tests
```

---

## 🛠️ Build & Development Setup

1. **Prerequisites:** macOS with Xcode 14.0 or newer. Minimum deployment target: **iOS 16.0**.
2. **Create Xcode Project:**
   * Open Xcode and create a new **iOS App** project named `heatWaveIOS` (Interface: `SwiftUI`, Language: `Swift`).
   * Set Minimum Deployment Target to **iOS 16.0** under Target Settings.
3. **Import Source Files:**
   * Drag all `.swift` files from `heatWaveIOS/heatWaveIOS/` into the `heatWaveIOS` main source group.
   * Drag all `.swift` files from `heatWaveIOS/heatWaveIOSTests/` into the test target group.
4. **Run Unit Tests:** Press `Cmd + U` to run the 100% offline XCTest suite.
5. **Launch App:** Press `Cmd + R` to run in Simulator or on a physical iOS device.

---

## 🏷️ Version Metadata

* **SemVer Baseline:** `v0.1.0-alpha.1`
* **Marketing Version (`CFBundleShortVersionString`):** `0.1.0`
* **Build Number (`CFBundleVersion`):** `1`
* **Minimum Deployment Target:** `iOS 16.0`
