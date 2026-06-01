# Running heatWaveIOS in Xcode

This guide will walk you through setting up and running the `heatWaveIOS` application in Xcode from scratch. This project is a 100% native SwiftUI app with no third-party dependencies.

## Prerequisites
- **Xcode 14.0** or newer installed on your Mac.
- The minimum deployment target for this application is **iOS 16.0** (required for native Swift Regex support).

## Step 1: Create a New Xcode Project

1. Open Xcode.
2. Select **File > New > Project...** from the menu bar.
3. Choose the **iOS** tab, select **App**, and click **Next**.
4. Configure the project options:
   - **Product Name:** `heatWaveIOS`
   - **Team:** Select your Apple Developer account (or "None" if you just want to run in the simulator).
   - **Organization Identifier:** (e.g., `com.yourname`)
   - **Interface:** `SwiftUI`
   - **Language:** `Swift`
   - Ensure "Include Tests" is **checked**.
5. Click **Next** and save the project to your preferred location.

## Step 2: Set the Minimum Deployment Target

1. In the Project Navigator (left sidebar), click on the top-level `heatWaveIOS` project file (it has a blue icon).
2. In the main editor pane, select the `heatWaveIOS` target under the **Targets** list.
3. Click the **General** tab.
4. Under the **Minimum Deployments** section, set the iOS version to **16.0**.
5. Repeat this process for the `heatWaveIOSTests` target, ensuring it is also set to iOS 16.0.

## Step 3: Add the Source Files

This project uses a flat directory structure. You need to replace the default files Xcode generated with the ones from this repository.

1. Locate the source files in this repository under the `heatWaveIOS/heatWaveIOS` directory.
2. In Xcode, delete the default `ContentView.swift` and `heatWaveIOSApp.swift` (or `App.swift`) that were generated in the main app group. Choose "Move to Trash" when prompted.
3. Drag and drop all the `.swift` files from the repository's `heatWaveIOS/heatWaveIOS` directory into the main `heatWaveIOS` folder in the Xcode Project Navigator.
   - The required files are:
     - `App.swift`
     - `ContentView.swift`
     - `DocumentPicker.swift`
     - `Models.swift`
     - `PDFExtractor.swift`
     - `PDFGenerator.swift`
     - `RegexParser.swift`
     - `SeedingEngine.swift`
     - `ShareSheet.swift`
4. Ensure **"Copy items if needed"** is checked and the `heatWaveIOS` target is selected in the dialog that appears.

## Step 4: Add the Test Files

1. In the Project Navigator, find the `heatWaveIOSTests` folder (it will contain a default test file).
2. Delete the default `heatWaveIOSTests.swift` file (Move to Trash).
3. Drag and drop all the `.swift` files from the repository's `heatWaveIOS/heatWaveIOSTests` directory into the `heatWaveIOSTests` group in Xcode.
   - The required files are:
     - `PDFExtractorTests.swift`
     - `RegexParserTests.swift`
     - `SeedingEngineTests.swift`
     - `PDFGeneratorTests.swift`
4. Ensure **"Copy items if needed"** is checked and the `heatWaveIOSTests` target is selected.

## Step 5: Run the App

1. Select a simulator (e.g., iPhone 15 Pro) from the device dropdown menu in the toolbar at the top of the Xcode window.
2. Click the **Run** button (the "Play" icon) or press `Cmd + R` to build and run the app.
3. The app will launch in the simulator, presenting the "Import Psych Sheet" interface.

## Step 6: Run the Tests (Optional)

1. To execute the test suite, press `Cmd + U` or select **Product > Test** from the menu bar.
2. Xcode will build the project and run all unit tests, confirming that the extraction, parsing, and seeding logic functions correctly.

Enjoy generating heat sheets right on your device!
