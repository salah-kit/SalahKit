# Calculation parity: Salah today and SalahCalculation

The Salah app computes prayer times with adhan-swift. It will move to SalahCalculation, SalahKit's calculated prayer source built on the SalahTimes engine, in session D1. This document compares the two for the same user settings, over every day of 2026, and explains every difference larger than one minute. The differences listed here are the changes Salah's users would see after that move.

All differences are signed: SalahCalculation minus Salah, in minutes. A "kind-day" is one of the six kinds (Fajr, sunrise, Dhuhr, Asr, Maghrib, Isha) on one day in one configuration.

## Summary

- **Salah's default settings, 21 places, 45,990 kind-days.** Every time agrees within one minute at 16 of the 21 places. The other five are at or beyond 54.8° of latitude. In Oslo, Stockholm and Ushuaia, Asr differs by up to 2 minutes on 66 to 95 days a year; in Reykjavik by up to 6 minutes on 176 days. Tromsø (69.6° N) differs more around polar night and the midnight sun, and there adhan-swift gives no times at all on 118 days.
- **Dhuhr is one minute earlier** with the Muslim World League, Egyptian, Karachi and North America methods, on 35,012 kind-days. adhan-swift adds an undocumented minute to Dhuhr for these methods, and SalahTimes doesn't. This is a difference of exactly one minute, and it isn't rounding.
- **Every method at high latitudes.** The comparison runs all 12 of Salah's methods at Stockholm, Oslo, Reykjavik, Tromsø and Ushuaia with Salah's automatic high-latitude rule, and at those places and London with the middle-of-the-night and twilight-angle rules.
  - **Tehran under Salah's own automatic rule** (the seventh of the night beyond 48°) changes most. From 59° north, on summer nights, Maghrib moves up to 51 minutes later at Stockholm and Oslo, 54 at Reykjavik and 60 at Tromsø, and SalahCalculation gives no Isha on those nights: 40 days at Stockholm, 48 at Oslo, 88 at Reykjavik and 55 at Tromsø. With the middle-of-the-night rule Maghrib moves up to 142 minutes later; with the twilight-angle rule, between 52 minutes earlier and 26 minutes later.
  - **The middle-of-the-night rule** moves Isha on a few days a year where the Sun barely reaches the Isha angle: by up to 24 minutes at London, 29 to 32 at Stockholm, Oslo, Reykjavik and Ushuaia, and 41 at Tromsø (class D). Where adhan-swift's single correction step put Isha up to two and a half hours early, Isha moves later by up to 144 minutes (class G). Fajr moves by up to 4 minutes at 51° to 64°, 6 at Ushuaia, and −21 to +32 at Tromsø.
  - **The twilight-angle rule** moves Fajr by up to 3 minutes at 51° to 64° and −14 to +21 at Tromsø. Isha stays within a minute except at Reykjavik (up to 66 minutes later on one day) and Tromsø (−7 to +13).
  - **Umm al-Qura and Qatar** lose Isha on 13 days at Reykjavik under the middle-of-the-night rule, and on 5 to 11 days at Tromsø: their 90-minute Isha falls after the next day's Fajr.
  - **The Moonsighting Committee** moves Fajr by up to 67 minutes and Isha by up to 25 south of 55° S, and Fajr at Tromsø by −6 to +4 on 49 days a year (class F), +7 on 15 January (G) and +9 on 26 July (F with G).
  - **User adjustments** move both sides' times by the same minutes. At high latitudes they can push a time out of order, and SalahCalculation then reports it missing: with Tehran, Isha is missing on 50 days at Stockholm instead of 40.
- **Ramadan.** With Salah's delayed-Isha toggle (on by default) mapped to `.interval(minutes: 120, hijriDayOffset:)`, the two agree on every day, for Hijri offsets −1, 0, 1 and 2, at Makkah, Riyadh and Doha.
- **Every difference over a minute has an identified cause**: 39,336 kind-days over the 320 parity configurations, in seven classes (table below). Each cause is either a documented SalahTimes rule that differs from adhan-swift's, or an adhan-swift approximation that SalahTimes doesn't make. None is a defect in SalahCalculation. With adhan-swift's behaviors switched on, the attribution model reproduces Salah within a minute on all 638,873 kind-days on which both sides give a time. Nothing was left unexplained.
- Before rounding, the two libraries' instants agree within 1.2 to 8 seconds for sunrise, Dhuhr, Maghrib and Isha at the 20 default places other than Tromsø, and for Fajr below 54°. So most one-minute differences are rounding.

| Class | Kinds | Kind-days over 1 min | Where | Largest | Intended change |
|---|---|---:|---|---|---|
| [A. Asr's noon shadow](#a-asrs-noon-shadow) | Asr | 24,019 | 54.8° and beyond | −7 to +10 min | Yes: correct definition |
| [B. Asr when the noon Sun is low](#b-asr-when-the-noon-sun-is-low) | Asr | 1,407 | Tromsø, 19 January–6 February and 11–22 November | −2279 to +104 min: adhan-swift's Asr is up to 38 hours off | Yes: fixes wrong times |
| [C. Fajr's night for the high-latitude bound](#c-fajrs-night-for-the-high-latitude-bound) | Fajr | 11,565 (+57 with G) | 51.5° and beyond, rule-dependent | −137 to +12 min (with G, Tromsø: +9 to +32) | Yes: documented |
| [D. Crossings only one library finds](#d-crossings-only-one-library-finds) | Isha, Fajr, Maghrib | 98 (+4 with E) | 51.5° and beyond, middle-of-the-night rule | Isha −41 to +20, Fajr −4, Maghrib +14 min (with E, Maghrib +108 and +113) | Yes: more accurate |
| [E. Tehran's Maghrib at high latitudes](#e-tehrans-maghrib-at-high-latitudes) | Maghrib | 1,016 (+25 with G, +4 with D) | 54.8° and beyond, Tehran only | −52 to +142 min | Yes: documented |
| [F. The Moonsighting Committee's 55° rule](#f-the-moonsighting-committees-55-rule) | Fajr, Isha | 478 (+5 with G) | Puerto Toro (55.08° S), Tromsø | Fajr −6 to +67, Isha −25 to −2 min | Yes: documented |
| [G. One correction step at slow crossings](#g-one-correction-step-at-slow-crossings) | Isha, Maghrib, Fajr, sunrise | 662 (+87 with C, E or F) | 51.5° and beyond | Isha −7 to +144, Maghrib −8 to +16, Fajr −6 to +7, sunrise +7 min | Yes: more accurate |

The counts add up over configurations, so a place that appears in several configurations is counted in each. A kind-day that needs two classes together appears in parentheses in both rows ("+57 with G" under C, and among the 87 under G), and counts once in the total of 39,336. A behavior that adds less than a minute to a kind-day, or works against its difference, doesn't name its class, unless it is the only behavior involved: then it names the class even when it adds under a minute (561 kind-days, see "How differences were attributed"). The country-suggestion comparison (section 4) compares different methods on purpose, and isn't in these counts.

## What was compared

### Versions

| Component | Version |
|---|---|
| Salah | `salah-kit/Salah` at `4bc00e9`, the imported Guidance v3 rebuild |
| adhan-swift | `batoulapps/adhan-swift` at `a6fa2de` (MIT), the version Salah builds with |
| SalahKit | `salah-kit/SalahKit` at `723d9cc` (branch `b1/calculation`), with `SalahCalculation` and `SalahCore` |
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

323 configurations, each over every day of 2026 except the Ramadan runs:

1. **Salah's defaults** at the 21 places: the auto-detected method for the country and the automatic high-latitude rule, with Ramadan delayed Isha on.
2. **Every Salah method** (12, custom included, with Salah's default custom angles 18° and 17.5°) with the automatic high-latitude rule: at Makkah and London, and at Stockholm, Oslo, Reykjavik, Tromsø and Ushuaia. Beyond 48°, the automatic rule is the seventh of the night.
3. **Customized settings:**
   - Hanafi Asr: Karachi (Karachi), Istanbul (Egyptian), London (Moonsighting Committee), Oslo (Muslim World League), Cairo (Egyptian).
   - Each high-latitude rule with the Muslim World League at London, Stockholm, Oslo, Reykjavik, Tromsø and Ushuaia. The middle-of-the-night and twilight-angle rules with Umm al-Qura and Tehran at Oslo and Reykjavik.
   - Every Salah method with the middle-of-the-night and twilight-angle rules at London, Stockholm, Oslo, Reykjavik, Tromsø and Ushuaia.
   - The Moonsighting Committee at Stockholm, Oslo, Reykjavik, Ushuaia and Puerto Toro, for its 55° rule.
   - Adjustments of Fajr +2, Shuruq −1, Dhuhr +3, Asr +1, Maghrib +2 and Isha −3: Umm al-Qura at Makkah, Moonsighting Committee at London, North America at New York, Singapore at Singapore. The same adjustments at high latitudes: the Muslim World League, Tehran, Umm al-Qura, the Moonsighting Committee and Gulf, with the automatic and the middle-of-the-night rules, at Stockholm, Reykjavik, Tromsø and Ushuaia (40 configurations).
   - The custom method: 18°/17.5° (Salah's defaults) at Cairo and London, 16°/14° at London, 15°/15° at Oslo, 18°/18° at Kuala Lumpur.
   - Ramadan delayed Isha on with Hijri offsets 0, 1, −1 and 2, and off. Umm al-Qura at Makkah and Riyadh, Qatar at Doha, from 2026-02-01 to 2026-03-31. That window contains Ramadan 1447 (18 February to 19 March 2026 in the Umm al-Qura calendar) with a margin on both sides.
4. **Country suggestions:** at Istanbul, Kuala Lumpur and Jakarta, Salah's auto-detected method against the method SalahTimes' `CalculationMethod.suggested(forCountryCode:)` suggests.

A configuration identical to one already listed runs once. Of the 60 runs in item 2 beyond 54°, 9 are already there: the Muslim World League is Salah's default at all five places, and the Moonsighting Committee runs at Stockholm, Oslo, Reykjavik and Ushuaia. Of the 144 runs of every method with two rules, the 20 already in item 3 are reused. That leaves 51 and 124 new configurations. With the 40 adjustment runs at high latitudes, that's 215 on top of the first 108.

### The harness

A throwaway Swift package outside SalahKit, not committed, at `.worktrees/B1-parity-harness/` in the workspace. It depends on the local adhan-swift clone and on SalahKit's worktree by path, and on SalahTimes 0.1.0 by URL. It has four targets, so that the two libraries' same-named types never meet in one file:

- `Common`: the places, Salah's `MethodPreference` with `detect(forCountry:)` copied verbatim, the preferences with Salah's defaults, and an independent solar model used only to attribute differences (below).
- `SalahSide` (imports `Adhan`): the reproduction of Salah's calculation described above.
- `KitSide` (imports `SalahCalculation`, `SalahCore`, `SalahTimes`): the mapping above. It calls `CalculationSource(settings).prayerDay(_:at:)` with a `PrayerLocation` carrying the place's coordinates, time zone and country code, and records each missing kind's `ScheduleGapReason` with SalahTimes' own `NonOccurrence` behind it. For a time the adapter leaves out, it records which documented rule applied, and for a time after an event of a later day, whether that day was the next one. It also computes the same day with SalahTimes directly with rounding off, for comparisons before rounding.
- `parity` (executable): the configurations, the comparison and the attribution. It writes a summary table, every kind-day over a minute as CSV with its cause and any minor contribution, the counts and ranges by class, the one-minute counts, every kind-day with a time on one side only, the summary of every method under the two rules, the adjustment runs against the same settings without adjustments, every change a user sees per place, method, rule and kind, with Salah's own out-of-order days (`d1-changes.tsv`; a separate script, not the harness, checks hand-written claims about the last section against it, method by method), the configurations reused, and each configuration's settings. It exits with an error if any kind-day is unexplained or classed against the attribution rule below.

```sh
cd .worktrees/B1-parity-harness
swift build -j 4
.build/debug/parity <output-dir>              # all 323 configurations, about 100 seconds
.build/debug/parity dump Tromso 2026-01-14 2026-01-20 [method] [rule]   # both sides' times, day by day
.build/debug/parity deltas London             # largest difference before rounding, per kind
.build/debug/parity probe London 2026-07-15 17 after   # adhan-swift's existence test for a crossing
```

Two runs wrote byte-identical output, in about 100 seconds each.

### How differences were attributed

For each kind-day, the harness compares Salah's time with SalahCalculation's. Both are on whole minutes. For every difference of a minute or more, it looks for the cause with a model:

- The model takes SalahTimes' raw astronomy for the day and its neighbors: Fajr, Isha and an angle-based Maghrib computed with no high-latitude bound and no rounding, plus sunrise, sunset, transit and Asr. It then builds each kind with SalahTimes' rules. With no adhan-swift behavior switched on, it reproduces SalahCalculation exactly (0 seconds) on every kind-day where SalahCalculation gives a time. That also confirms that SalahCalculation passes the parameters to SalahTimes unchanged.
- It can switch on the behaviors in which adhan-swift differs, each read from adhan-swift's source:
  1. Dhuhr +1 minute for the Muslim World League, Egyptian, Karachi and North America (`Sources/Models/CalculationMethod.swift:137, 141, 145, 159`).
  2. Fajr bounded with the night after the day instead of its own night (`Sources/PrayerTimes.swift:87, 99–112`).
  3. The Moonsighting Committee's latitude-55 rule as adhan-swift has it (`PrayerTimes.swift:93–97, 122–126`).
  4. Tehran's 4.5° Maghrib only when it falls between sunset and Isha, unbounded (`PrayerTimes.swift:144–151`).
  5. Asr's noon shadow from the declination at 0 h UTC (`Sources/Astronomy/SolarTime.swift:40–50, 88–95`).
  6. Every altitude crossing found with a single correction step (`Sources/Astronomy/Astronomical.swift:175–193`).
  7. Whether a crossing exists at all, decided from the declination at 0 h UTC. adhan-swift computes the crossing's hour angle as the arc cosine of a value built from the Sun's declination at 0 h UTC of the date (`Astronomical.swift:180–183`; `SolarTime.swift:43, 48, 64–69, 80–84` pass that declination). When the value is beyond ±1, the hour is not finite and `DateUtilities.swift:56` returns no time. Without a time, Fajr and Isha fall back to the high-latitude bound (`PrayerTimes.swift:110–112, 139–141`), and Tehran's Maghrib keeps sunset (`:79, :145–151`).

  Behaviors 5, 6 and 7 are applied with the harness's own solar model, written from NOAA's "General Solar Position Calculations" and Meeus (*Astronomical Algorithms*, p. 102), independent of both libraries. For 6, it runs adhan-swift's one-step procedure and a converged search with that model, and moves SalahTimes' crossing by the difference. For 7, it evaluates the same existence test with that model. Where the test fails, the crossing is dropped and the kind falls back as in adhan-swift. Where the test passes and SalahTimes finds no crossing, the model takes adhan-swift's one-step time. With 5 and 6 together, Asr is adhan-swift's whole procedure: the shadow altitude from the declination at 0 h UTC, found with one step.
- The harness first finds the smallest set of behaviors that brings the model within 45 seconds of Salah's unrounded instant: single behaviors first, then pairs, then larger sets. Salah's unrounded instants come from adhan-swift with `rounding = .none`, with Dhuhr's extra minute removed when comparing instants. A one-minute difference whose instants differ by under 60 seconds is rounding.
- Within that set, the harness takes e, the difference the model explains: the model with the whole set minus SalahCalculation's unrounded instant. A behavior's contribution x is the model with the whole set minus the model without that behavior. The behavior names the class only if x has the same sign as e and is at least a minute. A behavior that adds less, or works against the difference, is recorded as a minor contribution, and the class sections give its size along the difference (negative when it works against it). A behavior without which the kind has no time at all decides it, and counts in e's direction. If no behavior qualifies, the one with the largest contribution in e's direction names the class. Where two or more behaviors are involved, at least one always qualified. Where a single behavior explains the difference, its contribution is the whole difference the model explains, and on 561 kind-days over a minute that is under a minute, so the fallback names the class: 560 class A Asr (Ushuaia 279, Tromsø 103, Oslo 76, Stockholm 50, Reykjavik 47, Puerto Toro 5) and one class G Isha at Oslo, with contributions of 48.1 to 59.9 seconds. It does the same on 6,527 one-minute kind-days. The harness prints these counts with its other checks. So a difference is classed by the mechanisms that make it, not by which set first crosses 45 seconds.
- The harness checks the rule on every classed kind-day and fails the run if a behavior that names a class works against the difference. That count is 0.
- Each behavior but the first is a class: 5 is A, 2 is C, 7 is D, 4 is E, 3 is F and 6 is G. Behavior 1 only ever makes a one-minute difference. Class B is Asr on a day when the Sun rises less than 6° at noon, where behavior 6, the single correction step, names the class: it moves Asr by a minute or more, in the direction of the difference.

With every applicable behavior switched on, the model lands within a minute of Salah on all 638,873 kind-days on which both sides give a time (of 673,260 kind-days in the parity configurations). No kind-day needed a cause outside the seven behaviors.

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

At latitudes below 52°, every kind agrees within a minute on every day. Before rounding, Fajr, sunrise, Dhuhr, Maghrib and Isha agree within 1.2 to 8 seconds at every place but Tromsø, except Fajr at 54.8° and beyond (class C, up to 59 seconds). adhan-swift truncates each instant to the whole second before rounding (`Sources/Extensions/DateUtilities.swift:55–70`). The column's larger values are Asr (class A): 14 to 34 seconds at low latitudes, about a minute at London, New York and Toronto, and more beyond 54°. Riyadh, Makkah and Doha show 30 days with a 120-minute Isha, identical on both sides.

### 2. Every method with the automatic high-latitude rule

**At Makkah and London**

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

**Beyond 54°, with the automatic high-latitude rule (the seventh of the night)**

| Method | Place | Days | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Kind-days > 1 min | Kind-days = 1 min | Salah: days without times | SalahCalculation: missing kind-days | Days with 120-min Isha | Largest \|Δ\| before rounding (s) | Classes, kind-days > 1 min |
|---|---|---:|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|---|
| egyptian | Stockholm | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | 0 to 1 | 66 | 801 | 0 | 0 | 0 | 107 | A 66 |
| karachi | Stockholm | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | 0 to 1 | 66 | 801 | 0 | 0 | 0 | 107 | A 66 |
| northAmerica | Stockholm | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 66 | 726 | 0 | 0 | 0 | 107 | A 66 |
| muslimWorldLeague (defaults) | Stockholm | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 66 | 804 | 0 | 0 | 0 | 107 | A 66 |
| ummAlQura | Stockholm | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 66 | 437 | 0 | 0 | 30 | 107 | A 66 |
| gulf | Stockholm | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 66 | 436 | 0 | 0 | 0 | 107 | A 66 |
| moonsightingCommittee (section 3) | Stockholm | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 66 | 318 | 0 | 0 | 0 | 107 | A 66 |
| custom | Stockholm | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 66 | 436 | 0 | 0 | 0 | 107 | A 66 |
| kuwait | Stockholm | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 66 | 436 | 0 | 0 | 0 | 107 | A 66 |
| qatar | Stockholm | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 66 | 437 | 0 | 0 | 30 | 107 | A 66 |
| singapore | Stockholm | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | 0 to 1 | 61 | 458 | 0 | 0 | 0 | 108 | A 61 |
| tehran | Stockholm | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 51 | −1 to 1 | 106 | 440 | 0 | 40 | 0 | 107 | A 66, E 40 |
| egyptian | Oslo | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 760 | 0 | 0 | 0 | 117 | A 95 |
| karachi | Oslo | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 760 | 0 | 0 | 0 | 117 | A 95 |
| northAmerica | Oslo | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 95 | 688 | 0 | 0 | 0 | 117 | A 95 |
| muslimWorldLeague (defaults) | Oslo | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 761 | 0 | 0 | 0 | 117 | A 95 |
| ummAlQura | Oslo | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 399 | 0 | 0 | 30 | 117 | A 95 |
| gulf | Oslo | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 397 | 0 | 0 | 0 | 117 | A 95 |
| moonsightingCommittee (section 3) | Oslo | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 287 | 0 | 0 | 0 | 117 | A 95 |
| custom | Oslo | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 397 | 0 | 0 | 0 | 117 | A 95 |
| kuwait | Oslo | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 397 | 0 | 0 | 0 | 117 | A 95 |
| qatar | Oslo | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 399 | 0 | 0 | 30 | 117 | A 95 |
| singapore | Oslo | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | 0 to 1 | 86 | 446 | 0 | 0 | 0 | 113 | A 86 |
| tehran | Oslo | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 51 | −1 to 1 | 143 | 406 | 0 | 48 | 0 | 117 | A 95, E 48 |
| egyptian | Reykjavik | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −6 to 5 | −1 to 1 | 0 to 1 | 176 | 797 | 0 | 0 | 0 | 114 | A 176 |
| karachi | Reykjavik | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −6 to 5 | −1 to 1 | 0 to 1 | 176 | 797 | 0 | 0 | 0 | 114 | A 176 |
| northAmerica | Reykjavik | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −6 to 5 | −1 to 1 | 0 to 1 | 176 | 771 | 0 | 0 | 0 | 114 | A 176 |
| muslimWorldLeague (defaults) | Reykjavik | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −6 to 5 | −1 to 1 | 0 to 1 | 176 | 797 | 0 | 0 | 0 | 114 | A 176 |
| ummAlQura | Reykjavik | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −6 to 5 | −1 to 1 | −1 to 1 | 176 | 435 | 0 | 0 | 30 | 114 | A 176 |
| gulf | Reykjavik | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −6 to 5 | −1 to 1 | 0 to 1 | 176 | 436 | 0 | 0 | 0 | 114 | A 176 |
| moonsightingCommittee (section 3) | Reykjavik | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −6 to 5 | −1 to 1 | 0 to 1 | 176 | 297 | 0 | 0 | 0 | 114 | A 176 |
| custom | Reykjavik | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −6 to 5 | −1 to 1 | 0 to 1 | 176 | 436 | 0 | 0 | 0 | 114 | A 176 |
| kuwait | Reykjavik | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −6 to 5 | −1 to 1 | 0 to 1 | 176 | 436 | 0 | 0 | 0 | 114 | A 176 |
| qatar | Reykjavik | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −6 to 5 | −1 to 1 | −1 to 1 | 176 | 435 | 0 | 0 | 30 | 114 | A 176 |
| singapore | Reykjavik | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −6 to 5 | 0 to 1 | 0 to 1 | 179 | 464 | 0 | 0 | 0 | 116 | A 179 |
| tehran | Reykjavik | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −6 to 5 | 0 to 54 | −1 to 1 | 263 | 435 | 0 | 88 | 0 | 114 | A 176, E 87 |
| egyptian | Tromsø | 365 | −131 to 9 | 0 to 7 | −1 to 0 | −2279 to 104 | −7 to 15 | −6 to 13 | 259 | 511 | 118 | 425 | 0 | 108 | A 114, B 31, C 102, C+G 1, G 11 |
| karachi | Tromsø | 365 | −113 to 9 | 0 to 7 | −1 to 0 | −2279 to 104 | −7 to 15 | −6 to 13 | 259 | 511 | 118 | 425 | 0 | 108 | A 114, B 31, C 102, C+G 1, G 11 |
| northAmerica | Tromsø | 365 | −77 to 9 | 0 to 7 | −1 to 0 | −2279 to 104 | −7 to 15 | −6 to 13 | 259 | 511 | 118 | 425 | 0 | 108 | A 114, B 31, C 102, C+G 1, G 11 |
| muslimWorldLeague (defaults) | Tromsø | 365 | −113 to 9 | 0 to 7 | −1 to 0 | −2279 to 104 | −7 to 15 | −6 to 13 | 259 | 511 | 118 | 425 | 0 | 108 | A 114, B 31, C 102, C+G 1, G 11 |
| ummAlQura | Tromsø | 365 | −119 to 9 | 0 to 7 | 0 to 1 | −2279 to 104 | −7 to 15 | −7 to 1 | 255 | 268 | 118 | 479 | 30 | 108 | A 114, B 31, C 102, C+G 1, G 7 |
| gulf | Tromsø | 365 | −115 to 9 | 0 to 7 | 0 to 1 | −2279 to 104 | −7 to 15 | −6 to 13 | 258 | 266 | 118 | 428 | 0 | 108 | A 114, B 31, C 102, C+G 1, G 10 |
| moonsightingCommittee | Tromsø | 365 | −6 to 9 | 0 to 7 | 0 to 1 | −73 to 30 | −7 to 15 | −7 to 13 | 201 | 195 | 118 | 432 | 0 | 108 | A 114, B 26, F 49, F+G 1, G 11 |
| custom | Tromsø | 365 | −113 to 9 | 0 to 7 | 0 to 1 | −2279 to 104 | −7 to 15 | −6 to 13 | 259 | 266 | 118 | 425 | 0 | 108 | A 114, B 31, C 102, C+G 1, G 11 |
| kuwait | Tromsø | 365 | −113 to 9 | 0 to 7 | 0 to 1 | −2279 to 104 | −7 to 15 | −6 to 13 | 259 | 266 | 118 | 425 | 0 | 108 | A 114, B 31, C 102, C+G 1, G 11 |
| qatar | Tromsø | 365 | −113 to 9 | 0 to 7 | 0 to 1 | −2279 to 104 | −7 to 15 | −7 to 1 | 255 | 268 | 118 | 479 | 30 | 108 | A 114, B 31, C 102, C+G 1, G 7 |
| singapore | Tromsø | 365 | −137 to 9 | 0 to 7 | 0 to 1 | −2278 to 57 | −8 to 16 | −6 to 14 | 273 | 265 | 118 | 426 | 0 | 116 | A 111, B 30, C 121, C+G 1, G 10 |
| tehran | Tromsø | 365 | −110 to 9 | 0 to 7 | 0 to 1 | −2279 to 104 | 0 to 60 | −6 to 1 | 305 | 242 | 118 | 433 | 0 | 108 | A 114, B 31, C 102, C+G 1, E 50, E+G 5, G 2 |
| egyptian | Ushuaia | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 77 | 773 | 0 | 0 | 0 | 100 | A 77 |
| karachi | Ushuaia | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 77 | 733 | 0 | 0 | 0 | 100 | A 77 |
| northAmerica | Ushuaia | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 77 | 698 | 0 | 0 | 0 | 100 | A 77 |
| muslimWorldLeague (defaults) | Ushuaia | 365 | −1 to 1 | 0 to 1 | −1 to 0 | −2 to 2 | 0 to 1 | −1 to 1 | 77 | 732 | 0 | 0 | 0 | 100 | A 77 |
| ummAlQura | Ushuaia | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 77 | 370 | 0 | 0 | 30 | 100 | A 77 |
| gulf | Ushuaia | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | −1 to 1 | 77 | 373 | 0 | 0 | 0 | 100 | A 77 |
| moonsightingCommittee (section 3) | Ushuaia | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 77 | 229 | 0 | 0 | 0 | 100 | A 77 |
| custom | Ushuaia | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | −1 to 1 | 77 | 367 | 0 | 0 | 0 | 100 | A 77 |
| kuwait | Ushuaia | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | −1 to 1 | 77 | 367 | 0 | 0 | 0 | 100 | A 77 |
| qatar | Ushuaia | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 77 | 361 | 0 | 0 | 30 | 100 | A 77 |
| singapore | Ushuaia | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | −1 to 1 | 84 | 425 | 0 | 0 | 0 | 100 | A 84 |
| tehran | Ushuaia | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | −1 to 1 | 77 | 364 | 0 | 0 | 0 | 100 | A 77 |

The Muslim World League rows are Salah's defaults (section 1), and the Moonsighting Committee rows at Stockholm, Oslo, Reykjavik and Ushuaia are the committee's runs in section 3. They're listed again here, not run twice.

- **Stockholm, Oslo and Ushuaia:** every method but Tehran differs only in Asr (class A). Singapore's counts differ a little because both libraries round its times up.
- **Reykjavik:** Asr (class A) for every method, and Tehran's Maghrib and Isha (below).
- **Tromsø:** every method shows classes A, B and G, and class C, or class F for the Moonsighting Committee. With Umm al-Qura and Qatar, SalahCalculation gives no Isha on 5 days where Salah has one (15–17 May, 26–27 July): the 90-minute Isha falls after the next day's Fajr. With Gulf and the Moonsighting Committee it gives no Isha on 17 May, and with the Committee and Singapore no Asr on a few days in January and November (see "Times one side doesn't give").
- **Tehran, at Stockholm, Oslo, Reykjavik and Tromsø:** on summer nights Maghrib is up to 51 to 60 minutes later, and SalahCalculation gives no Isha on 40, 48, 88 and 55 days (class E). At Ushuaia the 4.5° time always comes before the bound, and nothing differs beyond class A.

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

**Every method with the middle-of-the-night and twilight-angle rules**

These 144 runs (the 12 methods, two rules, six places) are summarized here; the harness writes every row. The first table gives, for each place and rule, the range of differences over all 12 methods. Dhuhr agrees within a minute everywhere.

| Place | Rule | Fajr | Sunrise | Asr | Maghrib | Isha | Kind-days > 1 min | By class |
|---|---|---|---|---|---|---|---:|---|
| London | middle of the night | −2 to 2 | 0 to 1 | −1 to 1 | 0 to 1 | −24 to 7 | 68 | C 39, D 10, G 19 |
| London | twilight angle | −1 to 2 | 0 to 1 | −1 to 1 | 0 to 1 | −1 to 1 | 3 | C 3 |
| Stockholm | middle of the night | −4 to 3 | 0 to 1 | −2 to 2 | 0 to 1 | −31 to 58 | 1,713 | A 787, C 880, D 10, G 36 |
| Stockholm | twilight angle | −2 to 2 | 0 to 1 | −2 to 2 | −34 to 1 | −1 to 1 | 1,324 | A 787, C 441, E 96 |
| Oslo | middle of the night | −3 to 3 | 0 to 1 | −2 to 2 | 0 to 1 | −29 to 26 | 2,104 | A 1,131, C 932, D 13, G 28 |
| Oslo | twilight angle | −2 to 2 | 0 to 1 | −2 to 2 | −39 to 1 | −1 to 1 | 1,735 | A 1,131, C 503, E 101 |
| Reykjavik | middle of the night | −4 to 4 | 0 to 1 | −6 to 5 | −1 to 130 | −32 to 144 | 3,630 | A 2,115, C 1,409, D 12, D+E 1, E 49, G 44 |
| Reykjavik | twilight angle | −3 to 3 | 0 to 1 | −6 to 5 | −47 to 24 | −1 to 66 | 3,592 | A 2,115, C 1,347, E 127, G 3 |
| Tromsø | middle of the night | −21 to 32 | 0 to 7 | −2279 to 104 | −8 to 142 | −41 to 65 | 3,122 | A 1,365, B 366, C 1,140, C+G 22, D 19, D+E 1, E 23, E+G 5, F 49, F+G 1, G 131 |
| Tromsø | twilight angle | −14 to 21 | 0 to 7 | −2279 to 104 | −52 to 26 | −7 to 13 | 3,385 | A 1,365, B 366, C 1,391, C+G 11, E 92, E+G 5, F 49, F+G 1, G 105 |
| Ushuaia | middle of the night | −6 to 3 | 0 to 1 | −2 to 2 | 0 to 1 | −32 to 26 | 1,336 | A 931, C 346, D 14, G 45 |
| Ushuaia | twilight angle | −2 to 2 | 0 to 1 | −2 to 2 | −9 to 1 | −1 to 1 | 1,091 | A 931, C 106, E 54 |

The second table gives, for each method and rule, the largest difference of each kind over the six places, with its place and date, and the kind-days with a time on one side only. Sunrise, Dhuhr and Asr are the same in every row: sunrise +7 at Tromsø on 15 January (class G), Dhuhr within a minute, and Asr down to −2279 at Tromsø on 19 January (class B; −2278 with Singapore, and −73 on 21 January with the Moonsighting Committee). The last column leaves out the Tromsø days on which adhan-swift returns no times at all (see "Times one side doesn't give").

| Method | Rule | Largest Fajr | Largest Maghrib | Largest Isha | Kind-days > 1 min | By class | One side only (kind-days) |
|---|---|---|---|---|---:|---|---|
| egyptian | middle of the night | +32 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +144 (Reykjavik, 1 Sep) | 1,074 | A 528, B 31, C 472, C+G 2, D 7, G 34 | Tromsø Asr 8 |
| egyptian | twilight angle | +21 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +66 (Reykjavik, 1 Sep) | 977 | A 528, B 31, C 406, C+G 1, G 11 | Tromsø Asr 8 |
| karachi | middle of the night | +32 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +64 (Tromsø, 17 Sep) | 1,031 | A 528, B 31, C 429, C+G 2, D 11, G 30 | Tromsø Asr 8 |
| karachi | twilight angle | +20 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +11 (Tromsø, 26 Jul) | 907 | A 528, B 31, C 339, C+G 1, G 8 | Tromsø Asr 8 |
| northAmerica | middle of the night | +32 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +42 (Reykjavik, 25 Aug) | 928 | A 528, B 31, C 333, C+G 2, D 5, G 29 | Tromsø Asr 8 |
| northAmerica | twilight angle | +16 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +12 (Tromsø, 26 Jul) | 796 | A 528, B 31, C 226, C+G 1, G 10 | Tromsø Asr 8 |
| muslimWorldLeague | middle of the night | +32 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | −35 (Tromsø, 14 Sep) | 1,030 | A 528, B 31, C 429, C+G 2, D 11, G 29 | Tromsø Asr 8 |
| muslimWorldLeague | twilight angle | +20 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +11 (Tromsø, 26 Jul) | 908 | A 528, B 31, C 339, C+G 1, G 9 | Tromsø Asr 8 |
| ummAlQura | middle of the night | +32 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | −7 (Tromsø, 15 Jan) | 1,011 | A 528, B 31, C 443, C+G 2, G 7 | Reykjavik Isha 13, Tromsø Asr 8, Tromsø Isha 11 |
| ummAlQura | twilight angle | +19 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | −7 (Tromsø, 15 Jan) | 937 | A 528, B 31, C 370, C+G 1, G 7 | Tromsø Asr 8, Tromsø Isha 7 |
| gulf | middle of the night | +32 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +43 (Reykjavik, 3 Sep) | 1,037 | A 528, B 31, C 433, C+G 2, D 8, G 35 | Tromsø Asr 8 |
| gulf | twilight angle | +20 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +11 (Tromsø, 26 Jul) | 919 | A 528, B 31, C 349, C+G 1, G 10 | Tromsø Asr 8 |
| moonsightingCommittee | middle of the night | +9 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +13 (Tromsø, 26 Jul) | 615 | A 528, B 26, F 49, F+G 1, G 11 | Tromsø Asr 13, Tromsø Isha 1 |
| moonsightingCommittee | twilight angle | +9 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +13 (Tromsø, 26 Jul) | 615 | A 528, B 26, F 49, F+G 1, G 11 | Tromsø Asr 13, Tromsø Isha 1 |
| custom | middle of the night | +32 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +144 (Reykjavik, 1 Sep) | 1,032 | A 528, B 31, C 429, C+G 2, D 8, G 34 | Tromsø Asr 8 |
| custom | twilight angle | +20 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +66 (Reykjavik, 1 Sep) | 910 | A 528, B 31, C 339, C+G 1, G 11 | Tromsø Asr 8 |
| kuwait | middle of the night | +32 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +144 (Reykjavik, 1 Sep) | 1,032 | A 528, B 31, C 429, C+G 2, D 8, G 34 | Tromsø Asr 8 |
| kuwait | twilight angle | +20 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | +66 (Reykjavik, 1 Sep) | 910 | A 528, B 31, C 339, C+G 1, G 11 | Tromsø Asr 8 |
| qatar | middle of the night | +32 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | −7 (Tromsø, 15 Jan) | 999 | A 528, B 31, C 429, C+G 2, D 1, G 8 | Reykjavik Isha 13, Tromsø Asr 8, Tromsø Isha 11 |
| qatar | twilight angle | +20 (Tromsø, 26 Jul) | +15 (Tromsø, 26 Jul) | −7 (Tromsø, 15 Jan) | 906 | A 528, B 31, C 339, C+G 1, G 7 | Tromsø Asr 8, Tromsø Isha 7 |
| singapore | middle of the night | +32 (Tromsø, 26 Jul) | +16 (Tromsø, 26 Jul) | +65 (Tromsø, 17 Sep) | 1,095 | A 521, B 30, C 500, C+G 2, D 10, G 32 | Tromsø Asr 9 |
| singapore | twilight angle | +21 (Tromsø, 26 Jul) | +16 (Tromsø, 26 Jul) | +11 (Tromsø, 26 Jul) | 978 | A 521, B 30, C 416, C+G 1, G 10 | Tromsø Asr 9 |
| tehran | middle of the night | +32 (Tromsø, 26 Jul) | +142 (Tromsø, 8 Aug) | +83 (Reykjavik, 22 Aug) | 1,089 | A 528, B 31, C 420, C+G 2, D 9, D+E 2, E 72, E+G 5, G 20 | Reykjavik Isha 50, Tromsø Asr 8, Tromsø Isha 29 |
| tehran | twilight angle | +19 (Tromsø, 26 Jul) | −52 (Tromsø, 14 Aug) | +12 (Tromsø, 26 Jul) | 1,367 | A 528, B 31, C 329, C+G 1, E 470, E+G 5, G 3 | Tromsø Asr 8 |

In every row the classes are the same ones as in the rest of the report. Class D appears only under the middle-of-the-night rule, and class E only with Tehran.

**The Moonsighting Committee at 55° and beyond**

| Configuration | Place | Days | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Kind-days > 1 min | Kind-days = 1 min | Salah: days without times | SalahCalculation: missing kind-days | Days with 120-min Isha | Largest \|Δ\| before rounding (s) |
|---|---|---:|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| moonsightingCommittee | Stockholm | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 66 | 318 | 0 | 0 | 0 | 107 |
| moonsightingCommittee | Oslo | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | 0 to 1 | 95 | 287 | 0 | 0 | 0 | 117 |
| moonsightingCommittee | Reykjavik | 365 | −1 to 1 | 0 to 1 | 0 to 1 | −6 to 5 | −1 to 1 | 0 to 1 | 176 | 297 | 0 | 0 | 0 | 114 |
| moonsightingCommittee | Ushuaia | 365 | −1 to 1 | 0 to 1 | 0 | −2 to 2 | 0 to 1 | 0 to 1 | 77 | 229 | 0 | 0 | 0 | 100 |
| moonsightingCommittee | Puerto Toro | 365 | 0 to 67 | 0 to 1 | 0 to 1 | −2 to 2 | 0 to 1 | −25 to 1 | 311 | 246 | 0 | 0 | 0 | 103 |

North of 55°, the committee's two formulations, adhan-swift's and SalahTimes', differ by at most a minute in 2026 at Stockholm, Oslo and Reykjavik. At Tromsø (section 2) Fajr differs by −6 to +4 minutes on 49 days, and south of 55° the two differ more (class F).

**Adjustments**

| Configuration | Place | Days | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha | Kind-days > 1 min | Kind-days = 1 min | Salah: days without times | SalahCalculation: missing kind-days | Days with 120-min Isha | Largest \|Δ\| before rounding (s) |
|---|---|---:|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|
| ummAlQura, adjustments +2 -1 +3 +1 +2 -3 | Makkah | 365 | 0 | 0 to 1 | 0 to 1 | −1 to 1 | 0 | 0 | 0 | 95 | 0 | 0 | 30 | 25 |
| moonsightingCommittee, adjustments +2 -1 +3 +1 +2 -3 | London | 365 | −1 to 0 | 0 | 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 238 | 0 | 0 | 0 | 62 |
| northAmerica, adjustments +2 -1 +3 +1 +2 -3 | New York | 365 | −1 to 1 | 0 | −1 to 0 | −1 to 1 | 0 to 1 | −1 to 1 | 0 | 591 | 0 | 0 | 0 | 55 |
| singapore, adjustments +2 -1 +3 +1 +2 -3 | Singapore | 365 | 0 to 1 | 0 to 1 | 0 to 1 | −1 to 1 | 0 to 1 | 0 to 1 | 0 | 80 | 0 | 0 | 0 | 14 |

User adjustments move both sides' times by the same minutes. Nothing differs by more than a minute.

**Adjustments at high latitudes.** The same adjustments with the Muslim World League, Tehran, Umm al-Qura, the Moonsighting Committee and Gulf, under the automatic and the middle-of-the-night rules, at Stockholm, Reykjavik, Tromsø and Ushuaia: 40 configurations. The harness compares each with the same settings without adjustments, kind-day by kind-day. Apart from the days in the table below, every difference over a minute and its class is the same, and the attribution model reproduces Salah within a minute on every kind-day both sides give, as without adjustments (on 389 kind-days it is a minute off, 377 later and 12 earlier). But an adjustment can push a time out of order on a short night or near polar night, and SalahCalculation then reports it missing under the adapter's documented rule. Every change against the unadjusted runs:

| Settings | Place | Change against the same settings without adjustments |
|---|---|---|
| Tehran, automatic rule | Stockholm | Isha missing on 10 more days, 27–31 May and 11–15 July (50 in all). Salah's own times are out of order on the same 10 days, against none without adjustments |
| Tehran, automatic rule | Reykjavik | Isha missing on 4 more days, 6–7 May and 4–5 August (92 in all). Salah's own times are out of order on 5 days (6–7 May, 3–5 August) instead of 1 |
| Tehran, middle of the night | Reykjavik | Salah's own times are out of order on 27 May |
| Tehran, automatic rule | Tromsø | Isha missing on 4 more days, 18–19 April and 22–23 August (59 in all). Salah's own times are out of order on 18 days instead of 12: those 4, 17 May and 15 November |
| Umm al-Qura, middle of the night | Reykjavik | Isha given on 14–26 June, which it isn't without adjustments: with Isha −3 and Fajr +2, the 90-minute Isha no longer falls after the next Fajr |
| Umm al-Qura, automatic rule | Tromsø | Isha given on 15 May and 27 July, for the same reason. On 27 July it differs by +2 (class G); on 15 May it agrees within a minute |
| Muslim World League, Tehran, Umm al-Qura and Gulf, both rules | Tromsø | Asr missing on 19 January and 22 November: an Asr minutes after the transit, plus 1 minute, isn't after Dhuhr plus 3 |
| Moonsighting Committee, both rules | Tromsø | Asr missing on 21–22 January and 19 November, besides its 5 days without adjustments |
| Muslim World League, automatic rule | Tromsø | Isha missing on 17 May, where it differs by +7 (class G) without adjustments: with Maghrib +2 and Isha −3 it isn't after Maghrib |
| Gulf, automatic rule | Tromsø | Sunrise missing on 26 July: with sunrise −1 on top of Gulf's −3 it isn't after Fajr |
| Muslim World League, Tehran and Umm al-Qura, automatic rule; Moonsighting Committee, both rules | Tromsø | No sunrise on 18 May, a day on which Salah gives no times: with sunrise −1 and Fajr +2 it isn't after Fajr. Without adjustments SalahCalculation gives it |
| Muslim World League, automatic rule | Tromsø | No Isha on 25 July, a day on which Salah gives no times: with Maghrib +2 and Isha −3 it isn't after Maghrib. Without adjustments SalahCalculation gives it |

Because Asr or Isha goes missing on those days, the Tromsø runs have 1 to 3 fewer kind-days over a minute than without adjustments; the one exception the other way is Umm al-Qura's 27 July. Salah's own times there are out of order on up to 2 more days (17 May, 15 November), and with Tehran under the automatic rule on 6 more.

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

117,402 kind-days differ by exactly one minute, over all parity configurations:

| Kind | Cause | Kind-days |
|---|---|---:|
| Dhuhr | adhan-swift's extra Dhuhr minute (Muslim World League, Egyptian, Karachi, North America) | 35,012 |
| Dhuhr | Rounding of a sub-minute difference | 271 |
| Asr | Rounding of a sub-minute difference | 31,293 |
| Asr | Asr's noon shadow (class A), a 60 to 120 second difference | 18,862 |
| Fajr | Rounding of a sub-minute difference | 19,458 |
| Fajr | Fajr's night (class C) | 5,209 |
| Fajr, Isha | The Moonsighting Committee's 55° rule (class F) | 333 |
| Fajr, Isha, Maghrib | One correction step at slow crossings (class G) | 165 |
| Isha | Crossings only one library finds (class D) | 4 |
| Isha | Rounding of a sub-minute difference | 4,388 |
| Maghrib | Rounding of a sub-minute difference | 1,711 |
| Maghrib | Tehran's Maghrib (class E) | 2 |
| Sunrise | Rounding of a sub-minute difference | 694 |

The Dhuhr minute is systematic, not rounding: SalahCalculation's Dhuhr is a minute earlier on nearly every day for those four methods. The rounding cases are instants a few seconds apart, often only adhan-swift's truncation to the whole second (up to one second), on either side of a half minute. The rounded minutes then differ by one. Asr has the most of them because its instants differ by up to half a minute even at low latitudes (class A). Fajr's rounding cases are mostly at 54.8° and beyond, where class C is under a minute.

## Every class of difference over a minute

### A. Asr's noon shadow

**What users see.** Asr moves by up to 2 minutes at Oslo, Stockholm, Ushuaia and Puerto Toro, and by up to 6 at Reykjavik and 10 at Tromsø. It moves earlier in the half of the year when days lengthen and later when they shorten. With defaults: Oslo 95, Stockholm 66, Reykjavik 176, Tromsø 114 and Ushuaia 77 days a year over a minute. Tromsø's largest values come just outside class B's days: −6 and −7 on 7–11 February, and +6 to +10 on 2–10 November. The method and the high-latitude rule hardly change these counts. At lower latitudes the same effect stays under a minute: up to 25 seconds at Makkah and about a minute at London.

**Cause.** Asr begins when an object's shadow equals its length plus its noon shadow. The noon shadow depends on the Sun's declination at noon. SalahTimes takes the declination at the transit (`docs/algorithm.md` §7, "Asr"). adhan-swift takes it from the solar coordinates at 0 h UTC of the date (`SolarTime.swift:40–50` sets the hour to 0; `:88–95` uses `solar.declination`). Near the equinoxes the declination changes by about 0.4° a day. By the transit, about 10½ to 16½ hours after 0 h UTC at these places, the two values differ by up to about 0.3°. At high latitudes the Sun descends slowly in the afternoon, so that changes Asr by minutes.

**Evidence.** Switching on behavior 5 alone, computed with the independent solar model, brings the model within 45 seconds of Salah on 23,314 of the 24,019 kind-days. On the other 705, all when the noon Sun is low, the single correction step (behavior 6) is needed to land within 45 seconds but is minor. At Tromsø on 7–8 February it adds 48 to 55 seconds to the difference. At Reykjavik on 3–6 December it works against the difference by 46 to 47 seconds, and at Tromsø on 2–10 November by 51 to 401 seconds: there behavior 5 alone overshoots, and the step brings the model back. Behavior 5 makes the 4 to 10 minutes on all of these days, so they are class A. SalahTimes' self-consistency check confirms its Asr against an independent model within 0.0128° of altitude (`docs/validation.md`, "Self-consistency").

**Intended.** Yes. SalahTimes computes the shadow the way the definition states.

### B. Asr when the noon Sun is low

**What users see.** In Tromsø, from 15 January to 6 February and from 11 to 26 November, Salah's Asr is wrong:
- **Out of order** on 18 days with Salah's defaults. On 15 to 20 January Salah's Asr falls after Maghrib; on 19 January it is the morning of 21 January, 38 hours late. On 15 November it equals Dhuhr (both 11:30), and from 16 to 26 November it falls before Dhuhr.
- **In order but far off** on the days around them. On 21 January Salah shows Asr at 13:14, before its Maghrib at 13:23; SalahCalculation gives 12:01 (−73). Then −48 on 22 January, −35 on 23 January, and −27 to −8 through 6 February. From 11 to 14 November Salah's Asr comes after Dhuhr and SalahCalculation's is 10 to 14 minutes later.

SalahCalculation puts Asr minutes after Dhuhr, or reports it missing (below). With Salah's defaults, 31 kind-days are in this class (19 January–6 February, 11–22 November); over the 47 Tromsø configurations, 1,407. On the days just outside it Asr still moves, as class A: −6 and −7 on 7–11 February, and +6 to +10 on 2–10 November, where Salah's times are in order.

**Cause.** When the noon Sun is only a few degrees up, the Asr altitude, `atan(1 / (k + tan z))`, is barely below the noon altitude, so Asr comes soon after the transit, where the Sun's altitude hardly changes. adhan-swift takes that altitude from the declination at 0 h UTC (behavior 5; with the noon zenith distance at 0 h UTC beyond 90°, it computes an Asr altitude below the horizon, `SolarTime.swift:88–95`). It then finds the crossing with one correction step from an estimate made at 0 h UTC (behavior 6, `Astronomical.swift:175–193`), and one step can't land on a crossing that close to the transit. SalahTimes reports Asr as not occurring when the Sun is below the horizon at the transit. Otherwise it finds the crossing by iteration, with bisection as a fallback (`docs/algorithm.md` §6 and §7). `docs/validation.md` ("Known limitations", "Dhuhr and Asr before polar night") describes the expected behavior: Asr seconds to minutes after the transit.

**Evidence.** With behaviors 5 and 6 together, adhan-swift's whole Asr procedure, the model reproduces Salah within 45 seconds on all 1,407 kind-days, 19 January's 38-hour error included. On each of them the noon altitude is below 6° (the harness's geometry check), and the single step contributes a minute or more in the direction of the difference: the model with behaviors 5 and 6 differs from the model with 5 alone by at least that, the same way. On 30–31 January the step alone accounts for it, and behavior 5 works against the difference (94 kind-days). The rule sets the class's edges: on 7–8 February the step adds under a minute, and on 2–10 November it works against the difference, so those days are class A.

**Intended.** Yes. It corrects times up to 73 minutes off, and replaces impossible ones: with an Asr minutes after the transit, or with none where the Sun stays below the horizon at noon (8 of the 18 out-of-order days with the defaults).

### C. Fajr's night for the high-latitude bound

**What users see.** Under the middle-of-the-night rule, Fajr differs by up to 2 minutes at London, 3 at Oslo, Stockholm and Ushuaia, 4 at Reykjavik and −21 to +12 at Tromsø. Under the twilight-angle rule: up to 2 minutes at London, Oslo, Stockholm and Ushuaia, 3 at Reykjavik and −14 to +10 at Tromsø. Under the seventh-of-the-night rule (Salah's automatic choice beyond 48°) it stays within a minute everywhere except Tromsø, which has 100 to 119 days a year of −4 to +5 minutes, depending on the method, and 15 January and 17 May (below). Fajr is earlier in spring and later in autumn. With defaults, only Tromsø is affected. These figures hold for every method but the Moonsighting Committee, whose Fajr follows its own rule (class F).

**Cause.** A high-latitude rule keeps Fajr no earlier than sunrise minus a portion of the night. adhan-swift measures that night from the day's sunset to the next sunrise (`PrayerTimes.swift:87` and `:104–107`), a night that comes after the Fajr it bounds. SalahTimes uses the night that ends at Fajr's own sunrise (`docs/algorithm.md` §8 and §8.1, and RFC 0001 §6, "Each prayer uses its own night"). The two nights differ by the night's day-to-day change, several minutes a day at these latitudes around the equinoxes. The bounds then differ by that change times the portion (1/2, 1/7, or the angle over 60). Isha's bound uses the night after its sunset in both, so Isha agrees.

The largest case is Tromsø on 15 January, the first sunrise after polar night: Salah 08:07, SalahCalculation 06:14 with the defaults (−113 minutes; −77 to −137 depending on the method's Fajr angle). 14 January has no sunset, so Fajr's own night doesn't exist. SalahTimes then leaves the angle's time unbounded (`docs/algorithm.md` §8.1, "if nightBefore is undefined: return raw", and §9). adhan-swift bounds it with the following night, from a sunrise that is itself 7 minutes off (class G). That sunrise works against the difference, by 345 seconds, so the day is class C. At the edges of the midnight sun, Fajr moves by −6 on 17 May with the defaults (−21 under the middle-of-the-night rule), class C, and by +9 to +32 on 26–27 July, where the single step adds more than a minute (class C with G).

**Evidence.** Behavior 2 explains 11,565 kind-days: alone on 11,490, and on 75 at Tromsø with the single step minor. The step works against the difference on 15 January and 16–17 May (by 56 to 345 seconds), and adds 45 to 46 seconds on 27 July. With class G, 57 more at Tromsø (26–27 July), where the single step adds more than a minute in the direction of the difference.

**Intended.** Yes. Using one night for both prayers can put a bounded Fajr before the previous evening's bounded Isha when nights lengthen quickly (adhan-swift issue #102, cited in SalahTimes RFC 0001 §6).

### D. Crossings only one library finds

**What users see.** Only under the middle-of-the-night rule, on one or two days a year for most methods, at the start and end of the season in which the Sun no longer gets as low as the Isha angle. On these days its lowest point is within about a third of a degree of that angle. The two libraries then disagree on whether the Sun reaches it at all:
- **adhan-swift misses a crossing that happens** (62 kind-days). Salah shows Isha at the middle of the night; SalahCalculation shows the real crossing, earlier: by 18 to 24 minutes at London (15–22 July), 13 to 31 at Stockholm (6–20 August), 12 to 29 at Oslo (8–21 August), 11 to 32 at Reykjavik (21 August–2 September), 24 to 41 at Tromsø (6–17 September) and 11 to 32 at Ushuaia (14 January–1 February). For example, London on 15 July with the Muslim World League: Salah 01:07, SalahCalculation 00:49 (−18).
- **adhan-swift finds a crossing that doesn't happen** (36 kind-days). Salah shows Isha minutes before the middle of the night; SalahCalculation shows the middle of the night: 3 to 20 minutes later, from 26 March to 22 May and at Ushuaia on 9 and 13 November. For example, Oslo on 24 April with the Muslim World League: Salah 01:01, SalahCalculation 01:15 (+14). The same happens to Tehran's 4.5° Maghrib at Tromsø on 3 May (+14, two configurations). Fajr at Tromsø on 17 September, in six configurations, is a borderline case: adhan-swift finds a crossing at 00:44 (22:44 UTC on 16 September) and Salah shows it; SalahCalculation shows the bound, 00:40 (−4). There the Sun's lowest point is within about 0.002° of 18° below the horizon (below).
- **With Tehran's Maghrib** (4 kind-days, one in each of four configurations: Tehran under the middle-of-the-night rule at Reykjavik and at Tromsø, each with and without adjustments; with class E): at Reykjavik on 16 July and Tromsø on 9 August, adhan-swift's test says the Sun doesn't reach 4.5° below the horizon, so Salah keeps Maghrib at sunset (23:21 and 22:22). SalahCalculation's Maghrib is the real 4.5° crossing, 01:09 and 00:15, which comes before the bound: +108 and +113 minutes.

Under the seventh-of-the-night and twilight-angle rules the bound comes long before such a late crossing and decides Isha on both sides, so this class doesn't appear. Salah's defaults don't show it.

**Cause.** adhan-swift decides whether the Sun reaches an altitude h₀ from the cosine of the crossing's hour angle, (sin h₀ − sin φ sin δ) / (cos φ cos δ), with δ the declination at 0 h UTC of the date: the crossing exists when that value is within ±1 (`Astronomical.swift:180–183`). Otherwise the hour isn't finite, no time is returned (`DateUtilities.swift:56`), and Fajr and Isha fall back to the bound and Tehran's Maghrib to sunset (`PrayerTimes.swift:110–112, 139–141, 145–151`). An Isha or Maghrib near the middle of the night comes 22 to 29 hours after 0 h UTC at these places, and on these days the declination moved by 0.16° to 0.39° in that time. Where the Sun's lowest point is that close to the angle, the answer flips. Tromsø's Fajr on 17 September is the exception: adhan-swift's crossing is 1.27 hours before 0 h UTC and the antitransit 1.35 hours before it, so the declination moves by only 0.02°. The test gives −0.9990 at 0 h UTC and −1.0001 at the antitransit. The second value lies inside the band of ±1e-4 around −1 in which, by `docs/algorithm.md` §6, implementations "can decide either way": whether the Sun reaches 18° that night is a 0.002° call. SalahCalculation's Fajr stands either way: a crossing that night would be at the antitransit, before the bound, so Fajr would still be the bound. SalahTimes decides with the declination at the antitransit, the instant the Sun is lowest (`docs/algorithm.md` §6, step 1).

**Evidence.** Switching on behavior 7 alone brings the model within 45 seconds of Salah on all 98 kind-days, and together with behavior 4 on the 4 Tehran Maghribs. On each of these days adhan-swift's test, as the model computes it, disagrees with SalahTimes on whether the crossing exists. Examples, with the test from the declination at 0 h UTC and from the declination at the antitransit: London, 15 July, Isha at 17°: −1.0017 with the declination at 0 h UTC (21.55°), −0.9971 with the declination at the antitransit (21.39°, 00:06 UTC on 16 July). Oslo, 24 April: −0.9902 against −1.0010. Reykjavik, 16 July, Maghrib at 4.5°: −1.0016 against −0.9941. The harness prints these with `parity probe`.

**Intended.** Yes. More accurate: SalahCalculation's Isha is the real crossing when there is one, and the bound when there isn't.

### E. Tehran's Maghrib at high latitudes

**What users see.** With the Tehran method:
- **Seventh-of-the-night rule, Salah's automatic choice beyond 48°:** on summer nights from 59°, Maghrib is later and SalahCalculation gives no Isha. Stockholm: Maghrib 46 to 51 minutes later on 40 days (1 June–10 July), no Isha on the same 40 days. Oslo: 44 to 51 minutes on 48 days (28 May–14 July), no Isha on the same days. Reykjavik: 24 to 54 minutes on 87 days (8 May–2 August), no Isha on 88 (8 May–3 August); on 3 August Salah's own Maghrib and Isha are both 23:19. Tromsø: 15 to 60 minutes on 50 days (20 April–15 May, 29 July–21 August) and 12 to 26 on 5 more with class G (16–17 May, 26–28 July), no Isha on 55 days (20 April–17 May, 26 July–21 August). For example, Stockholm on 20 June: Salah shows Maghrib 22:08 and Isha 22:54; SalahCalculation shows Maghrib 22:54 and no Isha. Ushuaia (54.8° S) is unaffected.
- **Middle-of-the-night rule:** Reykjavik: Maghrib 86 to 130 minutes later on 49 days (28 May–15 July), and 108 on 16 July with class D; no Isha on 50 days (27 May–15 July). Tromsø: 52 to 142 minutes later on 23 days (4–15 May, 29 July–8 August), 20 to 64 on 5 days with class G (16–17 May, 26–28 July) and 113 on 9 August with class D; no Isha on 29 days (3–17 May, 26 July–8 August). At Stockholm, Oslo, London and Ushuaia Maghrib doesn't differ by more than a minute.
- **Twilight-angle rule:** Maghrib is earlier: by 2 to 34 minutes at Stockholm on 96 days (4 May–7 August), 2 to 39 at Oslo on 101 days (2 May–10 August) and 2 to 9 at Ushuaia on 54 days (1–16 January, 24 November–31 December). At Reykjavik it is between 47 minutes earlier and 24 minutes later on 127 days (18 April–22 August), and at Tromsø between 52 minutes earlier and 26 later on 92 days, plus 5 days of 8 to 21 minutes later with class G (16–17 May, 26–28 July). Isha is given on both sides.

Salah's defaults use Tehran only in Iran, where nothing differs. A user anywhere else who picks Tehran beyond 48° gets the seventh-of-the-night rule automatically.

**Cause.** Tehran's Maghrib is the Sun at 4.5° below the horizon. adhan-swift uses that time only when it falls after sunset and before Isha, and otherwise falls back to sunset, with no high-latitude bound (`PrayerTimes.swift:144–151`). SalahTimes bounds an angle-based Maghrib like Isha, by the same portion of the night (`docs/algorithm.md` §8.3, RFC 0001 §6, `METHODS.md` "Differences from adhan-swift's presets"):
- **Seventh-of-the-night and middle-of-the-night rules:** both portions are the same for Maghrib and Isha. When the 4.5° time comes after the bound, Maghrib and Isha are both bounded at the same instant, sunset plus a seventh or a half of the night. That's the specified tie (`docs/validation.md`, "Known limitations", "Tehran at high latitudes": its order test found the tie at 60° and 65° and not at 55°, and its wide scan finds it from 58° in both hemispheres). SalahCalculation reports the later of an equal pair as missing, as its contract requires (`CalculationSource`: "one that isn't strictly after the kind before it"). adhan-swift keeps Maghrib at sunset when the 4.5° time isn't before its Isha, so its Maghrib is earlier and it keeps a separate Isha.
- **Twilight-angle rule:** the bound, sunset plus 4.5/60 of the night, comes before the 4.5° time, so SalahCalculation's Maghrib is earlier. When adhan-swift falls back to sunset because the 4.5° time isn't before its Isha, SalahCalculation's is later. The Isha bound is 14/60 of the night, so the two never tie.

**Evidence.** Behavior 4 explains 1,016 kind-days, counting the 8 adjusted Tehran runs: alone on 1,011, and on 5 at Tromsø (15 May) with the single step adding 56 seconds. With class G, 25 more, and with class D, 4. The Isha gaps are listed under "Times one side doesn't give".

**Intended.** Yes, as specified. For D1: under Salah's own automatic rule, a Tehran user at 59° or beyond sees Maghrib later and no separate Isha on summer nights, and under the middle-of-the-night rule from Reykjavik's latitude northward. Salah's UI should present that.

### F. The Moonsighting Committee's 55° rule

**What users see.** At Puerto Toro (55.08° S), Fajr is 2 to 67 minutes later on 162 days, and Isha 2 to 25 minutes earlier on 71 days. Both are largest at the December solstice. At Tromsø (69.6° N), Fajr differs on 49 days a year: by up to 4 minutes on 48 of them, earlier on days between 22 March and 16 May and later on days between 27 July and 18 September, and by −6 on 17 May. With class G it differs by +9 on 26 July. The user's high-latitude rule doesn't change this, since the committee's own rule decides Fajr and Isha on both sides.

**Cause.** The committee bounds Fajr and Isha by the seventh of the night from 55° of latitude. SalahTimes applies that from 55° of absolute latitude, in both hemispheres, as the committee's own timetable generator does (`docs/algorithm.md` §8.2 and §8.4; `METHODS.md`, "Moonsighting Committee Worldwide", "From 55°", and "Differences from adhan-swift's presets"). adhan-swift tests `coordinates.latitude >= 55` (`PrayerTimes.swift:94` and `:123`), so it never applies the rule in the south. In the north both apply it, but adhan-swift measures Fajr's seventh over the night after the day (`PrayerTimes.swift:87, 94–96`), and SalahTimes over Fajr's own night, as in class C. At Stockholm, Oslo and Reykjavik that changed nothing by more than a minute in 2026; at Tromsø it did. SalahTimes also keeps the 18° time as one of the bounds where adhan-swift replaces it; in 2026 that changed nothing by more than a minute anywhere.

**Evidence.** Behavior 3 explains 478 kind-days (233 at Puerto Toro, 49 in each of the five Tromsø runs): alone on 473, and on 17 May at Tromsø with the single step working against the difference by 82 seconds. With class G, 5 more at Tromsø (26 July). With the committee's Fajr bound measured over the night after the day, as a check, every Tromsø difference disappears: there it's the choice of night, not the 18° time.

**Intended.** Yes.

### G. One correction step at slow crossings

**What users see.** A few days a year at high latitudes:
- **Isha under the middle-of-the-night rule,** on days near those of class D, when adhan-swift does find the crossing but lands minutes to hours from it: London 2 to 4 minutes later, Oslo, Stockholm and Ushuaia mostly 2 to 26. The largest cases are crossings just before the middle of the night: Stockholm +58 on 18 August (Egyptian, Kuwait, custom), Reykjavik +83 on 22 August (Tehran) and +144 on 1 September (Egyptian, Kuwait, custom: Salah 22:24, SalahCalculation 00:48), and Tromsø +64 and +65 on 17 September (Karachi, Singapore). Under the twilight-angle rule the same day at Reykjavik gives +66.
- **Tromsø, at the edges of polar night and the midnight sun** (15 January, 16–17 May, 26–27 July) and of its twilight seasons: sunrise +7 on 15 January, Maghrib −8 to +16, Isha −7 to +14 after a moved sunset, and, with the Moonsighting Committee only, Fajr +7 on 15 January.
- **Fajr under the middle-of-the-night rule** at Ushuaia (2 to 6 minutes earlier, late January and early February) and Stockholm (−4 on 23 April), and Tehran's Maghrib at Reykjavik under that rule on 26 May and 17 July (+4).
- **With other classes:** Fajr at Tromsø with class C (+9 to +32, 26–27 July), Tehran's Maghrib with class E (+8 to +64), and the committee's Fajr with class F (+9, 26 July). Where the step adds less than a minute to a difference that another behavior makes, or works against it, the kind-day belongs to that other class: 705 in class A, 75 in C, 5 in E and 5 in F. Its size there runs from 401 seconds against the difference to 56 seconds with it.

**Cause.** adhan-swift finds each crossing with one correction step from an estimate made with the declination at 0 h UTC (`Astronomical.swift:175–193`, after Meeus, *Astronomical Algorithms*, p. 102). The step divides the altitude error by the rate at which the altitude changes (`:189–191`). Where that rate is low, near the antitransit for an Isha the Sun barely reaches, or for the first and last sunrises around polar night, one step leaves an error of minutes, and of hours when the estimate lies near the antitransit. SalahTimes iterates each crossing to under a millisecond and bisects when the iteration can't settle (`docs/algorithm.md` §6). Near polar transitions its times agree with JPL Horizons within 30 to 82 seconds (`docs/validation.md`, "Astronomy cross-checks").

**Evidence.** Running adhan-swift's one-step procedure and a converged search with the harness's independent solar model, and moving SalahTimes' crossing by the difference, reproduces Salah within 45 seconds on all 662 kind-days, and on 87 more together with class C, E or F. On these days both libraries find the crossing: at Reykjavik on 1 September, Isha at 17.5°, the test gives −0.9998, the one step lands at 22:24 and the converged crossing is at 00:48.

**Intended.** Yes. More accurate times.

## Times one side doesn't give

These kind-days have a time on only one side, so they aren't counted as differences. The harness lists every one, by configuration and date.

| Where | Salah | SalahCalculation |
|---|---|---|
| Tromsø, all configurations: 1–14 January and 27 November–31 December (polar night, 49 days) | No times (adhan-swift returns `nil`); Salah keeps showing the last day it computed | Fajr and Dhuhr on all 49 days, and Isha where it's an angle; with Umm al-Qura and Qatar, whose Isha follows sunset, Isha only on 27 November. Asr missing with `sunStaysBelow`. Sunrise and Maghrib missing with `sunStaysBelow` on 48 days; on 27 November the Sun rises for 21 minutes, so they're given. Tehran's 4.5° Maghrib is given on all 49 days |
| Tromsø, all configurations without adjustments (for adjusted runs, see section 3): 18 May–25 July (midnight sun, 69 days) | No times | Dhuhr and Asr on all 69 days; Fajr, sunrise, Maghrib and Isha missing with `sunStaysAbove`. On 18 May Fajr and sunrise are given too (sunrise not with Gulf under the automatic rule, whose sunrise −3 minutes isn't after its Fajr; under the other two rules Gulf's sunrise is given, 00:48). On 25 July Maghrib is given, and Isha in most configurations. Isha is missing that day with Umm al-Qura and Qatar (after the next day's Fajr), and with the Moonsighting Committee, Gulf under the automatic rule and Tehran under the automatic and middle-of-the-night rules (not after Maghrib) |
| Tromsø: 15–18 January, 23–26 November | An Asr, out of order (class B) | Asr missing with `sunStaysBelow`: the Sun is below the horizon at noon |
| Tromsø, Moonsighting Committee: 19–20 January, 20–22 November; Singapore: 22 November | An Asr, out of order (class B) | Asr missing: it comes minutes after the transit, and isn't after Dhuhr with the method's added minutes (+5 and +1) |
| Tromsø, Gulf under the automatic rule and the Moonsighting Committee under every rule: 17 May | Isha 2 minutes after Maghrib | Isha missing: the seventh of a very short night puts it at or before Maghrib, which carries the method's 3 added minutes |
| Reykjavik, Umm al-Qura and Qatar with the middle-of-the-night rule: 14–26 June (13 days) | Isha 90 minutes after sunset | Isha missing: it falls after the next day's Fajr, which the rule puts at the middle of the night |
| Tromsø, Umm al-Qura and Qatar: 15–17 May and 26–27 July (5 days, automatic rule); 12–17 May and 26–30 July (11, middle of the night); 14–17 May and 26–28 July (7, twilight angle) | Isha 90 minutes after sunset | Isha missing: it falls after the next day's Fajr |
| Tehran, automatic rule (seventh of the night): Stockholm 1 June–10 July (40 days), Oslo 28 May–14 July (48), Reykjavik 8 May–3 August (88), Tromsø 20 April–17 May and 26 July–21 August (55) | Maghrib at sunset or the 4.5° time, Isha at the bound | Isha missing: tied with the bounded Maghrib (class E) |
| Tehran, middle-of-the-night rule: Reykjavik 27 May–15 July (50 days), Tromsø 3–17 May and 26 July–8 August (29) | Isha at the middle of the night, Maghrib at sunset or the 4.5° time | Isha missing: tied with the bounded Maghrib (class E) |
| With user adjustments at high latitudes: the days listed in section 3, "Adjustments at high latitudes" | As without adjustments | A time pushed out of order by the adjustments is missing; a few Isha times are given that are missing without adjustments |

On every day where SalahCalculation reports a kind missing and SalahTimes computed a time, the reason is one of the adapter rules that `CalculationSource` documents. In this comparison that was a time that isn't strictly after the kind before it, or a time after an event of a later day. In every case of the second kind, the later day was the next one: the time came after the next day's first event.

## What Salah's users will see after D1

Grouped by place and high-latitude rule. "Automatic" is Salah's automatic rule, its default: the seventh of the night beyond 48°. In the bullets, a range is the extreme over every method compared at the place, unless a method is named; the table after the list gives each method's own range. A script checks this section against the harness's table of changes (`d1-changes.tsv`: one row per place, method, rule, adjustment setting and kind, with every date). It doesn't read the prose. It checks claims written by hand for the sentences of the list:
- every kind-day in the table is covered by exactly one claim (other claims may restate some of them, such as the range with the defaults);
- the ranges, dates, counts, methods and classes a claim gives equal the data, and a named method's range is that method's alone;
- each claim's phrase appears in its sentence and holds the same set of numbers as the claim;
- every number in the bullets is in some claim's phrase or is a fixed fact such as a latitude;
- every cell of the table below equals that method's own range.

The order of the numbers within a phrase, the months written with them, and the words were checked by reading, not by the script.

- **Everywhere:** with the Muslim World League, Egyptian, Karachi or North America method, Dhuhr is a minute earlier. Other times move by at most a minute, through rounding, except as listed below. At the places below 51.5° in this comparison, nothing else differs by more than a minute.
- **London (51.5° N):**
  - Automatic: nothing differs by more than a minute.
  - Middle of the night: Fajr −2 to +2 (class C); Isha −24 to +7 on a few days in May and July (D, G).
  - Twilight angle: Fajr +2 on a few days in August with Egyptian and Singapore (C).
- **Stockholm and Oslo (59° to 60° N):** Asr −2 to +2 under every rule (A).
  - Automatic: with Tehran, on summer nights Maghrib is later and there is no Isha: at Stockholm Maghrib is 46 to 51 minutes later and Isha missing on 40 days (1 June–10 July), at Oslo 44 to 51 minutes and 48 days (28 May–14 July) (E).
  - Middle of the night: Fajr −4 to +3 (C, G); Isha −31 to +58 on a few days in April, May and August (D, G).
  - Twilight angle: Fajr −2 to +2 (C); with Tehran, Maghrib earlier in summer, by 2 to 34 minutes at Stockholm and 2 to 39 at Oslo (E).
- **Reykjavik (64.1° N):** Asr −6 to +5 under every rule (A).
  - Automatic: with Tehran, Maghrib 24 to 54 minutes later, and no Isha on 88 days (8 May–3 August) (E).
  - Middle of the night: Fajr −4 to +4 (C); Isha −32 to +144 on a few days in April and from late August to early September (D, G). With Tehran, Maghrib +4 to +130 and no Isha on 50 days (27 May–15 July): +86 to +130 (E), +108 on 16 July (E with D), +4 on 26 May and 17 July (G). With Umm al-Qura and Qatar, no Isha on 13 days (14–26 June): their 90 minutes after sunset reach past the next Fajr.
  - Twilight angle: Fajr −3 to +3 (C); Isha +66 on 1 September with Egyptian, Kuwait and custom (G); with Tehran, Maghrib −47 to +24 (E).
- **Tromsø (69.6° N), under every rule, Salah's defaults included:**
  - **Polar night and midnight sun:** the 118 days on which Salah computes nothing become partial days with the missing prayers named (see "Times one side doesn't give").
  - **Asr:** −7 to +10 from February to April and from August to November (A), largest just outside class B's days: −7 on 7–9 February, +10 on 10 November. Around polar night −2279 to +104 (B). With the defaults, on 35 days a year when Salah's times look plausible, Asr moves by 6 to 73 minutes (class B on 21 January–6 February and 11–14 November, class A on 7–11 February and 2–10 November). On 18 more days Salah's Asr is out of order. On 8 of those (15–18 January, 23–26 November) the Sun is below the horizon at noon and SalahCalculation gives no Asr; with the Moonsighting Committee that's 13 days and with Singapore 9, because an Asr minutes after the transit isn't after their Dhuhr minutes.
  - **Fajr,** every method but the Moonsighting Committee: automatic: −4 to +5 on 100 to 119 days a year, depending on the method (C); on 15 January −113 with the defaults, −77 to −137 depending on the Fajr angle (C); −6 on 17 May (C); +9 on 26 July (C with G); so −137 to +9 in all. Middle of the night: −21 to +32. Twilight angle: −14 to +21.
  - **Fajr with the Moonsighting Committee,** under every rule: −6 to +4 on 49 days (F), +7 on 15 January (G) and +9 on 26 July (F with G).
  - **Sunrise:** +7 on 15 January (G).
  - **Maghrib:** −8 to +16 on 15 January, 16–17 May and 26–27 July (G; −7 to +15 with the defaults). With Tehran: up to 60 minutes later under the automatic rule (E, and E with G); up to 142 under the middle-of-the-night rule (E, and on a few days E with G, G, D or E with D); and between 52 minutes earlier and 26 later under the twilight-angle rule (E, and E with G). So −8 to +60, −8 to +142 and −52 to +26 by rule.
  - **Isha:** automatic: −7 to +14 on 15 January, 16–17 May and 26–27 July (G; −6 to +13 with the defaults). Middle of the night: −41 to +65 (D, G). Twilight angle: −7 to +13 (G). Isha is missing with Umm al-Qura and Qatar after the next day's Fajr (5 days under the automatic rule, 11 under the middle-of-the-night rule, 7 under the twilight-angle rule); with Tehran, tied with Maghrib (55 days automatic, 29 middle of the night); and on 17 May with Gulf under the automatic rule and the Moonsighting Committee under every rule.
- **Ushuaia (54.8° S):** Asr −2 to +2 under every rule (A).
  - Automatic: nothing else.
  - Middle of the night: Fajr −6 to +3 (C, G); Isha −32 to +26 on a few days in January, February and November (D, G).
  - Twilight angle: Fajr −2 to +2 (C); with Tehran, Maghrib 2 to 9 minutes earlier around the December solstice (E).
- **Puerto Toro (55.08° S), Moonsighting Committee:** Fajr 2 to 67 minutes later, Isha 2 to 25 earlier (F), Asr −2 to +2 (A).
- **With adjustments at high latitudes** (section 3): the same as without, except where an adjustment pushes a time out of order and SalahCalculation reports it missing. With Tehran under the automatic rule, Isha is missing on 50 days at Stockholm, 92 at Reykjavik and 59 at Tromsø. At Tromsø, Asr is missing on 19 January and 22 November with the Muslim World League, Tehran, Umm al-Qura and Gulf, and on 21–22 January and 19 November too with the Moonsighting Committee. There, Isha is missing on 17 May with the Muslim World League under the automatic rule, and sunrise on 26 July with Gulf under the automatic rule. On two days on which Salah gives no times, SalahCalculation gives less with adjustments: no sunrise on 18 May with the Muslim World League, Tehran and Umm al-Qura under the automatic rule and the Moonsighting Committee under both rules, and no Isha on 25 July with the Muslim World League under the automatic rule. The other way round, Umm al-Qura's Isha is given again at Reykjavik on 14–26 June (middle of the night) and at Tromsø on 15 May and 27 July (automatic; +2 on 27 July).
- **Ramadan delayed Isha** behaves as before.

**Each method's own range.** Every place, rule and kind with a difference over a minute, and each method's range in minutes; methods with the same range share a cell. Rows with adjustments appear only where a method's range differs from the same settings without them.

| Place | Rule | Kind | Each method's own range (minutes) |
|---|---|---|---|
| London | middle of the night | Fajr | `egyptian`, `karachi`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2 |
| London | middle of the night | Isha | `egyptian`, `custom`, `kuwait`: −19 to +4; `karachi`, `gulf`: −23 to +6; `muslimWorldLeague`: −18 to +4; `singapore`: −24 to +7 |
| London | twilight angle | Fajr | `egyptian`, `singapore`: +2 |
| Stockholm | automatic | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2 |
| Stockholm | automatic | Maghrib | `tehran`: +46 to +51 |
| Stockholm | middle of the night | Fajr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −3 to +3; `gulf`: −4 to +3 |
| Stockholm | middle of the night | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2 |
| Stockholm | middle of the night | Isha | `egyptian`, `custom`, `kuwait`: +2 to +58; `karachi`, `singapore`: −23 to +7; `northAmerica`: −13 to +17; `muslimWorldLeague`: −25 to +7; `gulf`: −31 to +9; `tehran`: −26 to +7 |
| Stockholm | twilight angle | Fajr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2 |
| Stockholm | twilight angle | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2 |
| Stockholm | twilight angle | Maghrib | `tehran`: −34 to −2 |
| Oslo | automatic | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `custom` 15/15, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2; `muslimWorldLeague` (Hanafi): −2 |
| Oslo | automatic | Maghrib | `tehran`: +44 to +51 |
| Oslo | middle of the night | Fajr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −3 to +3 |
| Oslo | middle of the night | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2 |
| Oslo | middle of the night | Isha | `egyptian`, `custom`, `kuwait`: −16 to +15; `karachi`: −29 to +13; `northAmerica`: −15 to +16; `muslimWorldLeague`, `singapore`: −29 to +14; `gulf`: −12 to +26; `tehran`: −25 to +5 |
| Oslo | twilight angle | Fajr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2 |
| Oslo | twilight angle | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2 |
| Oslo | twilight angle | Maghrib | `tehran`: −39 to −2 |
| Reykjavik | automatic | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −6 to +5 |
| Reykjavik | automatic | Maghrib | `tehran`: +24 to +54 |
| Reykjavik | middle of the night | Fajr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −4 to +4 |
| Reykjavik | middle of the night | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −6 to +5 |
| Reykjavik | middle of the night | Maghrib | `tehran`: +4 to +130 |
| Reykjavik | middle of the night | Isha | `egyptian`, `custom`, `kuwait`: −11 to +144; `karachi`: −32 to +16; `northAmerica`: −15 to +42; `muslimWorldLeague`: −26 to +12; `gulf`: −15 to +43; `singapore`: −32 to +15; `tehran`: −11 to +83 |
| Reykjavik | twilight angle | Fajr | `egyptian`, `singapore`: −3 to +3; `karachi`, `northAmerica`, `muslimWorldLeague`, `custom`, `kuwait`, `qatar`, `tehran`: −2 to +2; `ummAlQura`: −2 to +3; `gulf`: −3 to +2 |
| Reykjavik | twilight angle | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −6 to +5 |
| Reykjavik | twilight angle | Maghrib | `tehran`: −47 to +24 |
| Reykjavik | twilight angle | Isha | `egyptian`, `custom`, `kuwait`: +66 |
| Tromsø | automatic | Fajr | `egyptian`: −131 to +9; `karachi`, `muslimWorldLeague`, `custom`, `kuwait`, `qatar`: −113 to +9; `northAmerica`: −77 to +9; `ummAlQura`: −119 to +9; `gulf`: −115 to +9; `moonsightingCommittee`: −6 to +9; `singapore`: −137 to +9; `tehran`: −110 to +9 |
| Tromsø | automatic | Sunrise | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: +7 |
| Tromsø | automatic | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `custom`, `kuwait`, `qatar`, `tehran`: −2279 to +104; `moonsightingCommittee`: −73 to +30; `singapore`: −2278 to +57 |
| Tromsø | automatic | Maghrib | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`: −7 to +15; `singapore`: −8 to +16; `tehran`: +12 to +60 |
| Tromsø | automatic | Isha | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `gulf`, `custom`, `kuwait`: −6 to +13; `ummAlQura`, `qatar`: −7; `moonsightingCommittee`: −7 to +13; `singapore`: −6 to +14; `tehran`: −6 |
| Tromsø | automatic, with adjustments | Asr | `muslimWorldLeague`, `ummAlQura`, `gulf`, `tehran`: −162 to +56; `moonsightingCommittee`: −35 to +24 |
| Tromsø | automatic, with adjustments | Isha | `muslimWorldLeague`, `gulf`: −6 to +13; `ummAlQura`: −7 to +2; `moonsightingCommittee`: −7 to +13; `tehran`: −6 |
| Tromsø | middle of the night | Fajr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −21 to +32; `moonsightingCommittee`: −6 to +9 |
| Tromsø | middle of the night | Sunrise | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: +7 |
| Tromsø | middle of the night | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `custom`, `kuwait`, `qatar`, `tehran`: −2279 to +104; `moonsightingCommittee`: −73 to +30; `singapore`: −2278 to +57 |
| Tromsø | middle of the night | Maghrib | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`: −7 to +15; `singapore`: −8 to +16; `tehran`: +3 to +142 |
| Tromsø | middle of the night | Isha | `egyptian`, `custom`, `kuwait`: −24 to +16; `karachi`: +2 to +64; `northAmerica`: −41 to +8; `muslimWorldLeague`: −35 to +8; `ummAlQura`, `qatar`: −7; `gulf`: −30 to +9; `moonsightingCommittee`: −7 to +13; `singapore`: +2 to +65; `tehran`: −31 to +20 |
| Tromsø | middle of the night, with adjustments | Asr | `muslimWorldLeague`, `ummAlQura`, `gulf`, `tehran`: −162 to +56; `moonsightingCommittee`: −35 to +24 |
| Tromsø | twilight angle | Fajr | `egyptian`, `singapore`: −14 to +21; `karachi`, `muslimWorldLeague`, `gulf`, `custom`, `kuwait`, `qatar`: −13 to +20; `northAmerica`: −10 to +16; `ummAlQura`, `tehran`: −13 to +19; `moonsightingCommittee`: −6 to +9 |
| Tromsø | twilight angle | Sunrise | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: +7 |
| Tromsø | twilight angle | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `custom`, `kuwait`, `qatar`, `tehran`: −2279 to +104; `moonsightingCommittee`: −73 to +30; `singapore`: −2278 to +57 |
| Tromsø | twilight angle | Maghrib | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`: −7 to +15; `singapore`: −8 to +16; `tehran`: −52 to +26 |
| Tromsø | twilight angle | Isha | `egyptian`, `muslimWorldLeague`, `gulf`, `custom`, `kuwait`, `singapore`: +2 to +11; `karachi`: +6 to +11; `northAmerica`: +2 to +12; `ummAlQura`, `qatar`: −7; `moonsightingCommittee`: −7 to +13; `tehran`: +6 to +12 |
| Ushuaia | automatic | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2 |
| Ushuaia | middle of the night | Fajr | `egyptian`: −6 to +3; `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2 |
| Ushuaia | middle of the night | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2 |
| Ushuaia | middle of the night | Isha | `egyptian`, `custom`, `kuwait`: −32 to +9; `karachi`, `singapore`: −18 to +26; `northAmerica`: −15 to +21; `muslimWorldLeague`: −30 to +13; `gulf`: −24 to +10; `tehran`: −16 to +15 |
| Ushuaia | twilight angle | Fajr | `egyptian`, `karachi`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2; `northAmerica`: +2 |
| Ushuaia | twilight angle | Asr | `egyptian`, `karachi`, `northAmerica`, `muslimWorldLeague`, `ummAlQura`, `gulf`, `moonsightingCommittee`, `custom`, `kuwait`, `qatar`, `singapore`, `tehran`: −2 to +2 |
| Ushuaia | twilight angle | Maghrib | `tehran`: −9 to −2 |
| Puerto Toro | automatic | Fajr | `moonsightingCommittee`: +2 to +67 |
| Puerto Toro | automatic | Asr | `moonsightingCommittee`: −2 to +2 |
| Puerto Toro | automatic | Isha | `moonsightingCommittee`: −25 to −2 |
