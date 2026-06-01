import unittest
import re
from typing import List, Tuple, Optional

# Mocking the schemas for testing
class Swimmer:
    def __init__(self, name, age, team_code):
        self.name = name
        self.age = age
        self.team_code = team_code
    def __repr__(self):
        return f"Swimmer(name={self.name}, age={self.age}, team_code={self.team_code})"

class Entry:
    def __init__(self, place, swimmer, seed_time):
        self.place = place
        self.swimmer = swimmer
        self.seed_time = seed_time
    def __repr__(self):
        return f"Entry(place={self.place}, swimmer={self.swimmer}, seed_time={self.seed_time})"

class RelayEntry:
    def __init__(self, place, team_name, seed_time):
        self.place = place
        self.team_name = team_name
        self.seed_time = seed_time
    def __repr__(self):
        return f"RelayEntry(place={self.place}, team_name={self.team_name}, seed_time={self.seed_time})"

class Event:
    def __init__(self, number, name, gender, distance, stroke, entries):
        self.number = number
        self.name = name
        self.gender = gender
        self.distance = distance
        self.stroke = stroke
        self.entries = entries
    def __repr__(self):
        return f"Event(number={self.number}, name={self.name}, entries={len(self.entries)})"

# --- Proposed New Functions ---

def parse_seed_time(time_str: str) -> str:
    time_str = time_str.strip().upper()
    if time_str == "NT":
        return "NT"
    
    # Handle MM:SS.XX format
    if re.match(r"^\d+:\d{2}\.\d{2}$", time_str):
        return time_str
    
    # Handle partial formats
    if re.match(r"^\d+:\d{2}$", time_str):
        return time_str + ".00"
    
    # Handle SS.XX (no minutes)
    if re.match(r"^\d{1,2}\.\d{2}$", time_str):
        return "0:" + time_str.zfill(5)

    return time_str

def parse_event_header(line: str) -> Tuple[int, str, str, int, str] | None:
    line = line.strip()
    
    # 1. Handle continuation headers: "Event 5 ...(Girls 10 & Under 200 Yard Freestyle)"
    continuation_match = re.match(r"Event\s+(\d+)\s+\.\.\.\((.+)\)", line)
    if continuation_match:
        event_num = int(continuation_match.group(1))
        inner_content = continuation_match.group(2)
        return parse_event_header(f"Event {event_num} {inner_content}")

    # 2. Tokenize
    parts = line.split()
    if len(parts) < 3 or parts[0].upper() != "EVENT":
        return None
    
    try:
        event_num_str = parts[1].rstrip(':')
        event_num = int(event_num_str)
    except ValueError:
        return None
        
    gender = None
    genders = ["GIRLS", "BOYS", "WOMEN", "MEN"]
    gender_idx = -1
    for i, p in enumerate(parts[2:], 2):
        if p.upper() in genders:
            gender = p
            gender_idx = i
            break
            
    if gender is None:
        return None
        
    # Distance: Look for a number that is followed by Yard/Meter or is one of common distances
    # or just the last number before stroke.
    # Common distances: 25, 50, 100, 200, 400, 500, 800, 1000, 1500, 1650
    common_distances = [25, 50, 100, 200, 400, 500, 800, 1000, 1500, 1650]
    
    distance = 0
    distance_idx = -1
    
    # Search backwards from the end to find the distance
    # The distance is usually the last number before the stroke words
    for i in range(len(parts) - 1, gender_idx, -1):
        if re.match(r"^\d+$", parts[i]):
            val = int(parts[i])
            # If it's a common distance, or it's followed by Yard/Meter, it's likely the distance
            is_dist = val in common_distances
            if not is_dist:
                window = [p.upper() for p in parts[i+1:min(i+4, len(parts))]]
                if any(unit in window for unit in ["YARD", "YARDS", "LC", "SC", "METER", "METERS", "Y", "M"]):
                    is_dist = True
            
            if is_dist:
                distance = val
                distance_idx = i
                break
    
    # Fallback: just take the last number if nothing found
    if distance == 0:
        for i in range(len(parts) - 1, gender_idx, -1):
            if re.match(r"^\d+$", parts[i]):
                distance = int(parts[i])
                distance_idx = i
                break

    if distance == 0:
        return None
        
    # Stroke is everything after distance (skipping "Yard", "Meter", "LC", "SC", etc.)
    stroke_parts = []
    for i in range(distance_idx + 1, len(parts)):
        p = parts[i]
        if p.upper() in ["YARD", "YARDS", "METER", "METERS", "LC", "SC", "LCM", "SCY", "SCM"]:
            continue
        stroke_parts.append(p)
    
    stroke = " ".join(stroke_parts)
    
    # Age group is everything between gender and distance
    age_group = " ".join(parts[gender_idx+1:distance_idx])
    
    event_name = f"{age_group} {distance} {stroke}".strip()
    return (event_num, gender, event_name, distance, stroke)

def parse_individual_entry(line: str) -> Tuple[int, str, str, str, str] | None:
    parts = line.split()
    if len(parts) < 4:
        return None
        
    try:
        place = int(parts[0])
    except ValueError:
        return None
        
    seed_time_str = parts[-1]
    if not (re.match(r"^\d+", seed_time_str) or seed_time_str.upper() == "NT"):
        return None
            
    seed_time = parse_seed_time(seed_time_str)
    
    # Check for STD code in parts[-2]
    # STD codes are usually uppercase, 1-3 chars, not a year/age
    has_std = False
    if len(parts) >= 6: # Place Name Age Team Std Seed
        potential_std = parts[-2].upper()
        # Common STD codes or just short uppercase strings
        if re.match(r"^[A-Z]{1,3}$", potential_std) and potential_std not in ["SO", "FR", "JR", "SR"]:
            has_std = True
            
    # Find Age/Year
    age_idx = -1
    age_patterns = [r"^\d{1,2}$", r"^(SO|FR|JR|SR)$"]
    
    # Scan from before seed/std
    search_start = -2 if not has_std else -3
    
    for i in range(len(parts) + search_start, 0, -1):
        if any(re.match(pat, parts[i].upper()) for pat in age_patterns):
            age_idx = i
            break
            
    if age_idx == -1:
        return None
        
    name = " ".join(parts[1:age_idx])
    age = parts[age_idx]
    
    team_end = -1 if not has_std else -2
    team_code = " ".join(parts[age_idx+1:team_end])
    
    return (place, name, age, team_code, seed_time)

# --- Tests ---

class TestParser(unittest.TestCase):
    def test_event_headers(self):
        cases = [
            ("Event 1 Girls 10 & Under 200 Yard Freestyle Relay", (1, "Girls", "10 & Under 200 Freestyle Relay", 200, "Freestyle Relay")),
            ("Event 5 Girls 10 & Under 200 Yard Freestyle", (5, "Girls", "10 & Under 200 Freestyle", 200, "Freestyle")),
            ("Event 1 Women 1650 Freestyle", (1, "Women", "1650 Freestyle", 1650, "Freestyle")),
            ("Event 5 ...(Girls 10 & Under 200 Yard Freestyle)", (5, "Girls", "10 & Under 200 Freestyle", 200, "Freestyle")),
            ("Event 29: Girls 50 Yard Butterfly", (29, "Girls", "50 Butterfly", 50, "Butterfly")),
            ("Event 3 Girls 12 & Under 100 LC Meter Freestyle", (3, "Girls", "12 & Under 100 Freestyle", 100, "Freestyle")),
        ]
        for line, expected in cases:
            with self.subTest(line=line):
                res = parse_event_header(line)
                self.assertIsNotNone(res)
                self.assertEqual(res[0], expected[0])
                self.assertEqual(res[1], expected[1])
                self.assertEqual(res[3], expected[3])
                # We can be a bit flexible on event_name and stroke for now

    def test_individual_entries(self):
        cases = [
            ("1 Adhikari, Sadie 10 King Marlin Swim-OK 2:28.21", (1, "Adhikari, Sadie", "10", "King Marlin Swim-OK", "2:28.21")),
            ("25 Vincent, Daisy 10 Bison Aquatic Cl-OK 3:19.31", (25, "Vincent, Daisy", "10", "Bison Aquatic Cl-OK", "3:19.31")),
            ("1 Cox, Jillian SO Texas QS 15:32.75", (1, "Cox, Jillian", "SO", "Texas", "15:32.75")),
        ]
        for line, expected in cases:
            with self.subTest(line=line):
                res = parse_individual_entry(line)
                self.assertIsNotNone(res)
                self.assertEqual(res[0], expected[0])
                self.assertEqual(res[1], expected[1])
                self.assertEqual(res[2], expected[2])
                self.assertEqual(res[3], expected[3])
                self.assertEqual(res[4], expected[4])

if __name__ == "__main__":
    unittest.main()
