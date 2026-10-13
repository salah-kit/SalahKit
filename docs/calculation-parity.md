# Calculation parity: Salah today and SalahCalculation

The Salah app computes prayer times with adhan-swift. It will move to SalahCalculation, SalahKit's calculated prayer source built on the SalahTimes engine, in session D1. This document compares the two for the same user settings, over every day of 2026, and explains every difference larger than one minute. The differences listed here are the changes Salah's users would see after that move.

All differences are signed: SalahCalculation minus Salah, in minutes. A "kind-day" is one of the six kinds (Fajr, sunrise, Dhuhr, Asr, Maghrib, Isha) on one day in one configuration.

## Summary

- **Salah's default settings, 21 places, 45,990 kind-days.** Every time agrees within one minute at 16 of the 21 places. The other five are at or beyond 54.8° of latitude. In Oslo, Stockholm and Ushuaia, Asr differs by up to 2 minutes on 66 to 95 days a year; in Reykjavik by up to 6 minutes on 176 days. Tromsø (69.6° N) differs more around polar night and the midnight sun, and there adhan-swift gives no times at all on 118 days.
- **Dhuhr is one minute earlier** with the Muslim World League, Egyptian, Karachi and North America methods, on 14,817 kind-days. adhan-swift adds an undocumented minute to Dhuhr for these methods, and SalahTimes doesn't. This is a difference of exactly one minute, and it isn't rounding.
- **Settings Salah offers but doesn't choose by default** produce larger differences at high latitudes. With the middle-of-the-night or twilight-angle rule, Fajr moves by up to 4 minutes at 59° to 64° (12 minutes in Tromsø), and Isha by up to 35 minutes on a few days a year (83 with Tehran's 14° Isha). The Tehran method there moves Maghrib by up to 130 minutes. The Moonsighting Committee method south of 55° S moves Fajr by up to 67 minutes and Isha by up to 25.
- **Ramadan.** With Salah's delayed-Isha toggle (on by default) mapped to `.interval(minutes: 120, hijriDayOffset:)`, the two agree on every day, for Hijri offsets −1, 0, 1 and 2, at Makkah, Riyadh and Doha.
- **Every difference over a minute has an identified cause**: 6,241 kind-days over the 105 parity configurations, in six classes (table below). Each cause is either a documented SalahTimes rule that differs from adhan-swift's, or an adhan-swift approximation that SalahTimes doesn't make. None is a defect in SalahCalculation. Nothing was left unexplained.
- Before rounding, the two libraries' instants agree within 1.3 to 8 seconds for sunrise, Dhuhr, Maghrib and Isha at the 20 default places other than Tromsø, and for Fajr below 54°. So most one-minute differences are rounding.

| Class | Kinds | Kind-days over 1 min | Where | Largest | Intended change |
|---|---|---:|---|---|---|
| [A. Asr's noon shadow](#a-asrs-noon-shadow) | Asr | 3,704 (+64 with D) | 54.8° and beyond | −7 to +5 min | Yes: correct definition |
| [B. Asr in the weeks around polar night](#b-asr-in-the-weeks-around-polar-night) | Asr | 140 | Tromsø | adhan-swift's Asr is up to 38 hours off | Yes: fixes wrong times |
| [C. Fajr's night for the high-latitude bound](#c-fajrs-night-for-the-high-latitude-bound) | Fajr | 1,727 (+12 with D) | 51.5° and beyond, rule-dependent | −4 to +4 min (Tromsø −11 to +12, one day −113) | Yes: documented |
| [D. Crossings the Sun barely makes](#d-crossings-the-sun-barely-makes) | all but Dhuhr | 84 (+76 with A or C) | 51.5° and beyond | −35 to +83 min | Yes: more accurate |
| [E. Tehran's Maghrib at high latitudes](#e-tehrans-maghrib-at-high-latitudes) | Maghrib | 277 | Oslo, Reykjavik | −47 to +130 min | Yes: documented |
| [F. Moonsighting Committee south of 55° S](#f-the-moonsighting-committee-south-of-55-s) | Fajr, Isha | 233 | Puerto Toro (55.08° S) | Fajr up to +67, Isha down to −25 min | Yes: documented |

The counts add up over configurations, so a place that appears in several configurations is counted in each. The country-suggestion comparison (section 4) compares different methods on purpose, and isn't in these counts.

## What was compared

### Versions

| Component | Version |
|---|---|
| Salah | `salah-kit/Salah` at `4bc00e9`, the imported Guidance v3 rebuild |
| adhan-swift | `batoulapps/adhan-swift` at `a6fa2de` (MIT), the version Salah builds with |
| SalahKit | branch `b1/calculation` at `1db6654`, with `SalahCalculation` and `SalahCore` |
| SalahTimes | 0.1.0 (`42a291c`), resolved from `https://github.com/salah-kit/SalahTimes.git` |
| Toolchain | Swift 6.4, Xcode 27.0, macOS 27 on Apple silicon, run on 2026-10-13 |

### Salah's calculation, as reproduced

The harness reproduces `PrayerManager.calculatePrayerTimes()` and `calculationParameters(for:)` (`Guidance/Features/Prayers/PrayerManager.swift:249` and `:315` at `4bc00e9`) with adhan-swift's public API, one civil day at a time:

1. The day is a Gregorian date in the place's stored time zone (`prayerCalendar`, `PrayerManager.swift:473`), passed to adhan-swift as `DateComponents` (year, month, day).
2. The parameters start from `MethodPreference.adhanMethod.params` (`PreferenceEnums.swift:35`). Madhab and high-latitude rule come from the preferences. User adjustments go into `params.adjustments`. For the custom method (adhan-swift's `.other`), the custom Fajr and Isha angles replace the preset's zeros.
3. Auto-detection, on by default, sets the method from the country code with `MethodPreference.detect(forCountry:)` (`PreferenceEnums.swift:52`). It sets the high-latitude rule to `abs(latitude) > 48 ? seventhOfTheNight : middleOfTheNight` (`Preferences+API.swift:52`). Salah always sets the rule explicitly, so adhan-swift's own `HighLatitudeRule.recommended(for:)`, which compares the signed latitude, never runs.
4. The delayed-Isha toggle (`applyDelayedIshaIfNeeded`, `PrayerManager.swift:338`) is on by default (`PreferencesDefaults.swift:26`). When the method's Isha is an interval, it moves the start of the civil day by the Hijri offset in the Umm al-Qura calendar, in the stored zone (`PrayerDisplayFormatter.adjustedHijriDate`, `PrayerDisplayFormatter.swift:49`). If that date falls in month 9, Isha is 120 minutes after Maghrib.
5. If adhan-swift's initializer returns `nil`, Salah has no times for the day. It keeps showing the last day it could compute (`PrayerManager.swift:288`).

Defaults (`PreferencesDefaults.swift` and `Preferences.swift`): Umm al-Qura before a location is set, Shafi'i, custom angles 18° and 17.5°, adjustments 0, Hijri offset 0.

### Mapping Salah's settings to SalahCalculation

| Salah setting | SalahCalculation |
|---|---|
| `egyptian` | `CalculationSettings(method: .egyptian)` |
| `karachi` | `.karachi` |
| `northAmerica` | `.isna` |
| `muslimWorldLeague` | `.muslimWorldLeague` |
| `ummAlQura` | `.ummAlQura` |
| `gulf` | `.dubai` |
| `moonsightingCommittee` | `.moonsightingCommittee` |
| `kuwait` | `.kuwait` |
| `qatar` | `.qatar` |
| `singapore` | `.muis` |
| `tehran` | `.tehran` |
| `custom` with angles F and I | `CalculationSettings(parameters: CalculationParameters(fajr: .angle(F), isha: .angle(I)))`, with rounding to the nearest minute and no method minutes, as adhan-swift's `.other` |
| Madhab | `madhab: .shafi` or `.hanafi` |
| High-latitude rule (middle, seventh, twilight angle), auto or chosen | `parameters.highLatitudeRule` set to the same rule explicitly. Salah's automatic choice equals SalahTimes' `.recommended`. |
| Adjustments (Fajr, Shuruq, Dhuhr, Asr, Maghrib, Isha) | `parameters.adjustments` |
| Delayed Isha in Ramadan on, Hijri offset k | `ramadanIsha: .interval(minutes: 120, hijriDayOffset: k)` |
| Delayed Isha off | `ramadanIsha: .off` |

Every preset keeps its SalahTimes values (`METHODS.md`). Where those differ from adhan-swift's, the differences show up below. The harness writes each configuration's resulting `CalculationParameters` as JSON, to check the mapping.

### Places

| Place | Latitude | Longitude | Time zone | Country |
|---|---:|---:|---|---|
| Makkah | 21.4225 | 39.8262 | Asia/Riyadh | SA |
| Riyadh | 24.7136 | 46.6753 | Asia/Riyadh | SA |
| Cairo | 30.0444 | 31.2357 | Africa/Cairo | EG |
| Karachi | 24.8607 | 67.0011 | Asia/Karachi | PK |
| Dubai | 25.2048 | 55.2708 | Asia/Dubai | AE |
| Kuwait City | 29.3759 | 47.9774 | Asia/Kuwait | KW |
| Doha | 25.2854 | 51.5310 | Asia/Qatar | QA |
| Singapore | 1.3521 | 103.8198 | Asia/Singapore | SG |
| Tehran | 35.6892 | 51.3890 | Asia/Tehran | IR |
| Istanbul | 41.0082 | 28.9784 | Europe/Istanbul | TR |
| Kuala Lumpur | 3.1390 | 101.6869 | Asia/Kuala_Lumpur | MY |
| Jakarta | −6.2088 | 106.8456 | Asia/Jakarta | ID |
| London | 51.5074 | −0.1278 | Europe/London | GB |
| New York | 40.7128 | −74.0060 | America/New_York | US |
| Toronto | 43.6532 | −79.3832 | America/Toronto | CA |
| Oslo | 59.9139 | 10.7522 | Europe/Oslo | NO |
| Stockholm | 59.3293 | 18.0686 | Europe/Stockholm | SE |
| Reykjavik | 64.1466 | −21.9426 | Atlantic/Reykjavik | IS |
| Tromsø | 69.6492 | 18.9553 | Europe/Oslo | NO |
| Ushuaia | −54.8019 | −68.3030 | America/Argentina/Ushuaia | AR |
| Kashgar | 39.4704 | 75.9898 | Asia/Shanghai | CN |
| Puerto Toro | −55.0833 | −67.0833 | America/Punta_Arenas | CL |

Kashgar keeps China's clock, about three hours ahead of the Sun. Puerto Toro is used only for the Moonsighting Committee's 55° rule, which nowhere else in the list crosses in the south (Ushuaia is at 54.80°).

### Configurations

108 configurations, each over every day of 2026 except the Ramadan runs:

1. **Salah's defaults** at the 21 places: the auto-detected method for the country and the automatic high-latitude rule, with Ramadan delayed Isha on.
2. **Every Salah method** (12, custom included) at Makkah and London, with the automatic high-latitude rule.
3. **Customized settings:**
   - Hanafi Asr: Karachi (Karachi), Istanbul (Egyptian), London (Moonsighting Committee), Oslo (Muslim World League), Cairo (Egyptian).
   - Each high-latitude rule with the Muslim World League at London, Stockholm, Oslo, Reykjavik, Tromsø and Ushuaia. The middle-of-the-night and twilight-angle rules with Umm al-Qura and Tehran at Oslo and Reykjavik.
   - The Moonsighting Committee at Stockholm, Oslo, Reykjavik, Ushuaia and Puerto Toro, for its 55° rule.
   - Adjustments of Fajr +2, Shuruq −1, Dhuhr +3, Asr +1, Maghrib +2 and Isha −3: Umm al-Qura at Makkah, Moonsighting Committee at London, North America at New York, Singapore at Singapore.
   - The custom method: 18°/17.5° (Salah's defaults) at Cairo and London, 16°/14° at London, 15°/15° at Oslo, 18°/18° at Kuala Lumpur.
   - Ramadan delayed Isha on with Hijri offsets 0, 1, −1 and 2, and off. Umm al-Qura at Makkah and Riyadh, Qatar at Doha, from 2026-02-01 to 2026-03-31. That window contains Ramadan 1447 (18 February to 19 March 2026 in the Umm al-Qura calendar) with a margin on both sides.
4. **Country suggestions:** at Istanbul, Kuala Lumpur and Jakarta, Salah's auto-detected method against the method SalahTimes' `CalculationMethod.suggested(forCountryCode:)` suggests.

### The harness

A throwaway Swift package outside SalahKit, not committed, at `.worktrees/B1-parity-harness/` in the workspace. It depends on the local adhan-swift clone and on SalahKit's worktree by path, and on SalahTimes 0.1.0 by URL. It has four targets, so that the two libraries' same-named types never meet in one file:

- `Common`: the places, Salah's `MethodPreference` with `detect(forCountry:)` copied verbatim, the preferences with Salah's defaults, and an independent solar model used only to attribute differences (below).
- `SalahSide` (imports `Adhan`): the reproduction of Salah's calculation described above.
- `KitSide` (imports `SalahCalculation`, `SalahCore`, `SalahTimes`): the mapping above. It calls `CalculationSource(settings).prayerDay(_:at:)` with a `PrayerLocation` carrying the place's coordinates, time zone and country code, and records each missing kind's `ScheduleGapReason` with SalahTimes' own `NonOccurrence` behind it. It also computes the same day with SalahTimes directly with rounding off, for comparisons before rounding.
- `parity` (executable): the configurations, the comparison and the attribution. It writes a summary table, every kind-day over a minute as CSV, the attribution counts, the one-minute counts, the missing times, the suggestion table and each configuration's settings.

```sh
cd .worktrees/B1-parity-harness
swift build -j 4
.build/debug/parity <output-dir>              # all 108 configurations, about 20 seconds
.build/debug/parity dump Tromso 2026-01-14 2026-01-20   # both sides' times, day by day
.build/debug/parity deltas London             # largest difference before rounding, per kind
```

Two runs wrote byte-identical output.

### How differences were attributed

For each kind-day, the harness compares Salah's time with SalahCalculation's. Both are on whole minutes. For every difference of a minute or more, it looks for the cause with a model:

- The model takes SalahTimes' raw astronomy for the day and its neighbors: Fajr, Isha and an angle-based Maghrib computed with no high-latitude bound and no rounding, plus sunrise, sunset, transit and Asr. It then builds each kind with SalahTimes' rules. With no adhan-swift behavior switched on, it reproduces SalahCalculation exactly (0 seconds) on every kind-day where SalahCalculation gives a time. That also confirms that SalahCalculation passes the parameters to SalahTimes unchanged.
- It can switch on, one at a time, the behaviors in which adhan-swift differs, each read from adhan-swift's source:
  1. Dhuhr +1 minute for the Muslim World League, Egyptian, Karachi and North America (`Sources/Models/CalculationMethod.swift:137, 141, 145, 159`).
  2. Fajr bounded with the night after the day instead of its own night (`Sources/PrayerTimes.swift:87, 99–112`).
  3. The Moonsighting Committee's latitude-55 rule as adhan-swift has it (`PrayerTimes.swift:93–97, 122–126`).
  4. Tehran's 4.5° Maghrib only when it falls between sunset and Isha, unbounded (`PrayerTimes.swift:144–151`).
  5. Asr's noon shadow from the declination at 0 h UTC (`Sources/Astronomy/SolarTime.swift:40–50, 88–95`).
  6. Every altitude crossing found with a single correction step (`Sources/Astronomy/Astronomical.swift:175–193`).

  Behaviors 5 and 6 are applied as corrections computed with the harness's own solar model, written from NOAA's "General Solar Position Calculations", independent of both libraries. For 6, it runs adhan-swift's one-step procedure and a converged search with that model, and moves the crossing by the difference.
- A difference is attributed to a behavior when switching it on brings the model within 45 seconds of Salah's unrounded instant. Salah's unrounded instants come from adhan-swift with `rounding = .none`, with Dhuhr's extra minute removed when comparing instants. Failing a single behavior, it tries pairs, then all of them. A one-minute difference whose instants differ by under 60 seconds is rounding.
- What's left falls into two classes defined by geometry: Asr at Tromsø on days when the Sun rises less than 6° at noon (class B), and crossings where the Sun's altitude changes by less than 2° an hour (class D).

With every applicable behavior switched on, the model lands within a minute of Salah on 199,347 of the 199,483 kind-days on which both sides give a time. All 136 others are crossings where the Sun's altitude changes by less than 2° an hour, at the edges of polar night, the midnight sun and twilight seasons. There a few hundredths of a degree in the solar model move the time by minutes, more than the harness's simple solar model can resolve.

## Results

Each cell gives the range of differences for that kind over the days compared, from the most negative to the most positive. The largest absolute difference is the larger of the two ends. "Largest |Δ| before rounding" is the largest difference between the two instants before rounding, on kind-days whose rounded difference is a minute or less, with Dhuhr's extra minute removed.

### 1. Salah's default settings

| Place | Method (Salah → SalahCalculation) | High-latitude rule | Days | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Kind-days > 1 min | Kind-days = 1 min | Salah: days without times | SalahCalculation: missing kind-days | Days with 120-min Isha | Largest \|Δ\| before rounding (s) |
|---|---|---|---:|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| Makkah | ummAlQura → ummAlQura | middle | 365 | 0 | 0 to 1 | 0 to 1 | −1 to 1 | 0 | 0 | 0 | 95 | 0 | 0 | 30 | 25 |
| Riyadh | ummAlQura → ummAlQura | middle | 365 | 0 to 1 | 0 | 0 to 1 | −1 to 1 | 0 to 1 | 0 to 1 | 0 | 100 | 0 | 0 | 30 | 25 |
| Cairo | egyptian → egyptian | middle | 365 | 0 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 497 | 0 | 0 | 0 | 28 |
| Karachi | karachi → karachi | middle | 365 | 0 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 451 | 0 | 0 | 0 | 21 |
| Dubai | gulf → dubai | middle | 365 | 0 to 1 | 0 | 0 to 1 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 102 | 0 | 0 | 0 | 23 |
| Kuwait City | kuwait → kuwait | middle | 365 | 0 | 0 to 1 | 0 to 1 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 111 | 0 | 0 | 0 | 25 |
| Doha | qatar → qatar | middle | 365 | 0 | 0 to 1 | 0 | −1 to 1 | 0 to 1 | 0 to 1 | 0 | 90 | 0 | 0 | 30 | 24 |
| Singapore | singapore → muis | middle | 365 | 0 to 1 | 0 to 1 | 0 to 1 | −1 to 1 | 0 to 1 | 0 to 1 | 0 | 80 | 0 | 0 | 0 | 14 |
| Tehran | tehran → tehran | middle | 365 | 0 to 1 | 0 to 1 | 0 to 1 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 106 | 0 | 0 | 0 | 26 |
| Istanbul | egyptian → egyptian | middle | 365 | 0 to 1 | 0 to 1 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 533 | 0 | 0 | 0 | 34 |
| Kuala Lumpur | egyptian → egyptian | middle | 365 | 0 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | 0 | 0 | 401 | 0 | 0 | 0 | 14 |
| Jakarta | muslimWorldLeague → muslimWorldLeague | middle | 365 | 0 to 1 | 0 to 1 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 410 | 0 | 0 | 0 | 14 |
| London | moonsightingCommittee → moonsightingCommittee | seventh | 365 | −1 to 0 | 0 | 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 238 | 0 | 0 | 0 | 62 |
| New York | moonsightingCommittee → moonsightingCommittee | middle | 365 | −1 to 1 | 0 | 0 to 1 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 223 | 0 | 0 | 0 | 55 |
| Toronto | moonsightingCommittee → moonsightingCommittee | middle | 365 | 0 | 0 to 1 | 0 to 1 | −1 to 1 | 0 to 1 | 0 to 1 | 0 | 260 | 0 | 0 | 0 | 61 |
| Oslo | muslimWorldLeague → muslimWorldLeague | seventh | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 761 | 0 | 0 | 0 | 117 |
| Stockholm | muslimWorldLeague → muslimWorldLeague | seventh | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 66 | 804 | 0 | 0 | 0 | 107 |
| Reykjavik | muslimWorldLeague → muslimWorldLeague | seventh | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −6 to 5 | −1 to 1 | 0 to 1 | 176 | 797 | 0 | 0 | 0 | 114 |
| Tromsø | muslimWorldLeague → muslimWorldLeague | seventh | 365 | −113 to 9 | 0 to 7 | −1 to 0 | −2279 to 104 | −7 to 15 | −6 to 13 | 259 | 511 | 118 | 425 | 0 | 108 |
| Ushuaia | muslimWorldLeague → muslimWorldLeague | seventh | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 77 | 732 | 0 | 0 | 0 | 100 |
| Kashgar | muslimWorldLeague → muslimWorldLeague | middle | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 0 | 0 | 453 | 0 | 0 | 0 | 23 |

At latitudes below 52°, every kind agrees within a minute on every day. Before rounding, Fajr, sunrise, Dhuhr, Maghrib and Isha agree within 1.3 to 8 seconds at every place but Tromsø, except Fajr at 54.8° and beyond (class C, up to 59 seconds). adhan-swift truncates each instant to the whole second before rounding (`Sources/Extensions/DateUtilities.swift:55–70`). The column's larger values are Asr (class A): 14 to 34 seconds at low latitudes, about a minute at London, New York and Toronto, and more beyond 54°. Riyadh, Makkah and Doha show 30 days with a 120-minute Isha, identical on both sides.

### 2. Every method at Makkah and London

| Configuration | Place | Days | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Kind-days > 1 min | Kind-days = 1 min | Salah: days without times | SalahCalculation: missing kind-days | Days with 120-min Isha | Largest \|Δ\| before rounding (s) |
|---|---|---:|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| egyptian | Makkah | 365 | 0 to 1 | 0 to 1 | −1 to 0 | −1 to 1 | 0 | −1 to 1 | 0 | 465 | 0 | 0 | 0 | 25 |
| karachi | Makkah | 365 | 0 | 0 to 1 | −1 to 0 | −1 to 1 | 0 | 0 to 1 | 0 | 458 | 0 | 0 | 0 | 25 |
| northAmerica | Makkah | 365 | 0 to 1 | 0 to 1 | −1 to 0 | −1 to 1 | 0 | 0 | 0 | 456 | 0 | 0 | 0 | 25 |
| muslimWorldLeague | Makkah | 365 | 0 | 0 to 1 | −1 to 0 | −1 to 1 | 0 | −1 to 1 | 0 | 460 | 0 | 0 | 0 | 25 |
| ummAlQura | Makkah | 365 | 0 | 0 to 1 | 0 to 1 | −1 to 1 | 0 | 0 | 0 | 95 | 0 | 0 | 30 | 25 |
| gulf | Makkah | 365 | 0 to 1 | 0 to 1 | 0 to 1 | −1 to 1 | 0 | −1 to 1 | 0 | 102 | 0 | 0 | 0 | 25 |
| moonsightingCommittee | Makkah | 365 | 0 | 0 to 1 | 0 to 1 | −1 to 1 | 0 | 0 to 1 | 0 | 98 | 0 | 0 | 0 | 25 |
| custom | Makkah | 365 | 0 | 0 to 1 | 0 to 1 | −1 to 1 | 0 | −1 to 1 | 0 | 105 | 0 | 0 | 0 | 25 |
| kuwait | Makkah | 365 | 0 | 0 to 1 | 0 to 1 | −1 to 1 | 0 | −1 to 1 | 0 | 105 | 0 | 0 | 0 | 25 |
| qatar | Makkah | 365 | 0 | 0 to 1 | 0 to 1 | −1 to 1 | 0 | 0 | 0 | 95 | 0 | 0 | 30 | 25 |
| singapore | Makkah | 365 | 0 to 1 | 0 to 1 | 0 to 1 | −1 to 1 | 0 to 1 | 0 to 1 | 0 | 118 | 0 | 0 | 0 | 25 |
| tehran | Makkah | 365 | 0 to 1 | 0 to 1 | 0 to 1 | −1 to 1 | 0 to 1 | 0 to 1 | 0 | 100 | 0 | 0 | 0 | 25 |
| egyptian | London | 365 | −1 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 728 | 0 | 0 | 0 | 62 |
| karachi | London | 365 | −1 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 703 | 0 | 0 | 0 | 62 |
| northAmerica | London | 365 | −1 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 668 | 0 | 0 | 0 | 62 |
| muslimWorldLeague | London | 365 | −1 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 702 | 0 | 0 | 0 | 62 |
| ummAlQura | London | 365 | −1 to 1 | 0 | 0 | −1 to 1 | 0 to 1 | 0 to 1 | 0 | 335 | 0 | 0 | 30 | 62 |
| gulf | London | 365 | −1 to 1 | 0 | 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 342 | 0 | 0 | 0 | 62 |
| moonsightingCommittee | London | 365 | −1 to 0 | 0 | 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 238 | 0 | 0 | 0 | 62 |
| custom | London | 365 | −1 to 1 | 0 | 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 338 | 0 | 0 | 0 | 62 |
| kuwait | London | 365 | −1 to 1 | 0 | 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 338 | 0 | 0 | 0 | 62 |
| qatar | London | 365 | −1 to 1 | 0 | 0 | −1 to 1 | 0 to 1 | 0 to 1 | 0 | 330 | 0 | 0 | 30 | 62 |
| singapore | London | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 406 | 0 | 0 | 0 | 62 |
| tehran | London | 365 | −1 to 1 | 0 | 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 329 | 0 | 0 | 0 | 62 |

No difference exceeds a minute. The one-minute Dhuhr differences with `egyptian`, `karachi`, `northAmerica` and `muslimWorldLeague` are adhan-swift's extra Dhuhr minute. Umm al-Qura and Qatar show the default delayed Isha on 30 days at both places.

### 3. Customized settings

**Hanafi Asr**

| Configuration | Place | Days | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Kind-days > 1 min | Kind-days = 1 min | Salah: days without times | SalahCalculation: missing kind-days | Days with 120-min Isha | Largest \|Δ\| before rounding (s) |
|---|---|---:|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| Hanafi, karachi | Karachi | 365 | 0 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 413 | 0 | 0 | 0 | 9 |
| Hanafi, egyptian | Istanbul | 365 | 0 to 1 | 0 to 1 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 446 | 0 | 0 | 0 | 16 |
| Hanafi, moonsightingCommittee | London | 365 | −1 to 0 | 0 | 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 115 | 0 | 0 | 0 | 32 |
| Hanafi, muslimWorldLeague | Oslo | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 1 | 0 to 1 | 0 to 1 | 1 | 774 | 0 | 0 | 0 | 70 |
| Hanafi, egyptian | Cairo | 365 | 0 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 409 | 0 | 0 | 0 | 12 |

**High-latitude rules**

| Configuration | Place | Days | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Kind-days > 1 min | Kind-days = 1 min | Salah: days without times | SalahCalculation: missing kind-days | Days with 120-min Isha | Largest \|Δ\| before rounding (s) |
|---|---|---:|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| muslimWorldLeague, middleOfTheNight | London | 365 | −2 to 2 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −18 to 4 | 6 | 670 | 0 | 0 | 0 | 78 |
| muslimWorldLeague, seventhOfTheNight | London | 365 | −1 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 702 | 0 | 0 | 0 | 62 |
| muslimWorldLeague, twilightAngle | London | 365 | −1 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 679 | 0 | 0 | 0 | 62 |
| muslimWorldLeague, middleOfTheNight | Stockholm | 365 | −3 to 3 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −25 to 7 | 151 | 633 | 0 | 0 | 0 | 107 |
| muslimWorldLeague, seventhOfTheNight | Stockholm | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 66 | 804 | 0 | 0 | 0 | 107 |
| muslimWorldLeague, twilightAngle | Stockholm | 365 | −2 to 2 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 105 | 681 | 0 | 0 | 0 | 107 |
| muslimWorldLeague, middleOfTheNight | Oslo | 365 | −3 to 3 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −29 to 14 | 185 | 602 | 0 | 0 | 0 | 119 |
| muslimWorldLeague, seventhOfTheNight | Oslo | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 761 | 0 | 0 | 0 | 117 |
| muslimWorldLeague, twilightAngle | Oslo | 365 | −2 to 2 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 137 | 654 | 0 | 0 | 0 | 117 |
| muslimWorldLeague, middleOfTheNight | Reykjavik | 365 | −4 to 4 | 0 to 1 | −1 to 0 | −6 to 5 | −1 to 1 | −26 to 12 | 310 | 556 | 0 | 0 | 0 | 114 |
| muslimWorldLeague, seventhOfTheNight | Reykjavik | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −6 to 5 | −1 to 1 | 0 to 1 | 176 | 797 | 0 | 0 | 0 | 114 |
| muslimWorldLeague, twilightAngle | Reykjavik | 365 | −2 to 2 | 0 to 1 | −1 to 0 | −6 to 5 | −1 to 1 | −1 to 1 | 301 | 570 | 0 | 0 | 0 | 118 |
| muslimWorldLeague, middleOfTheNight | Tromsø | 365 | −21 to 32 | 0 to 7 | −1 to 0 | −2279 to 104 | −7 to 15 | −35 to 8 | 263 | 379 | 118 | 425 | 0 | 108 |
| muslimWorldLeague, seventhOfTheNight | Tromsø | 365 | −113 to 9 | 0 to 7 | −1 to 0 | −2279 to 104 | −7 to 15 | −6 to 13 | 259 | 511 | 118 | 425 | 0 | 108 |
| muslimWorldLeague, twilightAngle | Tromsø | 365 | −13 to 20 | 0 to 7 | −1 to 0 | −2279 to 104 | −7 to 15 | −1 to 11 | 281 | 381 | 118 | 425 | 0 | 108 |
| muslimWorldLeague, middleOfTheNight | Ushuaia | 365 | −2 to 2 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −30 to 13 | 115 | 666 | 0 | 0 | 0 | 108 |
| muslimWorldLeague, seventhOfTheNight | Ushuaia | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 77 | 732 | 0 | 0 | 0 | 100 |
| muslimWorldLeague, twilightAngle | Ushuaia | 365 | −2 to 2 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 84 | 693 | 0 | 0 | 0 | 100 |
| ummAlQura, middleOfTheNight | Oslo | 365 | −3 to 3 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | 0 to 1 | 182 | 215 | 0 | 0 | 30 | 119 |
| tehran, middleOfTheNight | Oslo | 365 | −3 to 3 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | −25 to 5 | 183 | 238 | 0 | 0 | 0 | 119 |
| ummAlQura, twilightAngle | Oslo | 365 | −2 to 2 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | 0 to 1 | 150 | 262 | 0 | 0 | 30 | 117 |
| tehran, twilightAngle | Oslo | 365 | −2 to 2 | 0 to 1 | 0 to 1 | −2 to 2 | −39 to 1 | −1 to 1 | 236 | 282 | 0 | 0 | 0 | 117 |
| ummAlQura, middleOfTheNight | Reykjavik | 365 | −4 to 4 | 0 to 1 | 0 to 1 | −6 to 5 | −1 to 1 | −1 to 1 | 306 | 169 | 0 | 13 | 30 | 114 |
| tehran, middleOfTheNight | Reykjavik | 365 | −4 to 4 | 0 to 1 | 0 to 1 | −6 to 5 | 0 to 130 | −11 to 83 | 359 | 197 | 0 | 50 | 0 | 114 |
| ummAlQura, twilightAngle | Reykjavik | 365 | −2 to 3 | 0 to 1 | 0 to 1 | −6 to 5 | −1 to 1 | −1 to 1 | 307 | 185 | 0 | 0 | 30 | 115 |
| tehran, twilightAngle | Reykjavik | 365 | −2 to 2 | 0 to 1 | 0 to 1 | −6 to 5 | −47 to 24 | −1 to 1 | 413 | 214 | 0 | 0 | 0 | 118 |

**The Moonsighting Committee at 55° and beyond**

| Configuration | Place | Days | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Kind-days > 1 min | Kind-days = 1 min | Salah: days without times | SalahCalculation: missing kind-days | Days with 120-min Isha | Largest \|Δ\| before rounding (s) |
|---|---|---:|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| moonsightingCommittee | Stockholm | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 66 | 318 | 0 | 0 | 0 | 107 |
| moonsightingCommittee | Oslo | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 287 | 0 | 0 | 0 | 117 |
| moonsightingCommittee | Reykjavik | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −6 to 5 | −1 to 1 | 0 to 1 | 176 | 297 | 0 | 0 | 0 | 114 |
| moonsightingCommittee | Ushuaia | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 77 | 229 | 0 | 0 | 0 | 100 |
| moonsightingCommittee | Puerto Toro | 365 | 0 to 67 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | −25 to 1 | 311 | 246 | 0 | 0 | 0 | 103 |

North of 55°, the committee's two formulations, adhan-swift's and SalahTimes', differ by at most a minute in 2026 at Stockholm, Oslo and Reykjavik. The seasonal bound decides Fajr and Isha in both. South of 55° they differ (class F).

**Adjustments**

| Configuration | Place | Days | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Kind-days > 1 min | Kind-days = 1 min | Salah: days without times | SalahCalculation: missing kind-days | Days with 120-min Isha | Largest \|Δ\| before rounding (s) |
|---|---|---:|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| ummAlQura, adjustments +2 -1 +3 +1 +2 -3 | Makkah | 365 | 0 | 0 to 1 | 0 to 1 | −1 to 1 | 0 | 0 | 0 | 95 | 0 | 0 | 30 | 25 |
| moonsightingCommittee, adjustments +2 -1 +3 +1 +2 -3 | London | 365 | −1 to 0 | 0 | 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 238 | 0 | 0 | 0 | 62 |
| northAmerica, adjustments +2 -1 +3 +1 +2 -3 | New York | 365 | −1 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 591 | 0 | 0 | 0 | 55 |
| singapore, adjustments +2 -1 +3 +1 +2 -3 | Singapore | 365 | 0 to 1 | 0 to 1 | 0 to 1 | −1 to 1 | 0 to 1 | 0 to 1 | 0 | 80 | 0 | 0 | 0 | 14 |

User adjustments move both sides' times by the same minutes. Nothing differs by more than a minute.

**The custom method**

| Configuration | Place | Days | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Kind-days > 1 min | Kind-days = 1 min | Salah: days without times | SalahCalculation: missing kind-days | Days with 120-min Isha | Largest \|Δ\| before rounding (s) |
|---|---|---:|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| custom 18.0/17.5 | Cairo | 365 | 0 to 1 | 0 | 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 133 | 0 | 0 | 0 | 28 |
| custom 18.0/17.5 | London | 365 | −1 to 1 | 0 | 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 338 | 0 | 0 | 0 | 62 |
| custom 16.0/14.0 | London | 365 | −1 to 1 | 0 | 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 312 | 0 | 0 | 0 | 62 |
| custom 15.0/15.0 | Oslo | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | −1 to 1 | 95 | 325 | 0 | 0 | 0 | 117 |
| custom 18.0/18.0 | Kuala Lumpur | 365 | 0 to 1 | 0 | 0 to 1 | −1 to 1 | 0 to 1 | 0 to 1 | 0 | 40 | 0 | 0 | 0 | 14 |

**Ramadan delayed Isha**

| Configuration | Place | Days | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Kind-days > 1 min | Kind-days = 1 min | Salah: days without times | SalahCalculation: missing kind-days | Days with 120-min Isha | Largest \|Δ\| before rounding (s) |
|---|---|---:|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| ummAlQura, Ramadan on, hijriOffset 0 | Makkah | 59 | 0 | 0 to 1 | 0 to 1 | −1 to 0 | 0 | 0 | 0 | 24 | 0 | 0 | 30 | 21 |
| ummAlQura, Ramadan on, hijriOffset 1 | Makkah | 59 | 0 | 0 to 1 | 0 to 1 | −1 to 0 | 0 | 0 | 0 | 24 | 0 | 0 | 30 | 21 |
| ummAlQura, Ramadan on, hijriOffset -1 | Makkah | 59 | 0 | 0 to 1 | 0 to 1 | −1 to 0 | 0 | 0 | 0 | 24 | 0 | 0 | 30 | 21 |
| ummAlQura, Ramadan on, hijriOffset 2 | Makkah | 59 | 0 | 0 to 1 | 0 to 1 | −1 to 0 | 0 | 0 | 0 | 24 | 0 | 0 | 30 | 21 |
| ummAlQura, Ramadan off, hijriOffset 0 | Makkah | 59 | 0 | 0 to 1 | 0 to 1 | −1 to 0 | 0 | 0 | 0 | 24 | 0 | 0 | 0 | 21 |
| ummAlQura, Ramadan on, hijriOffset 0 | Riyadh | 59 | 0 to 1 | 0 | 0 to 1 | −1 to 0 | 0 | 0 | 0 | 23 | 0 | 0 | 30 | 21 |
| ummAlQura, Ramadan on, hijriOffset 1 | Riyadh | 59 | 0 to 1 | 0 | 0 to 1 | −1 to 0 | 0 | 0 | 0 | 23 | 0 | 0 | 30 | 21 |
| ummAlQura, Ramadan on, hijriOffset -1 | Riyadh | 59 | 0 to 1 | 0 | 0 to 1 | −1 to 0 | 0 | 0 | 0 | 23 | 0 | 0 | 30 | 21 |
| ummAlQura, Ramadan on, hijriOffset 2 | Riyadh | 59 | 0 to 1 | 0 | 0 to 1 | −1 to 0 | 0 | 0 | 0 | 23 | 0 | 0 | 30 | 21 |
| ummAlQura, Ramadan off, hijriOffset 0 | Riyadh | 59 | 0 to 1 | 0 | 0 to 1 | −1 to 0 | 0 | 0 | 0 | 23 | 0 | 0 | 0 | 21 |
| qatar, Ramadan on, hijriOffset 0 | Doha | 59 | 0 | 0 | 0 | −1 to 0 | 0 | 0 | 0 | 16 | 0 | 0 | 30 | 20 |
| qatar, Ramadan on, hijriOffset 1 | Doha | 59 | 0 | 0 | 0 | −1 to 0 | 0 | 0 | 0 | 16 | 0 | 0 | 30 | 20 |
| qatar, Ramadan on, hijriOffset -1 | Doha | 59 | 0 | 0 | 0 | −1 to 0 | 0 | 0 | 0 | 16 | 0 | 0 | 30 | 20 |
| qatar, Ramadan on, hijriOffset 2 | Doha | 59 | 0 | 0 | 0 | −1 to 0 | 0 | 0 | 0 | 16 | 0 | 0 | 30 | 20 |
| qatar, Ramadan off, hijriOffset 0 | Doha | 59 | 0 | 0 | 0 | −1 to 0 | 0 | 0 | 0 | 16 | 0 | 0 | 0 | 20 |

Isha agrees on every day of every run. With the toggle on, Salah used 120 minutes on 30 days in each run and SalahCalculation's Isha matched it on each of them. With it off, neither used 120 minutes. Salah reads the Umm al-Qura month at the start of the civil day in the stored zone. SalahTimes reads it at 12:00 UTC of the same civil date (`Sources/SalahTimes/Engine/Seasonal.swift`). Both give the same Umm al-Qura date for that civil day.

Salah's toggle lengthens any interval Isha, Qatar's included, and the mapping keeps that behavior. SalahTimes' `METHODS.md` (Qatar) notes that Qatar's official 1447 timetable keeps 90 minutes in Ramadan. Whether Salah should keep the toggle on for Qatar is a product choice for D1, not a parity difference.

### 4. Country suggestions

SalahKit applies no suggestion on its own. These tables show what would change if Salah adopted `CalculationMethod.suggested(forCountryCode:)` in place of its own detection. Country codes where the two differ:

| Code | Salah's auto-detected method (as mapped) | SalahTimes' suggestion |
|---|---|---|
| BH | `qatar` | none |
| BN | `muslimWorldLeague` | `muis` |
| DZ | `egyptian` | `muslimWorldLeague` |
| GB | `moonsightingCommittee` | none |
| ID | `muslimWorldLeague` | `kemenag` |
| IL | `egyptian` | none |
| IQ | `egyptian` | none |
| LB | `egyptian` | none |
| LY | `egyptian` | none |
| MA | `egyptian` | none |
| MY | `egyptian` | `jakim` |
| OM | `qatar` | none |
| PS | `egyptian` | none |
| SD | `egyptian` | none |
| SS | `egyptian` | none |
| SY | `egyptian` | none |
| TN | `muslimWorldLeague` | `karachi` |
| TR | `egyptian` | `diyanet` |
| UK | `moonsightingCommittee` | none |
| YE | `qatar` | none |

The two agree for EG, PK, IN, BD, AF, JO, SA, AE, US, CA, KW, QA, SG and IR, counting Salah's `gulf` as `dubai` and `singapore` as `muis`. Codes in neither table get `muslimWorldLeague` from Salah and `nil` (no sourced suggestion) from SalahTimes; Norway, Sweden, Iceland, Argentina and China are among them. `METHODS.md` ("Country suggestions") gives each suggestion's source and why the dropped entries were dropped.

The three places where both sides have a method but different ones:

| Configuration | Place | Days | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Kind-days > 1 min | Kind-days = 1 min | Salah: days without times | SalahCalculation: missing kind-days | Days with 120-min Isha | Largest \|Δ\| before rounding (s) |
|---|---|---:|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| Salah default vs SalahTimes suggestion (diyanet) | Istanbul | 365 | 0 to 16 | −7 to 0 | 0 to 5 | 0 to 5 | 0 to 8 | −5 to 0 | 2190 | 0 | 0 | 0 | 0 | 0 |
| Salah default vs SalahTimes suggestion (jakim) | Kuala Lumpur | 365 | 0 to 7 | 0 | 0 to 1 | −1 to 1 | 0 to 1 | 0 to 3 | 730 | 36 | 0 | 0 | 0 | 14 |
| Salah default vs SalahTimes suggestion (kemenag) | Jakarta | 365 | −7 to 0 | −3 to 0 | 0 to 3 | 0 to 3 | 0 to 4 | 0 to 8 | 2190 | 0 | 0 | 0 | 0 | 0 |

These differences come from the methods themselves, as `METHODS.md` defines them:

- **Istanbul:** Diyanet's temkin (sunrise −7, Dhuhr +5, Asr +4, Maghrib +7) and its 18°/17° angles, against Egyptian's 19.5°/17.5°.
- **Kuala Lumpur:** JAKIM's 18° Fajr (Malaysia moved from 20° in 2019), against Egyptian's 19.5°, with Isha at 18° against 17.5°. JAKIM's Dhuhr +1 and Egyptian's adhan-swift +1 cancel.
- **Jakarta:** Kemenag's 20°/18° angles, 1° Maghrib, ihtiyat minutes and upward rounding, against the Muslim World League's 18°/17°.

## Differences of exactly one minute

35,103 kind-days differ by exactly one minute, over all parity configurations:

| Kind | Cause | Kind-days |
|---|---|---:|
| Dhuhr | adhan-swift's extra Dhuhr minute (Muslim World League, Egyptian, Karachi, North America) | 14,817 |
| Dhuhr | Rounding of a sub-minute difference | 83 |
| Asr | Rounding of a sub-minute difference | 10,648 |
| Asr | Asr's noon shadow (class A), a 60 to 120 second difference | 3,132 |
| Fajr | Rounding of a sub-minute difference | 4,310 |
| Fajr | Fajr's night (class C) | 746 |
| Fajr, Isha | The Moonsighting Committee south of 55° S (class F) | 3 |
| Isha | Rounding of a sub-minute difference | 896 |
| Isha, Maghrib | Crossings the Sun barely makes (class D) | 21 |
| Maghrib | Rounding of a sub-minute difference | 312 |
| Maghrib | Tehran's Maghrib (class E) | 2 |
| Sunrise | Rounding of a sub-minute difference | 133 |

The Dhuhr minute is systematic, not rounding: SalahCalculation's Dhuhr is a minute earlier on nearly every day for those four methods. The rounding cases are instants a few seconds apart, often only adhan-swift's truncation to the whole second (up to one second), on either side of a half minute. The rounded minutes then differ by one. Asr has the most of them because its instants differ by up to half a minute even at low latitudes (class A). Fajr's rounding cases are mostly at 54.8° and beyond, where class C is under a minute.

## Every class of difference over a minute

### A. Asr's noon shadow

**What users see.** Asr moves by up to 2 minutes at Oslo, Stockholm, Ushuaia and Puerto Toro, up to 6 at Reykjavik and 7 at Tromsø (8 with class D). It moves earlier in the half of the year when days lengthen and later when they shorten. With defaults: Oslo 95, Stockholm 66, Reykjavik 172 (+4), Tromsø 103 (+7) and Ushuaia 77 days a year over a minute. At lower latitudes the same effect stays under a minute: up to 25 seconds at Makkah and about a minute at London.

**Cause.** Asr begins when an object's shadow equals its length plus its noon shadow. The noon shadow depends on the Sun's declination at noon. SalahTimes takes the declination at the transit (`docs/algorithm.md` §7, "Asr"). adhan-swift takes it from the solar coordinates at 0 h UTC of the date (`SolarTime.swift:40–50` sets the hour to 0; `:88–95` uses `solar.declination`). Near the equinoxes the declination changes by about 0.4° a day. By the transit, about 10½ to 16½ hours after 0 h UTC at these places, the two values differ by up to about 0.3°. At high latitudes the Sun descends slowly in the afternoon, so that changes Asr by minutes.

**Evidence.** Switching on behavior 5 alone, computed with the independent solar model, brings the model within 45 seconds of Salah on all 3,704 such kind-days. On another 64, at Reykjavik in early December and at Tromsø, it does so together with class D. SalahTimes' self-consistency check confirms its Asr against an independent model within 0.0128° of altitude (`docs/validation.md`, "Self-consistency").

**Intended.** Yes. SalahTimes computes the shadow the way the definition states.

### B. Asr in the weeks around polar night

**What users see.** In Tromsø, from 15 January into early February and from early November to 26 November, Salah's Asr is wrong. On 15 to 20 January it falls after Maghrib. On 19 January it is the morning of 21 January, 38 hours late. From 15 to 26 November it falls before Dhuhr. SalahCalculation puts Asr minutes after Dhuhr, or reports it missing (below). There are 35 kind-days over a minute per configuration, 140 over the four Tromsø configurations. Salah's times are out of order on 18 days: Asr after Maghrib on 15 to 20 January, Asr before Dhuhr on 15 to 26 November.

**Cause.** When the noon Sun is only a few degrees up, the Asr altitude, `atan(1 / (k + tan z))`, is barely below the noon altitude, so Asr comes soon after the transit. adhan-swift's single correction step from an estimate made at 0 h UTC (`Astronomical.swift:175–193`) can't find a crossing that close to the transit. With the noon zenith distance at 0 h UTC beyond 90°, it also computes an Asr altitude below the horizon (`SolarTime.swift:88–95`). SalahTimes reports Asr as not occurring when the Sun is below the horizon at the transit. Otherwise it finds the crossing by iteration, with bisection as a fallback (`docs/algorithm.md` §6 and §7). `docs/validation.md` ("Known limitations", "Dhuhr and Asr before polar night") describes the expected behavior: Asr seconds to minutes after the transit.

**Evidence.** On these days the noon altitude is below 6° (the harness's geometry check). Salah's own times are out of order on 18 of them.

**Intended.** Yes. It replaces impossible times.

### C. Fajr's night for the high-latitude bound

**What users see.** Under the middle-of-the-night rule, Fajr differs by up to 2 minutes at London and Ushuaia, 3 at Oslo and Stockholm, 4 at Reykjavik and 12 at Tromsø. Under the twilight-angle rule: up to 2 minutes at Oslo, Stockholm, Reykjavik and Ushuaia, and 9 at Tromsø. Under the seventh-of-the-night rule (Salah's automatic choice beyond 48°) it stays within a minute everywhere except Tromsø, which has 100 days of up to 5 minutes. Fajr is earlier in spring and later in autumn. With defaults, only Tromsø is affected.

**Cause.** A high-latitude rule keeps Fajr no earlier than sunrise minus a portion of the night. adhan-swift measures that night from the day's sunset to the next sunrise (`PrayerTimes.swift:87` and `:104–107`), a night that comes after the Fajr it bounds. SalahTimes uses the night that ends at Fajr's own sunrise (`docs/algorithm.md` §8 and §8.1, and RFC 0001 §6, "Each prayer uses its own night"). The two nights differ by the night's day-to-day change, several minutes a day at these latitudes around the equinoxes. The bounds then differ by that change times the portion (1/2, 1/7, or the angle over 60). Isha's bound uses the night after its sunset in both, so Isha agrees.

The largest case is Tromsø on 15 January, the first sunrise after polar night: Salah 08:07, SalahCalculation 06:14 (−113 minutes). 14 January has no sunset, so Fajr's own night doesn't exist. SalahTimes then leaves the 18° time unbounded (`docs/algorithm.md` §8.1, "if nightBefore is undefined: return raw", and §9). adhan-swift bounds it with the following night, from a sunrise that is itself 7 minutes off (class D).

**Evidence.** Behavior 2 alone explains 1,727 kind-days; with class D, 12 more at Tromsø.

**Intended.** Yes. Using one night for both prayers can put a bounded Fajr before the previous evening's bounded Isha when nights lengthen quickly (adhan-swift issue #102, cited in SalahTimes RFC 0001 §6).

### D. Crossings the Sun barely makes

**What users see.** A few days a year at high latitudes:
- **Isha with the middle-of-the-night rule,** on the days when the Sun's lowest point is close to the Isha angle. This happens at the start and end of the season in which the Sun no longer reaches that angle. London: 4 days, up to −18 minutes (15 July). Oslo, Stockholm, Reykjavik, Tromsø and Ushuaia: 5 or 6 days each, up to −35 minutes (Tromsø, 14 September), and +83 minutes for Tehran's 14° Isha at Reykjavik on 22 August. Under the seventh-of-the-night rule, the bound replaces such an Isha on both sides, so Salah's defaults don't show this except at Tromsø.
- **Tromsø's sunrise and sunset** on the last and first days of polar night and the midnight sun (15 January, 16–17 May, 26–27 July). Sunrise moves by 7 minutes and Maghrib by −7 to +15. Isha, an interval or bound after sunset, moves by −6 to +13, and Fajr by up to 32 minutes under the middle-of-the-night rule (with class C).

84 kind-days are in this class alone, and 76 more combine it with class A or C.

**Cause.** adhan-swift finds each crossing with one correction step from an estimate made with the declination at 0 h UTC (`Astronomical.swift:175–193`, after Meeus, *Astronomical Algorithms*, p. 102). Where the Sun's altitude changes slowly, near the transit, the antitransit or an altitude the Sun barely reaches, one step leaves an error of minutes. SalahTimes iterates each crossing to under a millisecond and bisects when the iteration can't settle (`docs/algorithm.md` §6). Near polar transitions its times agree with JPL Horizons within 30 to 82 seconds (`docs/validation.md`, "Astronomy cross-checks").

**Evidence.** Running adhan-swift's one-step procedure and a converged search with the harness's independent solar model, and moving the crossing by the difference, reproduces Salah within 45 seconds on 69 kind-days, and on 76 more together with class A or C. On the remaining 15, the Sun's altitude changes by less than 2° an hour at the event. There a few hundredths of a degree in the solar model move the result by minutes, beyond what the harness's model resolves. These are the same slow crossings.

**Intended.** Yes. More accurate times.

### E. Tehran's Maghrib at high latitudes

**What users see.** With the Tehran method:
- **Twilight-angle rule:** at Oslo, Maghrib is up to 39 minutes earlier on 101 days (2 May to 10 August). At Reykjavik it is between 47 minutes earlier and 24 minutes later on 127 days (18 April to 22 August).
- **Middle-of-the-night rule at Reykjavik:** Maghrib is 86 to 130 minutes later on 49 days (28 May to 15 July), and SalahCalculation reports no Isha on 50 days (27 May to 15 July). Salah shows Maghrib at sunset and Isha at the middle of the night. SalahCalculation puts Maghrib at the middle of the night, the same instant as Isha, and drops Isha.

Salah's defaults use Tehran only in Iran, where nothing differs.

**Cause.** Tehran's Maghrib is the Sun at 4.5° below the horizon. adhan-swift uses that time only when it falls after sunset and before Isha, and otherwise falls back to sunset, with no high-latitude bound (`PrayerTimes.swift:144–151`). SalahTimes bounds an angle-based Maghrib like Isha, by the same portion of the night (`docs/algorithm.md` §8.3, RFC 0001 §6, `METHODS.md` "Differences from adhan-swift's presets"):
- **Twilight-angle rule:** the bound, sunset plus 4.5/60 of the night, comes before the 4.5° time, so SalahCalculation's Maghrib is earlier. When adhan-swift falls back to sunset because the 4.5° time isn't before its Isha, SalahCalculation's is later.
- **Middle-of-the-night rule:** both Maghrib and Isha are bounded at the middle of the night, the specified tie (`docs/validation.md`, "Known limitations", "Tehran at high latitudes"). SalahCalculation reports the later of an equal pair as missing, as its contract requires (`CalculationSource`: "one that isn't strictly after the kind before it").

**Evidence.** Behavior 4 alone explains all 277 kind-days. The Isha gaps are listed under "Times one side doesn't give".

**Intended.** Yes, as specified. For D1: a Tehran user at high latitudes would see Maghrib at the middle of the night and no separate Isha on summer nights under the middle-of-the-night rule. Salah's UI should present that.

### F. The Moonsighting Committee south of 55° S

**What users see.** At Puerto Toro (55.08° S), Fajr is 2 to 67 minutes later on 162 days, and Isha 2 to 25 minutes earlier on 71 days. Both are largest at the December solstice.

**Cause.** The committee bounds Fajr and Isha by the seventh of the night from 55° of latitude. SalahTimes applies that from 55° of absolute latitude, in both hemispheres, as the committee's own timetable generator does (`docs/algorithm.md` §8.2 and §8.4; `METHODS.md`, "Moonsighting Committee Worldwide", "From 55°", and "Differences from adhan-swift's presets"). adhan-swift tests `coordinates.latitude >= 55` (`PrayerTimes.swift:94` and `:123`), so it never applies the rule in the south. SalahTimes also keeps the 18° time as one of the bounds where adhan-swift replaces it. In 2026 that changed nothing by more than a minute at Stockholm, Oslo or Reykjavik.

**Evidence.** Behavior 3 alone explains all 233 kind-days.

**Intended.** Yes.

## Times one side doesn't give

These kind-days have a time on only one side, so they aren't counted as differences:

| Where | Salah | SalahCalculation |
|---|---|---|
| Tromsø, all configurations: 1–14 January and 27 November–31 December (polar night) | No times (adhan-swift returns `nil`); Salah keeps showing the last day it computed | Fajr, Dhuhr and Isha on 48 days; sunrise, Asr and Maghrib missing with `sunStaysBelow` (on 27 November the Sun rises for 21 minutes, so sunrise and Maghrib are given too) |
| Tromsø: 18 May–25 July (midnight sun) | No times | Dhuhr and Asr on 67 days; Fajr, sunrise, Maghrib and Isha missing with `sunStaysAbove`; on the two edge days, four kinds |
| Tromsø: 15–18 January, 23–26 November | An Asr, out of order (class B) | Asr missing with `sunStaysBelow`: the Sun is below the horizon at noon |
| Reykjavik, Umm al-Qura with the middle-of-the-night rule: 14–26 June | Isha 90 minutes after sunset | Isha missing: it falls after the next day's Fajr, which the rule puts at the middle of the night |
| Reykjavik, Tehran with the middle-of-the-night rule: 27 May–15 July | Isha at the middle of the night, Maghrib at sunset | Isha missing: tied with the bounded Maghrib (class E) |

On every day where SalahCalculation reports a kind missing and SalahTimes computed a time, the reason is one of the adapter rules that `CalculationSource` documents. In this comparison that was a tie with the kind before, or a time after the next day's first event.

## What Salah's users will see after D1

- **Everywhere:** with the Muslim World League, Egyptian, Karachi or North America method, Dhuhr is a minute earlier. Other times move by at most a minute, through rounding.
- **At 54.8° and beyond:** Asr moves by 1 to 2 minutes on some days, and by up to 7 minutes at Reykjavik and Tromsø (classes A, D).
- **Users who chose the middle-of-the-night or twilight-angle rule at high latitudes:** Fajr moves by a few minutes in spring and autumn (class C). On a few days a year, Isha moves by up to half an hour (class D).
- **Tehran users at high latitudes:** Maghrib follows the high-latitude rule (class E).
- **Moonsighting Committee users south of 55° S:** the seventh-of-the-night bound now applies (class F).
- **Near and beyond the polar circle:** days that Salah couldn't compute become partial days with the missing prayers named, and impossible Asr times are gone (class B, and the table above).
- **Ramadan delayed Isha** behaves as before.
