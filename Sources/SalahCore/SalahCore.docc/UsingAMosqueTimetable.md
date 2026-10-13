# Using a mosque timetable with iqama and incomplete coverage

Show a mosque's published prayer and congregation times, and stay correct where the timetable
leaves a prayer blank, skips a day or ends.

## Overview

Many mosques publish their own timetable: a begin time for each prayer, a congregation (iqama)
time for most of them, and a fixed time for Jumu'ah on Fridays. ``TimetableSource`` holds such a
table, and ``PrayerSchedule`` answers the questions a screen, a widget or a notification asks:
the events of a day, the state at a moment, and when that state next changes.

Published data has holes. A row can leave a prayer blank, a day can be missing, and every table
ends. SalahCore never fills a hole with another day's times or with a calculation. It reports
the hole as a ``ScheduleGap`` with a reason, and the state stops naming a current or next prayer
wherever the hole makes it unknowable.

### Load the timetable

A timetable has one row per date, with the times as the mosque prints them: local clock times
in the mosque's time zone. This one belongs to a fictional mosque in Edinburgh:

```json
{
  "expectedKinds": ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"],
  "rows": [
    {
      "day": "2026-10-16",
      "times": { "fajr": "05:58", "sunrise": "07:44", "dhuhr": "13:08",
                 "asr": "15:41", "maghrib": "18:16", "isha": "19:50" },
      "iqama": { "fajr": "06:30", "isha": "20:15" },
      "observances": { "dhuhr": "jumuah" }
    },
    {
      "day": "2026-10-17",
      "times": { "fajr": "06:00", "sunrise": "07:46", "dhuhr": "13:08",
                 "asr": "15:39", "maghrib": "18:13" },
      "iqama": { "fajr": "06:30" }
    },
    {
      "day": "2026-10-18",
      "times": { "fajr": "06:02", "sunrise": "07:48", "dhuhr": "13:08",
                 "asr": "15:37", "maghrib": "18:11", "isha": "19:46" },
      "iqama": { "fajr": "06:30", "isha": "20:15" }
    }
  ]
}
```

`expectedKinds` lists the events the mosque publishes; leave out `"sunrise"` when the table has
no sunrise column. Friday's Dhuhr is declared as Jumu'ah in `observances`, because SalahCore
never infers Jumu'ah from the weekday. On 17 October the mosque left Isha blank, and the table
ends after 18 October.

Decode the table, describe the mosque's location, and add the mosque's own rules for the
congregation times the table doesn't print:

```swift
let source = try JSONDecoder().decode(TimetableSource.self, from: timetableJSON)
guard let zone = TimeZone(identifier: "Europe/London") else { return }
let location = PrayerLocation(latitude: 55.9533, longitude: -3.1883, timeZone: zone)

let rules = IqamaRules(
  rules: [
    .dhuhr: .at(WallClockTime(hour: 13, minute: 30)),
    .asr: .after(minutes: 10),
    .maghrib: .after(minutes: 5),
  ],
  jumuah: .at(WallClockTime(hour: 13, minute: 45)))
let schedule = PrayerSchedule(source: source, location: location, iqama: rules)
```

A published iqama always wins over a rule, so Fajr and Isha keep the table's 06:30 and 20:15.
A declared Jumu'ah takes its iqama only from the `jumuah` rule: its congregation follows the
khutbah, so the Dhuhr rule never applies to it.

### Show a day

``PrayerSchedule/day(_:)`` returns a day's events, or the reason it has none. Format times in
the location's time zone, not the device's:

```swift
let names = PrayerNames(locale: Locale(identifier: "en_GB"))
let clock = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: location.timeZone)

let friday = CivilDay(year: 2026, month: 10, day: 16)
if case .available(let day, let coverage) = schedule.day(friday) {
  for event in day.events {
    let iqama = event.iqama.map { " (iqama \($0.formatted(clock)))" } ?? ""
    print("\(names.name(of: event)) \(event.time.formatted(clock))\(iqama)")
  }
  print(coverage == .complete)  // true
}
```

The Dhuhr event of 16 October has the observance ``PrayerObservance/jumuah``, so
``PrayerNames/name(of:)-(PrayerEvent)`` names it Jumu'ah, and its iqama is 13:45. On Saturday,
`day(_:)` still returns the five published times, with the coverage
`.partial(missing: [.isha: .noPublishedData])`.

### Show what's happening now

``PrayerSchedule/state(at:through:policy:)`` describes one moment: the latest event that
started, the next one, and whether a prayer has just started or is approaching. It only looks
ahead to the bound you pass, so pass the end of what your screen shows.

```swift
func headline(at now: Date) -> String {
  switch schedule.state(at: now, through: now.addingTimeInterval(2 * 86_400)) {
  case .available(let state, _):
    if let current = state.justStarted {
      return "\(names.name(of: current)) has started"
    }
    if let next = state.nextPrayer {
      let remaining = PrayerDurationFormat.string(
        next.time.timeIntervalSince(now), locale: names.locale)
      return "\(names.name(of: next)) in \(remaining)"
    }
    return "The next prayer isn't published yet"
  case .unavailable:
    return "The timetable doesn't cover this time"
  }
}
```

With the default ``StatePolicy``, a prayer counts as just started until its iqama:

- At 13:20 on Friday, the headline is "Jumuah has started", until the Jumu'ah iqama at 13:45.
- At 13:50 on Friday, it's "Asr in 1:51".
- At 19:00 on Saturday, it's "The timetable doesn't cover this time". Isha is blank that day, so
  it could begin at any moment between Maghrib and Sunday's Fajr. Rather than guess, the
  schedule names neither the current nor the next prayer until Sunday's Fajr.
- At 21:00 on Sunday, it's "The next prayer isn't published yet". Isha is known to have
  started, but the table has nothing after it.
- From midnight on Monday, it's "The timetable doesn't cover this time" again, until the app
  adds newer rows.

The coverage that comes with every state says why:

```swift
let evening = try Date("2026-10-17T19:00:00+01:00", strategy: .iso8601)
let state = schedule.state(at: evening, through: evening.addingTimeInterval(86_400))
for gap in state.coverage.gaps {
  print(gap.day, gap.kinds.map(\.rawValue), gap.reason)  // 2026-10-17 ["isha"] noPublishedData
}
print(state.changesAt == (try Date("2026-10-18T06:02:00+01:00", strategy: .iso8601)))  // true
```

The gap belongs to 17 October. The missing Isha could fall anywhere from that day's Maghrib to
Sunday's Fajr, and the coverage reports that span clipped to the question, so the gap starts at
19:00. ``ScheduleState/changesAt`` is the next instant at which the
state changes within the bound, here Sunday's Fajr. A screen that redraws then never shows a
stale state.

### Plan widget refreshes

A widget can't run code at each change, so it needs its entries in advance.
``PrayerSchedule/refreshPlan(from:through:strategy:policy:limit:)`` lists every instant at which
the state changes, with the state for each:

```swift
let noon = try Date("2026-10-16T12:00:00+01:00", strategy: .iso8601)
let plan = try schedule.refreshPlan(from: noon, through: noon.addingTimeInterval(6 * 3_600))
for entry in plan.entries {
  print(entry.date.formatted(clock), entry.state.prayerState?.justStarted != nil)
}
```

From noon to 18:00 on Friday, the plan has seven entries: noon; 12:53, when Jumu'ah is
approaching; 13:08, when it starts; 13:45, its iqama; 15:26, when Asr is approaching; 15:41,
when Asr starts; and 15:51, its iqama. The plan's ``RefreshPlan/validUntil`` is 18:00, the end of
the horizon. When a plan needs more entries than its `limit`, it stops at the first change it
can't hold and sets `validUntil` there, so a widget never shows a state past its last valid
entry. In an expired timetable the plan still has entries: they show the gap.

### Times after midnight and clock changes

In summer at high latitudes, Isha can begin after midnight. A timetable writes it on the row of
the day it belongs to, with `+1` for the next calendar day:

```json
{ "day": "2026-06-21", "times": { "maghrib": "22:03", "isha": "00:20+1" } }
```

That Isha belongs to 21 June even though it happens on 22 June.
``PrayerSchedule/day(containing:)`` at 00:10 on 22 June returns 22 June, the calendar day;
``PrayerSchedule/state(at:through:policy:)`` at the same moment has 21 June's Isha as its next
prayer.

On the night the clocks go back, an hour of local times happens twice; on the morning they go
forward, an hour doesn't exist. A timetable can say how to read such a time:

```json
{ "wallTimeResolution": { "repeated": "earlier", "nonexistent": "nextValid" } }
```

By default both are rejected: the time is reported missing with the reason
``ScheduleGapReason/unresolvedWallTime`` instead of guessed. The same setting in ``IqamaRules``
governs iqama times written with `.at`.
