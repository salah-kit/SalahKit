# MosqueBoard timetables

MosqueBoard runs on published prayer times and calculates nothing. The iPad and the tvOS app bundle the same two timetables, in `Shared/Timetables/`, in SalahKit's `TimetableSource` JSON shape (RFC 0001 §4.4):

| File | What it is | Zone | Days |
|---|---|---|---|
| `muis-2026.json` | Real published data: MUIS's Muslim Prayer Timetable 2026 for Singapore | `Asia/Singapore` | 2026-01-01 to 2026-12-31 |
| `edinburgh-synthetic.json` | **Synthetic.** A fictional mosque in Edinburgh, with computed times | `Europe/London` | 2026-03-01 to 2026-10-31 |

The files carry no time zone. The app supplies it through the `PrayerLocation` it pairs each file with. Neither file sets `wallTimeResolution`, so both use the default, which rejects repeated and nonexistent local times. No time in either file falls in a clock change.

## Reading the files

Each row is one owning day:

```json
{"day": "2026-06-21",
 "times": {"fajr": "03:31", "sunrise": "04:26", "dhuhr": "13:16", "asr": "17:47", "maghrib": "22:03", "isha": "01:15+1"},
 "iqama": {"fajr": "03:45", "dhuhr": "13:45", "asr": "18:00", "maghrib": "22:10", "isha": "01:25+1"}}
```

- `times` are begin (adhan) times as local wall-clock times, `"HH:MM"` on a 24-hour clock.
- `"+1"` means the clock time is on the next civil day but the prayer still belongs to the row's day. Above, the Isha of Sunday 21 June begins at 01:15 on Monday 22 June (RFC §4.2).
- `iqama` holds the published jama'ah (congregation) times. Only the synthetic file has them.
- `"observances": {"dhuhr": "jumuah"}` declares Friday's Dhuhr as Jumu'ah. Its iqama is the Jumu'ah jama'ah time. SalahKit never infers Jumu'ah from the weekday.

## `muis-2026.json`: MUIS, Singapore

| | |
|---|---|
| Dataset | [Muslim Prayer Timetable 2026](https://data.gov.sg/datasets/d_d441e7242e78efc566024dd5b0d9829c/view), dataset id `d_d441e7242e78efc566024dd5b0d9829c` |
| Publisher | Majlis Ugama Islam Singapura (MUIS), on data.gov.sg |
| Licence | [Singapore Open Data Licence version 1.0](https://data.gov.sg/open-data-licence) |
| Accessed | 2026-10-13 (dataset last updated 2026-04-02) |
| Converter | `Scripts/convert-muis.py` |

**Required attribution:**

> Contains information from Muslim Prayer Timetable 2026 accessed on 2026-10-13 from data.gov.sg (Majlis Ugama Islam Singapura) which is made available under the terms of the Singapore Open Data Licence version 1.0 https://data.gov.sg/open-data-licence

The licence asks that the use doesn't suggest MUIS or data.gov.sg endorses the app or that the data is an official MUIS product as shown. MosqueBoard is an example app and makes no such claim.

**How it was converted.** The input is the dataset's response from the data.gov.sg datastore API, with all 365 records in one page (for example `https://data.gov.sg/api/action/datastore_search?resource_id=d_d441e7242e78efc566024dd5b0d9829c&limit=400`). To reproduce the file:

```sh
python3 -I Scripts/convert-muis.py <datastore-response.json> Shared/Timetables/muis-2026.json
```

The converter uses the standard library only. It fails unless there are exactly 365 rows, one for every date of 2026, each date `YYYY-MM-DD` and each time 24-hour `HH:MM`, with the six times strictly increasing on every row. The raw download isn't committed.

| MUIS column | SalahKit kind |
|---|---|
| Subuh | `fajr` |
| Syuruk | `sunrise` |
| Zohor | `dhuhr` |
| Asar | `asr` |
| Maghrib | `maghrib` |
| Isyak | `isha` |

`expectedKinds` is all six. Other details:
- **Time format.** The 2026 rows are 24-hour `HH:mm`, although the column legend says `Time (HH:mm:ss)`. Earlier years' datasets use a 12-hour clock without AM/PM. They're ambiguous and unused.
- **Time zone.** Local Singapore time, `Asia/Singapore` (UTC+8, no daylight saving). No time is after midnight, and the shortest gap from Isha to the next Fajr is about nine hours.
- **Day column.** It's inconsistent ("Thurs", "Tues") and ignored. The weekday comes from the date (`CivilDay.weekday`).
- **No iqama and no Jumu'ah.** MUIS publishes neither, so the file has neither. MosqueBoard adds them as its own mosque policy, visibly separate from the published data: `IqamaRules` for the daily congregations, and on Fridays a declared `.jumuah` observance with its own iqama rule.
- **End of data.** The table ends on 2026-12-31. After Isha that evening the app has a real case of expired coverage and must not invent the next Fajr.

## `edinburgh-synthetic.json`: synthetic, fictional mosque

**This timetable is synthetic.** The mosque is fictional, and the times weren't copied from any real timetable. They're computed for Edinburgh (55.9533° N, 3.1883° W, `Europe/London`). The layout imitates how UK mosques print timetables: separate begin and jama'ah times, a Jumu'ah time that changes with British Summer Time, and Isha after midnight in summer. It exists because no openly licensed published timetable covers daylight saving, events after midnight, published iqama and partial rows (RFC 0001 §8).

### Begin times

The begin times were computed with [adhan-swift](https://github.com/batoulapps/adhan-swift) (MIT, Batoul Apps) at commit `a6fa2de`, by a throwaway generator outside this repository. SalahKit doesn't depend on adhan-swift, and MosqueBoard doesn't link it.

| Parameter | Value |
|---|---|
| Coordinates | 55.9533, -3.1883 |
| Method | `CalculationMethod.muslimWorldLeague`: Fajr 18°, Isha 17°, plus the method's own +1 minute on Dhuhr |
| Asr | `Madhab.shafi` (shadow length 1) |
| High-latitude rule, Isha (and sunrise, Dhuhr, Asr, Maghrib) | `.middleOfTheNight`: Isha is never later than the midpoint between sunset and the next sunrise |
| High-latitude rule, Fajr | `.seventhOfTheNight`: Fajr is never earlier than the last seventh of the night |
| Rounding | `.nearest` minute |
| Zone | `Europe/London` |

Around midsummer Edinburgh's twilight never reaches 17-18° below the horizon, so the rules decide Fajr and Isha then. With Isha at the middle of the night and Fajr in the last seventh, Isha begins after local midnight from 2 May to 10 August (99 nights, around 01:10 BST). It always stays more than two hours before the next Fajr; the shortest gap is 2 h 17 min, on the night of 16 June. A middle-of-the-night rule for both would make Isha and the next Fajr coincide, which RFC 0001 allows but is a poor example. Each prayer's high-latitude rule only affects Fajr or Isha, so the other times are identical under either rule.

### Jama'ah conventions

Every jama'ah time is at or after its begin time, and rounded up to a multiple of five minutes.

| Prayer | Jama'ah |
|---|---|
| Fajr | One fixed time per printed block: the 1st-15th and the 16th to the end of each month, split again where the clocks change. It's 10 minutes after the block's latest begin time, and always at least 5 minutes before sunrise. |
| Dhuhr | 13:00 in GMT, 13:45 in BST |
| Jumu'ah (Fridays) | 12:45 in GMT, 13:30 in BST |
| Asr | 10 minutes after it begins |
| Maghrib | 5 minutes after it begins |
| Isha | 10 minutes after it begins. After midnight it's written with `+1`, including four nights (30 April, 1 May, 11 and 12 August) where Isha begins before midnight and its jama'ah falls after it. |

### Deliberate cases

| Date | Case |
|---|---|
| Every Friday (34 rows) | Declared Jumu'ah (`"observances": {"dhuhr": "jumuah"}`) with the Jumu'ah jama'ah as Dhuhr's iqama |
| 2026-03-29 (Sunday) | Spring forward. The row is ordinary local wall-clock times, and resolves at UTC+1 while the day before resolves at UTC+0. |
| 2026-05-02 to 2026-08-10 | Isha after midnight, written `"HH:MM+1"` (late June: 01:14+1 to 01:16+1) |
| 2026-06-24 (Wednesday) | Partial row: no Isha and no Isha jama'ah (the mosque hadn't confirmed it). The other times and jama'ah are present. |
| 2026-06-26 (Friday) | Missing day: no row at all |
| 2026-10-25 (Sunday) | Fall back. It resolves at UTC+0 while the day before resolves at UTC+1. |
| 2026-10-31 (Saturday) | Last published day. After that evening's Isha the coverage expires. |

### Generator

A Swift package depending on the local adhan-swift clone by path:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EdinburghGenerator",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "<path to adhan-swift at a6fa2de>"),
    ],
    targets: [
        .executableTarget(
            name: "EdinburghGenerator",
            dependencies: [.product(name: "Adhan", package: "adhan-swift")]
        ),
    ]
)
```

`Sources/EdinburghGenerator/main.swift`, run with `swift run -j 4 EdinburghGenerator > edinburgh-synthetic.json`:

```swift
// Generates MosqueBoard's synthetic Edinburgh timetable (a fictional mosque).
//
// Begin times: adhan-swift (MIT, github.com/batoulapps/adhan-swift, commit a6fa2de),
// Muslim World League angles (Fajr 18°, Isha 17°), Shafi'i Asr, rounded to the
// nearest minute. Where twilight never ends (around midsummer) adhan-swift's
// high-latitude rule caps the time: Isha uses the middle of the night and Fajr
// the last seventh of the night, so Isha falls after local midnight while
// staying well before the next Fajr.
// Jama'ah times follow typical UK conventions (see Timetables.md).
//
// Usage: swift run -j 4 EdinburghGenerator > edinburgh-synthetic.json

import Adhan
import Foundation

let coordinates = Coordinates(latitude: 55.9533, longitude: -3.1883)
let zone = TimeZone(identifier: "Europe/London")!
let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}()

let firstDay = DateComponents(year: 2026, month: 3, day: 1)
let lastDay = DateComponents(year: 2026, month: 10, day: 31)
let missingDay = "2026-06-26"   // no row at all
let partialDay = "2026-06-24"   // Isha not yet confirmed: no Isha time, no Isha jama'ah

func parameters(_ rule: HighLatitudeRule) -> CalculationParameters {
    var parameters = CalculationMethod.muslimWorldLeague.params
    parameters.madhab = .shafi
    parameters.highLatitudeRule = rule
    parameters.rounding = .nearest
    return parameters
}
let fajrParameters = parameters(.seventhOfTheNight)
let otherParameters = parameters(.middleOfTheNight)

let kinds = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]

/// A wall-clock time on an owning day, in minutes after the day's local midnight
/// (1440 and more means the next civil day, written with "+1").
struct Wall: Comparable {
    var minutes: Int
    static func < (a: Wall, b: Wall) -> Bool { a.minutes < b.minutes }
    var text: String {
        let offset = minutes / 1440
        precondition(offset == 0 || offset == 1, "day offset \(offset)")
        let m = minutes % 1440
        return String(format: "%02d:%02d", m / 60, m % 60) + (offset == 1 ? "+1" : "")
    }
    /// Rounded up to a multiple of five minutes.
    var ceil5: Wall { Wall(minutes: (minutes + 4) / 5 * 5) }
    func plus(_ m: Int) -> Wall { Wall(minutes: minutes + m) }
}

func wall(_ date: Date, on day: DateComponents) -> Wall {
    let local = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    precondition(local.second == 0)
    let start = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
    let other = calendar.date(from: DateComponents(year: local.year, month: local.month, day: local.day, hour: 12))!
    let offset = calendar.dateComponents([.day], from: start, to: other).day!
    return Wall(minutes: offset * 1440 + local.hour! * 60 + local.minute!)
}

struct Day {
    var key: String
    var components: DateComponents
    var isFriday: Bool
    var isSummerTime: Bool
    var begins: [String: Wall]
    var fajrInstant: Date
    var ishaInstant: Date
}

var days: [Day] = []
var cursor = calendar.date(from: firstDay)!
let end = calendar.date(from: lastDay)!
while cursor <= end {
    let c = calendar.dateComponents([.year, .month, .day, .weekday], from: cursor)
    let date = DateComponents(year: c.year, month: c.month, day: c.day)
    guard let fajrTimes = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: fajrParameters),
          let times = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: otherParameters)
    else { fatalError("no prayer times for \(date)") }
    let noon = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12))!
    days.append(Day(
        key: String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!),
        components: date,
        isFriday: c.weekday == 6,
        isSummerTime: zone.isDaylightSavingTime(for: noon),
        begins: [
            "fajr": wall(fajrTimes.fajr, on: date),
            "sunrise": wall(times.sunrise, on: date),
            "dhuhr": wall(times.dhuhr, on: date),
            "asr": wall(times.asr, on: date),
            "maghrib": wall(times.maghrib, on: date),
            "isha": wall(times.isha, on: date),
        ],
        fajrInstant: fajrTimes.fajr,
        ishaInstant: times.isha
    ))
    cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
}

// Fajr jama'ah: one fixed time per printed block (1st-15th, 16th-end of month,
// split again where the clocks change), 10 minutes after the block's latest
// begin time, rounded up to 5 minutes.
func block(_ day: Day) -> String {
    "\(day.components.month!)-\(day.components.day! <= 15 ? "a" : "b")-\(day.isSummerTime)"
}
var fajrJamaah: [String: Wall] = [:]
for day in days {
    let candidate = day.begins["fajr"]!.plus(10).ceil5
    fajrJamaah[block(day)] = max(fajrJamaah[block(day)] ?? candidate, candidate)
}

var lines: [String] = []
for (index, day) in days.enumerated() where day.key != missingDay {
    let b = day.begins
    for (k1, k2) in zip(kinds, kinds.dropFirst()) {
        precondition(b[k1]! < b[k2]!, "\(day.key): \(k1) not before \(k2)")
    }
    if index + 1 < days.count {
        let gap = days[index + 1].fajrInstant.timeIntervalSince(day.ishaInstant)
        precondition(gap >= 3600, "\(day.key): Isha is less than an hour before the next Fajr")
    }

    let dhuhrJamaah = Wall(minutes: day.isSummerTime ? 13 * 60 + 45 : 13 * 60)
    let jumuahJamaah = Wall(minutes: day.isSummerTime ? 13 * 60 + 30 : 12 * 60 + 45)
    var iqama: [String: Wall] = [
        "fajr": fajrJamaah[block(day)]!,
        "dhuhr": day.isFriday ? jumuahJamaah : dhuhrJamaah,
        "asr": b["asr"]!.plus(10).ceil5,
        "maghrib": b["maghrib"]!.plus(5).ceil5,
        "isha": b["isha"]!.plus(10).ceil5,
    ]
    precondition(iqama["fajr"]! < b["sunrise"]!.plus(-5), "\(day.key): Fajr jama'ah too close to sunrise")
    for (kind, time) in iqama {
        precondition(time >= b[kind]!, "\(day.key): \(kind) jama'ah before it begins")
    }

    var times = b
    if day.key == partialDay {
        times["isha"] = nil
        iqama["isha"] = nil
    }
    func object(_ values: [String: Wall]) -> String {
        "{" + kinds.compactMap { k in values[k].map { "\"\(k)\": \"\($0.text)\"" } }.joined(separator: ", ") + "}"
    }
    var row = "{\"day\": \"\(day.key)\", \"times\": \(object(times)), \"iqama\": \(object(iqama))"
    if day.isFriday { row += ", \"observances\": {\"dhuhr\": \"jumuah\"}" }
    lines.append("    " + row + "}")
}

print("{")
print("  \"expectedKinds\": [\"fajr\", \"sunrise\", \"dhuhr\", \"asr\", \"maghrib\", \"isha\"],")
print("  \"rows\": [")
print(lines.joined(separator: ",\n"))
print("  ]")
print("}")
```

## Checking the data

`Scripts/check-timetables.py` (standard library only) checks both files against RFC 0001's row rules. It checks the shapes, the kinds, and that iqama appears only on prayers that have a time and Jumu'ah only on a Friday's Dhuhr. It resolves every wall time in its zone and checks the ranges and the canonical order, that `+1` appears only where it's needed, cross-day order, and at least an hour from Isha to the next Fajr. It also checks each file's deliberate cases. Run it from `Examples/MosqueBoard`:

```sh
python3 -I Scripts/check-timetables.py
```

It exits with 1 and lists every problem if any check fails.

## For a person to confirm

- **MUIS Asr convention.** The table is presumably Shafi'i (shadow length 1), as is usual in Singapore. Confirm with MUIS or a local scholar.
- **MUIS times around midnight.** No 2026 time is near midnight, but confirm that MUIS means plain local wall-clock times.
- **Licence fit.** Confirm that bundling SODL v1.0 data in this MIT-licensed repository, with the attribution above and a NOTICE entry, is acceptable.
- **Scottish timetables after midnight.** Check how real Scottish or northern UK mosque timetables print an Isha after midnight. They might print it as "00:20" or "12:20 am", mark it, cap it, or use a fixed time. Also check whether a 01:15 summer Isha with a 01:25 jama'ah is plausible, or whether mosques typically use an earlier fixed time. The synthetic file should keep imitating real practice.
