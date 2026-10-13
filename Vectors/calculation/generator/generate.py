"""Generates Vectors/calculation/*.json from model.py (RFC 0001/0002) and SalahTimes' reference.

Usage: SALAHTIMES_VECTORS=<SalahTimes 0.1.0 checkout>/Vectors python3 generate.py <output-folder>
"""

import json
import os
import sys
from datetime import date, timedelta

from model import (
    FRAGILE, KINDS, SALAHTIMES_VECTORS, CalculationSource, Location, Schedule, civil, iso, local,
    start,
)

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
METHODS = json.load(open(os.path.join(SALAHTIMES_VECTORS, "methods.json")))["methods"]

REF = "instants from SalahTimes' Python reference (SalahTimes 0.1.0, Vectors/reference/salahtimes_reference.py)"


def P(name, **overrides):
    """A preset's parameters as SalahTimes encodes them, with zero adjustments and an off
    Ramadan rule left out (they decode as their defaults)."""
    p = dict(METHODS[name])
    p.update(overrides)
    for key in ("methodAdjustments", "adjustments"):
        if key in p:
            p[key] = {k: v for k, v in p[key].items() if v != 0}
            if not p[key]:
                del p[key]
    if p.get("ramadanIsha") == "off":
        del p["ramadanIsha"]
    return p


# Places -------------------------------------------------------------------------------------

makkah = Location(21.4225, 39.8262, "Asia/Riyadh", "Makkah", "SA")
cairo = Location(30.0444, 31.2357, "Africa/Cairo", "Cairo", "EG")
istanbul = Location(41.0082, 28.9784, "Europe/Istanbul", "Istanbul", "TR")
london = Location(51.5074, -0.1278, "Europe/London", "London", "GB")
jakarta = Location(-6.2088, 106.8456, "Asia/Jakarta", "Jakarta", "ID")
newyork = Location(40.7128, -74.006, "America/New_York", "New York", "US")
singapore = Location(1.3521, 103.8198, "Asia/Singapore", "Singapore", "SG")
buenosaires = Location(-34.6037, -58.3816, "America/Argentina/Buenos_Aires", "Buenos Aires", "AR")
kashgar = Location(39.4704, 75.9898, "Asia/Shanghai", "Kashgar", "CN")
kazan = Location(55.7963, 49.1088, "Europe/Moscow", "Kazan", "RU")
tromso = Location(69.6492, 18.9553, "Europe/Oslo", "Tromsø", "NO")
oslo = Location(59.9139, 10.7522, "Europe/Oslo", "Oslo", "NO")
rovaniemi = Location(66.5, 25.7, "Europe/Helsinki", "Rovaniemi", "FI")
arctic = Location(66.0, 25.0, "Europe/Helsinki")
beirut = Location(33.8938, 35.5018, "Asia/Beirut", "Beirut", "LB")
apia = Location(-13.8333, -171.7667, "Pacific/Apia", "Apia", "WS")

MWL = P("muslimWorldLeague")
KAZAN = P("muslimWorldLeague", highLatitudeRule="middleOfTheNight")

FILES = {}
DESCRIPTIONS = {
    "ordinary": "Ordinary calculated days at several places and methods: complete days whose instants are SalahTimes' unchanged, and the day, dayContaining, events and state queries over them.",
    "owning-days": "Owning days across midnight in both directions: an Isha after midnight that belongs to the evening before (Kashgar), and a Fajr before midnight that belongs to the next day within the 12-hour lead (Kazan, and a user adjustment at Makkah).",
    "polar": "Polar day and night at Tromsø, and a disabled high-latitude rule at Oslo: the kinds that don't occur are missing with calculationUnavailable, and the schedule's windows cover them.",
    "ordering": "Kinds the contract can't hold in order: a tie (Maghrib and Isha at one instant), an inverted pair (Fajr after sunrise, Isha before Maghrib), and times after an event of a later day: the next day's first event, or the first event of the day after a day without times.",
    "failures": "Every failure of RFC 0002 §4.5: invalid coordinates and parameters, unsupported years, an invalid date, a date the zone skips, a day with nothing left, and a kind outside the owning span.",
    "opt-ins": "The opt-in Ramadan Isha rule, and a Friday whose Dhuhr stays ordinary because a calculated source never declares Jumu'ah.",
    "clock-changes": "Days on which the clock changes: spring forward and fall back in London and New York, and Beirut's skipped midnight.",
    "state-and-refresh": "State and refresh plans across an early-Fajr night, a polar gap, a missing Isha, a disabled high-latitude rule and an ordinary day.",
}


def settings(params):
    return {"parameters": params}


def day_of(text):
    return date.fromisoformat(text)


def check_fragile(vid, lo, hi, expected):
    """Fails when a fragile rounded instant could change the expectation."""
    dump = json.dumps(expected)
    problems = []
    for note, name, t, distance in FRAGILE:
        if (lo is not None and lo - 1800 <= t <= hi + 1800) or str(t) in dump:
            problems.append(f"{note} {name} ({distance:.3f} s)")
        else:
            for zone_text in [iso(t, z) for z in ZONES]:
                if zone_text in dump:
                    problems.append(f"{note} {name} ({distance:.3f} s) appears")
    if problems:
        raise SystemExit(f"{vid}: fragile rounding: {problems}")


ZONES = []


def add(file, case, description, provenance, loc, params, query, iqama=None, policy=None,
        statuses=None, entries=None, through=None):
    FRAGILE.clear()
    if loc.zone not in ZONES:
        ZONES.append(loc.zone)
    schedule = Schedule(CalculationSource(params), loc, iqama)
    Z = loc.zone
    kind = query["type"]
    q = {"type": kind}
    lo = hi = None
    if kind == "day":
        q["day"] = query["day"]
        y, m, d = (int(x) for x in query["day"].split("-"))
        try:
            D = date(y, m, d)
        except ValueError:
            D = (y, m, d)
        if isinstance(D, date):
            expected = schedule.day_json(D)
        else:
            assert schedule.source.prayer_day(D, loc).reason == "invalidData"
            expected = {"availability": "unavailable", "reason": "invalidData"}
    elif kind == "dayContaining":
        t = query["date"]
        q["date"] = iso(t, Z)
        expected = schedule.day_json(civil(t, Z))
        lo = hi = t
    elif kind == "events":
        a, b = query["from"], query["through"]
        q["from"], q["through"] = iso(a, Z), iso(b, Z)
        expected = schedule.events_json(a, b)
        lo, hi = a, b
    elif kind == "state":
        t = query["at"]
        b = query.get("through") or start(civil(t, Z) + timedelta(days=2), Z)
        q["at"], q["through"] = iso(t, Z), iso(b, Z)
        expected, raw = schedule.state_json(t, b, policy, statuses)
        lo, hi = t, (raw["changesAt"] or b)
    elif kind == "refresh":
        a, e = query["from"], query["through"]
        q["from"], q["through"], q["strategy"] = iso(a, Z), iso(e, Z), "stateChanges"
        if "limit" in query:
            q["limit"] = query["limit"]
        expected, states, B = schedule.refresh_json(
            a, e, policy, query.get("limit", 96), entries or [])
        lo, hi = a, e
    else:
        raise ValueError(kind)
    vid = f"calculation.{file}.{case}"
    check_fragile(vid, lo, hi, expected)
    vector = {
        "id": vid,
        "description": description,
        "provenance": provenance,
        "input": {"location": loc.json(), "settings": settings(params)},
        "expected": expected,
    }
    if iqama is not None:
        vector["input"]["iqama"] = iqama
    if policy is not None:
        vector["input"]["policy"] = policy
    vector["input"]["query"] = q
    FILES.setdefault(file, []).append(vector)
    return expected


# JSON output --------------------------------------------------------------------------------


def dumps(value, indent=0, width=100):
    compact = json.dumps(value, ensure_ascii=False, separators=(", ", ": "))
    if len(compact) + indent <= width or not isinstance(value, (dict, list)) or not value:
        return compact
    pad = " " * (indent + 2)
    if isinstance(value, dict):
        items = [f"{pad}{json.dumps(k, ensure_ascii=False)}: {dumps(v, indent + 2, width)}" for k, v in value.items()]
        return "{\n" + ",\n".join(items) + "\n" + " " * indent + "}"
    items = [f"{pad}{dumps(v, indent + 2, width)}" for v in value]
    return "[\n" + ",\n".join(items) + "\n" + " " * indent + "]"


def write():
    os.makedirs(OUT, exist_ok=True)
    ids = []
    for file, vectors in FILES.items():
        ids += [v["id"] for v in vectors]
        document = {"schemaVersion": 1, "description": DESCRIPTIONS[file], "vectors": vectors}
        with open(os.path.join(OUT, f"{file}.json"), "w") as handle:
            handle.write(dumps(document) + "\n")
        print(f"{file}.json: {len(vectors)} vectors")
    assert len(ids) == len(set(ids)), "duplicate ids"
    print(f"total: {len(ids)}")


exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "cases.py")).read())

write()
