# heatWaveIOS (v0.1.0-alpha.1)

Standalone native iOS application for the heatWave psych sheet processor.

- Native, 100% offline-capable SwiftUI application.
- Converts USA Swimming psych sheet PDFs to formatted heat sheet PDFs entirely on-device.
- Version: `v0.1.0-alpha.1` (`CFBundleShortVersionString`: `0.1.0`, `CFBundleVersion`: `1`).
- Minimum deployment target: iOS 16.0.


## Features

### Core Pipeline
Import a USA Swimming psych sheet PDF → configure meet settings → generate a seeded heat sheet PDF.

### Timeline Estimator
Each event is assigned an estimated duration computed as:

```
estimatedDuration = Σ(slowest timed seed per heat) + (numHeats × turnoverTime)
```

- `turnoverTime` defaults to **120 s (2 min)** and is adjustable via a stepper (1–15 min) on the Configure Meet screen.
- Heats where every entry is NT use a fallback time (`ntFallbackTime`, default 120 s).
- Each event header in the PDF shows **Est. Start** (running clock) and **Est. Event Duration**.
- The success screen shows a grand-total **Estimated Meet Duration** card.

### Find Swimmer
After generating a heat sheet, tap **Find Swimmer** (or press **Cmd+F** on a hardware keyboard) to open a search sheet:

1. Type any part of a first or last name.
2. Tap a result to open the swimmer's personal schedule.
3. The schedule shows event, heat, lane, seed time, and estimated start time for each individual entry. Relay entries are excluded.

### iPad + Magic Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+O` | Import psych sheet |
| `Cmd+Return` | Generate heat sheet |
| `Cmd+S` | Share PDF |
| `Cmd+F` | Open Find Swimmer |
| `Cmd+R` | Start Over (reset) |
| `Escape` | Dismiss the Find Swimmer sheet |
| `Return` | Jump to first search result |

The search field uses `@FocusState` + a plain `TextField` (not `.searchable`) so focus connects immediately on both software and hardware keyboards.

---

## Implementation Phases

| Phase | Focus | Status |
|---|---|---|
| 1 | UI Shell and scaffolding | ✅ Complete |
| 2 | File I/O and PDF text extraction | ✅ Complete |
| 3 | Regex parser (port from Python) | ✅ Complete |
| 4 | Seeding engine and PDF generation | ✅ Complete |
| 5 | Timeline estimator + Find Swimmer + keyboard shortcuts | ✅ Complete |

---

## Xcode Setup

1. Create a new **iOS App** project in Xcode (SwiftUI lifecycle, minimum iOS 16).
2. Drag all files from `heatWaveIOS/heatWaveIOS/` into the Xcode source group.
3. Drag all files from `heatWaveIOS/heatWaveIOSTests/` into the test target.
4. No third-party dependencies are required — all frameworks used are Apple system frameworks.

---

## Key Constraints

- Use `PDFPage.string(for: CGRect)` for column-aware extraction (see `EXTRACTION_SPIKE.md`).
- Save output PDFs to `.documentDirectory` — do not use `.temporaryDirectory`.
- Surface scanned-PDF errors with the exact message: `"This PDF appears to be image-based. Scanned PDFs are not yet supported."`
- Every core Swift file must have a corresponding XCTest file.
- Relay entries are deliberately excluded from Find Swimmer — there is no individual swimmer to look up.
