#!/usr/bin/env python3
"""Check MosqueBoard's bundled timetables against SalahKit RFC 0001 §4.3-§4.4.

Usage:
    python3 -I check-timetables.py [timetable.json ...]

With no arguments it checks every file in ../Shared/Timetables. Each file
needs a known time zone (ZONES below). Standard library only.

Checked for every row (RFC §4.4 row checks and prayerDay steps):
- the day is a valid YYYY-MM-DD date and appears once;
- every time is "HH:MM" or "HH:MM+1" (hour 0-23, minute 0-59) or an ISO 8601
  instant with an offset;
- every kind in times is in expectedKinds; iqama only on prayers (not sunrise)
  that have a time; observances only on kinds with a time, and jumuah only on
  the dhuhr of a Friday;
- each wall time resolves in the zone under the file's wallTimeResolution
  (default: reject repeated and nonexistent times);
- resolved times lie in [start(D), start(D+2)) and strictly increase in
  canonical order; each iqama lies in [time, start(D+2));
- "+1" appears only where the same clock time on the owning day would come
  before the preceding prayer (or, for an iqama, before its prayer).

Across days (RFC §4.3 rule 6, plus MosqueBoard's own margin): no event of a
day is later than an event of the next published day, and Isha is at least an
hour before the next day's Fajr.

The file-specific expectations in EXPECTATIONS describe the cases each file
exists to exercise (full year, gaps, partial rows, clock changes, Jumu'ah).
"""

import datetime
import json
import os
import re
import sys
from zoneinfo import ZoneInfo

KINDS = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]
PRAYERS = [kind for kind in KINDS if kind != "sunrise"]
OBSERVANCES = {"ordinary", "jumuah"}
POLICIES = {"repeated": {"earlier", "later", "reject"}, "nonexistent": {"nextValid", "reject"}}

ZONES = {
    "muis-2026.json": "Asia/Singapore",
    "edinburgh-synthetic.json": "Europe/London",
}

WALL_RE = re.compile(r"^(\d{1,2}):(\d{2})(\+1)?$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
UTC = datetime.timezone.utc
MIN_ISHA_TO_FAJR = datetime.timedelta(hours=1)


class Problems:
    def __init__(self):
        self.items = []

    def add(self, where, message):
        self.items.append(f"{where}: {message}")


def local_midnight(day, zone):
    """start(D): local midnight, earliest occurrence; next valid instant if skipped."""
    return resolve(datetime.datetime.combine(day, datetime.time()), zone, "earlier", "nextValid")[0]


def resolve(naive, zone, repeated, nonexistent):
    """Returns (instant or None, note) for a local date-time, per RFC §4.2."""
    candidates = []
    for fold in (0, 1):
        aware = naive.replace(tzinfo=zone, fold=fold)
        instant = aware.astimezone(UTC)
        back = instant.astimezone(zone).replace(tzinfo=None)
        if back == naive and instant not in candidates:
            candidates.append(instant)
    candidates.sort()
    if len(candidates) == 1:
        return candidates[0], None
    if len(candidates) == 2:
        if repeated == "reject":
            return None, "repeated"
        return (candidates[0] if repeated == "earlier" else candidates[1]), "repeated"
    if nonexistent == "reject":
        return None, "nonexistent"
    probe = naive.replace(tzinfo=zone, fold=0).astimezone(UTC) - datetime.timedelta(hours=30)
    # The first valid local time after the gap: scan forward minute by minute.
    probe = probe.replace(second=0, microsecond=0)
    while probe.astimezone(zone).replace(tzinfo=None) < naive:
        probe += datetime.timedelta(minutes=1)
    return probe, "nonexistent"


def parse_time(text):
    """Returns ("wall", hour, minute, offset) or ("instant", datetime), or None."""
    if not isinstance(text, str):
        return None
    match = WALL_RE.match(text)
    if match:
        hour, minute = int(match.group(1)), int(match.group(2))
        if hour > 23 or minute > 59:
            return None
        return ("wall", hour, minute, 1 if match.group(3) else 0)
    try:
        instant = datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if instant.tzinfo is None:
        return None
    return ("instant", instant.astimezone(UTC))


def check_file(path, problems):
    name = os.path.basename(path)
    if name not in ZONES:
        problems.add(name, "no known time zone for this file")
        return None
    zone = ZoneInfo(ZONES[name])
    with open(path, encoding="utf-8") as handle:
        source = json.load(handle)

    expected = source.get("expectedKinds")
    if not isinstance(expected, list) or not expected or len(set(expected)) != len(expected) \
            or any(kind not in KINDS for kind in expected):
        problems.add(name, f"bad expectedKinds {expected!r}")
        return None
    policy = source.get("wallTimeResolution", {})
    repeated = policy.get("repeated", "reject")
    nonexistent = policy.get("nonexistent", "reject")
    if repeated not in POLICIES["repeated"] or nonexistent not in POLICIES["nonexistent"]:
        problems.add(name, f"bad wallTimeResolution {policy!r}")
    unknown = set(source) - {"expectedKinds", "wallTimeResolution", "rows"}
    if unknown:
        problems.add(name, f"unknown top-level keys {sorted(unknown)}")

    rows = source.get("rows")
    if not isinstance(rows, list) or not rows:
        problems.add(name, "no rows")
        return None

    days = {}
    stats = {
        "zone": ZONES[name], "rows": 0, "partial": [], "plus_one_times": 0,
        "plus_one_nights": [], "plus_one_iqama": 0, "rows_with_iqama": 0,
        "jumuah": 0, "fridays": 0, "offset_changes": [], "min_isha_to_fajr": None,
    }
    for index, row in enumerate(rows):
        where = f"{name} row {index}"
        if not isinstance(row, dict):
            problems.add(where, "not an object")
            continue
        unknown = set(row) - {"day", "times", "iqama", "observances"}
        if unknown:
            problems.add(where, f"unknown keys {sorted(unknown)}")
        text = row.get("day")
        try:
            if not isinstance(text, str) or not DATE_RE.match(text):
                raise ValueError
            day = datetime.date.fromisoformat(text)
        except ValueError:
            problems.add(where, f"bad day {text!r}")
            continue
        where = f"{name} {text}"
        if day in days:
            problems.add(where, "duplicate day")
            continue
        days[day] = check_row(row, day, where, expected, zone, repeated, nonexistent, problems, stats)

    ordered = sorted(days)
    stats["rows"] = len(ordered)
    stats["first"], stats["last"] = ordered[0], ordered[-1]
    stats["missing"] = [
        ordered[0] + datetime.timedelta(days=n)
        for n in range((ordered[-1] - ordered[0]).days + 1)
        if ordered[0] + datetime.timedelta(days=n) not in days
    ]
    stats["fridays"] = sum(1 for day in ordered if day.weekday() == 4)

    previous_offset = None
    for day in ordered:
        offset = datetime.datetime.combine(day, datetime.time(12)).replace(tzinfo=zone).utcoffset()
        if previous_offset is not None and offset != previous_offset:
            stats["offset_changes"].append((day, previous_offset, offset))
        previous_offset = offset

    for day in ordered:
        following = day + datetime.timedelta(days=1)
        if following not in days or days[day] is None or days[following] is None:
            continue
        today, tomorrow = days[day], days[following]
        if not today or not tomorrow:
            continue
        if max(today.values()) > min(tomorrow.values()):
            problems.add(f"{name} {day}", "an event is later than an event of the next day")
        if "isha" in today and "fajr" in tomorrow:
            gap = tomorrow["fajr"] - today["isha"]
            if gap < MIN_ISHA_TO_FAJR:
                problems.add(f"{name} {day}", f"Isha is only {gap} before the next Fajr")
            if stats["min_isha_to_fajr"] is None or gap < stats["min_isha_to_fajr"][1]:
                stats["min_isha_to_fajr"] = (day, gap)
    return stats


def check_row(row, day, where, expected, zone, repeated, nonexistent, problems, stats):
    """Checks one row; returns {kind: instant} for its resolved times, or None."""
    times = row.get("times", {})
    iqama = row.get("iqama", {})
    observances = row.get("observances", {})
    ok = True
    for label, value in (("times", times), ("iqama", iqama), ("observances", observances)):
        if not isinstance(value, dict):
            problems.add(where, f"{label} is not an object")
            return None
    if not times:
        problems.add(where, "row has no times")
        return None

    for kind in times:
        if kind not in expected:
            problems.add(where, f"time for unexpected kind {kind!r}")
            ok = False
    for kind in iqama:
        if kind not in PRAYERS or kind not in times:
            problems.add(where, f"iqama for {kind!r}, which isn't a prayer with a time")
            ok = False
    for kind, value in observances.items():
        if kind not in times:
            problems.add(where, f"observance for {kind!r} without a time")
            ok = False
        if value not in OBSERVANCES:
            problems.add(where, f"unknown observance {value!r}")
            ok = False
        if value == "jumuah" and (kind != "dhuhr" or day.weekday() != 4):
            problems.add(where, "jumuah outside Friday's dhuhr")
            ok = False
    if observances.get("dhuhr") == "jumuah":
        stats["jumuah"] += 1

    start = local_midnight(day, zone)
    end = local_midnight(day + datetime.timedelta(days=2), zone)

    def instant_of(text, label):
        parsed = parse_time(text)
        if parsed is None:
            problems.add(where, f"{label}: malformed time {text!r}")
            return None, None
        if parsed[0] == "instant":
            return parsed[1], None
        _, hour, minute, offset = parsed
        naive = datetime.datetime.combine(day + datetime.timedelta(days=offset), datetime.time(hour, minute))
        instant, note = resolve(naive, zone, repeated, nonexistent)
        if instant is None:
            problems.add(where, f"{label}: {text} is a {note} local time and is rejected")
        return instant, parsed

    resolved = {}
    walls = {}
    for kind in KINDS:
        if kind in times:
            instant, parsed = instant_of(times[kind], kind)
            if instant is None:
                ok = False
                continue
            if not (start <= instant < end):
                problems.add(where, f"{kind} {times[kind]} is outside [start(D), start(D+2))")
                ok = False
            resolved[kind] = instant
            walls[kind] = parsed
    present = [kind for kind in KINDS if kind in resolved]
    for first, second in zip(present, present[1:]):
        if not resolved[first] < resolved[second]:
            problems.add(where, f"{first} is not before {second}")
            ok = False

    # "+1" only where needed: the same clock time without it must come too early.
    for position, kind in enumerate(present):
        parsed = walls.get(kind)
        if parsed and parsed[0] == "wall" and parsed[3] == 1:
            stats["plus_one_times"] += 1
            stats["plus_one_nights"].append(day)
            earlier = [walls[k] for k in present[:position] if walls.get(k) and walls[k][0] == "wall"]
            same_day = parsed[1] * 60 + parsed[2]
            if earlier and all(w[3] * 1440 + w[1] * 60 + w[2] < same_day for w in earlier):
                problems.add(where, f"{kind} {times[kind]} doesn't need +1")
                ok = False

    if iqama:
        stats["rows_with_iqama"] += 1
    for kind, text in iqama.items():
        instant, parsed = instant_of(text, f"{kind} iqama")
        if instant is None or kind not in resolved:
            ok = False
            continue
        if not (resolved[kind] <= instant < end):
            problems.add(where, f"{kind} iqama {text} is outside [time, start(D+2))")
            ok = False
        if parsed and parsed[0] == "wall" and parsed[3] == 1:
            stats["plus_one_iqama"] += 1
            prayer = walls.get(kind)
            if prayer and prayer[0] == "wall" and prayer[3] == 0 \
                    and parsed[1] * 60 + parsed[2] >= prayer[1] * 60 + prayer[2]:
                problems.add(where, f"{kind} iqama {text} doesn't need +1")
                ok = False

    missing = [kind for kind in expected if kind not in times]
    if missing:
        stats["partial"].append((day, missing))
    return resolved if ok else None


EXPECTATIONS = {
    "muis-2026.json": lambda s, add: [
        s["rows"] == 365 or add("expected 365 rows"),
        (s["first"], s["last"]) == (datetime.date(2026, 1, 1), datetime.date(2026, 12, 31))
        or add("expected 2026-01-01 to 2026-12-31"),
        not s["missing"] or add("expected no missing days"),
        not s["partial"] or add("expected no partial rows"),
        s["rows_with_iqama"] == 0 or add("expected no published iqama"),
        s["jumuah"] == 0 or add("expected no declared Jumu'ah"),
        s["plus_one_times"] == 0 or add("expected no times after midnight"),
    ],
    "edinburgh-synthetic.json": lambda s, add: [
        (s["first"], s["last"]) == (datetime.date(2026, 3, 1), datetime.date(2026, 10, 31))
        or add("expected 2026-03-01 to 2026-10-31"),
        s["missing"] == [datetime.date(2026, 6, 26)] or add("expected exactly 2026-06-26 missing"),
        s["partial"] == [(datetime.date(2026, 6, 24), ["isha"])] or add("expected only 2026-06-24 without isha"),
        [c[0] for c in s["offset_changes"]] == [datetime.date(2026, 3, 29), datetime.date(2026, 10, 25)]
        or add("expected offset changes on 2026-03-29 and 2026-10-25"),
        s["jumuah"] == s["fridays"] or add("expected Jumu'ah on every Friday"),
        s["rows_with_iqama"] == s["rows"] or add("expected iqama on every row"),
        sum(1 for d in s["plus_one_nights"] if d.month == 6 and d.day >= 20) >= 3
        or add("expected several late-June nights with Isha after midnight"),
    ],
}


def describe(name, stats):
    lines = [f"{name} ({stats['zone']})"]
    lines.append(f"  rows: {stats['rows']}, {stats['first']} to {stats['last']} (last published day)")
    lines.append("  missing days: " + (", ".join(map(str, stats["missing"])) or "none"))
    lines.append("  partial rows: " + (", ".join(f"{d} without {', '.join(k)}" for d, k in stats["partial"]) or "none"))
    lines.append(f"  rows with published iqama: {stats['rows_with_iqama']}")
    lines.append(f"  Fridays: {stats['fridays']}, declared Jumu'ah: {stats['jumuah']}")
    nights = stats["plus_one_nights"]
    if nights:
        lines.append(f"  times after midnight (+1): {stats['plus_one_times']} on {len(nights)} nights, "
                     f"{nights[0]} to {nights[-1]}; iqama with +1: {stats['plus_one_iqama']}")
    else:
        lines.append("  times after midnight (+1): none")
    if stats["offset_changes"]:
        for day, before, after in stats["offset_changes"]:
            lines.append(f"  UTC offset changes on {day}: {fmt(before)} -> {fmt(after)}")
    else:
        lines.append("  UTC offset changes: none")
    if stats["min_isha_to_fajr"]:
        day, gap = stats["min_isha_to_fajr"]
        lines.append(f"  shortest Isha -> next Fajr: {gap} (night of {day})")
    return "\n".join(lines)


def fmt(offset):
    minutes = int(offset.total_seconds() // 60)
    return f"UTC{'+' if minutes >= 0 else '-'}{abs(minutes) // 60:02d}:{abs(minutes) % 60:02d}"


def main(argv):
    here = os.path.dirname(os.path.abspath(argv[0]))
    paths = argv[1:] or sorted(
        os.path.join(here, "..", "Shared", "Timetables", name) for name in ZONES
    )
    problems = Problems()
    for path in paths:
        name = os.path.basename(path)
        stats = check_file(path, problems)
        if stats is None:
            continue
        if name in EXPECTATIONS:
            EXPECTATIONS[name](stats, lambda message, n=name: problems.add(n, message))
        print(describe(name, stats))
    if problems.items:
        print(f"\nFAILED: {len(problems.items)} problem(s)")
        for item in problems.items:
            print("  " + item)
        return 1
    print("\nOK: every row passes RFC 0001 §4.4's row checks and resolves cleanly.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
