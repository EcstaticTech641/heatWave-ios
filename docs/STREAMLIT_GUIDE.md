# Streamlit Developer Reference Guide

This guide details how to use the Streamlit interface within the `heatWave-ios` repository. The Streamlit application serves as the reference developer UI, allowing local validation and debugging of the core parsing and seeding business logic before porting or verification in the iOS application.

---

## Purpose

The Streamlit interface acts as a local sandbox to:
1. Validate that the text extraction logic handles specific psych sheet PDF files correctly.
2. Confirm the regex parser correctly identifies events, individual entries, relays, age metrics, and seed times.
3. Verify that the seeding engine applies the center-out lane assignment and heat distribution in compliance with USA Swimming rules.
4. Preview the layout of the generated PDF heat sheets.

---

## Local Setup

### Prerequisites
- Python 3.10 or higher
- Package dependencies installed via `requirements.txt`

### Starting the Application
To run the Streamlit UI, execute the following command in the project root:

```bash
streamlit run src/ui/streamlit_app.py
```

The application will launch in your default web browser (typically at `http://localhost:8501`).

---

## Application Layout and Workflow

The developer UI is split into four primary tabs:

### 1. Upload Tab
- **Functionality:** Upload a USA Swimming psych sheet PDF.
- **Action:** Click "Parse PDF" to run the extraction engine (`extractor.py`).
- **Feedback:** Displays parser statistics (total parsed events, individual entries, relays, and parsed swimmer count).

### 2. Preview Tab
- **Functionality:** Inspect the parsed data structure before seeding.
- **Action:** Use filters (All, Individual, Relay) or search queries to review event headers and sample entries.
- **Purpose:** Detect parsing discrepancies or unrecognized formats in the source PDF.

### 3. Settings Tab
- **Functionality:** Configure meet parameters.
- **Parameters:** Adjust the Meet Title, Meet Date, and pool lane configuration (4 to 10 lanes, standard is 8).

### 4. Generate Tab
- **Functionality:** Compute heat assignments and generate print-ready documents.
- **Action:** Click "Generate Heat Sheets". The app seeds all parsed entries and displays heat distribution metrics.
- **Output:** Download links for the full meet PDF or individual event PDFs.

---

## Data Management and Safety

- **Temporary Storage:** The Streamlit application generates output PDFs in a local temporary directory (`data/output/`).
- **Cleanup Daemon:** A background thread automatically deletes files in the output directory that are older than one hour. The check runs every five minutes.
- **Manual Cleanup:** An administration panel in the sidebar allows developers to clear all generated files immediately.
- **Privacy:** All computation and PDF parsing occur locally. No data is transmitted to remote servers.
