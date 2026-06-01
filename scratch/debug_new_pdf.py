import sys
import os

# Add root to path
sys.path.append(os.path.abspath('.'))

from src.parser.extractor import extract_text_from_pdf, parse_events_from_text

pdf_path = r"C:\Users\aarhill\AppData\Local\Temp\heatwave\users\729dfaeb-e124-49d0-b818-6adc16b97662\Full_Meet_Heatsheets.pdf"

print(f"Extracting from: {pdf_path}")
try:
    text = extract_text_from_pdf(pdf_path)
    lines = text.split("\n")
    print("\n--- CONTEXT AROUND 'Event' LINES ---")
    for i, line in enumerate(lines):
        if "Event" in line:
            print(f"\n--- Line {i} ---")
            for j in range(max(0, i-2), min(len(lines), i+5)):
                prefix = ">> " if j == i else "   "
                print(f"{prefix}{j:3}: {lines[j]}")
            
    events = parse_events_from_text(text)
    print(f"\nDetected {len(events)} events.")
    for i, event in enumerate(events[:5]):
        print(f"Event {event.number}: {event.name} ({len(event.entries)} entries)")
        
except Exception as e:
    print(f"Error: {e}")
