"""Generates Vectors/alerts/*.json and Vectors/reconciliation/*.json from model.py (RFC 0003).

Usage: python3 generate.py [vectors-folder]   (default: the Vectors folder above this one)

The cases below are the vectors' inputs. Every expectation is computed by model.py, which
follows RFC 0003 §4.3-§4.5 and RFC 0001 §4.4/§4.6 without reading the Swift implementation.
"""

import json
import os
import sys
from datetime import date, timedelta
from zoneinfo import ZoneInfo

from model import (
    KINDS, ORDER, Center, Clock, FixedDays, PlanningError, Timetable, alert_schedule,
    apply_plan, deliver_alerts, iso, notification_plan, parse_instant,
)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(HERE))

RFC = "RFC 0003"


# Places and sources ---------------------------------------------------------------------------

RIYADH = ZoneInfo("Asia/Riyadh")
LONDON = ZoneInfo("Europe/London")
MOSCOW = ZoneInfo("Europe/Moscow")

MAKKAH = {"latitude": 21.4225, "longitude": 39.8262, "timeZone": "Asia/Riyadh"}
EDINBURGH = {"latitude": 55.9533, "longitude": -3.1883, "timeZone": "Europe/London"}
KAZAN = {"latitude": 55.7963, "longitude": 49.1088, "timeZone": "Europe/Moscow",
         "countryCode": "RU", "name": "Kazan"}

# Salah's characterization fixture (A2): Makkah, Tuesday 2 June 2026, every day the same.
MAKKAH_TIMES = {"fajr": "04:11", "sunrise": "05:38", "dhuhr": "12:19", "asr": "15:35",
                "maghrib": "19:00", "isha": "20:30"}
# Synthetic midsummer times for Edinburgh: Isha after midnight belongs to the evening before.
EDINBURGH_TIMES = {"fajr": "02:35", "sunrise": "04:26", "dhuhr": "13:14", "asr": "17:43",
                   "maghrib": "22:03", "isha": "00:15+1"}


def days(first, last):
    d = date.fromisoformat(first)
    end = date.fromisoformat(last)
    while d <= end:
        yield d
        d += timedelta(days=1)


def rows(first, last, times, changes=None):
    """One row per day with the same times; `changes` maps a day to its own times dict, or to
    None for a day the timetable leaves out, or adds `observances`."""
    changes = changes or {}
    result = []
    for d in days(first, last):
        text = d.isoformat()
        if text in changes:
            change = changes[text]
            if change is None:
                continue
            row = {"day": text, "times": dict(change.get("times", times))}
            for kind in change.get("drop", []):
                del row["times"][kind]
            if "observances" in change:
                row["observances"] = change["observances"]
            result.append(row)
        else:
            result.append({"day": text, "times": dict(times)})
    return result


def makkah(first="2026-05-25", last="2026-06-20", changes=None, expected=KINDS):
    return Timetable(RIYADH, expected, rows(first, last, MAKKAH_TIMES, changes))


def edinburgh(first="2026-06-15", last="2026-06-28", changes=None):
    return Timetable(LONDON, KINDS, rows(first, last, EDINBURGH_TIMES, changes))


KAZAN_PARAMETERS = {"parameters": {
    "fajr": {"angle": 18}, "isha": {"angle": 17}, "maghrib": "sunset", "madhab": "shafi",
    "highLatitudeRule": "middleOfTheNight", "nightSpan": "sunsetToFajr", "rounding": "nearest"}}


def kazan_day(day, previous):
    return [("fajr", parse_instant(f"{previous}T23:45:00+03:00")),
            ("sunrise", parse_instant(f"{day}T02:58:00+03:00")),
            ("dhuhr", parse_instant(f"{day}T11:45:00+03:00")),
            ("asr", parse_instant(f"{day}T16:17:00+03:00")),
            ("maghrib", parse_instant(f"{day}T20:32:00+03:00")),
            ("isha", parse_instant(f"{day}T23:45:00+03:00"))]


# Kazan under the middle-of-the-night rule (Vectors/calculation/owning-days.json, from SalahTimes'
# reference): on 19 and 20 June every time is the same, and each day's Fajr falls at 23:45 the
# evening before, the same instant as the previous Isha. The vectors below only read events from
# the evening of the 19th, so the context days before it hold no alert and no gap.
KAZAN_SOURCE = FixedDays(MOSCOW, KINDS, 12 * 3600, {
    date(2026, 6, d): kazan_day(f"2026-06-{d:02d}", f"2026-06-{d - 1:02d}") for d in range(16, 23)
}, None)


# Settings -------------------------------------------------------------------------------------

def every(at_time=True, before=None, after=None, **sounds):
    s = {"atTime": at_time}
    if before is not None:
        s["before"] = before
    if after is not None:
        s["after"] = after
    s.update(sounds)
    return s


FIVE = ["fajr", "dhuhr", "asr", "maghrib", "isha"]
ALL_THREE = {"kinds": {k: every(before=600, after=300) for k in FIVE}}
AT_TIME_ONLY = {"kinds": {k: every() for k in FIVE}}

MIN = 60
HOUR = 3600
DAY = 86400


# Output helpers -------------------------------------------------------------------------------

def t(text):
    return parse_instant(text)


def alert_ref(alert, zone):
    return {"id": f"{alert['day'].isoformat()}/{alert['prayer']}/{alert['kind']}",
            "fireDate": iso(alert["fireDate"], zone), "event": iso(alert["event"], zone),
            "observance": alert["observance"], "sound": alert["sound"]}


def short_ref(alert, zone):
    return {"id": f"{alert['day'].isoformat()}/{alert['prayer']}/{alert['kind']}",
            "fireDate": iso(alert["fireDate"], zone)}


def gap_ref(gap, zone):
    return {"start": iso(gap["start"], zone), "end": iso(gap["end"], zone), "kind": gap["kind"],
            "day": gap["day"].isoformat(),
            "prayers": sorted(gap["prayers"], key=ORDER.get), "reason": gap["reason"]}


FILES = {}


def add(folder, name, description, vector):
    file = FILES.setdefault((folder, name), {"schemaVersion": 1, "description": description,
                                              "vectors": []})
    assert file["description"] == description
    file["vectors"].append(vector)


def location_zone(location):
    return ZoneInfo(location["timeZone"])


def source_input(source):
    if isinstance(source, FixedDays):
        return {"calculation": KAZAN_PARAMETERS}
    return {"source": source.json}


# Alert vectors --------------------------------------------------------------------------------

def alert_vector(file, description, vid, text, provenance, location, source, settings, query,
                 namespace="prayers", maximum=None):
    zone = location_zone(location)
    inp = {"location": location}
    inp.update(source_input(source))
    inp["namespace"] = namespace
    inp["alertSettings"] = settings
    if maximum is not None:
        inp["maximumReminderOffset"] = maximum
    inp["query"] = query
    m = 2 * HOUR if maximum is None else maximum
    try:
        schedule = alert_schedule(source, namespace, t(query["from"]), t(query["to"]), m, settings)
    except PlanningError as error:
        expected = {"error": error.value}
    else:
        if query["type"] == "schedule":
            expected = {
                "requested": [iso(schedule["requested"][0], zone), iso(schedule["requested"][1], zone)],
                "alerts": [alert_ref(a, zone) for a in schedule["alerts"]],
                "gaps": [gap_ref(g, zone) for g in schedule["gaps"]],
            }
        else:
            budget = {"maxPending": 60, "nearTermWindow": 2 * DAY, "horizon": 14 * DAY}
            budget.update(query.get("budget", {}))
            plan = notification_plan(schedule, t(query["now"]), budget)
            expected = {
                "effectiveRange": [iso(plan["effectiveRange"][0], zone),
                                   iso(plan["effectiveRange"][1], zone)],
                "alerts": [alert_ref(a, zone) for a in plan["alerts"]],
                "omitted": [short_ref(a, zone) for a in plan["omitted"]],
                "coveredUntil": iso(plan["coveredUntil"], zone),
                "coverageByKind": {k: iso(v, zone) for k, v in
                                   sorted(plan["coverageByKind"].items(),
                                          key=lambda kv: ["atTime", "before", "after"].index(kv[0]))},
            }
    add("alerts", file, description,
        {"id": vid, "description": text, "provenance": provenance, "input": inp,
         "expected": expected})
    return expected


SCHEDULE = ("Alert schedules (RFC 0003 §4.3): candidate alerts from known events, the half-open "
            "range, the query bounded by maximumReminderOffset, owning days across midnight, "
            "Jumu'ah and per-day settings, and the canonical order.")
GAPS = ("Alert gaps (RFC 0003 §4.3): source gaps moved by each alert kind's offset, only for "
        "prayers whose alerts are on, with both observances on a Friday's Dhuhr.")
PLANS = ("Notification plans (RFC 0003 §4.4): near-term reservation, at-time fill, the budget, "
         "equal-time ties, the horizon, ranges that start after or end before now, and coverage "
         "per alert kind with source gaps.")
ERRORS = "Planning errors (RFC 0003 §4.3), in the order they are checked."


def q_schedule(start_, end_):
    return {"type": "schedule", "from": start_, "to": end_}


def q_plan(start_, end_, now, **budget):
    q = {"type": "plan", "from": start_, "to": end_, "now": now}
    if budget:
        q["budget"] = budget
    return q


def schedule_vectors():
    v = lambda *a, **k: alert_vector("schedule", SCHEDULE, *a, **k)

    v("alerts.schedule.every-kind-one-day",
      "Every prayer with an at-time alert, a 10-minute before-reminder and a 5-minute "
      "after-reminder over one day: fifteen alerts by fire date. Sunrise has no settings.",
      "RFC 0003 §4.3 Candidates; proposal §7.5 (fifteen requests for a full day).",
      MAKKAH, makkah(), ALL_THREE,
      q_schedule("2026-06-02T00:00:00+03:00", "2026-06-03T00:00:00+03:00"))

    v("alerts.schedule.half-open-range",
      "The range starts at Dhuhr and ends at Asr: Dhuhr's at-time alert at the start is in, "
      "Asr's at-time alert at the end is out, and the reminders between are in.",
      "RFC 0003 §4.3: the fire-date range [start, end) is half-open.",
      MAKKAH, makkah(), ALL_THREE,
      q_schedule("2026-06-02T12:19:00+03:00", "2026-06-02T15:35:00+03:00"))

    v("alerts.schedule.reminders-of-events-outside-the-range",
      "A short range holds only Dhuhr's before-reminder, though Dhuhr is after the range "
      "(alerts.schedule.after-reminder-of-an-earlier-prayer is the other direction).",
      "RFC 0003 §4.3 Candidates; proposal §7.5: query events before and after the range to "
      "include after-reminders of earlier prayers and before-reminders of later ones.",
      MAKKAH, makkah(), ALL_THREE,
      q_schedule("2026-06-02T12:05:00+03:00", "2026-06-02T12:15:00+03:00"))
    v("alerts.schedule.after-reminder-of-an-earlier-prayer",
      "The range holds only Isha's after-reminder at 20:35; Isha at 20:30 is before it.",
      "RFC 0003 §4.3 Candidates.",
      MAKKAH, makkah(), ALL_THREE,
      q_schedule("2026-06-02T20:31:00+03:00", "2026-06-02T20:40:00+03:00"))

    two_hours = {"kinds": {"fajr": every(before=2 * HOUR), "isha": every(after=2 * HOUR)}}
    v("alerts.schedule.offsets-at-the-maximum",
      "Fajr's before-reminder and Isha's after-reminder are exactly maximumReminderOffset (two "
      "hours) away from their prayers, which the planner accepts: 02:11 and 22:30.",
      "RFC 0003 §4.3 Errors 3: an offset may equal maximumReminderOffset.",
      MAKKAH, makkah(), two_hours,
      q_schedule("2026-06-02T00:00:00+03:00", "2026-06-03T00:00:00+03:00"))
    v("alerts.schedule.offset-at-the-maximum-on-the-range-end",
      "The range ends at 02:11, the fire date of Fajr's two-hour before-reminder: the "
      "reminder is at the excluded end, so the range holds no alert.",
      "RFC 0003 §4.3: the fire-date range [start, end) excludes its end.",
      MAKKAH, makkah(), two_hours,
      q_schedule("2026-06-02T00:00:00+03:00", "2026-06-02T02:11:00+03:00"))
    v("alerts.schedule.after-reminder-from-the-query-start",
      "The range starts at 22:30, exactly two hours after Isha. Isha is read at the query's "
      "first instant (start − m), and its two-hour after-reminder fires at the range's start, "
      "which is included.",
      "RFC 0003 §4.3 Candidates: events(from: start − m, through: end + m) includes its start; "
      "proposal §7.5: this boundary behavior is part of the vectors.",
      MAKKAH, makkah(), two_hours,
      q_schedule("2026-06-02T22:30:00+03:00", "2026-06-03T00:00:00+03:00"))
    v("alerts.schedule.before-reminder-from-near-the-query-end",
      "The range ends at 02:12. Fajr at 04:11 is a minute inside the query's end (end + m), "
      "and its two-hour before-reminder at 02:11 is in the range.",
      "RFC 0003 §4.3 Candidates: the query reaches m past the range's end; proposal §7.5: this "
      "boundary behavior is part of the vectors.",
      MAKKAH, makkah(), two_hours,
      q_schedule("2026-06-02T00:00:00+03:00", "2026-06-02T02:12:00+03:00"))

    edinburgh_settings = {"kinds": {
        "isha": every(before=30 * MIN, after=15 * MIN),
        "fajr": every(before=HOUR),
    }}
    v("alerts.schedule.isha-after-midnight-keeps-its-day",
      "In Edinburgh at midsummer, 21 June's Isha is at 00:15 on the 22nd. Its before-reminder "
      "at 23:45, its alert and its after-reminder at 00:30 all belong to 21 June. The 22nd's "
      "Fajr reminder at 01:35 belongs to the 22nd.",
      "RFC 0003 §4.2: the identity's day is the event's owning day, even after midnight "
      "(RFC 0001 §4.3).",
      EDINBURGH, edinburgh(), edinburgh_settings,
      q_schedule("2026-06-21T22:00:00+01:00", "2026-06-22T03:00:00+01:00"))

    kazan_settings = {"kinds": {"fajr": every(before=15 * MIN), "isha": every(after=10 * MIN)}}
    v("alerts.schedule.fajr-before-midnight-belongs-to-the-next-day",
      "In Kazan under the middle-of-the-night rule, 20 June's Fajr is at 23:45 on the 19th, the "
      "instant of the 19th's Isha. Fajr's alerts belong to 20 June though they fire on the "
      "19th, and at 23:45 the 19th's Isha alert comes first.",
      "RFC 0003 §4.2 (owning days; order by day, then prayer, then kind); "
      "Vectors/calculation/owning-days.json for the instants.",
      KAZAN, KAZAN_SOURCE, kazan_settings,
      q_schedule("2026-06-19T23:00:00+03:00", "2026-06-20T00:30:00+03:00"))

    jumuah = {"kinds": {"dhuhr": every(before=10 * MIN)},
              "jumuah": every(before=45 * MIN, sound={"named": "jumuah.caf"},
                              beforeSound="none")}
    friday = makkah(changes={"2026-06-05": {"observances": {"dhuhr": "jumuah"}}})
    v("alerts.schedule.jumuah-has-its-own-settings",
      "Friday 5 June declares Jumu'ah: its Dhuhr uses the Jumu'ah settings (45-minute "
      "reminder, a named sound, a silent reminder). Thursday's Dhuhr uses Dhuhr's.",
      "RFC 0003 §4.1: settings are asked per subject, whose observance comes from the event.",
      MAKKAH, friday, jumuah,
      q_schedule("2026-06-04T00:00:00+03:00", "2026-06-06T00:00:00+03:00"))
    v("alerts.schedule.an-ordinary-friday-is-dhuhr",
      "The same settings on a Friday whose timetable declares nothing: Dhuhr's settings apply.",
      "RFC 0003 §4.1; RFC 0001 §4.3 rule 11: a Friday is a date, Jumu'ah is declared.",
      MAKKAH, makkah(), jumuah,
      q_schedule("2026-06-05T00:00:00+03:00", "2026-06-06T00:00:00+03:00"))

    by_day = {"kinds": {"fajr": every(), "isha": every()},
              "days": {"2026-06-03": {"kinds": {"fajr": every(before=45 * MIN),
                                                "isha": every(after=20 * MIN)}}}}
    v("alerts.schedule.settings-can-depend-on-the-day",
      "One day has its own settings (a reminder before Fajr, after Isha); the days around it "
      "use the usual ones.",
      "RFC 0003 §4.1: the subject carries its owning day.",
      MAKKAH, makkah(), by_day,
      q_schedule("2026-06-02T12:00:00+03:00", "2026-06-04T12:00:00+03:00"))

    ties = {"kinds": {"maghrib": every(at_time=False, after=45 * MIN),
                      "isha": every(before=45 * MIN)}}
    v("alerts.schedule.equal-fire-dates-by-identity",
      "Maghrib's 45-minute after-reminder and Isha's 45-minute before-reminder both fire at "
      "19:45: Maghrib's comes first, by prayer order.",
      "RFC 0003 §4.2 Order: fire date, then identity (day, prayer, kind).",
      MAKKAH, makkah(), ties,
      q_schedule("2026-06-02T19:00:00+03:00", "2026-06-02T21:00:00+03:00"))

    sunrise = {"kinds": {"sunrise": every(before=20 * MIN, sound="none"),
                         "fajr": every(sound={"named": "fajr.caf"})}}
    v("alerts.schedule.sunrise-alerts-and-sounds",
      "Sunrise can have alerts too (here a silent alert and a reminder 20 minutes before), and "
      "each alert carries the sound of its kind.",
      "RFC 0003 §4.1: subjects are any PrayerKind; each kind has its own sound.",
      MAKKAH, makkah(), sunrise,
      q_schedule("2026-06-02T00:00:00+03:00", "2026-06-02T12:00:00+03:00"))

    v("alerts.schedule.end-before-start",
      "An end before the start counts as the start: no alerts, and an empty requested range.",
      "RFC 0003 §4.3.",
      MAKKAH, makkah(), ALL_THREE,
      q_schedule("2026-06-02T12:00:00+03:00", "2026-06-02T11:00:00+03:00"))

    v("alerts.schedule.no-settings-no-alerts",
      "Settings that are nil for every prayer: no alerts and no gaps, though the timetable "
      "has a missing day in range.",
      "RFC 0003 §4.3: a gap of a prayer whose settings are nil makes no alert gap.",
      MAKKAH, makkah(changes={"2026-06-03": None}), {"kinds": {}},
      q_schedule("2026-06-02T00:00:00+03:00", "2026-06-05T00:00:00+03:00"))


def gap_vectors():
    v = lambda *a, **k: alert_vector("gaps", GAPS, *a, **k)
    no_isha = makkah(changes={"2026-06-03": {"drop": ["isha"]}})
    isha_all = {"kinds": {"isha": every(before=15 * MIN, after=10 * MIN),
                          "maghrib": every(), "fajr": every()}}
    v("alerts.gaps.missing-isha-per-kind",
      "3 June publishes no Isha, so Isha may fall anywhere from Maghrib (19:00) to the next "
      "Fajr (04:11). Isha's alert is unknown in that interval, its 15-minute before-reminder "
      "15 minutes earlier, and its 10-minute after-reminder 10 minutes later.",
      "RFC 0003 §4.3 Gaps; RFC 0001 §4.6 missing-event windows; proposal §7.5: an unknown "
      "future prayer can make its before-reminder unknown sooner.",
      MAKKAH, no_isha, isha_all,
      q_schedule("2026-06-03T00:00:00+03:00", "2026-06-05T00:00:00+03:00"))
    v("alerts.gaps.no-alerts-for-the-missing-prayer",
      "The same missing Isha, with no settings for Isha: no alert gap, and the other alerts "
      "are unaffected.",
      "RFC 0003 §4.3: missing data for a prayer the app doesn't alert never shortens coverage.",
      MAKKAH, no_isha, {"kinds": {"maghrib": every(), "fajr": every(before=30 * MIN)}},
      q_schedule("2026-06-03T00:00:00+03:00", "2026-06-05T00:00:00+03:00"))

    missing_day = makkah(changes={"2026-06-04": None})
    v("alerts.gaps.missing-day",
      "No row for 4 June: every kind of the day may fall from its midnight to the 5th's Fajr. "
      "The at-time gap lists the five alerted prayers; Fajr's 30-minute before-reminder is "
      "unknown from 23:30 on the 3rd.",
      "RFC 0003 §4.3; RFC 0001 §4.6 (an unavailable day's window).",
      MAKKAH, missing_day, {"kinds": {"fajr": every(before=30 * MIN), "dhuhr": every(),
                                      "asr": every(), "maghrib": every(), "isha": every()}},
      q_schedule("2026-06-03T00:00:00+03:00", "2026-06-06T00:00:00+03:00"))

    friday_no_dhuhr = makkah(changes={"2026-06-05": {"drop": ["dhuhr"]}})
    v("alerts.gaps.friday-dhuhr-asks-both-observances",
      "Friday 5 June publishes no Dhuhr. The source might have declared Jumu'ah, so both "
      "settings count: the at-time gaps coincide and merge, and the before-reminder is "
      "unknown 10 minutes (ordinary) and 45 minutes (Jumu'ah) before the window.",
      "RFC 0003 §4.3 Gaps: .ordinary, and .jumuah too for Dhuhr on a Friday.",
      MAKKAH, friday_no_dhuhr, {"kinds": {"dhuhr": every(before=10 * MIN)},
                                "jumuah": every(before=45 * MIN)},
      q_schedule("2026-06-05T00:00:00+03:00", "2026-06-06T00:00:00+03:00"))

    no_sunrise = makkah(changes={"2026-06-02": {"drop": ["sunrise"]}})
    v("alerts.gaps.missing-sunrise-without-sunrise-alerts",
      "A missing sunrise makes no alert gap when sunrise has no alerts.",
      "RFC 0003 §4.3.",
      MAKKAH, no_sunrise, AT_TIME_ONLY,
      q_schedule("2026-06-02T00:00:00+03:00", "2026-06-03T00:00:00+03:00"))
    v("alerts.gaps.missing-sunrise-with-sunrise-alerts",
      "With a sunrise alert, the missing sunrise is an at-time gap from Fajr to Dhuhr.",
      "RFC 0003 §4.3; RFC 0001 §4.6.",
      MAKKAH, no_sunrise, {"kinds": {"sunrise": every(), "fajr": every()}},
      q_schedule("2026-06-02T00:00:00+03:00", "2026-06-03T00:00:00+03:00"))

    expired = makkah(last="2026-06-03")
    v("alerts.gaps.expired-timetable",
      "The timetable ends on 3 June. Each later day is unknown from its midnight, so the "
      "gaps start at the 4th's midnight, and Fajr's 30-minute reminder 30 minutes before it.",
      "RFC 0003 §4.3; RFC 0001 §4.6 (unavailable days, one gap per day).",
      MAKKAH, expired, {"kinds": {"fajr": every(before=30 * MIN), "isha": every()}},
      q_schedule("2026-06-03T00:00:00+03:00", "2026-06-05T12:00:00+03:00"))

    v("alerts.gaps.clipped-to-the-range",
      "The range ends at 23:00 on 3 June, inside the missing Isha's window: the gaps end at "
      "the range's end.",
      "RFC 0003 §4.3: each interval is clipped to the requested range.",
      MAKKAH, no_isha, isha_all,
      q_schedule("2026-06-03T12:00:00+03:00", "2026-06-03T23:00:00+03:00"))


def plan_vectors():
    v = lambda *a, **k: alert_vector("plans", PLANS, *a, **k)
    fourteen = ("2026-06-01T00:00:00+03:00", "2026-06-15T00:00:00+03:00")
    d7 = v("alerts.plan.d7-two-complete-days-and-eight-days-at-time",
           "Proposal D7: five prayers, each with an at-time alert, a 10-minute before- and a "
           "5-minute after-reminder; now at midnight; the default budget (60 requests, two "
           "near-term days, a 14-day horizon). The two near-term days reserve 30 requests and "
           "the other 30 go to the at-time alerts of the next six days: eight days of at-time "
           "alerts, two of reminders. Coverage ends at the third day's first reminder; at-time "
           "coverage runs to the ninth day's Fajr.",
           "Proposal §7.5 ('30 near-term requests + 30 later at-time requests = eight days of "
           "at-time alerts and two days of reminders') and Appendix D7; RFC 0003 §4.4.",
           MAKKAH, makkah(), ALL_THREE, q_plan(*fourteen, now=fourteen[0]))
    assert len(d7["alerts"]) == 60
    assert d7["coveredUntil"] == "2026-06-03T04:01:00+03:00", d7["coveredUntil"]
    assert d7["coverageByKind"] == {"atTime": "2026-06-09T04:11:00+03:00",
                                    "before": "2026-06-03T04:01:00+03:00",
                                    "after": "2026-06-03T04:16:00+03:00"}, d7["coverageByKind"]

    v("alerts.plan.insufficient-near-term-capacity",
      "The same fixture with a budget of 20: the 30 near-term alerts don't fit, so the first "
      "20 are kept in order and nothing later is selected. Coverage ends at the first omitted "
      "alert, 2 June's Dhuhr after-reminder; each kind's coverage ends at its own first "
      "omitted alert.",
      "Proposal §7.5 rule 3 ('keep the earliest alerts up to the allowance … record the first "
      "omitted alert as the completeness cutoff'); RFC 0003 §4.4.",
      MAKKAH, makkah(), ALL_THREE, q_plan(*fourteen, now=fourteen[0], maxPending=20))

    ties = {"kinds": {"maghrib": every(after=45 * MIN), "isha": every(before=45 * MIN)}}
    v("alerts.plan.equal-fire-dates-at-the-budget-edge",
      "Maghrib's after-reminder and Isha's before-reminder both fire at 19:45, and the budget "
      "of two ends between them. Identity order keeps Maghrib's; Isha's is the first omitted "
      "alert, so coverage ends at 19:45 though an alert at 19:45 was selected.",
      "Proposal §7.5 rule 3 ('Break equal-time ties by the canonical logical identifier'); "
      "RFC 0003 §4.2 Order, §4.4.",
      MAKKAH, makkah(), ties,
      q_plan("2026-06-02T19:00:00+03:00", "2026-06-03T00:00:00+03:00",
             now="2026-06-02T19:00:00+03:00", maxPending=2))

    edinburgh_settings = {"kinds": {"isha": every(before=30 * MIN, after=15 * MIN)}}
    v("alerts.plan.reminders-across-midnight-keep-the-evening",
      "Edinburgh at 23:00 on 21 June, with a one-hour near-term window ending at midnight. The "
      "Isha before-reminder at 23:45 is near-term; Isha's alert at 00:15 is selected as a later "
      "at-time alert; its after-reminder at 00:30 is omitted. All three belong to 21 June.",
      "RFC 0003 §4.2 (owning days), §4.4 (reservation, at-time fill).",
      EDINBURGH, edinburgh(), edinburgh_settings,
      q_plan("2026-06-21T23:00:00+01:00", "2026-06-24T00:00:00+01:00",
             now="2026-06-21T23:00:00+01:00", nearTermWindow=HOUR))

    v("alerts.plan.horizon-clips-the-range",
      "A 14-day range with a 3-day horizon: nothing after the third day can be selected, so "
      "at-time coverage ends at the horizon, not at an omitted alert.",
      "Proposal §7.5: the effective range is [now, min(candidateRange.end, now + horizon)); "
      "RFC 0003 §4.4.",
      MAKKAH, makkah(), ALL_THREE, q_plan(*fourteen, now=fourteen[0], horizon=3 * DAY))
    v("alerts.plan.near-window-longer-than-the-horizon",
      "A five-day near-term window with a one-day horizon: the window is clipped to the "
      "horizon, which ends coverage of every kind.",
      "Proposal §7.5: 'A near-term window longer than the horizon cannot extend coverage or "
      "select requests beyond it.'",
      MAKKAH, makkah(), ALL_THREE,
      q_plan(*fourteen, now=fourteen[0], nearTermWindow=5 * DAY, horizon=DAY))

    v("alerts.plan.range-starts-after-now",
      "The range starts at noon, twelve hours after now: alerts from noon are selected, but "
      "nothing is known before noon, so every cutoff is now.",
      "Proposal §7.5: 'if candidates begin later than now, the initial uncovered interval "
      "likewise makes coveredUntil == now'; RFC 0003 §4.4.",
      MAKKAH, makkah(), ALL_THREE,
      q_plan("2026-06-01T12:00:00+03:00", "2026-06-03T00:00:00+03:00",
             now="2026-06-01T00:00:00+03:00"))
    v("alerts.plan.range-ends-before-now",
      "A range that ended before now: an empty effective range, no alerts, coverage at now.",
      "Proposal §7.5: 'A candidate range ending at/before now produces an empty plan with "
      "coverage ending at now'.",
      MAKKAH, makkah(), ALL_THREE,
      q_plan("2026-06-01T00:00:00+03:00", "2026-06-03T00:00:00+03:00",
             now="2026-06-05T00:00:00+03:00"))
    v("alerts.plan.range-ends-at-now",
      "A range that ends exactly at now is empty too.",
      "Proposal §7.5; RFC 0003 §4.4.",
      MAKKAH, makkah(), ALL_THREE,
      q_plan("2026-06-01T00:00:00+03:00", "2026-06-03T00:00:00+03:00",
             now="2026-06-03T00:00:00+03:00"))

    missing_isha_1 = makkah(changes={"2026-06-01": {"drop": ["isha"]}})
    isha_settings = {"kinds": {k: every(before=15 * MIN, after=10 * MIN) for k in FIVE}}
    v("alerts.plan.past-only-gap",
      "1 June's Isha is missing, but now is 06:00 on the 2nd, after every interval that gap "
      "makes: it doesn't shorten coverage. The range starts at midnight, as an in-process "
      "caller's would, and alerts before now aren't selected.",
      "Proposal §7.5: 'a past-only gap does not shorten future coverage'; RFC 0003 §4.4.",
      MAKKAH, missing_isha_1, isha_settings,
      q_plan("2026-06-01T00:00:00+03:00", "2026-06-04T00:00:00+03:00",
             now="2026-06-02T06:00:00+03:00", nearTermWindow=DAY))
    v("alerts.plan.gap-containing-now",
      "At 01:00 on 2 June, 1 June's Isha may still be to come: every kind's interval contains "
      "now, so coverage is now.",
      "Proposal §7.5: 'a gap containing now yields now'.",
      MAKKAH, missing_isha_1, isha_settings,
      q_plan("2026-06-01T00:00:00+03:00", "2026-06-04T00:00:00+03:00",
             now="2026-06-02T01:00:00+03:00", nearTermWindow=DAY))

    missing_isha_3 = makkah(changes={"2026-06-03": {"drop": ["isha"]}})
    one_hour = {"kinds": {"isha": every(before=HOUR, after=20 * MIN), "maghrib": every(),
                          "fajr": every()}}
    v("alerts.plan.coverage-differs-by-kind",
      "3 June publishes no Isha; the budget holds everything. Before-reminder coverage ends "
      "at 18:00, an hour before the window opens at Maghrib; at-time coverage runs to 19:00 "
      "and after-reminder coverage to 19:20. Overall coverage is the earliest, 18:00.",
      "Proposal §7.5: 'Each enabled kind's coverage uses its own offset transformation; "
      "at-time coverage is not shortened solely by a before-reminder's lookahead'; RFC 0003 §4.4.",
      MAKKAH, missing_isha_3, one_hour,
      q_plan("2026-06-02T00:00:00+03:00", "2026-06-06T00:00:00+03:00",
             now="2026-06-02T00:00:00+03:00", maxPending=200, nearTermWindow=5 * DAY))

    expired = makkah(last="2026-06-03")
    v("alerts.plan.expired-timetable",
      "The timetable ends on 3 June: every known alert fits, and coverage ends where the "
      "first unknown day's reminder could fall (Fajr's 30-minute reminder, 23:30 on the 3rd); "
      "at-time coverage ends at the 4th's midnight.",
      "Proposal §7.5: 'A partial/expired timetable or a too-small budget shortens coverage "
      "without inventing missing alerts.'",
      MAKKAH, expired, {"kinds": {"fajr": every(before=30 * MIN), "isha": every()}},
      q_plan("2026-06-02T00:00:00+03:00", "2026-06-09T00:00:00+03:00",
             now="2026-06-02T00:00:00+03:00"))

    v("alerts.plan.zero-budget",
      "A budget of zero selects nothing; each kind's coverage ends at its first alert.",
      "RFC 0003 §4.4.",
      MAKKAH, makkah(), ALL_THREE,
      q_plan("2026-06-02T00:00:00+03:00", "2026-06-04T00:00:00+03:00",
             now="2026-06-02T00:00:00+03:00", maxPending=0))
    v("alerts.plan.negative-budget-counts-as-zero",
      "A negative horizon counts as zero: the effective range is empty, so nothing is selected "
      "and every kind's coverage is now.",
      "RFC 0003 §4.4: negative budget values count as zero.",
      MAKKAH, makkah(), ALL_THREE,
      q_plan("2026-06-02T00:00:00+03:00", "2026-06-04T00:00:00+03:00",
             now="2026-06-02T00:00:00+03:00", maxPending=-5, nearTermWindow=-60,
             horizon=-60))
    v("alerts.plan.negative-max-pending-counts-as-zero",
      "A negative allowance with the default window and horizon selects nothing, like an "
      "allowance of zero: each kind's coverage ends at its first alert.",
      "RFC 0003 §4.4: negative budget values count as zero.",
      MAKKAH, makkah(), ALL_THREE,
      q_plan("2026-06-02T00:00:00+03:00", "2026-06-04T00:00:00+03:00",
             now="2026-06-02T00:00:00+03:00", maxPending=-5))
    v("alerts.plan.negative-near-term-window-counts-as-zero",
      "A negative near-term window reserves nothing: the allowance goes to at-time alerts, and "
      "every reminder is left out, so reminder coverage ends at the first one.",
      "RFC 0003 §4.4: negative budget values count as zero; the near-term window is [now, N).",
      MAKKAH, makkah(), ALL_THREE,
      q_plan("2026-06-02T00:00:00+03:00", "2026-06-04T00:00:00+03:00",
             now="2026-06-02T00:00:00+03:00", nearTermWindow=-60))

    fajr_two = {"kinds": {"fajr": every(before=30 * MIN)}}
    v("alerts.plan.later-reminders-stay-out-with-room-left",
      "Fajr only, with a reminder, over 14 days: the plan has room for all 28 alerts, yet "
      "after the two near-term days it selects at-time alerts only. Before-reminder coverage "
      "ends at the third day's reminder.",
      "Proposal §7.5 rule 2: 'Later reminders stay in AlertSchedule for the in-process engine "
      "but are omitted from NotificationPlan.'",
      MAKKAH, makkah(), fajr_two, q_plan(*fourteen, now=fourteen[0]))

    v("alerts.plan.nothing-enabled",
      "No prayer has settings: an empty plan whose coverage is the whole effective range, "
      "with no kind listed.",
      "RFC 0003 §4.4: coveredUntil is the effective range's end when no kind is present.",
      MAKKAH, makkah(), {"kinds": {}}, q_plan(*fourteen, now=fourteen[0]))

    v("alerts.plan.now-between-alerts",
      "Planning at 12:20 on 2 June: Dhuhr's alert (12:19) has passed and isn't selected, its "
      "after-reminder (12:24) is the first request, and the near-term window ends at 12:20 two "
      "days later.",
      "RFC 0003 §4.4: only fire dates in [now, E) can be selected.",
      MAKKAH, makkah(), ALL_THREE,
      q_plan("2026-06-02T12:00:00+03:00", "2026-06-09T00:00:00+03:00",
             now="2026-06-02T12:20:00+03:00"))


def error_vectors():
    v = lambda *a, **k: alert_vector("errors", ERRORS, *a, **k)
    one_day = q_schedule("2026-06-02T00:00:00+03:00", "2026-06-03T00:00:00+03:00")
    v("alerts.errors.empty-namespace", "An empty namespace is invalid.",
      "RFC 0003 §4.2 Namespaces, §4.3 Errors 1.", MAKKAH, makkah(), ALL_THREE, one_day,
      namespace="")
    v("alerts.errors.namespace-with-a-slash", "A namespace can't contain a slash.",
      "RFC 0003 §4.2 Namespaces, §4.3 Errors 1.", MAKKAH, makkah(), ALL_THREE, one_day,
      namespace="a/b")
    v("alerts.errors.namespace-checked-first",
      "An invalid namespace is reported before an invalid maximum offset.",
      "RFC 0003 §4.3 Errors (order).", MAKKAH, makkah(), ALL_THREE, one_day, namespace="",
      maximum=-1)
    v("alerts.errors.negative-maximum-offset", "A negative maximumReminderOffset is invalid.",
      "RFC 0003 §4.3 Errors 2.", MAKKAH, makkah(), ALL_THREE, one_day, maximum=-60)
    v("alerts.errors.maximum-offset-above-the-limit",
      "A maximumReminderOffset longer than seven days is invalid.",
      "RFC 0003 §4.3 Errors 2.", MAKKAH, makkah(), ALL_THREE, one_day, maximum=7 * DAY + 1)
    v("alerts.errors.maximum-offset-at-the-limit",
      "Seven days exactly is accepted.",
      "RFC 0003 §4.3 Errors 2.", MAKKAH, makkah(), ALL_THREE, one_day, maximum=7 * DAY)
    v("alerts.errors.maximum-offset-checked-before-settings",
      "An invalid maximum is reported before any settings are asked.",
      "RFC 0003 §4.3 Errors (order).", MAKKAH, makkah(),
      {"kinds": {"dhuhr": every(before=0)}}, one_day, maximum=-1)
    v("alerts.errors.zero-offset", "A before-reminder of zero isn't positive.",
      "RFC 0003 §4.3 Errors 3; proposal §7.5: reject settings outside the declared positive "
      "offset bound.", MAKKAH, makkah(), {"kinds": {"dhuhr": every(before=0)}}, one_day)
    v("alerts.errors.negative-offset", "A negative after-reminder is rejected.",
      "RFC 0003 §4.3 Errors 3.", MAKKAH, makkah(), {"kinds": {"asr": every(after=-300)}},
      one_day)
    v("alerts.errors.offset-above-the-maximum",
      "A before-reminder longer than maximumReminderOffset is rejected.",
      "RFC 0003 §4.3 Errors 3.", MAKKAH, makkah(),
      {"kinds": {"fajr": every(before=2 * HOUR + 1)}}, one_day)
    v("alerts.errors.offset-at-the-maximum-is-accepted",
      "An after-reminder exactly maximumReminderOffset long is accepted.",
      "RFC 0003 §4.3 Errors 3.", MAKKAH, makkah(),
      {"kinds": {"isha": every(after=30 * MIN)}}, one_day, maximum=30 * MIN)
    v("alerts.errors.first-subject-in-events-order",
      "Two prayers have bad offsets; the first known event in events order (the query's "
      "first Isha, the evening before the range) is reported, before-reminder first.",
      "RFC 0003 §4.3 Errors 3 (subjects in events order, before before after).", MAKKAH,
      makkah(), {"kinds": {"isha": every(before=0, after=0), "fajr": every(after=0)}}, one_day,
      maximum=6 * HOUR)
    v("alerts.errors.jumuah-gap-subject",
      "Friday 5 June publishes no Dhuhr, and the Jumu'ah settings have a zero reminder: the "
      "gap's .jumuah subject is rejected.",
      "RFC 0003 §4.3 Errors 3 (a Friday's Dhuhr gap asks both observances).", MAKKAH,
      makkah(changes={"2026-06-05": {"drop": ["dhuhr"]}}),
      {"kinds": {"dhuhr": every(before=600)}, "jumuah": every(before=0)},
      q_schedule("2026-06-05T11:00:00+03:00", "2026-06-05T13:00:00+03:00"))
    v("alerts.errors.gap-subject-ordinary-before-jumuah",
      "Both the ordinary and the Jumu'ah settings for Friday's missing Dhuhr have bad "
      "reminders: the ordinary subject is asked first and reported.",
      "RFC 0003 §4.3 Errors 3 (gap subjects, .ordinary before .jumuah).", MAKKAH,
      makkah(changes={"2026-06-05": {"drop": ["dhuhr"]}}),
      {"kinds": {"dhuhr": every(before=-1)}, "jumuah": every(before=0)},
      q_schedule("2026-06-05T11:00:00+03:00", "2026-06-05T13:00:00+03:00"))
    v("alerts.errors.gap-subjects-are-checked-too",
      "A bad offset for a prayer that only a gap holds is rejected as well.",
      "RFC 0003 §4.3 Errors 3 (gap subjects follow the events).", MAKKAH,
      makkah(changes={"2026-06-02": {"drop": ["asr"]}}),
      {"kinds": {"asr": every(before=-1), "dhuhr": every()}},
      q_schedule("2026-06-02T13:00:00+03:00", "2026-06-02T14:00:00+03:00"))


# Reconciliation vectors -----------------------------------------------------------------------

RECON_FILES = {
    "apply": "Applying plans (RFC 0003 §4.5): a fresh install, unchanged requests, and the "
             "calls a batch makes.",
    "identity": "Stable identities (RFC 0003 §4.2, §4.5): changed times and offsets replace "
                "a request under the same identifier, never remove it first; occurrences "
                "differ by fire date.",
    "obsolete": "Obsolete requests (RFC 0003 §4.5 step 4): only owned requests the plan no "
                "longer wants are removed.",
    "namespaces": "Plan validation (RFC 0003 §4.5): a foreign plan or alert, including an "
                  "empty plan, and a repeated identity are rejected before any call.",
    "failures": "Failures and read-back (RFC 0003 §4.5): failed, ignored and dropped adds, a "
                "failed read-back, and alerts that fire before it. The report claims only "
                "what the read-back confirmed.",
    "authorization": "Authorization (RFC 0003 §4.5 step 1): without it nothing is added and "
                     "owned requests are removed; the scheduler never asks for it.",
    "housekeeping": "Delivered-notification retention (RFC 0003 §4.5 step 5), limited to the "
                    "owned prefix and namespace.",
    "pump": "The update pump (RFC 0003 §4.5): serialized batches, and overlapping applies "
            "reconciled toward the latest plan.",
    "deliver": "Delivering due alerts (RFC 0003 §4.5): posted at once unless pending or "
               "already delivered.",
}

SCHEDULER = {"identifierPrefix": "salah.", "namespace": "prayers", "threadIdentifier": "prayers",
             "deliveredRetention": 2 * DAY}


def pend(rid, fire, title, body, thread="prayers"):
    return {"id": rid, "fireDate": fire, "title": title, "body": body, "thread": thread}


def rid(alert_id, namespace="prayers"):
    return f"salah.{namespace}/{alert_id}"


def a(alert_id, fire, namespace=None):
    alert = {"id": alert_id, "fireDate": fire}
    if namespace:
        alert["namespace"] = namespace
    return alert


def plan(alerts, covered, namespace="prayers"):
    return {"namespace": namespace, "coveredUntil": covered, "alerts": alerts}


def recon(file, vid, text, provenance, steps, center=None, scheduler=None, zone=RIYADH):
    scheduler = dict(scheduler or SCHEDULER)
    center = center or {}
    clock = Clock(t(steps[0]["now"]))
    model = Center(center, clock)
    reports = []
    index = 0
    while index < len(steps):
        step = steps[index]
        group = [step]
        while index + len(group) < len(steps) and steps[index + len(group)].get("duringPrevious"):
            group.append(steps[index + len(group)])
        clock.value = t(step["now"])
        clock.read_back = t(step.get("readBackAt", step["now"]))
        if len(group) == 1:
            model.begin_batch()
            if "apply" in step:
                reports.append(apply_plan(scheduler, model, step["apply"], step.get("wording", "v1")))
            else:
                reports.append(deliver_alerts(scheduler, model, step["deliver"],
                                              step.get("wording", "v1")))
        else:
            # The first batch makes `suspendAtCall` calls, then finds a later plan; the plans
            # submitted while it was suspended are superseded by the last one, which runs.
            model.begin_batch(step["suspendAtCall"])
            first = apply_plan(scheduler, model, step["apply"], step.get("wording", "v1"))
            assert first.get("superseded"), first
            reports.append(first)
            for later in group[1:-1]:
                reports.append({"superseded": True, "verifiedAt": clock.value, "confirmed": [],
                                "failures": {}, "confirmedCoveredUntil": None})
            last = group[-1]
            model.begin_batch()
            reports.append(apply_plan(scheduler, model, last["apply"], last.get("wording", "v1")))
        index += len(group)

    def report_json(r):
        if "error" in r:
            return {"error": r["error"]}
        if "posted" in r:
            return {"posted": [{"id": o["id"], "fireDate": iso(o["fireDate"], zone)} for o in r["posted"]],
                    "skipped": [{"id": o["id"], "fireDate": iso(o["fireDate"], zone)} for o in r["skipped"]],
                    "failures": dict(sorted(r["failures"].items()))}
        return {"superseded": r["superseded"], "verifiedAt": iso(r["verifiedAt"], zone),
                "confirmed": [{"id": o["id"], "fireDate": iso(o["fireDate"], zone)}
                              for o in r["confirmed"]],
                "failures": dict(sorted(r["failures"].items())),
                "confirmedCoveredUntil": (iso(r["confirmedCoveredUntil"], zone)
                                          if r["confirmedCoveredUntil"] else None)}

    def call_json(c):
        if isinstance(c, dict) and "fireDate" in c:
            return {"add": c["add"], "fireDate": iso(c["fireDate"], zone)}
        return c

    expected = {
        "reports": [report_json(r) for r in reports],
        "pending": [{"id": r.id, "fireDate": iso(r.fire, zone), "title": r.title, "body": r.body,
                     "thread": r.thread} for _, r in sorted(model.pending.items())],
        "delivered": [{"id": d, "date": iso(when, zone)} for d, when in model.delivered],
        "calls": [call_json(c) for c in model.calls],
    }
    inp = {"scheduler": scheduler, "center": center, "steps": steps}
    FILES.setdefault(("reconciliation", file), {"schemaVersion": 1,
                                                 "description": RECON_FILES[file], "vectors": []})
    FILES[("reconciliation", file)]["vectors"].append(
        {"id": vid, "description": text, "provenance": provenance, "input": inp,
         "expected": expected})
    return expected


D = "2026-06-02"
DHUHR = f"{D}T12:19:00+03:00"
DHUHR_BEFORE_10 = f"{D}T12:09:00+03:00"
DHUHR_BEFORE_15 = f"{D}T12:04:00+03:00"
DHUHR_AFTER = f"{D}T12:24:00+03:00"
ASR = f"{D}T15:35:00+03:00"
MAGHRIB = f"{D}T19:00:00+03:00"
ISHA = f"{D}T20:30:00+03:00"
MORNING = f"{D}T06:00:00+03:00"
COVER = "2026-06-04T00:00:00+03:00"

DHUHR_THREE = [a(f"{D}/dhuhr/before", DHUHR_BEFORE_10), a(f"{D}/dhuhr/atTime", DHUHR),
               a(f"{D}/dhuhr/after", DHUHR_AFTER)]


def reconciliation_vectors():
    recon("apply", "reconciliation.apply.fresh-install",
          "An empty center: the batch reads authorization, pending and delivered "
          "notifications, adds the three requests in plan order and reads them back. All "
          "three are confirmed, and confirmed coverage is the plan's.",
          "RFC 0003 §4.5 (the batch's calls, Requests, Matching, The report).",
          [{"apply": plan(DHUHR_THREE, COVER), "now": MORNING}])
    recon("apply", "reconciliation.apply.unchanged-requests-are-kept",
          "The center already holds the three requests exactly as the plan wants them: nothing "
          "is added or removed, and all three are confirmed.",
          "RFC 0003 §4.5 step 6: a matching owned request isn't added again.",
          [{"apply": plan(DHUHR_THREE, COVER), "now": MORNING}],
          center={"pending": [pend(rid(f"{D}/dhuhr/before"), DHUHR_BEFORE_10, "dhuhr", "v1 before"),
                              pend(rid(f"{D}/dhuhr/atTime"), DHUHR, "dhuhr", "v1 atTime"),
                              pend(rid(f"{D}/dhuhr/after"), DHUHR_AFTER, "dhuhr", "v1 after")]})
    recon("apply", "reconciliation.apply.fractional-second-rounds-up",
          "A fire date a quarter of a second past 12:19 gets a trigger at 12:19:01, never before "
          "the fire date (rounding to the nearest second would give 12:19:00); the read-back "
          "matches it, and the confirmed occurrence keeps the plan's fire date.",
          "RFC 0003 §4.5 Requests (rounded up to a whole second) and Matching.",
          [{"apply": plan([a(f"{D}/dhuhr/atTime", "2026-06-02T12:19:00.250+03:00")], COVER),
            "now": MORNING}])
    recon("apply", "reconciliation.apply.no-thread",
          "A scheduler without a thread identifier leaves the content's own (none here); a "
          "pending request with a thread no longer matches and is replaced.",
          "RFC 0003 §4.5 Requests (the thread), Matching.",
          [{"apply": plan([a(f"{D}/asr/atTime", ASR)], COVER), "now": MORNING}],
          center={"pending": [pend(rid(f"{D}/asr/atTime"), ASR, "asr", "v1 atTime")]},
          scheduler={**SCHEDULER, "threadIdentifier": None})

    recon("identity", "reconciliation.identity.moved-reminder-keeps-its-identifier",
          "Dhuhr's before-reminder moves from 10 to 15 minutes (12:09 to 12:04). Its identifier "
          "has no time in it, so the request is replaced by one add and never removed; the "
          "confirmed occurrence carries the new fire date.",
          "Proposal §7.5 'Identity and updates'; RFC 0003 §4.2, §4.5 step 4 and 6. Corrects "
          "A2's characterizesAMovedAlertIsRemovedBeforeItsReplacementIsAdded and "
          "characterizesIdentifiersCarryTheFireTimestamp.",
          [{"apply": plan([a(f"{D}/dhuhr/before", DHUHR_BEFORE_10)], COVER), "now": MORNING},
           {"apply": plan([a(f"{D}/dhuhr/before", DHUHR_BEFORE_15)], COVER), "now": MORNING}])
    recon("identity", "reconciliation.identity.changed-prayer-time",
          "A recalculation moves Asr from 15:35 to 15:41: the same request is replaced with "
          "the new trigger.",
          "Proposal §7.5: changing a calculation updates the same logical request.",
          [{"apply": plan([a(f"{D}/asr/atTime", ASR)], COVER), "now": MORNING},
           {"apply": plan([a(f"{D}/asr/atTime", f"{D}T15:41:00+03:00")], COVER), "now": MORNING}])
    recon("identity", "reconciliation.identity.changed-wording",
          "Only the wording changes: the content no longer matches, so the request is added "
          "again under the same identifier.",
          "RFC 0003 §4.5 Matching (content).",
          [{"apply": plan([a(f"{D}/maghrib/atTime", MAGHRIB)], COVER), "now": MORNING},
           {"apply": plan([a(f"{D}/maghrib/atTime", MAGHRIB)], COVER), "now": MORNING,
            "wording": "v2"}])
    recon("identity", "reconciliation.identity.isha-after-midnight",
          "In Edinburgh, 21 June's Isha after-reminder moves from 23:55 to 00:05 on the 22nd. "
          "It stays the 21st's request.",
          "RFC 0003 §4.2: the owning day, even after midnight.",
          [{"apply": plan([a("2026-06-21/isha/after", "2026-06-21T23:55:00+01:00")],
                          "2026-06-23T00:00:00+01:00"), "now": "2026-06-21T20:00:00+01:00"},
           {"apply": plan([a("2026-06-21/isha/after", "2026-06-22T00:05:00+01:00")],
                          "2026-06-23T00:00:00+01:00"), "now": "2026-06-21T20:00:00+01:00"}],
          zone=LONDON)
    recon("identity", "reconciliation.identity.fajr-before-midnight",
          "In Kazan, 20 June's Fajr alert fires at 23:45 on the 19th, the same instant as the "
          "19th's Isha alert. They are two requests, each of its own day.",
          "RFC 0003 §4.2 (owning days, order); B1's note: an at-time alert for the next day's "
          "Fajr can fire before midnight.",
          [{"apply": plan([a("2026-06-19/isha/atTime", "2026-06-19T23:45:00+03:00"),
                           a("2026-06-20/fajr/atTime", "2026-06-19T23:45:00+03:00")],
                          "2026-06-21T00:00:00+03:00"), "now": "2026-06-19T22:00:00+03:00"}],
          zone=MOSCOW)

    recon("obsolete", "reconciliation.obsolete.only-owned-requests-are-removed",
          "The center holds an owned request the plan no longer wants (Asr), an owned request "
          "it still wants (Maghrib), another app's request, a request of another namespace "
          "under the same prefix, and one under the prefix that isn't an identity. Only Asr's "
          "is removed, in one call; Isha's is added.",
          "RFC 0003 §4.2 Request identifiers, §4.5 step 4; A2's "
          "obsoleteOwnRequestsAreRemovedAndOthersKept (retained).",
          [{"apply": plan([a(f"{D}/maghrib/atTime", MAGHRIB), a(f"{D}/isha/atTime", ISHA)],
                          COVER), "now": "2026-06-02T13:00:00+03:00"}],
          center={"pending": [
              pend(rid(f"{D}/asr/atTime"), ASR, "asr", "v1 atTime"),
              pend(rid(f"{D}/maghrib/atTime"), MAGHRIB, "maghrib", "v1 atTime"),
              pend("com.example.other", ASR, "Other", "Another app's request", ""),
              pend(rid(f"{D}/asr/atTime", namespace="mosque"), ASR, "asr", "v1 atTime"),
              pend("salah.prayers/legacy", ASR, "asr", "An older format", ""),
          ]})
    recon("obsolete", "reconciliation.obsolete.empty-plan-clears-the-namespace",
          "An empty plan of the scheduler's namespace removes every owned request and nothing "
          "else.",
          "RFC 0003 §4.5 step 4; A2's emptyScheduleClearsOwnRequestsAndDeliveries (retained "
          "for pending requests).",
          [{"apply": plan([], COVER), "now": MORNING}],
          center={"pending": [pend(rid(f"{D}/isha/atTime"), ISHA, "isha", "v1 atTime"),
                              pend(rid("2026-06-03/fajr/before", namespace="mosque"),
                                   "2026-06-03T04:01:00+03:00", "fajr", "v1 before"),
                              pend("com.example.other", ISHA, "Other", "Another app", "")]})
    recon("obsolete", "reconciliation.obsolete.passed-alert-with-a-stale-request",
          "The plan was made at 12:00 and is applied at 12:21: Dhuhr's alert (12:19) has "
          "passed and isn't desired, so its stale request for 12:30 is obsolete and removed. "
          "It is neither confirmed nor a failure.",
          "RFC 0003 §4.5: the desired alerts are the plan's alerts after the batch's start.",
          [{"apply": plan([a(f"{D}/dhuhr/atTime", DHUHR), a(f"{D}/asr/atTime", ASR)], COVER),
            "now": "2026-06-02T12:21:00+03:00"}],
          center={"pending": [pend(rid(f"{D}/dhuhr/atTime"), f"{D}T12:30:00+03:00", "dhuhr",
                                   "v1 atTime")]})

    recon("namespaces", "reconciliation.namespaces.foreign-plan",
          "A plan of another namespace is rejected before any call.",
          "Proposal §7.5: validate the plan's namespace before any mutation; RFC 0003 §4.5.",
          [{"apply": plan([a(f"{D}/asr/atTime", ASR)], COVER, namespace="mosque"),
            "now": MORNING}],
          center={"pending": [pend(rid(f"{D}/isha/atTime"), ISHA, "isha", "v1 atTime")]})
    recon("namespaces", "reconciliation.namespaces.empty-foreign-plan",
          "An empty plan of another namespace is rejected too, so it can't clear this "
          "scheduler's requests.",
          "Proposal §7.5: 'including for an empty plan'.",
          [{"apply": plan([], COVER, namespace="mosque"), "now": MORNING}],
          center={"pending": [pend(rid(f"{D}/isha/atTime"), ISHA, "isha", "v1 atTime")]})
    recon("namespaces", "reconciliation.namespaces.foreign-alert-in-a-plan",
          "A plan of this namespace holding one alert of another namespace is rejected whole.",
          "Proposal §7.5: 'also reject alerts from another namespace'.",
          [{"apply": plan([a(f"{D}/asr/atTime", ASR),
                           a(f"{D}/maghrib/atTime", MAGHRIB, namespace="mosque")], COVER),
            "now": MORNING}])
    recon("namespaces", "reconciliation.namespaces.duplicate-identity-in-a-plan",
          "A hand-made plan holds Asr's alert twice, at two times: it is rejected before any "
          "call, since one identifier can hold only one request.",
          "RFC 0003 §4.5 Validation.",
          [{"apply": plan([a(f"{D}/asr/atTime", ASR), a(f"{D}/asr/atTime", f"{D}T15:41:00+03:00")],
                          COVER), "now": MORNING}])
    recon("namespaces", "reconciliation.namespaces.duplicate-identity-to-deliver",
          "Delivering the same identity twice, at two fire dates, is rejected too.",
          "RFC 0003 §4.5 Validation.",
          [{"deliver": [a(f"{D}/asr/atTime", ASR), a(f"{D}/asr/atTime", f"{D}T15:36:00+03:00")],
            "now": "2026-06-02T15:36:30+03:00"}])
    recon("namespaces", "reconciliation.namespaces.foreign-alert-before-repeated-identity",
          "A plan repeats Asr's identity and holds a foreign alert after it: the namespace is "
          "checked first.",
          "RFC 0003 §4.5 Validation: namespaces are checked first.",
          [{"apply": plan([a(f"{D}/asr/atTime", ASR), a(f"{D}/asr/atTime", f"{D}T15:41:00+03:00"),
                           a(f"{D}/maghrib/atTime", MAGHRIB, namespace="mosque")], COVER),
            "now": MORNING}])
    recon("namespaces", "reconciliation.namespaces.deliver-foreign-alert",
          "Delivering an alert of another namespace is rejected before any call.",
          "RFC 0003 §4.5 Validation.",
          [{"deliver": [a(f"{D}/asr/atTime", ASR, namespace="mosque")],
            "now": "2026-06-02T15:35:30+03:00"}])

    recon("failures", "reconciliation.failures.failed-add-keeps-the-old-request",
          "Asr moves to 15:41, but adding the new request fails. The old request (15:35) is "
          "still there with the same identifier; it isn't removed, and it isn't confirmed. "
          "Confirmed coverage ends at Asr's new time.",
          "Proposal §7.5: 'an unsuccessful replacement is not reported as confirmed merely "
          "because an older request shares its logical identifier'; RFC 0003 §4.5 The report.",
          [{"apply": plan([a(f"{D}/dhuhr/atTime", DHUHR),
                           a(f"{D}/asr/atTime", f"{D}T15:41:00+03:00"),
                           a(f"{D}/maghrib/atTime", MAGHRIB)], COVER), "now": MORNING}],
          center={"pending": [pend(rid(f"{D}/asr/atTime"), ASR, "asr", "v1 atTime")],
                  "failAdds": [rid(f"{D}/asr/atTime")]})
    recon("failures", "reconciliation.failures.stale-content-on-read-back",
          "The center accepts the new wording for Maghrib but still holds the old content on "
          "read-back: Maghrib is unconfirmed, and confirmed coverage ends at its time.",
          "Proposal §7.5: matching checks include the desired fire date and content; RFC 0003 "
          "§4.5 Matching.",
          [{"apply": plan([a(f"{D}/asr/atTime", ASR), a(f"{D}/maghrib/atTime", MAGHRIB)], COVER),
            "now": MORNING, "wording": "v2"}],
          center={"pending": [pend(rid(f"{D}/asr/atTime"), ASR, "asr", "v1 atTime"),
                              pend(rid(f"{D}/maghrib/atTime"), MAGHRIB, "maghrib", "v1 atTime")],
                  "ignoreAdds": [rid(f"{D}/maghrib/atTime")]})
    recon("failures", "reconciliation.failures.request-missing-on-read-back",
          "The center accepts Isha's request and then drops it, as a system does when an app "
          "has more pending requests than it keeps: Isha is unconfirmed.",
          "RFC 0003 §4.5 The report (unconfirmed).",
          [{"apply": plan([a(f"{D}/maghrib/atTime", MAGHRIB), a(f"{D}/isha/atTime", ISHA)],
                          COVER), "now": MORNING}],
          center={"dropAdds": [rid(f"{D}/isha/atTime")]})
    recon("failures", "reconciliation.failures.read-back-fails",
          "The read-back fails: every add succeeded, but nothing is confirmed, every alert is "
          "unconfirmed, and confirmed coverage is unknown.",
          "Proposal §7.5: 'A failed read-back leaves it unknown'; 'A failure report never claims "
          "the desired plan was fully installed.' RFC 0003 §4.5 The report.",
          [{"apply": plan(DHUHR_THREE, COVER), "now": MORNING}],
          center={"failReads": [2]})
    recon("failures", "reconciliation.failures.first-read-fails",
          "The first read fails: no request is known to be owned, so nothing is removed and "
          "every desired request is added, even one that already matched. The read-back "
          "confirms them.",
          "RFC 0003 §4.5 step 2.",
          [{"apply": plan([a(f"{D}/asr/atTime", ASR), a(f"{D}/maghrib/atTime", MAGHRIB)], COVER),
            "now": MORNING}],
          center={"pending": [pend(rid(f"{D}/asr/atTime"), ASR, "asr", "v1 atTime"),
                              pend(rid("2026-06-03/fajr/atTime"), "2026-06-03T04:11:00+03:00",
                                   "fajr", "v1 atTime")],
                  "failReads": [1]})
    recon("failures", "reconciliation.failures.alert-fires-before-read-back",
          "Dhuhr's after-reminder fires at 12:24, after the batch starts (12:23) and before its "
          "read-back (12:25): it was added, the center delivered it, and it is neither "
          "confirmed nor a failure. Confirmed coverage is measured from the read-back.",
          "RFC 0003 §4.5 The report: a desired alert whose fire date has passed by verifiedAt "
          "is neither; proposal §7.5: confirmed coverage is measured from verifiedAt.",
          [{"apply": plan([a(f"{D}/dhuhr/after", DHUHR_AFTER), a(f"{D}/asr/atTime", ASR)],
                          COVER), "now": "2026-06-02T12:23:00+03:00",
            "readBackAt": "2026-06-02T12:25:00+03:00"}])
    recon("failures", "reconciliation.failures.coverage-ends-at-the-plans",
          "Every request is confirmed, but the plan's own coverage ends at 16:00 (a gap or an "
          "omitted alert): confirmed coverage is the plan's, not later.",
          "Proposal §7.5: the report's coverage can't exceed what the plan intended.",
          [{"apply": plan([a(f"{D}/asr/atTime", ASR)], f"{D}T16:00:00+03:00"), "now": MORNING}])

    recon("authorization", "reconciliation.authorization.denied",
          "Notifications are denied: the owned request is removed, nothing is added, and every "
          "desired alert fails with notAuthorized. Confirmed coverage ends at the first one.",
          "A2's deniedAuthorizationRemovesOwnRequestsAndAddsNone (retained); RFC 0003 §4.5 "
          "step 4.",
          [{"apply": plan([a(f"{D}/isha/atTime", ISHA), a("2026-06-03/fajr/atTime",
                                                         "2026-06-03T04:11:00+03:00")], COVER),
            "now": "2026-06-02T13:00:00+03:00"}],
          center={"authorization": "denied",
                  "pending": [pend(rid(f"{D}/isha/atTime"), ISHA, "isha", "v1 atTime"),
                              pend("com.example.other", ISHA, "Other", "Another app", "")]})
    recon("authorization", "reconciliation.authorization.not-determined",
          "Authorization not determined: the scheduler doesn't ask (that's the app's), adds "
          "nothing and reports notAuthorized.",
          "Proposal §7.5 'Stays in apps: authorization requests'; A2's "
          "authorizationIsRequestedOnlyWithSomethingToSchedule (app policy).",
          [{"apply": plan([a(f"{D}/isha/atTime", ISHA)], COVER),
            "now": "2026-06-02T13:00:00+03:00"}],
          center={"authorization": "notDetermined"})
    recon("authorization", "reconciliation.authorization.provisional",
          "Provisional authorization allows requests.",
          "RFC 0003 §4.5 step 1.",
          [{"apply": plan([a(f"{D}/isha/atTime", ISHA)], COVER),
            "now": "2026-06-02T13:00:00+03:00"}],
          center={"authorization": "provisional"})

    recon("housekeeping", "reconciliation.housekeeping.delivered-retention",
          "At 13:00 the two-day retention cutoff is 13:00 on 31 May. An owned notification "
          "delivered a second before it is removed; one delivered at the cutoff, a recent one, "
          "another app's and another namespace's old ones stay.",
          "A2's launchHousekeepingRemovesOnlyOldOwnDeliveredNotifications (retained); proposal "
          "§7.5 'Housekeeping'; RFC 0003 §4.5 step 5.",
          [{"apply": plan([a(f"{D}/isha/atTime", ISHA)], COVER),
            "now": "2026-06-02T13:00:00+03:00"}],
          center={"delivered": [
              {"id": rid("2026-05-31/dhuhr/atTime"), "date": "2026-05-31T12:59:59+03:00"},
              {"id": rid("2026-05-31/asr/atTime"), "date": "2026-05-31T13:00:00+03:00"},
              {"id": rid(f"{D}/dhuhr/atTime"), "date": "2026-06-02T12:19:00+03:00"},
              {"id": "com.example.other", "date": "2026-05-30T09:00:00+03:00"},
              {"id": rid("2026-05-30/fajr/atTime", namespace="mosque"),
               "date": "2026-05-30T04:11:00+03:00"},
          ]})
    recon("housekeeping", "reconciliation.housekeeping.retention-off",
          "With no retention, delivered notifications aren't read or removed.",
          "RFC 0003 §4.5 step 3.",
          [{"apply": plan([a(f"{D}/isha/atTime", ISHA)], COVER),
            "now": "2026-06-02T13:00:00+03:00"}],
          center={"delivered": [{"id": rid("2026-05-20/dhuhr/atTime"),
                                 "date": "2026-05-20T12:19:00+03:00"}]},
          scheduler={**SCHEDULER, "deliveredRetention": None})

    recon("pump", "reconciliation.pump.serialized-applies",
          "Two applies, one after the other: the second sees what the first installed and "
          "changes only what differs.",
          "Proposal §7.5: the update pump serializes complete batches.",
          [{"apply": plan(DHUHR_THREE, COVER), "now": MORNING},
           {"apply": plan([a(f"{D}/dhuhr/before", DHUHR_BEFORE_15), a(f"{D}/dhuhr/atTime", DHUHR)],
                          COVER), "now": "2026-06-02T06:05:00+03:00"}])
    recon("pump", "reconciliation.pump.overlapping-applies-reconcile-to-the-latest",
          "A first apply is suspended in its fourth call, its first add. Two more plans arrive "
          "meanwhile. The first finishes its add, finds a later plan and stops; the second "
          "never makes a call; the third reconciles the center to itself, keeping the request "
          "the first added because it still matches. The first two reports say superseded "
          "and confirm nothing.",
          "Proposal §7.5: 'A superseded update finishes any already-started system operation "
          "before the latest generation reconciles; cancellation does not undo an accepted "
          "add'; RFC 0003 §4.5 The update pump.",
          [{"apply": plan(DHUHR_THREE, COVER), "now": MORNING, "suspendAtCall": 4},
           {"apply": plan([a(f"{D}/asr/atTime", ASR)], COVER), "now": MORNING,
            "duringPrevious": True},
           {"apply": plan([a(f"{D}/dhuhr/before", DHUHR_BEFORE_10), a(f"{D}/asr/atTime", ASR)],
                          COVER), "now": MORNING, "duringPrevious": True}])

    recon("pump", "reconciliation.pump.superseded-batch-reports-what-it-saw",
          "The first apply's first add fails, and a later plan arrives while it is in flight. The "
          "superseded report still names the failed add; the latest plan then fails the same "
          "add and confirms the rest.",
          "RFC 0003 §4.5 The report: a superseded batch reports the failures it saw.",
          [{"apply": plan(DHUHR_THREE, COVER), "now": MORNING, "suspendAtCall": 4},
           {"apply": plan([a(f"{D}/dhuhr/before", DHUHR_BEFORE_10), a(f"{D}/dhuhr/atTime", DHUHR)],
                          COVER), "now": MORNING, "duringPrevious": True}],
          center={"failAdds": [rid(f"{D}/dhuhr/before")]})

    recon("deliver", "reconciliation.deliver.due-alerts",
          "At 19:46 the app passes four alerts. Isha's before-reminder was left out of the plan "
          "and is posted at once. Maghrib's after-reminder still has its pending request and is "
          "skipped. Maghrib's alert was delivered at 19:00 and is skipped. Dhuhr's "
          "after-reminder moved to 19:45 after its earlier occurrence was delivered at 12:24, so "
          "it is posted, and its new delivery replaces the old one.",
          "RFC 0003 §4.5 Delivering due alerts; A2's catchUpWindows (caught-up alerts get an "
          "immediate request).",
          [{"deliver": [a(f"{D}/isha/before", "2026-06-02T19:45:00+03:00"),
                        a(f"{D}/maghrib/after", "2026-06-02T19:50:00+03:00"),
                        a(f"{D}/maghrib/atTime", MAGHRIB),
                        a(f"{D}/dhuhr/after", "2026-06-02T19:45:00+03:00")],
            "now": "2026-06-02T19:46:00+03:00"}],
          center={"pending": [pend(rid(f"{D}/maghrib/after"), "2026-06-02T19:50:00+03:00",
                                   "maghrib", "v1 after")],
                  "delivered": [{"id": rid(f"{D}/maghrib/atTime"), "date": MAGHRIB},
                                {"id": rid(f"{D}/dhuhr/after"), "date": DHUHR_AFTER}]})
    recon("deliver", "reconciliation.deliver.just-delivered-by-the-system",
          "Asr's request fired at 15:35 and the center delivers it on the first read; the "
          "alert is skipped. An immediate post that fails is reported.",
          "RFC 0003 §4.5 Delivering due alerts.",
          [{"deliver": [a(f"{D}/asr/atTime", ASR), a(f"{D}/asr/after", "2026-06-02T15:40:00+03:00")],
            "now": "2026-06-02T15:40:01+03:00"}],
          center={"pending": [pend(rid(f"{D}/asr/atTime"), ASR, "asr", "v1 atTime")],
                  "failAdds": [rid(f"{D}/asr/after")]})
    recon("deliver", "reconciliation.deliver.failed-pending-read",
          "The pending read fails: no request counts as pending, so a due alert with no "
          "delivered notification is posted.",
          "RFC 0003 §4.5 Delivering due alerts: a pending read that throws leaves nothing "
          "pending.",
          [{"deliver": [a(f"{D}/isha/before", "2026-06-02T19:45:00+03:00")],
            "now": "2026-06-02T19:45:30+03:00"}],
          center={"failReads": [1]})
    recon("deliver", "reconciliation.deliver.failed-read-still-sees-deliveries",
          "Isha's request fires at 20:30 and the first read, which fails, delivers it first. "
          "Nothing counts as pending, but the delivered notification still shows the occurrence "
          "was delivered, so it is skipped rather than posted twice.",
          "RFC 0003 §4.5 Delivering due alerts; Vectors/README.md: a read in failReads delivers "
          "first, then throws.",
          [{"deliver": [a(f"{D}/isha/atTime", ISHA)], "now": "2026-06-02T20:30:30+03:00"}],
          center={"pending": [pend(rid(f"{D}/isha/atTime"), ISHA, "isha", "v1 atTime")],
                  "failReads": [1]})
    recon("deliver", "reconciliation.deliver.delivered-within-the-leeway",
          "Two alerts fire at 19:45. Maghrib's after-reminder was delivered at 19:44:58.500, 1.5 "
          "seconds early, which counts as this occurrence: skipped. Isha's before-reminder was "
          "delivered at 19:44:58.400, earlier than that, so it was another occurrence: posted.",
          "RFC 0003 §4.5 Delivering due alerts: a delivered notification dated no earlier than "
          "1.5 seconds before the fire date.",
          [{"deliver": [a(f"{D}/maghrib/after", "2026-06-02T19:45:00+03:00"),
                        a(f"{D}/isha/before", "2026-06-02T19:45:00+03:00")],
            "now": "2026-06-02T19:45:10+03:00"}],
          center={"delivered": [
              {"id": rid(f"{D}/maghrib/after"), "date": "2026-06-02T19:44:58.500+03:00"},
              {"id": rid(f"{D}/isha/before"), "date": "2026-06-02T19:44:58.400+03:00"}]})
    recon("deliver", "reconciliation.deliver.not-authorized",
          "Without authorization nothing is posted.",
          "RFC 0003 §4.5 Delivering due alerts.",
          [{"deliver": [a(f"{D}/asr/atTime", ASR)], "now": "2026-06-02T15:36:00+03:00"}],
          center={"authorization": "denied"})


def main():
    schedule_vectors()
    gap_vectors()
    plan_vectors()
    error_vectors()
    reconciliation_vectors()
    ids = [v["id"] for f in FILES.values() for v in f["vectors"]]
    assert len(ids) == len(set(ids)), "duplicate ids"
    for (folder, name), file in sorted(FILES.items()):
        path = os.path.join(OUT, folder, f"{name}.json")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            json.dump(file, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        print(f"{folder}/{name}.json: {len(file['vectors'])} vectors")
    print(f"{len(ids)} vectors")


if __name__ == "__main__":
    main()
