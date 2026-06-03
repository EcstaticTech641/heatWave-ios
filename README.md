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
│   │   ├── ContentView.swift    # Primary user interface
│   │   ├── DocumentPicker.swift # Native Document Picker wrapper
│   │   ├── Models.swift         # Data structures mapping entries and events
│   │   ├── PDFExtractor.swift   # Bounding-box text extraction (iOS 16+)
│   │   ├── RegexParser.swift    # Text-to-data parsing engine
│   │   ├── SeedingEngine.swift  # USA Swimming seeding rules
│   │   └── PDFGenerator.swift   # Native PDF renderer
│   └── heatWaveIOSTests/        # XCTest suite for Swift implementation
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
| `src/parser/extractor.py` | `PDFExtractor.swift` + `RegexParser.swift` | Coordinates column-aware text extraction and parses entries via regex. |
| `src/models/schemas.py` | `Models.swift` (inside `RegexParser.swift`) | Defines data schemas for Meet, Event, Entry, and HeatSheet. |
| `src/seeding/seeder.py` | `SeedingEngine.swift` | Applies USA Swimming rules to seed entries into heats and lanes. |
| `src/core/pdf_generator.py` | `PDFGenerator.swift` | Renders the final print-ready heat sheet PDF. |

---

## Developer Setup: Python Reference Logic

Developers can use the Python environment to inspect the reference parsing and seeding logic, debug rules, and run the reference suite.

### Installation
Ensure Python 3.10+ is installed.

```bash
# Install dependencies
pip install -r requirements.txt
```

### Running Reference Tests
Run the Python test suite to verify the reference parser and seeding calculations:

```bash
pytest tests/
```

### Running the Reference UI
To run the Streamlit frontend locally for quick visualization of the parsing/seeding logic:

```bash
streamlit run src/ui/streamlit_app.py
```

---

## Seeding Rules

The application enforces standard USA Swimming preliminary seeding rules:

1. **Heat Assignment:** Entries are sorted by seed time (slowest to fastest) and distributed across heats to achieve a balanced lane assignment.
2. **Lane Distribution (Center-Out):** Within each heat, lanes are assigned outward starting from the center lanes based on speed. For an 8-lane pool, the assignment order is:
   ```
   Lane 4 (Fastest) -> Lane 5 -> Lane 3 -> Lane 6 -> Lane 2 -> Lane 7 -> Lane 1 -> Lane 8
   ```

---

## iOS Deployment and Testing

To compile and execute the native iOS application:

1. Transfer the contents of the `heatWaveIOS` folder to an Apple macOS machine.
2. Open Xcode and create a new **iOS App** project (Interface: SwiftUI, Language: Swift, minimum deployment target: iOS 16.0).
3. Import the files from `heatWaveIOS/heatWaveIOS` into the main target and files from `heatWaveIOS/heatWaveIOSTests` into the test target.
4. Execute `Cmd + R` to run on a physical iOS device or simulator.
5. Execute `Cmd + U` to run the native XCTest suite.
