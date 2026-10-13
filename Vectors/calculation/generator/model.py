"""An independent model of RFC 0002 (CalculationSource) and RFC 0001 sections 4.6-4.8.

Written from the RFCs alone. Instants come from SalahTimes' Python reference
(Vectors/reference/salahtimes_reference.py in a SalahTimes 0.1.0 checkout, whose Vectors folder
SALAHTIMES_VECTORS names). Instants are POSIX seconds.
"""

import math
import os
import sys
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

SALAHTIMES_VECTORS = os.environ.get("SALAHTIMES_VECTORS")
if not SALAHTIMES_VECTORS:
    raise SystemExit("Set SALAHTIMES_VECTORS to the Vectors folder of a SalahTimes 0.1.0 checkout.")
sys.path.insert(0, os.path.join(SALAHTIMES_VECTORS, "reference"))
import salahtimes_reference as ref  # noqa: E402

KINDS = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]
PRAYERS = [k for k in KINDS if k != "sunrise"]
KIND_INDEX = {k: i for i, k in enumerate(KINDS)}
REASONS = ["noPublishedData", "calculationUnavailable", "invalidData", "unresolvedWallTime"]
LEAD = 12 * 3600
EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)

# The smallest distance, in seconds, between an unrounded time and a rounding boundary that
# a vector accepts. The reference matches the Swift engine within 0.51 s before rounding.
ROUNDING_MARGIN = 1.0


# ---------------------------------------------------------------------------------------------
# Civil days and zones (RFC 0001 section 4.1)
# ---------------------------------------------------------------------------------------------


def local_naive(t, zone):
    return datetime.fromtimestamp(t, tz=zone).replace(tzinfo=None)


def civil(t, zone):
    """The civil day containing instant t."""
    return local_naive(t, zone).date()


def start(day, zone):
    """Local midnight with repeated: earlier, nonexistent: nextValid."""
    target = datetime(day.year, day.month, day.day)
    candidates = []
    for fold in (0, 1):
        t = datetime(day.year, day.month, day.day, tzinfo=zone, fold=fold).timestamp()
        if local_naive(t, zone) == target:
            candidates.append(t)
    if candidates:
        return min(candidates)
    # Nonexistent: the first instant whose local time is after the target.
    lo = datetime(day.year, day.month, day.day, tzinfo=timezone.utc).timestamp() - 86400 * 2
    hi = lo + 86400 * 4
    assert local_naive(lo, zone) < target and local_naive(hi, zone) > target
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if local_naive(mid, zone) < target:
            lo = mid
        else:
            hi = mid
    return hi


def iso(t, zone):
    """An instant written with the zone's offset, to the second (or millisecond)."""
    dt = datetime.fromtimestamp(t, tz=zone)
    if dt.utcoffset().total_seconds() % 60:
        # Local mean time: write the instant in UTC instead of an offset with seconds.
        dt = datetime.fromtimestamp(t, tz=timezone.utc)
        return dt.isoformat(timespec="seconds").replace("+00:00", "Z")
    if abs(t - round(t)) > 1e-9:
        text = dt.isoformat(timespec="milliseconds")
    else:
        text = dt.isoformat(timespec="seconds")
    return text


# ---------------------------------------------------------------------------------------------
# The calculated source (RFC 0002 section 4)
# ---------------------------------------------------------------------------------------------


class Location:
    def __init__(self, latitude, longitude, zone, name=None, country=None):
        self.latitude = latitude
        self.longitude = longitude
        self.zone_name = zone
        self.zone = ZoneInfo(zone)
        self.name = name
        self.country = country

    def json(self):
        out = {"latitude": self.latitude, "longitude": self.longitude, "timeZone": self.zone_name}
        if self.country:
            out["countryCode"] = self.country
        if self.name:
            out["name"] = self.name
        return out


class Fragile(Exception):
    pass


# Every calculated day whose rounding is fragile; a generator must find this empty.
FRAGILE = []


def valid_date(y, m, d):
    try:
        date(y, m, d)
        return True
    except ValueError:
        return False


class Unavailable:
    def __init__(self, reason):
        self.reason = reason

    def __repr__(self):
        return f"unavailable({self.reason})"


class Available:
    """An owning day: events {kind: instant}, missing {kind: reason}."""

    def __init__(self, day, events, missing):
        self.day = day
        self.events = events
        self.missing = missing

    def __repr__(self):
        return f"available({self.day}, {sorted(self.events, key=KIND_INDEX.get)}, {self.missing})"


def check_rounding(result, params, note, names):
    mode = params.get("rounding", "nearest")
    if mode == "none":
        raise Fragile(f"{note}: rounding none can't be compared to the millisecond")
    for name in names:
        value = result.unrounded[name]
        if not ref.occurs(value):
            continue
        if mode == "nearest":
            distance = abs((value % 60) - 30)
        else:
            r = value % 60
            distance = min(r, 60 - r)
        if distance < ROUNDING_MARGIN:
            FRAGILE.append((note, name, result.events[name], distance))


def calculate(X, loc, params):
    """RFC 0002 section 4.3. Returns ('fail', reason) or ('ok', kept, missing, raw)."""
    Z = loc.zone
    if start(X + timedelta(days=1), Z) <= start(X, Z):
        return ("fail", "calculationUnavailable")
    try:
        result = ref.prayer_times(loc.latitude, loc.longitude, X, loc.zone_name, params)
    except ref.CalculationError as error:
        if error.case == "unsupportedDate":
            return ("fail", "calculationUnavailable")
        return ("fail", "invalidData")
    lo = start(X, Z) - LEAD
    hi = start(X + timedelta(days=2), Z)
    kept = {}
    missing = {}
    last = None
    raw = {}
    for kind in KINDS:
        value = result.events[kind]
        raw[kind] = value
        if not ref.occurs(value):
            missing[kind] = "calculationUnavailable"
            continue
        if value < lo or value >= hi:
            missing[kind] = "calculationUnavailable"
            continue
        if last is not None and not value > last:
            missing[kind] = "calculationUnavailable"
            continue
        kept[kind] = value
        last = value
    return ("ok", kept, missing, result)


class CalculationSource:
    def __init__(self, params):
        self.params = params
        self.cache = {}

    def prayer_day(self, D, loc):
        """RFC 0002 section 4.2. D is (y, m, d) or a date."""
        if isinstance(D, tuple):
            if not valid_date(*D):
                return Unavailable("invalidData")
            D = date(*D)
        key = (D, loc.latitude, loc.longitude, loc.zone_name)
        if key in self.cache:
            return self.cache[key]
        answer = self._prayer_day(D, loc)
        self.cache[key] = answer
        return answer

    def _prayer_day(self, D, loc):
        today = calculate(D, loc, self.params)
        if today[0] == "fail":
            return Unavailable(today[1])
        _, kept, missing, _ = today
        kept = dict(kept)
        missing = dict(missing)
        check_rounding(today[3], self.params, f"{loc.name} {D}", list(kept))
        # Step 3: no time of D after a time of a later day. A later day's times start at
        # start - LEAD, so only the days that start less than LEAD after D's latest time count.
        first = None
        latest = max(kept.values()) if kept else None
        offset = 1
        while latest is not None:
            try:
                later = D + timedelta(days=offset)
                if start(later, loc.zone) - LEAD >= latest:
                    break
                following = calculate(later, loc, self.params)
            except OverflowError:
                break
            if following[0] == "ok" and following[1]:
                first_kind = min(following[1], key=following[1].get)
                check_rounding(following[3], self.params, f"{loc.name} {later}", [first_kind])
                value = following[1][first_kind]
                first = value if first is None else min(first, value)
            offset += 1
        if first is not None:
            for kind in list(kept):
                if kept[kind] > first:
                    del kept[kind]
                    missing[kind] = "calculationUnavailable"
        if not kept:
            return Unavailable("calculationUnavailable")
        return Available(D, kept, missing)


# ---------------------------------------------------------------------------------------------
# The schedule (RFC 0001 sections 4.3, 4.5-4.8)
# ---------------------------------------------------------------------------------------------


class Event:
    def __init__(self, day, kind, time, iqama=None, observance="ordinary"):
        self.day = day
        self.kind = kind
        self.time = time
        self.iqama = iqama
        self.observance = observance

    @property
    def id(self):
        return f"{self.day}/{self.kind}/{self.time}"

    def order(self):
        return (self.time, self.day, KIND_INDEX[self.kind])

    def ref(self, zone):
        return {
            "day": str(self.day),
            "kind": self.kind,
            "time": iso(self.time, zone),
            "iqama": None if self.iqama is None else iso(self.iqama, zone),
            "observance": self.observance,
        }

    def __repr__(self):
        return self.id


class Gap:
    def __init__(self, lo, hi, day, kinds, reason):
        self.lo, self.hi, self.day, self.kinds, self.reason = lo, hi, day, set(kinds), reason

    def key(self):
        return (self.lo, self.hi, self.day, tuple(sorted(self.kinds, key=KIND_INDEX.get)), self.reason)

    def __repr__(self):
        return f"Gap({self.lo}, {self.hi}, {self.day}, {sorted(self.kinds)}, {self.reason})"


class Schedule:
    def __init__(self, source, loc, iqama=None):
        self.source = source
        self.loc = loc
        self.zone = loc.zone
        self.iqama = iqama or {}

    def start(self, d):
        return start(d, self.zone)

    def day(self, D):
        """The checked day: ('unavailable', reason) or ('available', [Event], missing)."""
        answer = self.source.prayer_day(D, self.loc)
        if isinstance(answer, Unavailable):
            return ("unavailable", answer.reason)
        D = answer.day
        # Rule 4: [start(D) - lead, start(D + 2)); rule 5: strictly increasing.
        lo = self.start(D) - LEAD
        hi = self.start(D + timedelta(days=2))
        times = [answer.events[k] for k in KINDS if k in answer.events]
        assert all(lo <= t < hi for t in times), f"rule 4 violated on {D}"
        assert all(a < b for a, b in zip(times, times[1:])), f"rule 5 violated on {D}"
        events = []
        for kind in KINDS:
            if kind not in answer.events:
                continue
            t = answer.events[kind]
            events.append(Event(D, kind, t, self._iqama(D, kind, t), "ordinary"))
        events.sort(key=lambda e: e.time)
        return ("available", events, dict(answer.missing))

    def _iqama(self, D, kind, t):
        """IqamaRules (RFC 0001 section 4.5), `after` only; observance is always ordinary."""
        rule = self.iqama.get("rules", {}).get(kind)
        if kind == "sunrise" or rule is None:
            return None
        assert "after" in rule, "the model supports only `after` rules"
        minutes = rule["after"]
        if minutes < 0:
            return None
        value = t + minutes * 60
        if not (t <= value < self.start(D + timedelta(days=2))):
            return None
        return value

    # Context and windows (section 4.6) ------------------------------------------------------

    def context_days(self, a, b):
        first = civil(a, self.zone) - timedelta(days=2)
        last = civil(b + LEAD, self.zone)
        days = []
        d = first
        while d <= last:
            days.append(d)
            d += timedelta(days=1)
        return days

    def context(self, a, b):
        days = self.context_days(a, b)
        answers = {d: self.day(d) for d in days}
        events = []
        for d in days:
            if answers[d][0] == "available":
                events += answers[d][1]
        events.sort(key=Event.order)
        gaps = []
        for i, d in enumerate(days):
            answer = answers[d]
            if answer[0] == "available":
                known = {e.kind: e.time for e in answer[1]}
                missing = answer[2]
            else:
                known = {}
                missing = {k: answer[1] for k in KINDS}
            prev_times = (
                [e.time for e in answers[days[i - 1]][1]]
                if i > 0 and answers[days[i - 1]][0] == "available"
                else []
            )
            next_times = (
                [e.time for e in answers[days[i + 1]][1]]
                if i + 1 < len(days) and answers[days[i + 1]][0] == "available"
                else []
            )
            groups = {}
            for kind, reason in missing.items():
                lo = max(
                    [self.start(d) - LEAD]
                    + [t for k, t in known.items() if KIND_INDEX[k] < KIND_INDEX[kind]]
                    + prev_times
                )
                hi = min(
                    [self.start(d + timedelta(days=2))]
                    + [t for k, t in known.items() if KIND_INDEX[k] > KIND_INDEX[kind]]
                    + next_times
                )
                if lo >= hi:
                    continue
                groups.setdefault((lo, hi, reason), set()).add(kind)
            for (lo, hi, reason), kinds in groups.items():
                gaps.append(Gap(lo, hi, d, kinds, reason))
        # Overlap gaps (rule 6): each available day against the next available one.
        available = [d for d in days if answers[d][0] == "available"]
        for this_day, next_day in zip(available, available[1:]):
            x, y = answers[this_day], answers[next_day]
            first_next = min(e.time for e in y[1])
            last_this = max(e.time for e in x[1])
            if last_this > first_next:
                raise AssertionError(f"a calculated source overlaps {this_day} and {next_day}")
                kinds = {e.kind for e in x[1] if e.time > first_next}
                gaps.append(Gap(first_next, last_this, this_day, kinds, "invalidData"))
        return events, gaps

    def coverage(self, a, b, gaps):
        assert a < b, "the model supports only positive-length requests"
        clipped = []
        for g in gaps:
            lo, hi = max(g.lo, a), min(g.hi, b)
            if lo < hi:
                clipped.append(Gap(lo, hi, g.day, g.kinds, g.reason))
        clipped.sort(key=lambda g: (g.lo, g.day, REASONS.index(g.reason)))
        # [a, b] minus the union of [lo, hi).
        known = []
        cursor = a
        for g in sorted(clipped, key=lambda g: g.lo):
            if g.lo > cursor:
                known.append((cursor, g.lo))
            cursor = max(cursor, g.hi)
        if cursor < b:
            known.append((cursor, b))
        return {"requested": (a, b), "known": known, "gaps": clipped}

    def coverage_json(self, coverage):
        Z = self.zone
        return {
            "requested": [iso(coverage["requested"][0], Z), iso(coverage["requested"][1], Z)],
            "known": [[iso(x, Z), iso(y, Z)] for x, y in coverage["known"]],
            "gaps": [
                {
                    "start": iso(g.lo, Z),
                    "end": iso(g.hi, Z),
                    "day": str(g.day),
                    "kinds": sorted(g.kinds, key=KIND_INDEX.get),
                    "reason": g.reason,
                }
                for g in coverage["gaps"]
            ],
        }

    # Queries --------------------------------------------------------------------------------

    def day_json(self, D):
        answer = self.day(D)
        if answer[0] == "unavailable":
            return {"availability": "unavailable", "reason": answer[1]}
        _, events, missing = answer
        d = events[0].day
        coverage = "complete" if not missing else {"partial": dict(sorted(missing.items(), key=lambda x: KIND_INDEX[x[0]]))}
        return {
            "availability": "available",
            "coverage": coverage,
            "isFriday": d.isoweekday() == 5,
            "events": [e.ref(self.zone) for e in events],
        }

    def events_json(self, a, b):
        events, gaps = self.context(a, b)
        chosen = [e for e in events if a <= e.time <= b]
        return {
            "events": [e.ref(self.zone) for e in chosen],
            "coverage": self.coverage_json(self.coverage(a, b, gaps)),
        }

    def raw_state(self, t, b, policy):
        events, gaps = self.context(t, b)
        windows = gaps
        prayer_windows = [w for w in windows if any(k != "sunrise" for k in w.kinds)]

        def latest(candidates, ws):
            past = [e for e in candidates if e.time <= t]
            if not past:
                return None
            p = past[-1]
            if any(w.lo <= t and w.hi > p.time for w in ws):
                return None
            return p

        def earliest(candidates, ws):
            future = [e for e in candidates if t < e.time <= b]
            if not future:
                return None
            n = future[0]
            if any(w.lo < n.time and w.hi > t for w in ws):
                return None
            return n

        prayers = [e for e in events if e.kind != "sunrise"]
        previous = latest(events, windows)
        latest_prayer = latest(prayers, prayer_windows)
        nxt = earliest(events, windows)
        next_prayer = earliest(prayers, prayer_windows)
        approaching_s = max(0, policy.get("approaching", 900))
        just = policy.get("justStarted", {"untilIqama": {"fallback": 900}})
        just_started = None
        just_end = None
        if latest_prayer is not None:
            if "fixed" in just:
                end = latest_prayer.time + max(0, just["fixed"])
            else:
                fallback = max(0, just["untilIqama"]["fallback"])
                end = latest_prayer.iqama if latest_prayer.iqama is not None else latest_prayer.time + fallback
            just_end = end
            if t < end:
                just_started = latest_prayer
        approaching_at = None if next_prayer is None else next_prayer.time - approaching_s
        is_approaching = next_prayer is not None and t >= approaching_at
        available = any(x is not None for x in (previous, latest_prayer, nxt, next_prayer))
        containing = frozenset(g.key() for g in gaps if g.lo <= t < g.hi)
        return {
            "t": t,
            "events": events,
            "gaps": gaps,
            "available": available,
            "previous": previous,
            "latestPrayer": latest_prayer,
            "next": nxt,
            "nextPrayer": next_prayer,
            "justStarted": just_started,
            "justEnd": just_end,
            "approachingAt": approaching_at,
            "isApproaching": is_approaching,
            "containing": containing,
        }

    @staticmethod
    def semantic(s):
        ident = lambda e: None if e is None else e.id
        return (
            s["available"],
            ident(s["previous"]),
            ident(s["latestPrayer"]),
            ident(s["next"]),
            ident(s["nextPrayer"]),
            ident(s["justStarted"]),
            s["isApproaching"],
            s["containing"],
        )

    def state(self, t, b, policy=None):
        policy = policy or {}
        s = self.raw_state(t, b, policy)
        candidates = set()
        for e in s["events"]:
            candidates.add(e.time)
        for g in s["gaps"]:
            candidates.add(g.lo)
            candidates.add(g.hi)
        if s["approachingAt"] is not None:
            candidates.add(s["approachingAt"])
        if s["justEnd"] is not None:
            candidates.add(s["justEnd"])
        # Midnights, as a safety net: the context moves with the instant.
        d = civil(t, self.zone)
        while self.start(d) <= b:
            candidates.add(self.start(d))
            d += timedelta(days=1)
        here = self.semantic(s)
        changes = None
        for c in sorted(x for x in candidates if t < x <= b):
            if self.semantic(self.raw_state(c, b, policy)) != here:
                changes = c
                break
        s["changesAt"] = changes
        s["coverage"] = self.coverage(t, b, s["gaps"])
        return s

    def status(self, s, event):
        same = lambda x: x is not None and x.id == event.id
        if same(s["justStarted"]):
            return "justStarted"
        if event.time <= s["t"]:
            return "passed"
        if same(s["next"]) or (s["next"] is None and same(s["nextPrayer"])):
            approaching = same(s["nextPrayer"]) and s["isApproaching"]
            return "nextApproaching" if approaching else "next"
        return "upcoming"

    def state_json(self, t, b, policy=None, statuses=None, coverage=True):
        s = self.state(t, b, policy)
        Z = self.zone
        out = {"availability": "available" if s["available"] else "unavailable"}
        for name in ("previous", "latestPrayer", "next", "nextPrayer", "justStarted"):
            e = s[name] if s["available"] else None
            out[name] = None if e is None else e.ref(Z)
        out["isApproaching"] = s["isApproaching"] if s["available"] else False
        out["changesAt"] = None if s["changesAt"] is None else iso(s["changesAt"], Z)
        if coverage:
            out["coverage"] = self.coverage_json(s["coverage"])
        if statuses and s["available"]:
            table = {}
            for key in statuses:
                dtext, kind = key.split("/")
                answer = self.day(date.fromisoformat(dtext))
                assert answer[0] == "available"
                event = [e for e in answer[1] if e.kind == kind][0]
                table[key] = self.status(s, event)
            out["statuses"] = table
        return out, s

    def refresh_json(self, s0, e0, policy=None, limit=96, entry_indices=None):
        """`.stateChanges` only."""
        policy = policy or {}
        B = self.start(civil(e0, self.zone) + timedelta(days=2))
        dates = [s0]
        states = []
        c = s0
        while True:
            st = self.state(c, B, policy)
            states.append(st)
            nxt = st["changesAt"]
            if nxt is None or nxt >= e0:
                break
            dates.append(nxt)
            c = nxt
        dates = sorted(set(dates))
        if len(dates) + 1 <= limit:
            kept = dates
            valid_until = e0
        else:
            kept = dates[: limit - 1]
            valid_until = dates[limit - 1]
        Z = self.zone
        out = {
            "dates": [iso(x, Z) for x in kept],
            "validUntil": iso(valid_until, Z),
            "isTruncated": valid_until < e0,
        }
        entries = []
        for index in entry_indices or []:
            if index >= len(kept):
                continue
            st = states[index]
            entry = {"index": index, "date": iso(kept[index], Z)}
            entry["availability"] = "available" if st["available"] else "unavailable"
            for name in ("previous", "latestPrayer", "next", "nextPrayer", "justStarted"):
                e = st[name] if st["available"] else None
                entry[name] = None if e is None else e.ref(Z)
            entry["isApproaching"] = st["isApproaching"] if st["available"] else False
            entry["changesAt"] = None if st["changesAt"] is None else iso(st["changesAt"], Z)
            entry["coverage"] = {"gaps": self.coverage_json(st["coverage"])["gaps"]}
            entries.append(entry)
        out["entries"] = entries
        return out, states, B


def local(loc, y, m, d, hh, mm, ss=0):
    """The instant of a local wall time (must be unambiguous)."""
    dt = datetime(y, m, d, hh, mm, ss, tzinfo=loc.zone)
    t = dt.timestamp()
    assert local_naive(t, loc.zone) == datetime(y, m, d, hh, mm, ss), "ambiguous local time"
    t1 = datetime(y, m, d, hh, mm, ss, tzinfo=loc.zone, fold=1).timestamp()
    assert t == t1, "repeated local time"
    return t
