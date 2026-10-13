# SalahFixtures data

This is the provenance record for the data behind `PrayerFixtures`: eight places with five consecutive daily rows each (four for `incomplete`), and seven moments. The begin times are computed, not published. The file lists every number, where it came from and how it was checked, so the fixtures can be audited or rebuilt without the tool that made them.

The tables under "Places" and "Moments" and the list under "Checks run by the generator" are the generator's output, inserted as it wrote them. The independent checks ran separately and are described under "Independent checks".

`PrayerFixtures` holds these tables as Swift code, in `PrayerFixtures+Places.swift` and `PrayerFixtures+Moments.swift`. The tests in `Tests/SalahFixturesTests` read this file and compare every begin time, every iqama and every moment with it, so a change to one without the other fails them.

## Conventions

- A time is a local wall-clock time in the place's time zone, written `HH:MM`. `HH:MM+1` is a time after local midnight that belongs to the previous day's row (RFC 0001, section 4.2).
- Begin times are whole minutes. The calculator rounds them to the nearest minute, or up, as each place says.
- A row covers one civil day. Each place has its featured day and the two days on either side. `incomplete` has four rows, because one of its five days has no row.
- Every place expects all six kinds: fajr, sunrise, dhuhr, asr, maghrib and isha.
- Iqama times are published values carried by the rows (`Row.iqama`), not `IqamaRules`. Each is the begin time plus a fixed number of minutes, so it is also a whole minute.
- Moments are ISO 8601 instants, written once with the place's UTC offset and once in UTC.

## Provenance

| | |
| --- | --- |
| Calculator | adhan-swift, commit `a6fa2deee80c5abb0b9ad04466f8ab12b53144e7` ("Merge pull request #96 from batoulapps/develop"), MIT License, Copyright (c) 2016 Batoul Apps |
| How it was used | As a calculator only. A throwaway Swift package outside this repository depends by path on a read-only local clone of adhan-swift. SalahKit contains none of its code and doesn't depend on it. |
| Generator | The two files listed at the end of this document |
| Machine | macOS 27.0.1 on arm64, Apple Swift 6.4 |
| Time zone data | tz database 2026c, the copy that Foundation (`icutz`) and Python's zoneinfo (`zoneinfo`) both read on this machine |
| Run on | 2026-10-13 |

A different adhan-swift commit or tz database can move a time by a minute. The fixtures keep the values below.

## Decisions

- London uses the Moonsighting Committee method rather than Muslim World League with a high-latitude rule. adhan-swift recommends it for the UK. At 51.5° N in June the 18° angles are never reached, and the Committee's seasonal rule supplies real Fajr and Isha times. Isha is late (22:41 to 22:43) but before midnight. The after-midnight case is Reykjavik's.
- Reykjavik uses Muslim World League with the seventh-of-the-night rule, which is also what adhan-swift picks by default above 48° N. Maghrib (00:03 or 00:04) and Isha (00:28 or 00:29) fall after midnight and carry `+1`. Every night's Isha is at least 2 h 2 min before the next Fajr. The other two rules are compared in the Reykjavik section: the middle of the night puts Isha one minute after the next Fajr on the night of 2026-06-21, which breaks the cross-day chronology rule of RFC 0001, section 4.3 (rule 6, and open question 3 in section 9), and the twilight angle leaves 1 h 11 min.
- The `friday` row for 2026-10-16 declares Jumu'ah, and its Dhuhr iqama is the Jumu'ah iqama at 12:15 local time. The other `friday` rows and all `jakarta` rows use Dhuhr + 10 minutes. `jakarta` ends on 2026-10-15, so it has no Friday.
- `ramadan` sets adhan-swift's Isha interval to 120 minutes after Maghrib. adhan-swift's documentation describes the same result as the preset's 90 minutes plus a 30-minute adjustment.
- Moments are anchored to the rounded begin times in the tables, not to unrounded values, so each one falls on a whole minute.
- `incomplete` removes data on purpose. The 2026-11-10 row has no Isha, 2026-11-11 has no row, and the table ends after 2026-11-13. The removed times were computed like the others and are listed under that place.

## Places

| Id | Place | Zone | Featured day | Method | Rows | Iqama |
| --- | --- | --- | --- | --- | --- | --- |
| `makkah` | Makkah, SA | `Asia/Riyadh` | 2026-10-13 | Umm al-Qura University, Makkah | 5 | published |
| `londonSummer` | London, GB | `Europe/London` | 2026-06-21 | Moonsighting Committee Worldwide | 5 | - |
| `reykjavikJune` | Reykjavik, IS | `Atlantic/Reykjavik` | 2026-06-21 | Muslim World League with the seventh-of-the-night rule | 5 | - |
| `newYorkDSTChange` | New York, US | `America/New_York` | 2026-03-08 | ISNA (Islamic Society of North America) | 5 | - |
| `jakarta` | Jakarta, ID | `Asia/Jakarta` | 2026-10-13 | Singapore/Kemenag-like | 5 | published |
| `friday` | Jakarta, ID | `Asia/Jakarta` | 2026-10-16 | Singapore/Kemenag-like | 5 | published |
| `ramadan` | Makkah, SA | `Asia/Riyadh` | 2026-03-01 | Umm al-Qura University, Makkah, with its Ramadan Isha interval | 5 | - |
| `incomplete` | Singapore, SG | `Asia/Singapore` | 2026-11-11 | Singapore preset, MUIS-like | 4 of 5 days | - |

### `makkah`: Makkah, SA

- Coordinates: 21.4225° N, 39.8262° E
- Time zone: `Asia/Riyadh`; UTC offset at noon: +03:00 (2026-10-11 to 2026-10-15)
- Featured day: 2026-10-13 (Tue); rows 2026-10-11 to 2026-10-15
- Method: Umm al-Qura University, Makkah; preset `ummAlQura`; Fajr 18.5°; Isha 90 min after Maghrib; Asr `shafi` (shadow factor 1); rounding `nearest`; preset offsets: none; high-latitude rule left unset (adhan would use `middleOfTheNight` here); all three rules give identical times on every row
- Iqama: published, minutes after the begin time: Fajr +25, Dhuhr +20, Asr +20, Maghrib +10, Isha +20

Begin times (local wall clock; `+1` is the next civil day):

| Day | Weekday | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-11 | Sun | 04:59 | 06:15 | 12:07 | 15:29 | 18:00 | 19:30 |  |
| 2026-10-12 | Mon | 04:59 | 06:15 | 12:07 | 15:28 | 17:59 | 19:29 |  |
| **2026-10-13** | Tue | 04:59 | 06:16 | 12:07 | 15:28 | 17:58 | 19:28 | featured day |
| 2026-10-14 | Wed | 05:00 | 06:16 | 12:07 | 15:27 | 17:57 | 19:27 |  |
| 2026-10-15 | Thu | 05:00 | 06:16 | 12:06 | 15:27 | 17:56 | 19:26 |  |

Published iqama (local wall clock):

| Day | Fajr | Dhuhr | Asr | Maghrib | Isha |
| --- | --- | --- | --- | --- | --- |
| 2026-10-11 | 05:24 | 12:27 | 15:49 | 18:10 | 19:50 |
| 2026-10-12 | 05:24 | 12:27 | 15:48 | 18:09 | 19:49 |
| 2026-10-13 | 05:24 | 12:27 | 15:48 | 18:08 | 19:48 |
| 2026-10-14 | 05:25 | 12:27 | 15:47 | 18:07 | 19:47 |
| 2026-10-15 | 05:25 | 12:26 | 15:47 | 18:06 | 19:46 |

### `londonSummer`: London, GB

- Coordinates: 51.5072° N, 0.1276° W
- Time zone: `Europe/London`; UTC offset at noon: +01:00 (2026-06-19 to 2026-06-23)
- Featured day: 2026-06-21 (Sun); rows 2026-06-19 to 2026-06-23
- Method: Moonsighting Committee Worldwide; preset `moonsightingCommittee`; Fajr 18°; Isha 18°; Asr `shafi` (shadow factor 1); rounding `nearest`; preset offsets: Dhuhr +5 min, Maghrib +3 min; shafaq `general`; high-latitude rule left unset (adhan would use `seventhOfTheNight` here); all three rules give identical times on every row
- Iqama: none
- In June at this latitude the sun never gets lower than about 15° below the horizon (latitude + declination - 90° = -15.05°), so the 18° angles are never reached. The method's seasonal rule sets Fajr (119 to 120 min before sunrise) and Isha (77 to 78 min after Maghrib) on every row. Isha is late but before midnight.

Begin times (local wall clock; `+1` is the next civil day):

| Day | Weekday | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-06-19 | Fri | 02:44 | 04:43 | 13:07 | 17:25 | 21:24 | 22:41 | Friday: Jumu'ah not declared, so Dhuhr is ordinary |
| 2026-06-20 | Sat | 02:43 | 04:43 | 13:07 | 17:25 | 21:24 | 22:42 |  |
| **2026-06-21** | Sun | 02:43 | 04:43 | 13:07 | 17:25 | 21:25 | 22:42 | featured day |
| 2026-06-22 | Mon | 02:43 | 04:43 | 13:08 | 17:25 | 21:25 | 22:43 |  |
| 2026-06-23 | Tue | 02:44 | 04:44 | 13:08 | 17:26 | 21:25 | 22:42 |  |

### `reykjavikJune`: Reykjavik, IS

- Coordinates: 64.1466° N, 21.9426° W
- Time zone: `Atlantic/Reykjavik`; UTC offset at noon: +00:00 (2026-06-19 to 2026-06-23)
- Featured day: 2026-06-21 (Sun); rows 2026-06-19 to 2026-06-23
- Method: Muslim World League with the seventh-of-the-night rule; preset `muslimWorldLeague`; Fajr 18°; Isha 17°; Asr `shafi` (shadow factor 1); rounding `nearest`; preset offsets: Dhuhr +1 min; high-latitude rule `seventhOfTheNight`, set explicitly
- Iqama: none
- The sun's lowest altitude is about -2.4° (latitude + declination - 90°), so the 18° and 17° angles are never reached and the seventh-of-the-night rule sets Fajr and Isha. The night from Maghrib to the next sunrise lasts 171 to 172 min. Maghrib and Isha are after local midnight on every row, so they carry `+1`.

Begin times (local wall clock; `+1` is the next civil day):

| Day | Weekday | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-06-19 | Fri | 02:31 | 02:55 | 13:30 | 18:22 | 00:03+1 | 00:28+1 | Friday: Jumu'ah not declared, so Dhuhr is ordinary |
| 2026-06-20 | Sat | 02:31 | 02:55 | 13:30 | 18:22 | 00:04+1 | 00:28+1 |  |
| **2026-06-21** | Sun | 02:31 | 02:55 | 13:31 | 18:23 | 00:04+1 | 00:29+1 | featured day |
| 2026-06-22 | Mon | 02:31 | 02:55 | 13:31 | 18:23 | 00:04+1 | 00:29+1 |  |
| 2026-06-23 | Tue | 02:31 | 02:56 | 13:31 | 18:23 | 00:04+1 | 00:29+1 |  |

The three high-latitude rules for the night of 2026-06-21 (chosen: the first):

| Rule | Maghrib 2026-06-21 | Isha 2026-06-21 | Fajr 2026-06-22 | Isha to Fajr |
| --- | --- | --- | --- | --- |
| `seventhOfTheNight` | 00:04+1 | 00:29+1 | 02:31 | 2 h 2 min |
| `middleOfTheNight` | 00:04+1 | 01:30+1 | 01:29 | -1 min: Isha is not before the next Fajr |
| `twilightAngle` | 00:04+1 | 00:53+1 | 02:04 | 1 h 11 min |

### `newYorkDSTChange`: New York, US

- Coordinates: 40.7128° N, 74.0060° W
- Time zone: `America/New_York`; UTC offset at noon: -05:00 (2026-03-06 to 2026-03-07), -04:00 (2026-03-08 to 2026-03-10); the clocks change at 2026-03-08T07:00:00Z: 2026-03-08T02:00:00-05:00 becomes 2026-03-08T03:00:00-04:00
- Featured day: 2026-03-08 (Sun); rows 2026-03-06 to 2026-03-10
- Method: ISNA (Islamic Society of North America); preset `northAmerica`; Fajr 15°; Isha 15°; Asr `shafi` (shadow factor 1); rounding `nearest`; preset offsets: Dhuhr +1 min; high-latitude rule left unset (adhan would use `middleOfTheNight` here); all three rules give identical times on every row
- Iqama: none

Begin times (local wall clock; `+1` is the next civil day):

| Day | Weekday | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-03-06 | Fri | 05:07 | 06:22 | 12:08 | 15:22 | 17:53 | 19:08 | Friday: Jumu'ah not declared, so Dhuhr is ordinary |
| 2026-03-07 | Sat | 05:06 | 06:20 | 12:08 | 15:22 | 17:54 | 19:09 |  |
| **2026-03-08** | Sun | 06:04 | 07:19 | 13:08 | 16:23 | 18:55 | 20:10 | featured day; clocks go forward at 02:00; every begin time is after the change |
| 2026-03-09 | Mon | 06:02 | 07:17 | 13:07 | 16:24 | 18:56 | 20:11 |  |
| 2026-03-10 | Tue | 06:01 | 07:16 | 13:07 | 16:24 | 18:57 | 20:12 |  |

### `jakarta`: Jakarta, ID

- Coordinates: 6.2088° S, 106.8456° E
- Time zone: `Asia/Jakarta`; UTC offset at noon: +07:00 (2026-10-11 to 2026-10-15)
- Featured day: 2026-10-13 (Tue); rows 2026-10-11 to 2026-10-15
- Method: Singapore/Kemenag-like; preset `singapore`; Fajr 20°; Isha 18°; Asr `shafi` (shadow factor 1); rounding `up`; preset offsets: Dhuhr +1 min; high-latitude rule left unset (adhan would use `middleOfTheNight` here); all three rules give identical times on every row
- Iqama: published, minutes after the begin time: Fajr +10, Dhuhr +10, Asr +10, Maghrib +10, Isha +10
- adhan-swift documents the Singapore preset as "Used in Singapore, Malaysia, and Indonesia". The times are computed, not taken from an official Indonesian timetable.

Begin times (local wall clock; `+1` is the next civil day):

| Day | Weekday | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-11 | Sun | 04:16 | 05:34 | 11:41 | 14:43 | 17:46 | 18:56 |  |
| 2026-10-12 | Mon | 04:15 | 05:33 | 11:41 | 14:43 | 17:46 | 18:56 |  |
| **2026-10-13** | Tue | 04:15 | 05:33 | 11:40 | 14:44 | 17:46 | 18:56 | featured day |
| 2026-10-14 | Wed | 04:14 | 05:32 | 11:40 | 14:44 | 17:46 | 18:56 |  |
| 2026-10-15 | Thu | 04:14 | 05:32 | 11:40 | 14:45 | 17:46 | 18:56 |  |

Published iqama (local wall clock):

| Day | Fajr | Dhuhr | Asr | Maghrib | Isha |
| --- | --- | --- | --- | --- | --- |
| 2026-10-11 | 04:26 | 11:51 | 14:53 | 17:56 | 19:06 |
| 2026-10-12 | 04:25 | 11:51 | 14:53 | 17:56 | 19:06 |
| 2026-10-13 | 04:25 | 11:50 | 14:54 | 17:56 | 19:06 |
| 2026-10-14 | 04:24 | 11:50 | 14:54 | 17:56 | 19:06 |
| 2026-10-15 | 04:24 | 11:50 | 14:55 | 17:56 | 19:06 |

### `friday`: Jakarta, ID

- Coordinates: 6.2088° S, 106.8456° E
- Time zone: `Asia/Jakarta`; UTC offset at noon: +07:00 (2026-10-14 to 2026-10-18)
- Featured day: 2026-10-16 (Fri); rows 2026-10-14 to 2026-10-18
- Method: Singapore/Kemenag-like; preset `singapore`; Fajr 20°; Isha 18°; Asr `shafi` (shadow factor 1); rounding `up`; preset offsets: Dhuhr +1 min; high-latitude rule left unset (adhan would use `middleOfTheNight` here); all three rules give identical times on every row
- Iqama: published, minutes after the begin time: Fajr +10, Dhuhr +10, Asr +10, Maghrib +10, Isha +10; the Jumu'ah on 2026-10-16 has its own iqama at 12:15 local time
- adhan-swift documents the Singapore preset as "Used in Singapore, Malaysia, and Indonesia". The times are computed, not taken from an official Indonesian timetable.

Begin times (local wall clock; `+1` is the next civil day):

| Day | Weekday | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-14 | Wed | 04:14 | 05:32 | 11:40 | 14:44 | 17:46 | 18:56 |  |
| 2026-10-15 | Thu | 04:14 | 05:32 | 11:40 | 14:45 | 17:46 | 18:56 |  |
| **2026-10-16** | Fri | 04:13 | 05:32 | 11:40 | 14:45 | 17:46 | 18:56 | featured day; Friday: Dhuhr declared as Jumu'ah, Jumu'ah iqama 12:15 |
| 2026-10-17 | Sat | 04:13 | 05:31 | 11:40 | 14:46 | 17:46 | 18:56 |  |
| 2026-10-18 | Sun | 04:12 | 05:31 | 11:39 | 14:46 | 17:46 | 18:56 |  |

Published iqama (local wall clock):

| Day | Fajr | Dhuhr | Asr | Maghrib | Isha |
| --- | --- | --- | --- | --- | --- |
| 2026-10-14 | 04:24 | 11:50 | 14:54 | 17:56 | 19:06 |
| 2026-10-15 | 04:24 | 11:50 | 14:55 | 17:56 | 19:06 |
| 2026-10-16 | 04:23 | 12:15 | 14:55 | 17:56 | 19:06 |
| 2026-10-17 | 04:23 | 11:50 | 14:56 | 17:56 | 19:06 |
| 2026-10-18 | 04:22 | 11:49 | 14:56 | 17:56 | 19:06 |

### `ramadan`: Makkah, SA

- Coordinates: 21.4225° N, 39.8262° E
- Time zone: `Asia/Riyadh`; UTC offset at noon: +03:00 (2026-02-27 to 2026-03-03)
- Featured day: 2026-03-01 (Sun); rows 2026-02-27 to 2026-03-03
- Method: Umm al-Qura University, Makkah, with its Ramadan Isha interval; preset `ummAlQura`; Fajr 18.5°; Isha 120 min after Maghrib; Asr `shafi` (shadow factor 1); rounding `nearest`; preset offsets: none; high-latitude rule left unset (adhan would use `middleOfTheNight` here); all three rules give identical times on every row
- Iqama: none
- Isha is Maghrib + 120 min on every row: the preset's 90 minutes plus the 30 that adhan-swift's documentation says to add in Ramadan. The first row is a Friday with no Jumu'ah declared.

Begin times (local wall clock; `+1` is the next civil day):

| Day | Weekday | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-02-27 | Fri | 05:27 | 06:43 | 12:33 | 15:55 | 18:24 | 20:24 | Friday: Jumu'ah not declared, so Dhuhr is ordinary; 10 Ramadan 1447 AH |
| 2026-02-28 | Sat | 05:26 | 06:42 | 12:33 | 15:55 | 18:24 | 20:24 | 11 Ramadan 1447 AH |
| **2026-03-01** | Sun | 05:25 | 06:41 | 12:33 | 15:55 | 18:25 | 20:25 | featured day; 12 Ramadan 1447 AH |
| 2026-03-02 | Mon | 05:25 | 06:41 | 12:33 | 15:55 | 18:25 | 20:25 | 13 Ramadan 1447 AH |
| 2026-03-03 | Tue | 05:24 | 06:40 | 12:33 | 15:55 | 18:26 | 20:26 | 14 Ramadan 1447 AH |

### `incomplete`: Singapore, SG

- Coordinates: 1.3521° N, 103.8198° E
- Time zone: `Asia/Singapore`; UTC offset at noon: +08:00 (2026-11-09 to 2026-11-13)
- Featured day: 2026-11-11 (Wed); rows 2026-11-09 to 2026-11-13
- Method: Singapore preset, MUIS-like; preset `singapore`; Fajr 20°; Isha 18°; Asr `shafi` (shadow factor 1); rounding `up`; preset offsets: Dhuhr +1 min; high-latitude rule left unset (adhan would use `middleOfTheNight` here); all three rules give identical times on every row
- Iqama: none
- Expected kinds are all six, so the partial row reports Isha as not published and the missing day has no row at all. The last published day is the last row; nothing follows it.

Begin times (local wall clock; `+1` is the next civil day):

| Day | Weekday | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-09 | Mon | 05:27 | 06:47 | 12:50 | 16:11 | 18:51 | 20:03 |  |
| 2026-11-10 | Tue | 05:27 | 06:47 | 12:50 | 16:11 | 18:51 | - | partial row: Isha not published |
| **2026-11-11** | Wed | - | - | - | - | - | - | no row for this day |
| 2026-11-12 | Thu | 05:27 | 06:47 | 12:50 | 16:12 | 18:51 | 20:03 |  |
| 2026-11-13 | Fri | 05:27 | 06:48 | 12:50 | 16:12 | 18:51 | 20:04 | Friday: Jumu'ah not declared, so Dhuhr is ordinary; last published day |

Computed but withheld, so the fixture has no row for them: Isha on 2026-11-10, 20:03; all six times on 2026-11-11 (Fajr 05:27, Sunrise 06:47, Dhuhr 12:50, Asr 16:12, Maghrib 18:51, Isha 20:03).

## Moments

| Moment | Place | Instant (place offset) | Instant (UTC) | Derivation |
| --- | --- | --- | --- | --- |
| `approaching` | `makkah` | `2026-10-13T17:48:00+03:00` | `2026-10-13T14:48:00Z` | Maghrib 17:58 on 2026-10-13 - 10 min |
| `justStarted` | `londonSummer` | `2026-06-21T13:11:00+01:00` | `2026-06-21T12:11:00Z` | Dhuhr 13:07 on 2026-06-21 + 4 min |
| `afterIsha` | `jakarta` | `2026-10-13T19:26:00+07:00` | `2026-10-13T12:26:00Z` | Isha 18:56 on 2026-10-13 + 30 min |
| `beforeFajr` | `newYorkDSTChange` | `2026-03-08T01:30:00-05:00` | `2026-03-08T06:30:00Z` | 01:30 local time on 2026-03-08, offset -05:00 |
| `partialDay` | `incomplete` | `2026-11-10T19:21:00+08:00` | `2026-11-10T11:21:00Z` | Maghrib 18:51 on 2026-11-10 + 30 min |
| `missingDay` | `incomplete` | `2026-11-11T12:00:00+08:00` | `2026-11-11T04:00:00Z` | 12:00 local time on 2026-11-11, offset +08:00 |
| `afterLastPublishedDay` | `incomplete` | `2026-11-13T20:34:00+08:00` | `2026-11-13T12:34:00Z` | Isha 20:04 on 2026-11-13 + 30 min |

What surrounds each moment in the published rows (before any coverage rule):

- `approaching`: published event before: Asr 15:28 (row 2026-10-13); after: Maghrib 17:58 (row 2026-10-13)
- `justStarted`: published event before: Dhuhr 13:07 (row 2026-06-21); after: Asr 17:25 (row 2026-06-21)
- `afterIsha`: published event before: Isha 18:56 (row 2026-10-13); after: Fajr 04:14 (row 2026-10-14)
- `beforeFajr`: published event before: Isha 19:09 (row 2026-03-07); after: Fajr 06:04 (row 2026-03-08)
- `partialDay`: published event before: Maghrib 18:51 (row 2026-11-10); after: Fajr 05:27 (row 2026-11-12)
- `missingDay`: published event before: Maghrib 18:51 (row 2026-11-10); after: Fajr 05:27 (row 2026-11-12)
- `afterLastPublishedDay`: published event before: Isha 20:04 (row 2026-11-13); after: none

What each moment is for:

- `approaching`: 10 minutes before Maghrib, inside the default 15-minute approaching window.
- `justStarted`: 4 minutes after Dhuhr, inside the default just-started window. `londonSummer` has no iqama, so the window is the 15-minute fallback.
- `afterIsha`: 30 minutes after the day's last prayer, with the next day's Fajr published.
- `beforeFajr`: 01:30 EST on the spring-forward day. Fajr is at 06:04 EDT, which is 3 h 34 min away; the wall clock suggests 4 h 34 min.
- `partialDay`: 30 minutes after Maghrib on a row that has no Isha.
- `missingDay`: midday on a day that has no row.
- `afterLastPublishedDay`: 30 minutes after Isha on the last published day, with no later row.

## Checks

### Checks run by the generator

The generator stops with a failed precondition if any of these does not hold.

- `makkah`: 7 days computed in full (2026-10-10 to 2026-10-16); six times strictly increasing on each, each on its owning day or the next, on a whole minute; Isha strictly before the next Fajr on every night, narrowest 9 h 28 min (night of 2026-10-10).
- `londonSummer`: 7 days computed in full (2026-06-18 to 2026-06-24); six times strictly increasing on each, each on its owning day or the next, on a whole minute; Isha strictly before the next Fajr on every night, narrowest 4 h 1 min (night of 2026-06-20).
- `reykjavikJune`: 7 days computed in full (2026-06-18 to 2026-06-24); six times strictly increasing on each, each on its owning day or the next, on a whole minute; Isha strictly before the next Fajr on every night, narrowest 2 h 2 min (night of 2026-06-21).
- `newYorkDSTChange`: 7 days computed in full (2026-03-05 to 2026-03-11); six times strictly increasing on each, each on its owning day or the next, on a whole minute; Isha strictly before the next Fajr on every night, narrowest 9 h 47 min (night of 2026-03-10).
- `jakarta`: 7 days computed in full (2026-10-10 to 2026-10-16); six times strictly increasing on each, each on its owning day or the next, on a whole minute; Isha strictly before the next Fajr on every night, narrowest 9 h 17 min (night of 2026-10-15).
- `friday`: 7 days computed in full (2026-10-13 to 2026-10-19); six times strictly increasing on each, each on its owning day or the next, on a whole minute; Isha strictly before the next Fajr on every night, narrowest 9 h 16 min (night of 2026-10-17).
- `ramadan`: 7 days computed in full (2026-02-26 to 2026-03-04); six times strictly increasing on each, each on its owning day or the next, on a whole minute; Isha strictly before the next Fajr on every night, narrowest 8 h 57 min (night of 2026-03-03).
- `incomplete`: 7 days computed in full (2026-11-08 to 2026-11-14); six times strictly increasing on each, each on its owning day or the next, on a whole minute; Isha strictly before the next Fajr on every night, narrowest 9 h 23 min (night of 2026-11-13).
- `ramadan`: 2026-03-01 is 12 Ramadan 1447 AH in the Umm al-Qura calendar; `friday`: 2026-10-16 is a Friday.

### Independent checks

A separate Python script (standard library only) read the generator's JSON and checked it without adhan-swift.

- Wall clocks and instants: 644 pairs, every begin time and iqama of the published rows plus the days computed around them, were converted again with Python's zoneinfo. None is repeated or nonexistent, and all match.
- Daylight saving: New York goes from 01:59:59 EST (UTC-5) to 03:00:00 EDT (UTC-4) at 2026-03-08T07:00:00Z, and 02:30 on that date does not exist.
- Moments: each moment's offset instant equals its UTC instant, the offset is the zone's offset at that instant, and each moment was re-derived from the published rows.
- Shapes: five consecutive rows per place (four for `incomplete`); Jumu'ah declared only on the `friday` row of 2026-10-16; the iqama offsets as listed; the 2026-11-10 row has no Isha, 2026-11-11 has no row, and 2026-11-13 is the last row.
- Solar times: sunrise, sunset, transit, Asr, and the angle-based Fajr and Isha were recomputed with the NOAA solar equations. With the preset's minute offsets applied, every time is within 0.6 minute of the NOAA value (rounding accounts for up to 0.5), except Asr near the March equinox: 1.5 minutes across the New York days and 0.9 across the `ramadan` days. adhan-swift takes the Asr shadow angle from the declination at 0:00 UT; with that convention the difference is at most 0.7. Reykjavik's Fajr and Isha were recomputed from NOAA sunrise and sunset with the seventh-of-the-night rule and agree within 0.5. London's Fajr and Isha come from the Moonsighting Committee's seasonal formulas inside adhan-swift. They were only range-checked here (Fajr 112 to 121 min before sunrise, Isha 74 to 82 min after Maghrib).
- Against a published timetable: the five Singapore days, 30 times, were compared with the MUIS Muslim Prayer Timetable 2026 on data.gov.sg (dataset `d_d441e7242e78efc566024dd5b0d9829c`, the one MosqueBoard uses; RFC 0001, section 8). 24 are equal and 6 are one minute earlier. None differs by more.
- adhan-swift's own test suite (51 tests) passes on this machine at the same commit. It was run in a scratch export of the commit, because the clone is read-only.

## Regenerating

1. Check out adhan-swift at `a6fa2de` and point the `.package(path:)` line in the manifest below at it.
2. Save the two listings below as `Package.swift` and `Sources/fixtures-generator/main.swift`.
3. Run `swift run -c release fixtures-generator <output-directory>`.

On success the tool writes `places.md`, `moments.md` and `checks.md`, which hold the sections above, and `fixtures.json`, which holds the same data with UTC instants.

## Generator listing

`Package.swift`:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "fixtures-generator",
  platforms: [.macOS(.v13)],
  dependencies: [
    // A read-only local clone of adhan-swift at commit a6fa2de (MIT). Never modified.
    .package(path: "../adhan-swift")
  ],
  targets: [
    .executableTarget(
      name: "fixtures-generator",
      dependencies: [.product(name: "Adhan", package: "adhan-swift")]
    )
  ]
)
```

`Sources/fixtures-generator/main.swift`:

```swift
// Generator for the SalahFixtures data (documented in FixtureData.md). A throwaway tool that
// lives outside the repository.
//
// It asks adhan-swift (commit a6fa2de, MIT license) for begin times, converts them to local wall
// clocks, applies the iqama, Jumu'ah and incomplete-coverage treatments, checks the invariants
// SalahCore relies on, and writes four files into the output directory:
//   places.md, moments.md, checks.md  the Markdown sections pasted into FixtureData.md
//   fixtures.json                     the same data with UTC instants, for an independent check
//
// Usage: swift run -c release fixtures-generator <output-directory>

import Adhan
import Foundation

// MARK: - Days, prayers and wall clocks

enum Kind: String, CaseIterable {
  case fajr, sunrise, dhuhr, asr, maghrib, isha

  var label: String { rawValue.capitalized }

  var prayer: Prayer {
    switch self {
    case .fajr: .fajr
    case .sunrise: .sunrise
    case .dhuhr: .dhuhr
    case .asr: .asr
    case .maghrib: .maghrib
    case .isha: .isha
    }
  }
}

func gregorian(_ zone: TimeZone) -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = zone
  return calendar
}

/// A Gregorian calendar date.
struct Day: Hashable, Comparable, CustomStringConvertible {
  let year: Int
  let month: Int
  let day: Int

  init(year: Int, month: Int, day: Int) {
    (self.year, self.month, self.day) = (year, month, day)
  }

  /// "2026-10-13"
  init(_ text: String) {
    let part = text.split(separator: "-").map { Int($0)! }
    self.init(year: part[0], month: part[1], day: part[2])
  }

  /// The date of an instant in a zone.
  init(containing instant: Date, in zone: TimeZone) {
    let c = gregorian(zone).dateComponents([.year, .month, .day], from: instant)
    self.init(year: c.year!, month: c.month!, day: c.day!)
  }

  var components: DateComponents { DateComponents(year: year, month: month, day: day) }
  private var midnightUTC: Date { gregorian(.gmt).date(from: components)! }

  func adding(_ days: Int) -> Day {
    Day(containing: gregorian(.gmt).date(byAdding: .day, value: days, to: midnightUTC)!, in: .gmt)
  }

  func days(to other: Day) -> Int {
    gregorian(.gmt).dateComponents([.day], from: midnightUTC, to: other.midnightUTC).day!
  }

  /// 1 = Sunday ... 6 = Friday ... 7 = Saturday, as in `Calendar` and RFC 0001.
  var weekday: Int { gregorian(.gmt).component(.weekday, from: midnightUTC) }
  var weekdayName: String { ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday - 1] }
  var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
  static func < (a: Day, b: Day) -> Bool { a.midnightUTC < b.midnightUTC }
}

/// A local clock time as a timetable writes it: "HH:MM", or "HH:MM+1" on the next civil day.
struct Wall: CustomStringConvertible {
  let hour: Int
  let minute: Int
  let dayOffset: Int

  /// The wall clock of `instant` in `zone`, for an event owned by `owner`. An event may fall on
  /// its owning day or the next one, and begin times are whole minutes.
  init(_ instant: Date, owner: Day, zone: TimeZone) {
    let units: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
    let c = gregorian(zone).dateComponents(units, from: instant)
    precondition(c.second == 0, "\(instant) is not on a whole minute")
    let offset = owner.days(to: Day(year: c.year!, month: c.month!, day: c.day!))
    precondition((0...1).contains(offset), "\(instant) is outside \(owner) and the next day")
    (hour, minute, dayOffset) = (c.hour!, c.minute!, offset)
  }

  var description: String {
    String(format: "%02d:%02d", hour, minute) + (dayOffset == 1 ? "+1" : "")
  }
}

/// The instant at which the clock in `zone` reads `clock` ("HH:MM") on `day`.
func localInstant(on day: Day, at clock: String, in zone: TimeZone) -> Date {
  let part = clock.split(separator: ":").map { Int($0)! }
  var components = day.components
  (components.hour, components.minute) = (part[0], part[1])
  let calendar = gregorian(zone)
  let date = calendar.date(from: components)!
  let back = calendar.dateComponents([.day, .hour, .minute], from: date)
  precondition(
    back.day == day.day && back.hour == part[0] && back.minute == part[1],
    "\(day) \(clock) does not exist in \(zone.identifier)")
  return date
}

func offsetText(_ seconds: Int) -> String {
  (seconds < 0 ? "-" : "+")
    + String(format: "%02d:%02d", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
}

/// ISO 8601 with the zone's offset at that instant, e.g. 2026-10-13T17:33:00+03:00.
func iso(_ instant: Date, in zone: TimeZone) -> String {
  let units: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
  let c = gregorian(zone).dateComponents(units, from: instant)
  let stamp = String(
    format: "%04d-%02d-%02dT%02d:%02d:%02d",
    c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
  return stamp + offsetText(zone.secondsFromGMT(for: instant))
}

func isoUTC(_ instant: Date) -> String {
  iso(instant, in: .gmt).replacingOccurrences(of: "+00:00", with: "Z")
}

// MARK: - The places

enum Treatment {
  /// The row is published without one time.
  case partial(without: Kind)
  /// No row at all for this day.
  case missing
  /// The timetable ends with this row.
  case lastPublished
}

struct Place {
  let id: String
  let name: String
  let country: String
  let latitude: Double
  let longitude: Double
  let zoneID: String
  let featured: Day
  /// Prose for the document.
  let methodName: String
  var parameters: CalculationParameters
  /// Published iqama: minutes after the begin time. Empty means no iqama.
  var iqamaMinutes: [Kind: Int] = [:]
  /// The Friday that declares Jumu'ah, with its own iqama as a local clock time.
  var jumuahDay: Day?
  var jumuahIqama = "12:15"
  var treatments: [Day: Treatment] = [:]

  var zone: TimeZone { TimeZone(identifier: zoneID)! }
  var coordinates: Coordinates { Coordinates(latitude: latitude, longitude: longitude) }
  /// The rows the fixture covers: featured day -2 ... +2.
  var days: [Day] { (-2...2).map { featured.adding($0) } }
}

func preset(
  _ method: CalculationMethod, _ edit: (inout CalculationParameters) -> Void = { _ in }
) -> CalculationParameters {
  var parameters = method.params
  edit(&parameters)
  return parameters
}

enum Catalog {
  static var places: [Place] {
    let jakartaIqama: [Kind: Int] = [.fajr: 10, .dhuhr: 10, .asr: 10, .maghrib: 10, .isha: 10]
    return [
      Place(
        id: "makkah", name: "Makkah", country: "SA", latitude: 21.4225, longitude: 39.8262,
        zoneID: "Asia/Riyadh", featured: Day("2026-10-13"),
        methodName: "Umm al-Qura University, Makkah", parameters: preset(.ummAlQura),
        iqamaMinutes: [.fajr: 25, .dhuhr: 20, .asr: 20, .maghrib: 10, .isha: 20]),
      Place(
        id: "londonSummer", name: "London", country: "GB", latitude: 51.5072, longitude: -0.1276,
        zoneID: "Europe/London", featured: Day("2026-06-21"),
        methodName: "Moonsighting Committee Worldwide", parameters: preset(.moonsightingCommittee)),
      Place(
        id: "reykjavikJune", name: "Reykjavik", country: "IS", latitude: 64.1466,
        longitude: -21.9426, zoneID: "Atlantic/Reykjavik", featured: Day("2026-06-21"),
        methodName: "Muslim World League with the seventh-of-the-night rule",
        parameters: preset(.muslimWorldLeague) { $0.highLatitudeRule = .seventhOfTheNight }),
      Place(
        id: "newYorkDSTChange", name: "New York", country: "US", latitude: 40.7128,
        longitude: -74.0060, zoneID: "America/New_York", featured: Day("2026-03-08"),
        methodName: "ISNA (Islamic Society of North America)", parameters: preset(.northAmerica)),
      Place(
        id: "jakarta", name: "Jakarta", country: "ID", latitude: -6.2088, longitude: 106.8456,
        zoneID: "Asia/Jakarta", featured: Day("2026-10-13"),
        methodName: "Singapore/Kemenag-like", parameters: preset(.singapore),
        iqamaMinutes: jakartaIqama),
      Place(
        id: "friday", name: "Jakarta", country: "ID", latitude: -6.2088, longitude: 106.8456,
        zoneID: "Asia/Jakarta", featured: Day("2026-10-16"),
        methodName: "Singapore/Kemenag-like", parameters: preset(.singapore),
        iqamaMinutes: jakartaIqama, jumuahDay: Day("2026-10-16")),
      Place(
        id: "ramadan", name: "Makkah", country: "SA", latitude: 21.4225, longitude: 39.8262,
        zoneID: "Asia/Riyadh", featured: Day("2026-03-01"),
        methodName: "Umm al-Qura University, Makkah, with its Ramadan Isha interval",
        parameters: preset(.ummAlQura) { $0.ishaInterval = 120 }),
      Place(
        id: "incomplete", name: "Singapore", country: "SG", latitude: 1.3521, longitude: 103.8198,
        zoneID: "Asia/Singapore", featured: Day("2026-11-11"),
        methodName: "Singapore preset, MUIS-like", parameters: preset(.singapore),
        treatments: [
          Day("2026-11-10"): .partial(without: .isha),
          Day("2026-11-11"): .missing,
          Day("2026-11-13"): .lastPublished,
        ]),
    ]
  }

  static func place(_ id: String) -> Place { places.first { $0.id == id }! }
}

// MARK: - Calculation

struct Row {
  let day: Day
  var begin: [Kind: Date]
  var iqama: [Kind: Date]
  var declaresJumuah = false
  var treatment: Treatment?
}

extension Place {
  /// Every begin time adhan-swift computes for `day`, before any treatment.
  func computed(_ day: Day) -> [Kind: Date] {
    let calculation = PrayerTimes(
      coordinates: coordinates, date: day.components, calculationParameters: parameters)
    guard let times = calculation else { fatalError("adhan-swift gave no times: \(id) \(day)") }
    return Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0, times.time(for: $0.prayer)) })
  }

  /// The published rows: a missing day has none, a partial row lacks one time.
  var rows: [Row] {
    days.compactMap { day in
      var begin = computed(day)
      let treatment = treatments[day]
      switch treatment {
      case .missing?: return nil
      case .partial(let kind)?: begin[kind] = nil
      default: break
      }
      var iqama: [Kind: Date] = [:]
      for (kind, minutes) in iqamaMinutes {
        iqama[kind] = begin[kind]?.addingTimeInterval(Double(minutes) * 60)
      }
      let declares = day == jumuahDay
      if declares { iqama[.dhuhr] = localInstant(on: day, at: jumuahIqama, in: zone) }
      return Row(
        day: day, begin: begin, iqama: iqama, declaresJumuah: declares, treatment: treatment)
    }
  }

  func wall(_ instant: Date, owner: Day) -> Wall { Wall(instant, owner: owner, zone: zone) }
}

// MARK: - Checks

/// The invariants of RFC 0001 section 4.3 over the days around the rows, computed in full.
/// Returns the line that goes into the document; any violation stops the generator.
func check(_ place: Place) -> String {
  let span = (-3...3).map { place.featured.adding($0) }
  let full = span.map { ($0, place.computed($0)) }
  for (day, times) in full {
    let instants = Kind.allCases.map { times[$0]! }
    precondition(
      zip(instants, instants.dropFirst()).allSatisfy { $0 < $1 },
      "\(place.id) \(day): kinds out of order")
    for kind in Kind.allCases { _ = place.wall(times[kind]!, owner: day) }
  }
  var smallest = (gap: TimeInterval.infinity, from: span[0])
  for ((day, tonight), (_, tomorrow)) in zip(full, full.dropFirst()) {
    let gap = tomorrow[.fajr]!.timeIntervalSince(tonight[.isha]!)
    precondition(gap > 0, "\(place.id): Isha of \(day) is not strictly before the next Fajr")
    if gap < smallest.gap { smallest = (gap, day) }
  }
  for row in place.rows {
    for (kind, time) in row.iqama {
      let begin = row.begin[kind]!
      precondition(time >= begin, "\(place.id) \(row.day): \(kind) iqama before its begin time")
      _ = place.wall(time, owner: row.day)
    }
  }
  let minutes = Int(smallest.gap / 60)
  return "`\(place.id)`: \(full.count) days computed in full (\(span[0]) to \(span[6])); six "
    + "times strictly increasing on each, each on its owning day or the next, on a whole minute; "
    + "Isha strictly before the next Fajr on every night, narrowest \(minutes / 60) h "
    + "\(minutes % 60) min (night of \(smallest.from))."
}

func highLatitudeRuleMatters(_ place: Place) -> Bool {
  place.days.contains { day in
    let results = HighLatitudeRule.allCases.map { rule -> [Kind: Date] in
      var variant = place
      variant.parameters.highLatitudeRule = rule
      return variant.computed(day)
    }
    return results.dropFirst().contains { $0 != results[0] }
  }
}

func hijri(_ day: Day, zone: TimeZone) -> (day: Int, month: Int, year: Int, text: String) {
  var calendar = Calendar(identifier: .islamicUmmAlQura)
  calendar.timeZone = zone
  let c = calendar.dateComponents(
    [.year, .month, .day], from: localInstant(on: day, at: "12:00", in: zone))
  let months = [
    "Muharram", "Safar", "Rabi I", "Rabi II", "Jumada I", "Jumada II", "Rajab", "Shaban",
    "Ramadan", "Shawwal", "Dhu al-Qadah", "Dhu al-Hijjah",
  ]
  return (c.day!, c.month!, c.year!, "\(c.day!) \(months[c.month! - 1]) \(c.year!) AH")
}

// MARK: - Markdown

func table(_ header: [String], _ rows: [[String]]) -> String {
  func line(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |" }
  return ([line(header), line(header.map { _ in "---" })] + rows.map(line)).joined(separator: "\n")
}

func number(_ value: Double) -> String { String(format: "%g", value) }

func coordinateText(_ place: Place) -> String {
  func part(_ value: Double, _ positive: String, _ negative: String) -> String {
    String(format: "%.4f° ", abs(value)) + (value < 0 ? negative : positive)
  }
  return "\(part(place.latitude, "N", "S")), \(part(place.longitude, "E", "W"))"
}

func parameterText(_ place: Place) -> String {
  let p = place.parameters
  let presetOffsets: [CalculationMethod: String] = [
    // Read from Sources/Models/CalculationMethod.swift at a6fa2de (`methodAdjustments` is
    // internal to Adhan, so the generator cannot read it).
    .ummAlQura: "none", .moonsightingCommittee: "Dhuhr +5 min, Maghrib +3 min",
    .muslimWorldLeague: "Dhuhr +1 min", .northAmerica: "Dhuhr +1 min", .singapore: "Dhuhr +1 min",
  ]
  var parts = ["preset `\(p.method.rawValue)`", "Fajr \(number(p.fajrAngle))°"]
  parts.append(
    p.ishaInterval > 0
      ? "Isha \(p.ishaInterval) min after Maghrib" : "Isha \(number(p.ishaAngle))°")
  parts.append("Asr `\(p.madhab)` (shadow factor \(p.madhab.rawValue))")
  parts.append("rounding `\(p.rounding.rawValue)`")
  parts.append("preset offsets: \(presetOffsets[p.method]!)")
  if p.method == .moonsightingCommittee { parts.append("shafaq `\(p.shafaq.rawValue)`") }
  if let rule = p.highLatitudeRule {
    parts.append("high-latitude rule `\(rule.rawValue)`, set explicitly")
  } else {
    let recommended = HighLatitudeRule.recommended(for: place.coordinates).rawValue
    parts.append(
      "high-latitude rule left unset (adhan would use `\(recommended)` here)"
        + (highLatitudeRuleMatters(place)
          ? ", and it matters" : "; all three rules give identical times on every row"))
  }
  return parts.joined(separator: "; ")
}

func offsetSummary(_ place: Place) -> String {
  var groups: [(offset: Int, first: Day, last: Day)] = []
  for day in place.days {
    let noon = localInstant(on: day, at: "12:00", in: place.zone)
    let offset = place.zone.secondsFromGMT(for: noon)
    if let last = groups.last, last.offset == offset {
      groups[groups.count - 1].last = day
    } else {
      groups.append((offset, day, day))
    }
  }
  var text = groups.map { "\(offsetText($0.offset)) (\($0.first) to \($0.last))" }
    .joined(separator: ", ")
  let start = localInstant(on: place.days[0], at: "00:00", in: place.zone)
  if let change = place.zone.nextDaylightSavingTimeTransition(after: start),
    change < localInstant(on: place.days[4].adding(1), at: "00:00", in: place.zone)
  {
    let before = TimeZone(
      secondsFromGMT: place.zone.secondsFromGMT(for: change.addingTimeInterval(-1)))!
    text +=
      "; the clocks change at \(isoUTC(change)): "
      + "\(iso(change, in: before)) becomes \(iso(change, in: place.zone))"
  }
  return text
}

func iqamaText(_ place: Place) -> String {
  guard !place.iqamaMinutes.isEmpty else { return "none" }
  let list = Kind.allCases.compactMap { kind in
    place.iqamaMinutes[kind].map { "\(kind.label) +\($0)" }
  }
  var text = "published, minutes after the begin time: " + list.joined(separator: ", ")
  if let day = place.jumuahDay {
    text += "; the Jumu'ah on \(day) has its own iqama at \(place.jumuahIqama) local time"
  }
  return text
}

func note(_ row: Row, in place: Place) -> String {
  var parts: [String] = []
  if row.day == place.featured { parts.append("featured day") }
  if row.declaresJumuah {
    parts.append("Friday: Dhuhr declared as Jumu'ah, Jumu'ah iqama \(place.jumuahIqama)")
  } else if row.day.weekday == 6 {
    parts.append("Friday: Jumu'ah not declared, so Dhuhr is ordinary")
  }
  switch row.treatment {
  case .partial(let kind)?: parts.append("partial row: \(kind.label) not published")
  case .lastPublished?: parts.append("last published day")
  default: break
  }
  if place.id == "ramadan" { parts.append(hijri(row.day, zone: place.zone).text) }
  if place.id == "newYorkDSTChange", row.day == place.featured {
    parts.append("clocks go forward at 02:00; every begin time is after the change")
  }
  return parts.joined(separator: "; ")
}

func minutesText(_ minutes: Int) -> String {
  abs(minutes) < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
}

func rangeText(_ values: [Int]) -> String {
  values.min() == values.max() ? "\(values[0])" : "\(values.min()!) to \(values.max()!)"
}

/// Observations about a place's numbers, computed from them so they cannot drift.
func remarks(_ place: Place) -> [String] {
  let days = place.days.map { ($0, place.computed($0)) }
  func spans(_ from: Kind, _ to: Kind) -> [Int] {
    days.map { Int($0.1[to]!.timeIntervalSince($0.1[from]!) / 60) }
  }
  switch place.id {
  case "londonSummer":
    return [
      "In June at this latitude the sun never gets lower than about 15° below the horizon "
        + "(latitude + declination - 90° = -15.05°), so the 18° angles are never reached. The "
        + "method's seasonal rule sets Fajr (\(rangeText(spans(.fajr, .sunrise))) min before "
        + "sunrise) and Isha (\(rangeText(spans(.maghrib, .isha))) min after Maghrib) on every "
        + "row. Isha is late but before midnight."
    ]
  case "reykjavikJune":
    let nights = zip(days, days.dropFirst()).map {
      Int($1.1[.sunrise]!.timeIntervalSince($0.1[.maghrib]!) / 60)
    }
    return [
      "The sun's lowest altitude is about -2.4° (latitude + declination - 90°), so the 18° and "
        + "17° angles are never reached and the seventh-of-the-night rule sets Fajr and Isha. The "
        + "night from Maghrib to the next sunrise lasts \(rangeText(nights)) min. Maghrib and Isha "
        + "are after local midnight on every row, so they carry `+1`."
    ]
  case "ramadan":
    return [
      "Isha is Maghrib + \(rangeText(spans(.maghrib, .isha))) min on every row: the preset's 90 "
        + "minutes plus the 30 that adhan-swift's documentation says to add in Ramadan. The "
        + "first row is a Friday with no Jumu'ah declared."
    ]
  case "jakarta", "friday":
    return [
      "adhan-swift documents the Singapore preset as \"Used in Singapore, Malaysia, and "
        + "Indonesia\". The times are computed, not taken from an official Indonesian timetable."
    ]
  case "incomplete":
    return [
      "Expected kinds are all six, so the partial row reports Isha as not published and the "
        + "missing day has no row at all. The last published day is the last row; nothing follows it."
    ]
  default:
    return []
  }
}

func placeSection(_ place: Place) -> String {
  var out = "### `\(place.id)`: \(place.name), \(place.country)\n\n"
  var facts = [
    "Coordinates: \(coordinateText(place))",
    "Time zone: `\(place.zoneID)`; UTC offset at noon: \(offsetSummary(place))",
    "Featured day: \(place.featured) (\(place.featured.weekdayName)); rows "
      + "\(place.days[0]) to \(place.days[4])",
    "Method: \(place.methodName); \(parameterText(place))",
    "Iqama: \(iqamaText(place))",
  ]
  facts += remarks(place)
  out += facts.map { "- \($0)" }.joined(separator: "\n") + "\n\n"

  let published = Dictionary(uniqueKeysWithValues: place.rows.map { ($0.day, $0) })
  let withNotes = place.days.contains { day in
    published[day].map { !note($0, in: place).isEmpty } ?? true
  }
  var header = ["Day", "Weekday"] + Kind.allCases.map(\.label)
  if withNotes { header.append("Notes") }
  let beginRows = place.days.map { day -> [String] in
    let name = day == place.featured ? "**\(day)**" : "\(day)"
    guard let row = published[day] else {
      return [name, day.weekdayName] + Kind.allCases.map { _ in "-" } + ["no row for this day"]
    }
    let cells = Kind.allCases.map {
      row.begin[$0].map { place.wall($0, owner: day).description } ?? "-"
    }
    return [name, day.weekdayName] + cells + (withNotes ? [note(row, in: place)] : [])
  }
  out += "Begin times (local wall clock; `+1` is the next civil day):\n\n"
  out += table(header, beginRows) + "\n"

  if !place.iqamaMinutes.isEmpty {
    let kinds = Kind.allCases.filter { $0 != .sunrise }
    let iqamaRows = place.rows.map { row -> [String] in
      let cells = kinds.map {
        row.iqama[$0].map { place.wall($0, owner: row.day).description } ?? "-"
      }
      return [String(describing: row.day)] + cells
    }
    out += "\nPublished iqama (local wall clock):\n\n"
    out += table(["Day"] + kinds.map(\.label), iqamaRows) + "\n"
  }

  if place.id == "reykjavikJune" { out += "\n" + ruleComparison(place) + "\n" }
  if place.id == "incomplete" {
    let withheld = place.days.compactMap { day -> String? in
      switch place.treatments[day] {
      case .partial(let kind)?:
        let time = place.computed(day)[kind]!
        return "\(kind.label) on \(day), \(place.wall(time, owner: day))"
      case .missing?:
        let times = place.computed(day)
        let list = Kind.allCases.map { "\($0.label) \(place.wall(times[$0]!, owner: day))" }
        return "all six times on \(day) (\(list.joined(separator: ", ")))"
      default: return nil
      }
    }
    out +=
      "\nComputed but withheld, so the fixture has no row for them: "
      + withheld.joined(separator: "; ") + ".\n"
  }
  return out
}

/// Why Reykjavik uses the seventh-of-the-night rule: the three rules side by side.
func ruleComparison(_ place: Place) -> String {
  let tonight = place.featured
  let rows = [HighLatitudeRule.seventhOfTheNight, .middleOfTheNight, .twilightAngle].map {
    rule -> [String] in
    var variant = place
    variant.parameters.highLatitudeRule = rule
    let evening = variant.computed(tonight)
    let morning = variant.computed(tonight.adding(1))
    let gap = Int(morning[.fajr]!.timeIntervalSince(evening[.isha]!) / 60)
    return [
      "`\(rule.rawValue)`", place.wall(evening[.maghrib]!, owner: tonight).description,
      place.wall(evening[.isha]!, owner: tonight).description,
      place.wall(morning[.fajr]!, owner: tonight.adding(1)).description,
      minutesText(gap) + (gap <= 0 ? ": Isha is not before the next Fajr" : ""),
    ]
  }
  return "The three high-latitude rules for the night of \(tonight) (chosen: the first):\n\n"
    + table(
      [
        "Rule", "Maghrib \(tonight)", "Isha \(tonight)", "Fajr \(tonight.adding(1))",
        "Isha to Fajr",
      ],
      rows)
}

// MARK: - Moments

enum Anchor {
  /// A begin time of the moment's day plus or minus minutes.
  case event(Kind, minutes: Int)
  /// A local clock time on the moment's day.
  case clock(String)
}

struct Moment {
  let id: String
  let placeID: String
  let day: Day
  let anchor: Anchor

  var place: Place { Catalog.place(placeID) }

  var instant: Date {
    switch anchor {
    case .event(let kind, let minutes):
      place.computed(day)[kind]!.addingTimeInterval(Double(minutes) * 60)
    case .clock(let text):
      localInstant(on: day, at: text, in: place.zone)
    }
  }

  var derivation: String {
    switch anchor {
    case .event(let kind, let minutes):
      let begin = place.wall(place.computed(day)[kind]!, owner: day)
      return "\(kind.label) \(begin) on \(day) \(minutes < 0 ? "-" : "+") \(abs(minutes)) min"
    case .clock(let text):
      let offset = offsetText(place.zone.secondsFromGMT(for: instant))
      return "\(text) local time on \(day), offset \(offset)"
    }
  }

  /// The published events just before and after the moment, ignoring coverage rules.
  var surroundings: String {
    let events = place.rows.flatMap { row in
      row.begin.map { (kind: $0.key, day: row.day, time: $0.value) }
    }
    func text(_ event: (kind: Kind, day: Day, time: Date)?) -> String {
      guard let event else { return "none" }
      return "\(event.kind.label) \(place.wall(event.time, owner: event.day)) (row \(event.day))"
    }
    let before = events.filter { $0.time <= instant }.max { $0.time < $1.time }
    let after = events.filter { $0.time > instant }.min { $0.time < $1.time }
    return "published event before: \(text(before)); after: \(text(after))"
  }

  static var all: [Moment] {
    [
      Moment(
        id: "approaching", placeID: "makkah", day: Day("2026-10-13"),
        anchor: .event(.maghrib, minutes: -10)),
      Moment(
        id: "justStarted", placeID: "londonSummer", day: Day("2026-06-21"),
        anchor: .event(.dhuhr, minutes: 4)),
      Moment(
        id: "afterIsha", placeID: "jakarta", day: Day("2026-10-13"),
        anchor: .event(.isha, minutes: 30)),
      Moment(
        id: "beforeFajr", placeID: "newYorkDSTChange", day: Day("2026-03-08"),
        anchor: .clock("01:30")),
      Moment(
        id: "partialDay", placeID: "incomplete", day: Day("2026-11-10"),
        anchor: .event(.maghrib, minutes: 30)),
      Moment(
        id: "missingDay", placeID: "incomplete", day: Day("2026-11-11"), anchor: .clock("12:00")),
      Moment(
        id: "afterLastPublishedDay", placeID: "incomplete", day: Day("2026-11-13"),
        anchor: .event(.isha, minutes: 30)),
    ]
  }
}

// MARK: - Run

func run(output: URL) throws {
  let places = Catalog.places
  var checkLines = places.map(check)

  let ramadan = Catalog.place("ramadan")
  let h = hijri(ramadan.featured, zone: ramadan.zone)
  precondition((h.day, h.month, h.year) == (12, 9, 1447), "expected 12 Ramadan 1447, got \(h.text)")
  precondition(Catalog.place("friday").featured.weekday == 6, "friday must be a Friday")
  checkLines.append(
    "`ramadan`: \(ramadan.featured) is \(h.text) in the Umm al-Qura calendar; `friday`: "
      + "\(Catalog.place("friday").featured) is a Friday.")

  // Markdown
  let glance = places.map { place -> [String] in
    [
      "`\(place.id)`", "\(place.name), \(place.country)", "`\(place.zoneID)`",
      "\(place.featured)", place.methodName,
      place.rows.count == 5 ? "5" : "\(place.rows.count) of 5 days",
      place.iqamaMinutes.isEmpty ? "-" : "published",
    ]
  }
  var placesMarkdown = table(
    ["Id", "Place", "Zone", "Featured day", "Method", "Rows", "Iqama"], glance)
  placesMarkdown += "\n\n" + places.map(placeSection).joined(separator: "\n")

  let moments = Moment.all
  let momentRows = moments.map { moment -> [String] in
    let zone = moment.place.zone
    return [
      "`\(moment.id)`", "`\(moment.placeID)`", "`\(iso(moment.instant, in: zone))`",
      "`\(isoUTC(moment.instant))`", moment.derivation,
    ]
  }
  var momentsMarkdown = table(
    ["Moment", "Place", "Instant (place offset)", "Instant (UTC)", "Derivation"], momentRows)
  momentsMarkdown +=
    "\n\nWhat surrounds each moment in the published rows (before any coverage rule):\n\n"
  momentsMarkdown +=
    moments.map { "- `\($0.id)`: \($0.surroundings)" }.joined(separator: "\n") + "\n"

  // JSON for the cross-check
  func wallMap(_ times: [Kind: Date], _ day: Day, _ place: Place) -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: times.map {
        ($0.key.rawValue, place.wall($0.value, owner: day).description)
      })
  }
  func utcMap(_ times: [Kind: Date]) -> [String: String] {
    Dictionary(uniqueKeysWithValues: times.map { ($0.key.rawValue, isoUTC($0.value)) })
  }
  let placeJSON = places.map { place -> [String: Any] in
    let rows = place.rows.map { row -> [String: Any] in
      var entry: [String: Any] = [
        "day": row.day.description, "weekday": row.day.weekday,
        "times": wallMap(row.begin, row.day, place), "instants": utcMap(row.begin),
      ]
      if !row.iqama.isEmpty {
        entry["iqama"] = wallMap(row.iqama, row.day, place)
        entry["iqamaInstants"] = utcMap(row.iqama)
      }
      if row.declaresJumuah { entry["observances"] = ["dhuhr": "jumuah"] }
      return entry
    }
    // Verification-only: the days around the rows, computed in full.
    let context = (-3...3).map { place.featured.adding($0) }.map { day -> [String: Any] in
      let times = place.computed(day)
      return [
        "day": day.description, "times": wallMap(times, day, place), "instants": utcMap(times),
      ]
    }
    return [
      "id": place.id, "latitude": place.latitude, "longitude": place.longitude,
      "timeZone": place.zoneID, "featuredDay": place.featured.description,
      "method": place.parameters.method.rawValue, "rows": rows, "computedContext": context,
    ]
  }
  let momentJSON = moments.map { moment -> [String: Any] in
    [
      "id": moment.id, "place": moment.placeID,
      "local": iso(moment.instant, in: moment.place.zone), "utc": isoUTC(moment.instant),
    ]
  }
  let json = try JSONSerialization.data(
    withJSONObject: ["places": placeJSON, "moments": momentJSON],
    options: [.prettyPrinted, .sortedKeys])

  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  try placesMarkdown.write(
    to: output.appendingPathComponent("places.md"), atomically: true, encoding: .utf8)
  try momentsMarkdown.write(
    to: output.appendingPathComponent("moments.md"), atomically: true, encoding: .utf8)
  try (checkLines.map { "- \($0)" }.joined(separator: "\n") + "\n")
    .write(to: output.appendingPathComponent("checks.md"), atomically: true, encoding: .utf8)
  try json.write(to: output.appendingPathComponent("fixtures.json"))
  print("wrote places.md, moments.md, checks.md and fixtures.json to \(output.path)")
  for line in checkLines { print("check: \(line)") }
}

guard CommandLine.arguments.count == 2 else {
  print("usage: fixtures-generator <output-directory>")
  exit(2)
}
try run(output: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
```
