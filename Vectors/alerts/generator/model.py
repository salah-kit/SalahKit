"""A model of RFC 0003 (SalahAlerts) for generating vectors, independent of the Swift code.

It holds three parts:
- the parts of SalahCore's schedule the planner reads (RFC 0001 §4.4 and §4.6): owning days,
  the events of a closed interval, and the missing-event windows clipped to it;
- the planner (RFC 0003 §4.3 and §4.4): the alert schedule and the notification plan;
- the scheduler (RFC 0003 §4.5) against a modelled notification center.

Instants are timezone-aware datetimes. Durations are whole seconds.
"""

from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

KINDS = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]
ORDER = {k: i for i, k in enumerate(KINDS)}
ALERT_KINDS = ["atTime", "before", "after"]
ALERT_ORDER = {k: i for i, k in enumerate(ALERT_KINDS)}
REASONS = ["noPublishedData", "calculationUnavailable", "invalidData", "unresolvedWallTime"]
REASON_ORDER = {r: i for i, r in enumerate(REASONS)}
SECOND = timedelta(seconds=1)
LIMIT = 7 * 86400  # AlertPlanner.reminderOffsetLimit


def parse_instant(text):
    value = datetime.fromisoformat(text.replace("Z", "+00:00"))
    assert value.tzinfo is not None, text
    return value


def iso(instant, zone):
    """An instant written in the zone's offset, as the vectors write them, with milliseconds
    only when it has a fraction of a second."""
    local = instant.astimezone(zone)
    return local.isoformat(timespec="milliseconds" if local.microsecond else "seconds")


def day_text(day):
    return day.isoformat()


# SalahCore -----------------------------------------------------------------------------------


@dataclass(frozen=True)
class Event:
    day: date
    kind: str
    time: datetime
    observance: str = "ordinary"

    def sort_key(self):
        return (self.time, self.day, ORDER[self.kind])


@dataclass
class Day:
    """A checked day: its events and the reasons of its missing expected kinds, or a reason for
    the whole day."""

    events: list = field(default_factory=list)
    missing: dict = field(default_factory=dict)
    unavailable: str = None


class Timetable:
    """TimetableSource rows (RFC 0001 §4.4) in a zone without clock changes in the vectors' range.

    A row: {"day": "YYYY-MM-DD", "times": {kind: "HH:MM" | "HH:MM+1" | instant},
    "observances": {"dhuhr": "jumuah"}}.
    """

    lead = 0

    def __init__(self, zone, expected, rows):
        self.zone = zone
        self.expected = list(expected)
        self.rows = {date.fromisoformat(r["day"]): r for r in rows}
        self.json = {"expectedKinds": list(expected), "rows": rows}

    def resolve(self, day, text):
        if "T" in text:
            return parse_instant(text)
        offset = 0
        if "+" in text:
            text, extra = text.split("+")
            offset = int(extra)
        hour, minute = (int(x) for x in text.split(":"))
        local = datetime.combine(day + timedelta(days=offset), time(hour, minute))
        aware = local.replace(tzinfo=self.zone)
        # The vectors avoid clock changes: the wall time must exist exactly once.
        roundtrip = aware.astimezone(timezone.utc).astimezone(self.zone)
        assert roundtrip.replace(tzinfo=None) == local, (day, text)
        assert local.replace(tzinfo=self.zone, fold=1).utcoffset() == aware.utcoffset(), (day, text)
        return aware

    def day(self, day):
        row = self.rows.get(day)
        if row is None or not row["times"]:
            return Day(unavailable="noPublishedData")
        observances = row.get("observances", {})
        events = []
        for kind in KINDS:
            if kind in row["times"]:
                events.append(
                    Event(day, kind, self.resolve(day, row["times"][kind]),
                          observances.get(kind, "ordinary")))
        events.sort(key=lambda e: e.time)
        # The vectors' rows are valid: in canonical order, within [start(D), start(D+2)).
        for a, b in zip(events, events[1:]):
            assert ORDER[a.kind] < ORDER[b.kind] and a.time < b.time, (day, a, b)
        for e in events:
            assert start(day, self.zone) <= e.time < start(day + timedelta(days=2), self.zone)
        missing = {k: "noPublishedData" for k in self.expected if k not in row["times"]}
        return Day(events=events, missing=missing)


class FixedDays:
    """A source given as checked days, for a calculated source whose instants the vectors take
    from SalahKit's calculation vectors (which come from SalahTimes' reference)."""

    def __init__(self, zone, expected, lead, days, json):
        self.zone = zone
        self.expected = list(expected)
        self.lead = lead
        self.days = days
        self.json = json

    def day(self, day):
        events = self.days.get(day)
        assert events is not None, f"the vector reads {day}, which the model doesn't hold"
        return Day(events=[Event(day, k, t) for k, t in events])


def start(day, zone):
    return datetime.combine(day, time(0, 0)).replace(tzinfo=zone)


def civil(instant, zone):
    return instant.astimezone(zone).date()


def schedule_events(source, a, b):
    """events(from: a, through: b): the known events in [a, b] and the gaps of the context's
    missing-event windows clipped to [a, b) (RFC 0001 §4.6). The vectors' data has no
    contradictions between days, so there are no overlap gaps."""
    zone = source.zone
    lead = timedelta(seconds=source.lead)
    first = civil(a, zone) - timedelta(days=2)
    last = civil(b + lead, zone)
    days = []
    d = first
    while d <= last:
        days.append(d)
        d += timedelta(days=1)
    checked = [source.day(d) for d in days]
    events = sorted((e for c in checked for e in c.events), key=Event.sort_key)

    windows = {}
    for index, d in enumerate(days):
        c = checked[index]
        missing = ({k: c.unavailable for k in source.expected} if c.unavailable else c.missing)
        for kind, reason in missing.items():
            lo = start(d, zone) - lead
            hi = start(d + timedelta(days=2), zone)
            for e in c.events:
                if ORDER[e.kind] < ORDER[kind]:
                    lo = max(lo, e.time)
                if ORDER[e.kind] > ORDER[kind]:
                    hi = min(hi, e.time)
            if index > 0:
                for e in checked[index - 1].events:
                    lo = max(lo, e.time)
            if index + 1 < len(days):
                for e in checked[index + 1].events:
                    hi = min(hi, e.time)
            if lo < hi:
                windows.setdefault((lo, hi, d, reason), set()).add(kind)

    gaps = []
    for (lo, hi, d, reason), kinds in windows.items():
        clo, chi = max(lo, a), min(hi, b)
        if clo < chi:
            gaps.append({"start": clo, "end": chi, "day": d, "kinds": kinds, "reason": reason})
    gaps.sort(key=lambda g: (g["start"], g["day"], REASON_ORDER[g["reason"]], g["end"]))
    return [e for e in events if a <= e.time <= b], gaps


# Settings ------------------------------------------------------------------------------------


class PlanningError(Exception):
    def __init__(self, value):
        super().__init__(value)
        self.value = value


def settings_for(table, subject_day, prayer, observance):
    """The vectors' settings table (Vectors/README.md): a day's own table if it has one, else
    the top level; Jumu'ah uses `jumuah`, or Dhuhr's settings when there's no `jumuah` key."""
    level = table.get("days", {}).get(day_text(subject_day), table)
    if observance == "jumuah" and "jumuah" in level:
        return level["jumuah"]
    return level.get("kinds", {}).get(prayer)


def offsets(settings):
    """The enabled alert kinds of a settings value, with their offsets in seconds and sounds."""
    if settings is None:
        return []
    result = []
    if settings.get("atTime", True):
        result.append(("atTime", 0, settings.get("sound", "system")))
    if settings.get("before") is not None:
        result.append(("before", -settings["before"], settings.get("beforeSound", "system")))
    if settings.get("after") is not None:
        result.append(("after", settings["after"], settings.get("afterSound", "system")))
    return result


def check(settings, subject, maximum):
    if settings is None:
        return
    for kind in ("before", "after"):
        value = settings.get(kind)
        if value is not None and not (0 < value <= maximum):
            raise PlanningError({"reminderOffsetOutOfRange": {
                "day": day_text(subject[0]), "prayer": subject[1], "observance": subject[2],
                "kind": kind, "offset": value}})


def identity_key(alert):
    return (alert["day"], ORDER[alert["prayer"]], ALERT_ORDER[alert["kind"]])


def alert_key(alert):
    return (alert["fireDate"],) + identity_key(alert)


def valid_namespace(namespace):
    return namespace != "" and "/" not in namespace


# The alert schedule (RFC 0003 §4.3) ----------------------------------------------------------


def alert_schedule(source, namespace, start_, end_, maximum, table):
    if not valid_namespace(namespace):
        raise PlanningError({"invalidNamespace": namespace})
    if not (0 <= maximum <= LIMIT):
        raise PlanningError({"invalidMaximumReminderOffset": maximum})
    end_ = max(end_, start_)
    m = timedelta(seconds=maximum)
    events, source_gaps = schedule_events(source, start_ - m, end_ + m)

    alerts = []
    for e in events:
        subject = (e.day, e.kind, e.observance)
        s = settings_for(table, *subject)
        check(s, subject, maximum)
        for kind, offset, sound in offsets(s):
            fire = e.time + timedelta(seconds=offset)
            if start_ <= fire < end_:
                alerts.append({"day": e.day, "prayer": e.kind, "kind": kind, "fireDate": fire,
                               "event": e.time, "observance": e.observance, "sound": sound})
    alerts.sort(key=alert_key)

    grouped = {}
    for g in source_gaps:
        for prayer in sorted(g["kinds"], key=ORDER.get):
            observances = ["ordinary"]
            if prayer == "dhuhr" and g["day"].isoweekday() == 5:
                observances.append("jumuah")
            for observance in observances:
                subject = (g["day"], prayer, observance)
                s = settings_for(table, *subject)
                check(s, subject, maximum)
                for kind, offset, _ in offsets(s):
                    lo = max(g["start"] + timedelta(seconds=offset), start_)
                    hi = min(g["end"] + timedelta(seconds=offset), end_)
                    if lo < hi:
                        grouped.setdefault((lo, hi, kind, g["day"], g["reason"]), set()).add(prayer)
    gaps = [{"start": lo, "end": hi, "kind": kind, "day": d, "prayers": prayers, "reason": reason}
            for (lo, hi, kind, d, reason), prayers in grouped.items()]
    gaps.sort(key=lambda g: (g["start"], g["day"], ALERT_ORDER[g["kind"]],
                             REASON_ORDER[g["reason"]], g["end"]))
    return {"requested": (start_, end_), "alerts": alerts, "gaps": gaps}


# The notification plan (RFC 0003 §4.4) -------------------------------------------------------


def notification_plan(schedule, now, budget):
    max_pending = max(0, budget["maxPending"])
    near = timedelta(seconds=max(0, budget["nearTermWindow"]))
    horizon = timedelta(seconds=max(0, budget["horizon"]))
    requested_start, requested_end = schedule["requested"]
    effective_end = max(now, min(requested_end, now + horizon))
    near_end = min(now + near, effective_end)

    in_range = [a for a in schedule["alerts"] if now <= a["fireDate"] < effective_end]
    near_term = [a for a in in_range if a["fireDate"] < near_end]
    if len(near_term) > max_pending:
        selected = near_term[:max_pending]
    else:
        later = [a for a in in_range if a["fireDate"] >= near_end and a["kind"] == "atTime"]
        selected = near_term + later[: max_pending - len(near_term)]
    selected.sort(key=alert_key)
    chosen = {id(a) for a in selected}

    kinds = {a["kind"] for a in schedule["alerts"]} | {g["kind"] for g in schedule["gaps"]}
    coverage = {}
    for kind in kinds:
        if requested_start > now:
            coverage[kind] = now
            continue
        cutoff = effective_end
        for a in in_range:
            if a["kind"] == kind and id(a) not in chosen:
                cutoff = min(cutoff, a["fireDate"])
                break
        for g in schedule["gaps"]:
            if g["kind"] == kind and g["start"] < effective_end and g["end"] > now:
                cutoff = min(cutoff, max(now, g["start"]))
        coverage[kind] = cutoff
    if requested_start > now:
        covered = now
    else:
        covered = min([effective_end] + list(coverage.values()))
    omitted = [a for a in in_range if id(a) not in chosen]
    return {"effectiveRange": (now, effective_end), "alerts": selected, "coveredUntil": covered,
            "coverageByKind": coverage, "omitted": omitted}


# The scheduler (RFC 0003 §4.5) ---------------------------------------------------------------


@dataclass
class Request:
    id: str
    fire: datetime  # None for an immediate request
    title: str
    body: str
    thread: str


class Superseded(Exception):
    pass


class Center:
    """The modelled notification center of Vectors/README.md (Reconciliation)."""

    def __init__(self, spec, clock):
        self.authorization = spec.get("authorization", "authorized")
        self.pending = {}
        for r in spec.get("pending", []):
            self.pending[r["id"]] = Request(r["id"], parse_instant(r["fireDate"]), r["title"],
                                            r["body"], r.get("thread", ""))
        self.delivered = [(d["id"], parse_instant(d["date"])) for d in spec.get("delivered", [])]
        self.fail_adds = set(spec.get("failAdds", []))
        self.ignore_adds = set(spec.get("ignoreAdds", []))
        self.drop_adds = set(spec.get("dropAdds", []))
        self.fail_reads = set(spec.get("failReads", []))
        self.reads = 0
        self.calls = []
        self.clock = clock
        # Supersession: once `limit` calls of the current batch have finished, the batch's
        # next check finds a later plan and stops (RFC 0003 §4.5, the update pump).
        self.limit = None
        self.batch_calls = 0

    def begin_batch(self, limit=None):
        self.limit = limit
        self.batch_calls = 0

    def call(self):
        if self.limit is not None and self.batch_calls >= self.limit:
            raise Superseded()
        self.batch_calls += 1

    def record_delivery(self, rid, when):
        """A delivered notification replaces an older one with the same identifier."""
        self.delivered = [d for d in self.delivered if d[0] != rid]
        self.delivered.append((rid, when))

    def deliver_due(self):
        due = sorted((r.fire, rid) for rid, r in self.pending.items() if r.fire <= self.clock.value)
        for fire, rid in due:
            del self.pending[rid]
            self.record_delivery(rid, fire)

    def authorization_status(self):
        self.call()
        self.calls.append("authorizationStatus")
        return self.authorization

    def pending_requests(self, read_back=False):
        self.call()
        self.calls.append("pendingRequests")
        self.reads += 1
        if read_back:
            self.clock.advance_to_read_back()
        self.deliver_due()
        if self.reads in self.fail_reads:
            return None
        return dict(self.pending)

    def delivered_records(self):
        self.call()
        self.calls.append("deliveredNotifications")
        return list(self.delivered)

    def remove_pending(self, ids):
        self.call()
        self.calls.append({"removePending": ids})
        for rid in ids:
            self.pending.pop(rid, None)

    def remove_delivered(self, ids):
        self.call()
        self.calls.append({"removeDelivered": ids})
        self.delivered = [d for d in self.delivered if d[0] not in ids]

    def add(self, request):
        self.call()
        if request.fire is None:
            self.calls.append({"addImmediate": request.id})
        else:
            self.calls.append({"add": request.id, "fireDate": request.fire})
        if request.id in self.fail_adds:
            return "addFailed"
        if request.id in self.ignore_adds:
            return None
        if request.id in self.drop_adds:
            self.pending.pop(request.id, None)
            return None
        if request.fire is None:
            self.record_delivery(request.id, self.clock.value)
        else:
            self.pending[request.id] = request
        return None


class Clock:
    def __init__(self, start_, read_back=None):
        self.value = start_
        self.read_back = read_back or start_

    def advance_to_read_back(self):
        self.value = self.read_back


ALLOWED = {"authorized", "provisional", "ephemeral"}


def parse_identity(identifier, prefix, namespace):
    if not identifier.startswith(prefix):
        return None
    parts = identifier[len(prefix):].split("/")
    if len(parts) != 4 or not valid_namespace(parts[0]) or parts[0] != namespace:
        return None
    try:
        date.fromisoformat(parts[1])
    except ValueError:
        return None
    if parts[2] not in KINDS or parts[3] not in ALERT_KINDS:
        return None
    return parts


def request_id(scheduler, alert_id, namespace=None):
    return scheduler["identifierPrefix"] + (namespace or scheduler["namespace"]) + "/" + alert_id


def ceil_second(instant):
    """Rounded up to a whole second, ⌈s − 0.001⌉: up to a millisecond past one keeps it."""
    if instant.microsecond > 1000:
        return instant.replace(microsecond=0) + SECOND
    return instant.replace(microsecond=0)


def content(alert, wording, scheduler):
    day, prayer, kind = alert["id"].split("/")
    return prayer, f"{wording} {kind}", scheduler.get("threadIdentifier") or ""


def apply_plan(scheduler, center, plan, wording):
    """One apply batch (RFC 0003 §4.5) without supersession; returns the report."""
    namespace = scheduler["namespace"]
    found = [plan["namespace"]] + [a.get("namespace", plan["namespace"]) for a in plan["alerts"]]
    for value in found:
        if value != namespace:
            return {"error": "namespaceMismatch"}
    if len({a["id"] for a in plan["alerts"]}) != len(plan["alerts"]):
        return {"error": "duplicateIdentity"}
    t = center.clock.value
    desired = [a for a in plan["alerts"] if parse_instant(a["fireDate"]) > t]
    requests = {}
    for a in desired:
        rid = request_id(scheduler, a["id"])
        title, body, thread = content(a, wording, scheduler)
        requests[rid] = Request(rid, ceil_second(parse_instant(a["fireDate"])), title, body, thread)

    try:
        allowed = center.authorization_status() in ALLOWED
        pending = center.pending_requests()
        owned = {}
        if pending is not None:
            owned = {rid: r for rid, r in pending.items()
                     if parse_identity(rid, scheduler["identifierPrefix"], namespace)}
        delivered = None
        retention = scheduler.get("deliveredRetention", 172800)
        if retention is not None:
            retention = max(0, retention)  # A negative retention counts as zero.
            delivered = center.delivered_records()

        obsolete = sorted(owned) if not allowed else sorted(r for r in owned if r not in requests)
        if obsolete:
            center.remove_pending(obsolete)
        if delivered is not None:
            cutoff = t - timedelta(seconds=retention)
            expired = sorted(rid for rid, when in delivered
                             if parse_identity(rid, scheduler["identifierPrefix"], namespace)
                             and when < cutoff)
            if expired:
                center.remove_delivered(expired)
    except Superseded:
        return {"superseded": True, "verifiedAt": center.clock.value, "confirmed": [],
                "failures": {}, "confirmedCoveredUntil": None}

    failures = {}
    if not allowed:
        failures = {a["id"]: "notAuthorized" for a in desired}
    try:
        if allowed:
            for a in desired:
                rid = request_id(scheduler, a["id"])
                r = requests[rid]
                if rid in owned and owned[rid] == r:
                    continue
                if center.add(r) == "addFailed":
                    failures[a["id"]] = "addFailed"
        read = center.pending_requests(read_back=True)
    except Superseded:
        return {"superseded": True, "verifiedAt": center.clock.value, "confirmed": [],
                "failures": failures, "confirmedCoveredUntil": None}

    verified = center.clock.value
    report = {"superseded": False, "verifiedAt": verified}
    if read is None:
        for a in desired:
            if parse_instant(a["fireDate"]) > verified:
                failures.setdefault(a["id"], "unconfirmed")
        report.update(confirmed=[], failures=failures, confirmedCoveredUntil=None)
        return report
    confirmed = []
    first_unconfirmed = None
    for a in desired:
        fire = parse_instant(a["fireDate"])
        if fire <= verified:
            continue
        rid = request_id(scheduler, a["id"])
        if allowed and rid in read and read[rid] == requests[rid]:
            confirmed.append({"id": a["id"], "fireDate": fire})
            failures.pop(a["id"], None)
            continue
        failures.setdefault(a["id"], "unconfirmed")
        if first_unconfirmed is None or fire < first_unconfirmed:
            first_unconfirmed = fire
    covered = parse_instant(plan["coveredUntil"])
    if first_unconfirmed is not None:
        covered = min(covered, first_unconfirmed)
    report.update(confirmed=confirmed, failures=failures,
                  confirmedCoveredUntil=max(verified, covered))
    return report


def deliver_alerts(scheduler, center, alerts, wording):
    namespace = scheduler["namespace"]
    for a in alerts:
        if a.get("namespace", namespace) != namespace:
            return {"error": "namespaceMismatch"}
    if len({a["id"] for a in alerts}) != len(alerts):
        return {"error": "duplicateIdentity"}

    def order(alert):
        day, prayer, kind = alert["id"].split("/")
        return (parse_instant(alert["fireDate"]), day, ORDER[prayer], ALERT_ORDER[kind])

    ordered = sorted(alerts, key=order)
    if center.authorization_status() not in ALLOWED:
        return {"posted": [], "skipped": [], "failures": {a["id"]: "notAuthorized" for a in ordered}}
    pending = center.pending_requests() or {}
    delivered = center.delivered_records()
    posted, skipped, failures = [], [], {}
    for a in ordered:
        rid = request_id(scheduler, a["id"])
        fire = parse_instant(a["fireDate"])
        occurrence = {"id": a["id"], "fireDate": fire}
        if rid in pending or any(d == rid and when >= fire - timedelta(seconds=1.5)
                                 for d, when in delivered):
            skipped.append(occurrence)
            continue
        title, body, thread = content(a, wording, scheduler)
        if center.add(Request(rid, None, title, body, thread)) == "addFailed":
            failures[a["id"]] = "addFailed"
        else:
            posted.append(occurrence)
    return {"posted": posted, "skipped": skipped, "failures": failures}
