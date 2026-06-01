import sys
import os

# Add root to path
sys.path.append(os.path.abspath('.'))

from src.parser.extractor import parse_events_from_text

text = """
Event 1 Women 1650 Freestyle
Name Elig. Year Team Name Std Seed
1 Cox, Jillian SO Texas QS 15:32.75

Event 5 Girls 10 & Under 200 Yard Freestyle
Name Age Team Seed Time
1 Adhikari, Sadie 10 King Marlin Swim-OK 2:28.21

Event 3 Girls 12 & Under 100 LC Meter Freestyle
Name Age Team Seed Time
1 Mitchell, Braylin R 12 SSC-OK 1:03.39
"""

print(f"Parsing sample text...")
events = parse_events_from_text(text)
print(f"Detected {len(events)} events.")

for event in events:
    print(f"\nEvent {event.number}: {event.name} ({event.gender})")
    for entry in event.entries:
        if hasattr(entry, 'swimmer'):
            print(f"  {entry.place}. {entry.swimmer.name} ({entry.swimmer.age}) - {entry.swimmer.team_code} [{entry.seed_time}]")
        else:
            print(f"  {entry.place}. {entry.team_name} [{entry.seed_time}]")
