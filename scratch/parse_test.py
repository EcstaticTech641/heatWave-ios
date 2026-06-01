import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from src.parser.extractor import extract_text_from_pdf, parse_events_from_text

pdf_path = r"R:\aaron\programs\heatWave\heatWaveIOS\test\2026.04.28 - updated psych sheets.pdf"
text = extract_text_from_pdf(pdf_path)
print(f"Extracted text length: {len(text)}")
print("--- First 500 characters ---")
print(text[:500])
print("--- Last 500 characters ---")
print(text[-500:])

events = parse_events_from_text(text)
print(f"Parsed {len(events)} events.")
for i, ev in enumerate(events[:5]):
    print(f"Event {ev.number} ({ev.gender}): {ev.name} - {len(ev.entries)} entries")
    for j, entry in enumerate(ev.entries[:3]):
        print(f"  Entry {j+1}: {entry}")
