# heatWave

heatWave is an application designed to transform USA Swimming psych sheets (entry lists) into professionally formatted, seeded heat sheets (meet programs). This repository is dedicated to the iOS version of the application, featuring a native, offline-capable SwiftUI implementation that performs all parsing and seeding calculations entirely on-device.

The Python implementation in the `src/` directory serves as the reference implementation and source of truth for the business logic.

---

## Project Structure

```
heatWave-ios/
├── heatWaveIOS/                 # Native iOS SwiftUI application source
│   ├── heatWaveIOS/             # Swift source files
│   │   ├── App.swift            # Main entry point
│   │   ├── ContentView.swift    # Primary UI, ProcessingState, keyboard shortcuts
│   │   ├── DocumentPicker.swift # Native Document Picker wrapper
│   │   ├── Models.swift         # Data structures: Event, HeatSheet, Swimmer, etc.
│   │   ├── PDFExtractor.swift   # Bounding-box text extraction (iOS 16+)
│   │   ├── RegexParser.swift    # Text-to-data parsing engine
│   │   ├── SeedingEngine.swift  # USA Swimming seeding rules + timeline estimation
│   │   ├── PDFGenerator.swift   # Native PDF renderer with timeline blocks
│   │   └── SwimmerSearchView.swift # Find Swimmer sheet + per-swimmer schedule
│   └── heatWaveIOSTests/        # XCTest suite for Swift implementation
│       ├── PDFExtractorTests.swift
│       ├── PDFGeneratorTests.swift
│       ├── RegexParserTests.swift
│       ├── SeedingEngineTests.swift
│       └── SwimmerSearchViewTests.swift
├── src/                         # Python Reference Implementation
│   ├── core/
│   │   └── pdf_generator.py     # PDF generation reference logic
│   ├── models/
│   │   └── schemas.py           # Dataclass schemas reference
│   ├── parser/
│   │   └── extractor.py         # Text extraction and regex parsing reference
│   ├── seeding/
│   │   └── seeder.py            # Seeding engine reference
│   ├── ui/
│   │   └── streamlit_app.py     # Local Streamlit UI for logic validation
│   └── utils/
│       └── cleanup.py           # Clean up utilities for local tests
├── tests/                       # Python reference test suite
├── docs/                        # Project documentation
└── requirements.txt             # Python reference environment dependencies
```

---

## Reference Implementation and Business Logic

The Python code in `src/` serves as the official reference implementation. The native Swift modules in `heatWaveIOS/` mirror this reference logic:

| Python Reference Module | Swift iOS Implementation | Purpose |
|-------------------------|--------------------------|---------|
| `src/parser/extractor.py` | `PDFExtractor.swift` + `RegexParser.swift` | Column-aware text extraction and entry parsing. |
| `src/models/schemas.py` | `Models.swift` | Data schemas for Event, Entry, HeatSheet, Swimmer. |
| `src/seeding/seeder.py` | `SeedingEngine.swift` | USA Swimming seeding rules + timeline estimation. |
| `src/core/pdf_generator.py` | `PDFGenerator.swift` | Print-ready heat sheet PDF with timeline blocks. |

---

## Features (Current)

### Core Pipeline
Import a psych sheet PDF → configure lanes and heat gap → generate a fully seeded heat sheet PDF.

### Timeline Estimator
For each event, the seeding engine sums the slowest timed seed in every heat and adds a configurable per-heat turnover gap (default **2 min**) to account for check-in, clearing the deck, and the start signal.

- **PDF:** Each event header prints `Est. Start` (running clock) and `Est. Event Duration`.
- **App:** The success screen shows a grand-total **Estimated Meet Duration** card.
- **Config:** The heat gap is adjustable on the Configure Meet screen (1–15 min stepper).

### Find Swimmer
After generating a heat sheet, tap **Find Swimmer** (or press **Cmd+F**) to look up any swimmer by first or last name. A detail screen shows every event they are entered in — heat, lane, seed time, and estimated start time. Relay entries are excluded.

### iPad + Magic Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+O` | Import psych sheet |
| `Cmd+Return` | Generate heat sheet |
| `Cmd+S` | Share PDF |
| `Cmd+F` | Open Find Swimmer |
| `Cmd+R` | Start Over |
| `Escape` | Dismiss Find Swimmer sheet |
| `Return` | Jump to first search result |

---

## Developer Setup: Python Reference Logic

### Installation
Ensure Python 3.10+ is installed.

```bash
pip install -r requirements.txt
```

### Running Reference Tests

```bash
pytest tests/
```

### Running the Reference UI

```bash
streamlit run src/ui/streamlit_app.py
```

---

## Seeding Rules

Standard USA Swimming preliminary seeding rules are enforced:

1. **Heat Assignment:** Entries are sorted by seed time (slowest to fastest) and distributed across heats. NT entries land in the earliest heat.
2. **Lane Distribution (Center-Out):** Within each heat, the fastest swimmer gets the center lane, with subsequent swimmers filling outward alternately. For an 8-lane pool:
   ```
   Lane 4 (Fastest) → Lane 5 → Lane 3 → Lane 6 → Lane 2 → Lane 7 → Lane 1 → Lane 8
   ```

---

## iOS Deployment and Testing

1. Transfer the contents of the `heatWaveIOS` folder to an Apple macOS machine.
2. Open Xcode and create a new **iOS App** project (Interface: SwiftUI, Language: Swift, minimum deployment target: iOS 16.0).
3. Import the files from `heatWaveIOS/heatWaveIOS` into the main target and files from `heatWaveIOS/heatWaveIOSTests` into the test target.
4. Run `Cmd+U` to execute the XCTest suite.
5. Run `Cmd+R` to launch on a simulator or physical device.
