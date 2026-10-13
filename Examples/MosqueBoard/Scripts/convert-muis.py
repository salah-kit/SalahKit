#!/usr/bin/env python3
"""Convert MUIS's "Muslim Prayer Timetable 2026" into a TimetableSource JSON file.

Source: data.gov.sg dataset d_d441e7242e78efc566024dd5b0d9829c, published by
Majlis Ugama Islam Singapura (MUIS) under the Singapore Open Data Licence v1.0.

Usage:
    python3 -I convert-muis.py <datastore-response.json> <output.json>

The input is the response of the data.gov.sg datastore API for the dataset, for
example (all 365 rows in one page):

    https://data.gov.sg/api/action/datastore_search?resource_id=d_d441e7242e78efc566024dd5b0d9829c&limit=400

The input is treated as untrusted data: it's parsed as JSON and every value is
validated before it's written. The script uses only the standard library.

Output: the TimetableSource JSON shape of SalahKit's RFC 0001 §4.4, one row per
line. MUIS publishes no iqama and no Jumu'ah, so the rows carry neither;
MosqueBoard adds them as its own mosque policy.
"""

import datetime
import json
import re
import sys

EXPECTED_ROWS = 365
YEAR = 2026

# MUIS column -> SalahKit PrayerKind, in canonical order.
COLUMNS = [
    ("Subuh", "fajr"),
    ("Syuruk", "sunrise"),
    ("Zohor", "dhuhr"),
    ("Asar", "asr"),
    ("Maghrib", "maghrib"),
    ("Isyak", "isha"),
]

DATE_RE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})$")
TIME_RE = re.compile(r"^(\d{2}):(\d{2})$")


def fail(message):
    sys.exit(f"convert-muis: {message}")


def parse_date(text):
    if not isinstance(text, str) or not DATE_RE.match(text):
        fail(f"bad date {text!r}")
    try:
        day = datetime.date.fromisoformat(text)
    except ValueError:
        fail(f"invalid date {text!r}")
    if day.year != YEAR:
        fail(f"date {text} is outside {YEAR}")
    return day


def parse_time(text, where):
    if not isinstance(text, str):
        fail(f"{where}: time is not a string: {text!r}")
    match = TIME_RE.match(text.strip())
    if not match:
        fail(f"{where}: time {text!r} is not 24-hour HH:MM")
    hour, minute = int(match.group(1)), int(match.group(2))
    if hour > 23 or minute > 59:
        fail(f"{where}: time {text!r} is out of range")
    return f"{hour:02d}:{minute:02d}", hour * 60 + minute


def convert(records):
    if not isinstance(records, list) or len(records) != EXPECTED_ROWS:
        count = len(records) if isinstance(records, list) else "no"
        fail(f"expected {EXPECTED_ROWS} records, found {count}")

    rows = {}
    for index, record in enumerate(records):
        if not isinstance(record, dict):
            fail(f"record {index} is not an object")
        day = parse_date(record.get("Date"))
        key = day.isoformat()
        if key in rows:
            fail(f"duplicate date {key}")
        times = {}
        previous = -1
        for column, kind in COLUMNS:
            if column not in record:
                fail(f"{key}: missing column {column}")
            text, minutes = parse_time(record[column], f"{key} {column}")
            if minutes <= previous:
                fail(f"{key}: {column} {text} doesn't follow the previous prayer")
            previous = minutes
            times[kind] = text
        # The Day column is inconsistent ("Thurs", "Tues") and is ignored.
        rows[key] = times

    first = datetime.date(YEAR, 1, 1)
    for offset in range(EXPECTED_ROWS):
        key = (first + datetime.timedelta(days=offset)).isoformat()
        if key not in rows:
            fail(f"no row for {key}")
    return [(key, rows[key]) for key in sorted(rows)]


def render(rows):
    kinds = [kind for _, kind in COLUMNS]
    lines = [
        "{",
        '  "expectedKinds": ' + json.dumps(kinds) + ",",
        '  "rows": [',
    ]
    for position, (day, times) in enumerate(rows):
        row = {"day": day, "times": times}
        comma = "," if position < len(rows) - 1 else ""
        lines.append("    " + json.dumps(row, separators=(", ", ": ")) + comma)
    lines += ["  ]", "}", ""]
    return "\n".join(lines)


def main(argv):
    if len(argv) != 3:
        sys.exit("usage: convert-muis.py <datastore-response.json> <output.json>")
    with open(argv[1], encoding="utf-8") as handle:
        response = json.load(handle)
    if not isinstance(response, dict) or response.get("success") is not True:
        fail("the response doesn't report success")
    result = response.get("result")
    if not isinstance(result, dict):
        fail("the response has no result object")
    rows = convert(result.get("records"))
    with open(argv[2], "w", encoding="utf-8") as handle:
        handle.write(render(rows))
    print(f"convert-muis: wrote {len(rows)} rows, {rows[0][0]} to {rows[-1][0]}, to {argv[2]}")


if __name__ == "__main__":
    main(sys.argv)
