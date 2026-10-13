# SalahCore vectors

Language-neutral JSON test vectors for SalahCore (RFC 0001, `docs/rfcs/0001-core.md`). Each vector pairs published timetable input with the output RFC 0001 §4 requires. The Swift tests run every file here, and a Kotlin or TypeScript port can run the same files.

The vectors were written from the RFC and the SalahKit proposal before any implementation existed. Every expectation was derived by hand from the RFC's rules, and the time-zone arithmetic was checked with Python's `zoneinfo` (tzdata 2026c/2026e). All inputs are `TimetableSource` data. Calculated sources add their own vectors later (RFC 0001 §7).

## Layout

| Path | Query types | Covers |
|---|---|---|
| `state/wall-time.json` | `day`, `dayContaining`, `events` | Wall-time resolution with every policy, for prayer times, published iqama and `IqamaRules .at`; publisher instants; `CivilDay.start` where a clock change moves midnight (Asia/Beirut, America/Havana) or skips a date (Pacific/Apia, 2011-12-30) |
| `state/overnight.json` | `day`, `dayContaining`, `events`, `state` | Isha and iqama after midnight, owned by the previous civil day |
| `state/coverage.json` | `day`, `events`, `state` | Complete, partial and unavailable days, empty timetables, five-prayer tables, missing-event windows, clipping and `knownIntervals` |
| `state/unknown-future.json` | `state`, `events` | The last published evening, a missing middle day, a partial row, a missing sunrise, `latestPrayer` after sunrise |
| `state/friday-and-iqama.json` | `day` | Declared Jumu'ah versus an ordinary Friday, Jumu'ah iqama rules, published iqama precedence (and a discarded published iqama that leaves room for a rule), iqama rule edge cases across clock changes and at the end of the owning span |
| `state/invalid-data.json` | `day`, `events` | Rows that make their day `unavailable(invalidData)`, and iqama that is discarded instead |
| `state/high-latitude.json` | `day`, `events`, `state` | Maghrib and Isha after midnight, a cross-day overlap, and Isha at the same instant as the next Fajr |
| `state/policy.json` | `state` | `StatePolicy` (`justStarted`, `approaching`), `changesAt`, `status(of:)`, the before-Fajr moment |
| `state/query-limits.json` | `events`, `state` | Zero-length requests inside and outside gaps; an end before the start; the inclusive bound; the 400-civil-day clamp |
| `refresh/state-changes.json` | `refresh` | `.stateChanges` transitions and the lookahead bound |
| `refresh/budget.json` | `refresh` | The entry budget and `validUntil` cutoff |
| `refresh/coverage.json` | `refresh` | Expiring, partial and empty timetables; a cross-day overlap; a delayed next request |
| `refresh/steps.json` | `refresh` | `.steps` fine and coarse grids, including across an expiring timetable |
| `refresh/errors.json` | `refresh` | `RefreshPlanError` and the order the errors are checked in |
| `calculation/*.json` | all five | A calculated source (RFC 0002): see [Calculation vectors](#calculation-vectors) |

## File shape

```json
{
  "schemaVersion": 1,
  "description": "What this file covers.",
  "vectors": [
    {
      "id": "state.overnight.state.tuesday-0020-previous-is-monday-isha",
      "description": "One or two sentences.",
      "provenance": "Where the expectation comes from: RFC 0001 and proposal sections.",
      "input": {
        "location": { "latitude": 55.95, "longitude": -3.19, "timeZone": "Europe/London" },
        "source": { "expectedKinds": ["fajr", "..."], "wallTimeResolution": { "...": "..." }, "rows": ["..."] },
        "iqama": { "rules": { "fajr": { "after": 20 } }, "jumuah": { "at": "13:30" } },
        "policy": { "approaching": 900, "justStarted": { "untilIqama": { "fallback": 900 } } },
        "query": { "type": "state", "at": "2026-06-23T00:20:00+01:00", "through": "2026-06-25T00:00:00+01:00" }
      },
      "expected": { "...": "..." }
    }
  ]
}
```

- `schemaVersion` is `1` in every file. A harness rejects a version it doesn't know.
- `id` is unique across all files, dotted and stable: `<area>.<case>.<detail>`. Tests name failures by id.
- Every key shown is present, except `iqama` and `policy`, which are optional.

## Input

All shapes are the RFC's JSON shapes (RFC 0001 §3, §4.4).

- **`location`**: `PrayerLocation`. `timeZone` is an IANA identifier.
- **`source`**: `TimetableSource` exactly as RFC 0001 §4.4 shows it. `wallTimeResolution`, and each row's `iqama` and `observances`, are optional; their defaults are reject/reject, none and none.
  - A time is a wall-time string or an ISO 8601 instant with `Z` or an offset.
  - Wall-time strings match `^\d{1,2}:\d{2}(\+\d+)?$` and decode to hour, minute and day offset. Range checks (hour 0-23, minute 0-59, day offset 0 or 1) are row checks, not decoding errors: `"24:00"`, `"15:60"` and `"00:15+2"` decode, and their row's day is `unavailable(invalidData)` (§4.4 row checks; "Decoding fails only for malformed JSON values").
  - A row's `day` decodes as a `CivilDay` whenever it has the `YYYY-MM-DD` shape, even if it isn't a real date (`"2026-02-30"`); such a day is invalid (§4.1, §4.4 step 1).
- **`iqama`** (optional): `IqamaRules`, `{"rules": {kind: Rule}, "jumuah": Rule, "wallTimeResolution": {...}}`. A `Rule` is `{"after": minutes}` or `{"at": "HH:MM"}` / `{"at": "HH:MM+1"}`. Each of the three keys is optional: `rules` defaults to none, `jumuah` to none, `wallTimeResolution` to reject/reject. Absent `iqama` means the schedule is built with `iqama: nil`.
- **`policy`** (optional): `StatePolicy`, durations in seconds. `justStarted` is `{"untilIqama": {"fallback": s}}` or `{"fixed": s}`. Absent means the default policy, `{"approaching": 900, "justStarted": {"untilIqama": {"fallback": 900}}}`. Negative values are allowed and count as zero (§4.7).
- **`query`**: one of the query types below.

Build `PrayerSchedule(source:location:iqama:)` from `source`, `location` and `iqama`, then run the query.

## Query types

| `type` | Fields | Call |
|---|---|---|
| `day` | `day`: `"YYYY-MM-DD"` | `schedule.day(day)` |
| `dayContaining` | `date`: instant | `schedule.day(containing: date)` |
| `events` | `from`, `through`: instants | `schedule.events(from:through:)` |
| `state` | `at`, `through`: instants | `schedule.state(at:through:policy:)` with `input.policy` |
| `refresh` | `from`, `through`: instants; `strategy`; `limit` (optional, default 96) | `schedule.refreshPlan(from:through:strategy:policy:limit:)` with `input.policy` |

`strategy` is `"stateChanges"` or `{"steps": {"fine": s, "coarse": s, "window": s}}` (seconds).

Most `state` vectors use `through = start(civil(at) + 2)`, the bound `PrayerFixtures.Moment` uses; a few use a later bound so that a later day could become `next` if the rules allowed it, and a few an earlier one to test the bound itself.

## Expected shapes

**Event reference** (`EventRef`), used everywhere an event appears:

```json
{"day": "2026-06-22", "kind": "isha", "time": "2026-06-23T00:15:00+01:00", "iqama": "2026-06-23T00:30:00+01:00", "observance": "ordinary"}
```

`day` is the owning `scheduleDay`, `iqama` is `null` when the event has none, and `observance` is `"ordinary"` or `"jumuah"`.

**Coverage** (`ScheduleCoverage`):

```json
{
  "requested": ["<start>", "<end>"],
  "known": [["<start>", "<end>"]],
  "gaps": [{"start": "<lo>", "end": "<hi>", "day": "YYYY-MM-DD", "kinds": ["isha"], "reason": "noPublishedData"}]
}
```

Gaps are half-open `[start, end)`, clipped to the request. For a zero-length request (`from` equal to, or after, `through`), each gap containing the instant appears as `[a, a]`, and `known` is `[[a, a]]` only when no gap is kept (RFC 0001 §4.6). `kinds` are written in canonical order.

**`day` and `dayContaining`:**

```json
{"availability": "available", "coverage": "complete", "isFriday": false, "events": [EventRef, ...]}
{"availability": "available", "coverage": {"partial": {"fajr": "unresolvedWallTime", "asr": "noPublishedData"}}, "isFriday": false, "events": [...]}
{"availability": "unavailable", "reason": "noPublishedData"}
```

**`events`:** `{"events": [EventRef, ...], "coverage": Coverage}`.

**`state`:**

```json
{
  "availability": "available",
  "previous": EventRef, "latestPrayer": EventRef, "next": null, "nextPrayer": EventRef, "justStarted": null,
  "isApproaching": false,
  "changesAt": "<instant>" | null,
  "coverage": Coverage,
  "statuses": {"YYYY-MM-DD/kind": "passed" | "justStarted" | "next" | "nextApproaching" | "upcoming"}
}
```

- Every field is listed. For an `unavailable` state, the five event fields are `null` and `isApproaching` is `false`; `changesAt` and `coverage` come from `ScheduleState.changesAt` and `.coverage`.
- `statuses` is optional and appears only for available states. For each key `"D/kind"`, take the event of that kind from `schedule.day(D)` and compare `prayerState.status(of: event)`: `.next(approaching: false)` is `"next"`, `.next(approaching: true)` is `"nextApproaching"`.

**`refresh`:**

```json
{"dates": ["<instant>", ...], "validUntil": "<instant>", "isTruncated": false,
 "entries": [{"index": 0, "availability": "available", "previous": EventRef, "...": "..."}]}
{"error": "nonPositiveHorizon" | "limitTooSmall" | "invalidStrategy"}
```

- `dates` is `RefreshPlan.dates`, the entries' dates in order.
- `entries` spot-checks entry states: `index` selects `plan.entries[index]`, and only the state fields present are checked (the `state` field names; `coverage` there may hold only `gaps`).

## Comparison rules

- **Instants** are compared as instants, exactly, to the millisecond. The strings are written in the location's offset to help a reader; a harness parses them and never compares strings.
- **Days, kinds, reasons, observances and statuses** are compared as strings.
- **Lists are ordered**:
  - events in events order (instant, then owning day, then canonical kind; RFC 0001 §4.6);
  - `known` by start;
  - `gaps` are compared as arrays, element by element, in the order RFC 0001 §4.6 defines: by start, then day, then reason in declaration order (`noPublishedData`, `calculationUnavailable`, `invalidData`, `unresolvedWallTime`). Every expected `gaps` array is listed in exactly that order;
  - `dates` ascending.
- **Gap `kinds`** and **`partial` coverage** are compared as a set and a map.
- **An EventRef** matches when its day, kind, time, iqama and observance all match.
- **Absent keys**: in `coverage`, a missing `requested`, `known` or `gaps` key isn't checked (only the 400-day clamp vectors omit some, to avoid hundreds of gaps). In `refresh` entries, only the listed fields are checked. A missing `statuses` isn't checked. Every other key in `expected` must match.

## Data

The times are synthetic. They resemble published tables for their places (Singapore, Edinburgh, New York, Beirut, Havana, Reykjavik, Apia) so a reader can follow them, but they aren't copied from any timetable, and some are placed deliberately (a Fajr inside a clock change, an Isha after the next Fajr). The Singapore-like rows repeat the same six times every day to keep the arithmetic checkable.

## Calculation vectors

`calculation/` holds vectors for SalahCalculation's `CalculationSource` (RFC 0002, `docs/rfcs/0002-calculation.md`, section 7). They use the schema above with one difference in the input: `settings` replaces `source`.

- **`settings`**: a `CalculationSettings` value, `{"parameters": <parameters>}`, where the parameters are SalahTimes' `CalculationParameters` JSON (SalahTimes' `Vectors/README.md` lists the keys). Missing keys decode as SalahTimes' defaults; only `fajr` and `isha` are required.
- Build `PrayerSchedule(source: CalculationSource(settings), location:, iqama:)` from `settings`, `location` and `iqama`, then run the query as above. Query types, expected shapes and comparison rules are unchanged.
- Ids start with `calculation.<file>.`.

| File | Query types | Covers |
|---|---|---|
| `calculation/ordinary.json` | `day`, `dayContaining`, `events`, `state` | Complete days at several places and methods, method and user adjustments, rounding up, Hanafi Asr, defaulted parameter keys |
| `calculation/owning-days.json` | `day`, `dayContaining`, `events`, `state` | Isha after midnight owned by the evening before (Kashgar); Fajr before midnight owned by the next day within the 12-hour lead, tied with the previous Isha (Kazan, middle-of-the-night rule) or moved there by a user adjustment (Makkah); the lead in queries that end before midnight |
| `calculation/polar.json` | `day`, `events`, `state` | Polar day and night (Tromsø) and a disabled high-latitude rule (Oslo): missing kinds, their windows and the states across them |
| `calculation/ordering.json` | `day`, `events`, `state` | Ties (Tehran's method at Oslo, Diyanet at 66° N), inverted pairs (Fajr after sunrise, Isha before Maghrib) and an Isha after the next day's first event (Umm al-Qura at 66.5° N, an Isha adjusted into the next day) |
| `calculation/failures.json` | `day`, `events` | Every failure of RFC 0002 §4.5: invalid coordinates and parameters, years outside 1000–3000 and the supported range's first and last days, an invalid date, Pacific/Apia's skipped 2011-12-30 and the days around it, a day with no kind left, a Fajr before the lead |
| `calculation/opt-ins.json` | `day`, `state` | The Ramadan Isha rule off and on, Ramadan's last day and the day after, a Hijri day offset, an angle-based Isha the rule leaves alone, and a Friday whose Dhuhr stays ordinary under a Jumu'ah iqama rule |
| `calculation/clock-changes.json` | `day`, `events`, `state` | Spring forward and fall back (London, New York), Beirut's skipped midnight, a state just after the clocks go forward |
| `calculation/state-and-refresh.json` | `refresh`, `state` | `.stateChanges` plans across an early-Fajr night, a polar day and night, a missing Isha, a disabled rule and Isha after midnight; the entry budget; states on Kazan's early-Fajr evening and in London's repeated hour |

**Where the expectations come from.** The instants are SalahTimes' results from its independent Python reference implementation (`Vectors/reference/salahtimes_reference.py` at SalahTimes 0.1.0), not from the Swift engine. Which of them each answer holds, and the coverage, windows, states and plans, follow RFC 0002 §4 and RFC 0001 §4.3–§4.8; they were derived from the RFCs without reading SalahCalculation's implementation. Every vector uses minute-rounded parameters, and no rounded instant it depends on lies within a second of a rounding boundary (the reference and the Swift engine agree within about half a second before rounding). An instant is written in the location's offset, or in UTC where the zone then kept local mean time with seconds in its offset (the year 1000).

A change to a calculation vector needs a written reason in RFC 0002 §10, in the same commit.

## Changing a vector

These vectors are the contract SalahCore is tested against. After the independent review, a change to an existing vector, its input or its expected output needs a written reason in RFC 0001 §10, in the same commit. Adding a vector needs no entry, but its id must be new: never reuse or rename an existing id. A change to the file shape increments `schemaVersion` in every file and this README.
