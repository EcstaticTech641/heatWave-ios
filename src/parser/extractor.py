import re
from typing import List, Tuple
import pdfplumber
from ..models.schemas import Event, Entry, RelayEntry, Swimmer


def extract_text_from_pdf(pdf_path: str) -> str:
    """
    Extract text from a Psych Sheet PDF.
    Handles the two-column layout parsing by extracting left and right columns separately.
    
    Returns:
        Full text with columns merged in reading order.
    """
    with pdfplumber.open(pdf_path) as pdf:
        full_text = ""
        for page_num, page in enumerate(pdf.pages):
            width = page.width
            height = page.height
            
            # Crop left and right columns
            left_bbox = (0, 0, width / 2, height)
            right_bbox = (width / 2, 0, width, height)
            
            left_col = page.crop(left_bbox)
            right_col = page.crop(right_bbox)
            
            left_text = left_col.extract_text() or ""
            right_text = right_col.extract_text() or ""
            
            # Merge columns intelligently (left then right)
            if page_num > 0:
                full_text += "\n"
            full_text += left_text + "\n" + right_text
        
        return full_text


def parse_event_header(line: str) -> Tuple[int, str, str, int, str] | None:
    """
    Parse event header line: "Event 1 Girls 10 & Under 200 Yard Freestyle"
    Also handles continuation headers like "Event 5 ...(Girls 10 & Under 200 Yard Freestyle)"
    
    Returns:
        Tuple of (event_number, gender, event_name, distance, stroke) or None if not matched.
    """
    line = line.strip()
    
    # 1. Handle continuation headers
    continuation_match = re.match(r"Event\s+(\d+)\s+\.\.\.\((.+)\)", line)
    if continuation_match:
        event_num = int(continuation_match.group(1))
        inner_content = continuation_match.group(2)
        # Recurse with reconstructed line
        return parse_event_header(f"Event {event_num} {inner_content}")

    # 2. Tokenize and parse
    parts = line.split()
    if len(parts) < 3 or parts[0].upper() != "EVENT":
        return None
    
    try:
        # Handle "Event 1:" or "Event 1"
        event_num_str = parts[1].rstrip(':')
        event_num = int(event_num_str)
    except ValueError:
        return None
        
    # Find gender
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
        
    # Distance: Look for a number that is a common distance or followed by Yard/Meter
    common_distances = [25, 50, 100, 200, 400, 500, 800, 1000, 1500, 1650]
    distance = 0
    distance_idx = -1
    
    # Search backwards from the end to find the distance
    for i in range(len(parts) - 1, gender_idx, -1):
        if re.match(r"^\d+$", parts[i]):
            val = int(parts[i])
            is_dist = val in common_distances
            if not is_dist:
                window = [p.upper() for p in parts[i+1:min(i+4, len(parts))]]
                if any(unit in window for unit in ["YARD", "YARDS", "LC", "SC", "METER", "METERS", "Y", "M"]):
                    is_dist = True
            
            if is_dist:
                distance = val
                distance_idx = i
                break
    
    # Fallback to last number if no common distance found
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
    
    # Construct full event name
    event_name = f"{age_group} {distance} {stroke}".strip()
    if not age_group:
        event_name = f"{distance} {stroke}".strip()
        
    return (event_num, gender, event_name, distance, stroke)


def parse_seed_time(time_str: str) -> str:
    """
    Parse and validate seed time formats (MM:SS.XX or NT).
    
    Returns:
        Normalized seed time string.
    """
    time_str = time_str.strip().upper()
    
    # Handle NT (no time)
    if time_str == "NT":
        return "NT"
    
    # Handle MM:SS.XX format
    if re.match(r"^\d+:\d{2}\.\d{2}$", time_str):
        return time_str
    
    # Handle partial formats
    if re.match(r"^\d+:\d{2}$", time_str):
        return time_str + ".00"
    
    return time_str


def parse_individual_entry(line: str) -> Tuple[int, str, str, str, str] | None:
    """
    Parse individual swimmer entry.
    Handles standard: "1 Meek, Keaston 10 Bartlesville Spl-OK 2:42.05"
    And collegiate: "1 Cox, Jillian SO Texas QS 15:32.75"
    
    Returns:
        Tuple of (place, swimmer_name, age_or_year, team_code, seed_time) or None if not matched.
    """
    parts = line.split()
    
    if len(parts) < 4:
        return None
    
    try:
        place = int(parts[0])
    except ValueError:
        return None
    
    # Seed time is the last part
    seed_time_str = parts[-1]
    if not (re.match(r"^\d+", seed_time_str) or seed_time_str.upper() == "NT"):
        return None
    
    seed_time = parse_seed_time(seed_time_str)
    
    # Check for optional Standard/Qualification code (e.g., "QS", "QT", "A")
    # These are usually short uppercase strings right before the seed time.
    has_std = False
    if len(parts) >= 6: # Need at least Place, Name, Age, Team, Std, Seed
        potential_std = parts[-2].upper()
        # Common pattern: 1-3 uppercase letters, not a year/age code
        if re.match(r"^[A-Z]{1,3}$", potential_std) and potential_std not in ["SO", "FR", "JR", "SR"]:
            has_std = True
            
    # Find Age or Eligibility Year (SO, FR, etc.)
    # Scan from before seed (and std) backwards
    age_idx = -1
    age_patterns = [r"^\d{1,2}$", r"^(SO|FR|JR|SR)$"]
    
    search_start = -2 if not has_std else -3
    
    for i in range(len(parts) + search_start, 0, -1):
        if any(re.match(pat, parts[i].upper()) for pat in age_patterns):
            age_idx = i
            break
            
    if age_idx == -1:
        return None
    
    # Name is everything between place and age
    name = " ".join(parts[1:age_idx])
    age = parts[age_idx]
    
    # Team code is everything between age and seed_time (excluding std)
    team_end = -1 if not has_std else -2
    team_code = " ".join(parts[age_idx + 1:team_end])
    
    return (place, name, age, team_code, seed_time)


def parse_relay_entry(line: str) -> Tuple[int, str, str] | None:
    """
    Parse relay entry: "1 King Marlin Swim-OK A 2:13.43"
    
    Returns:
        Tuple of (place, team_name, seed_time) or None if not matched.
    """
    parts = line.split()
    
    if len(parts) < 3:
        return None
    
    try:
        place = int(parts[0])
    except ValueError:
        return None
    
    # Find seed time (last part, should be MM:SS.XX or NT)
    seed_time_str = parts[-1]
    if not (re.match(r"^\d+:\d{2}", seed_time_str) or seed_time_str.upper() == "NT"):
        return None
    
    # Team everything in between place and seed time
    team_name = " ".join(parts[1:-1])
    seed_time = parse_seed_time(seed_time_str)
    
    return (place, team_name, seed_time)


def parse_events_from_text(text: str) -> List[Event]:
    """
    Parse all events from extracted psych sheet text.
    
    Returns:
        List of Event objects with parsed entries.
    """
    lines = text.split("\n")
    events: List[Event] = []
    
    current_event: Event | None = None
    is_relay_event = False
    
    for line in lines:
        line = line.strip()
        
        if not line:
            continue
        
        # Check for event header
        event_info = parse_event_header(line)
        if event_info:
            event_num, gender, event_name, distance, stroke = event_info
            
            # If this is a continuation of the current event, just keep going
            if current_event and current_event.number == event_num and current_event.name == event_name:
                continue
                
            # Otherwise, save previous event and start a new one
            if current_event:
                events.append(current_event)
            
            is_relay_event = "Relay" in line
            
            current_event = Event(
                number=event_num,
                name=event_name,
                gender=gender,
                distance=distance,
                stroke=stroke,
                entries=[]
            )
            continue
        
        # Skip header lines
        if any(skip in line for skip in ["Name Age Team", "Team Relay Seed", "Seed Time", "HY-TEK", "Elig. Year", "Std Seed"]):
            continue
        
        # Parse entries
        if current_event:
            if is_relay_event:
                entry_data = parse_relay_entry(line)
                if entry_data:
                    place, team_name, seed_time = entry_data
                    relay_entry = RelayEntry(
                        place=place,
                        team_name=team_name,
                        seed_time=seed_time
                    )
                    current_event.entries.append(relay_entry)
            else:
                entry_data = parse_individual_entry(line)
                if entry_data:
                    place, name, age, team_code, seed_time = entry_data
                    swimmer = Swimmer(name=name, age=age, team_code=team_code)
                    entry = Entry(place=place, swimmer=swimmer, seed_time=seed_time)
                    current_event.entries.append(entry)
    
    # Don't forget the last event
    if current_event:
        events.append(current_event)
    
    return events
