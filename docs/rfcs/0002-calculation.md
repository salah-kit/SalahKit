# RFC 0002: SalahCalculation

- **Status:** Draft. Open to findings from `CalculatedPhone` and from Salah's migration.
- **Products:** SalahCalculation.
- **Started:** 2026-10-13.
- **Supersedes:** the SalahAdhan sketch in the SalahKit proposal, §7.2, read with Amendment 3 (SalahTimes replaces adhan-swift).
- **Depends on:** RFC 0001 (SalahCore's source contract), and SalahTimes' RFC 0001 (its API).

SalahCalculation connects [SalahTimes](https://github.com/salah-kit/SalahTimes), the ecosystem's calculation engine, to SalahCore's `PrayerSource` contract. This RFC fixes its API and the rules by which a calculated day becomes a `PrayerDayAvailability`. The JSON vectors in `Vectors/calculation/` encode those rules.

References like "§7.2" point to the SalahKit proposal; "Core §4.3" points to RFC 0001.

---

## 1. Summary

An app that calculates prayer times builds `CalculationSettings` from a published method or from SalahTimes parameters it already has, and hands a `CalculationSource` to `PrayerSchedule`. Every SalahCore query then works the same as it does for a published timetable: owning days, coverage, state, refresh plans.

The source passes SalahTimes' parameters through whole and its results through unchanged. Where a result can't be held by SalahCore's contract (a prayer that doesn't occur in a polar summer, two kinds at the same instant, an Isha after the next day's Fajr), the kind is reported missing with a reason. Nothing is moved, reordered or borrowed from another day.

## 2. Scope

In SalahCalculation 0.1:
- `CalculationSettings`, a `Codable`, `Hashable`, `Sendable` value holding SalahTimes' `CalculationParameters`;
- `CalculationSource`, the calculated `PrayerSource`;
- `CalculationMethod.suggested(for:)`, SalahTimes' country suggestion for a `PrayerLocation`.

Not in SalahCalculation:
- the engine itself, its methods, rules and the Ramadan rule (SalahTimes);
- sunset, the night's middle and last third, and Qibla, which have no `PrayerKind`. Apps that want them import SalahTimes and call it directly;
- Jumu'ah and iqama, which are app or mosque policy (Core §4.5 and §9 #6);
- location services and time-zone lookup.

## 3. Public API

```swift
import SalahCore
import SalahTimes

nonisolated public struct CalculationSettings: Codable, Hashable, Sendable {
  public var parameters: CalculationParameters        // passed to SalahTimes unchanged
  public init(parameters: CalculationParameters)
  /// The method's parameters with this madhab and Ramadan rule; nothing else changes.
  public init(method: CalculationMethod, madhab: Madhab = .shafi,
              ramadanIsha: RamadanIshaRule = .off)
}

nonisolated public struct CalculationSource: PrayerSource, Hashable, Sendable {
  public let settings: CalculationSettings
  public init(_ settings: CalculationSettings)
  public var expectedKinds: Set<PrayerKind> { get }   // all six
  public var maximumLead: Duration { get }            // 12 hours
  public func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability
}

nonisolated extension CalculationMethod {
  /// SalahTimes' sourced suggestion for location.countryCode, or nil.
  public static func suggested(for location: PrayerLocation) -> CalculationMethod?
}
```

SalahCalculation doesn't re-export SalahTimes. An app that names SalahTimes types (`CalculationMethod`, `Madhab`, `HighLatitudeRule`, …) imports SalahTimes too; the types reach it through SalahCalculation's dependency. A package that does so lists the SalahTimes product in its own target's dependencies.

## 4. Behavior

### 4.1 Settings

- `parameters` is SalahTimes' `CalculationParameters`, the whole value: Fajr, Maghrib and Isha rules (angles, intervals, the Moonsighting Committee's seasonal rule and shafaq), madhab, high-latitude rule, night span, method adjustments, user adjustments, rounding and the opt-in Ramadan rule. The source never rebuilds it from a subset, resets a field to a method's value or fills in a default (§7.2 "Every upstream calculation control survives").
- `init(method:madhab:ramadanIsha:)` is `method.parameters` with `madhab` and `ramadanIsha` set. Every other field is the method's.
- `Codable` as `{"parameters": <SalahTimes' JSON>}`. SalahTimes decodes missing parameter keys as their defaults (only `fajr` and `isha` are required), so settings saved by an older version keep decoding.
- `Hashable` and `Equatable` are synthesized from `parameters`, which SalahTimes declares `Hashable` itself (§7.2 asked for `Hashable` only if it's honestly synthesized; it is). Two settings are equal exactly when their parameters are.

### 4.2 A calculated day

`CalculationSource.prayerDay(D, at: location)`, with `Z = location.timeZone`, `L = 12 hours` and `start(X)` = `X.start(in: Z)` (Core §4.1):

1. **Invalid date.** `D` isn't a real Gregorian date: `.unavailable(.invalidData)`.
2. **Calculate `D`** (the steps of §4.3). If that fails, `.unavailable(reason)` with its reason.
3. **The next day.** Calculate `D + 1` the same way. If it succeeds and has at least one time, let `first` be its earliest. Every time of `D` later than `first` is removed and its kind is missing with `.calculationUnavailable`. Equal instants stay. (Core §4.3 rule 6: no event of a day after an event of the next day. The earlier day gives way, because its late event, typically an interval Isha near the polar circles, is the one the rules can't place.)
4. **Nothing left:** `.unavailable(.calculationUnavailable)`.
5. **Otherwise** `.available(PrayerDay(day: D, timeZone: Z, events:), coverage:)`, with one event per remaining kind: `scheduleDay` `D`, `observance` `.ordinary`, `iqama` `nil`. Coverage is `.complete` when all six kinds remain, else `.partial(missing:)` with every missing kind and its reason.

### 4.3 Calculating one day

To calculate day `X`:

1. **A date the zone skips.** If `start(X + 1) <= start(X)`, the date has no time on the clock (Pacific/Apia, 2011-12-30): fail with `.calculationUnavailable`. SalahTimes would otherwise give it the next date's solar day, and the same instants would appear twice.
2. **The year.** If `GregorianDay(year:month:day:)` rejects `X`'s fields (a year beyond ±999,999), fail with `.calculationUnavailable`.
3. **SalahTimes.** `PrayerTimes(coordinates: (location.latitude, location.longitude), day: X, timeZone: Z, parameters: settings.parameters)`.
   - `CalculationError.unsupportedDate` (years outside 1000–3000): fail with `.calculationUnavailable`. The calculation can't produce the day.
   - `CalculationError.invalidCoordinates` or `.invalidParameters`: fail with `.invalidData`. The input contradicts the contract.
4. **Each kind**, in canonical order (fajr, sunrise, dhuhr, asr, maghrib, isha), mapped to SalahTimes' event of the same name. The kind is missing with `.calculationUnavailable` when:
   - its event is `.doesNotOccur` (either reason);
   - its instant is before `start(X) − L` or not before `start(X + 2)`;
   - its instant isn't strictly after the instant of the last kind kept so far. Of an equal or inverted pair, the later kind is missing.

   Otherwise the kind is kept at SalahTimes' instant, unchanged.

The steps never move an instant, never take one from another day, and never infer an observance.

### 4.4 Owning days and the lead

A calculated event belongs to the day it was computed for. SalahTimes picks that day's solar day by the transit nearest local noon (SalahTimes RFC 0001, decision 1), so:
- an Isha after midnight belongs to the evening before (Kashgar on Beijing time, high latitudes in summer);
- where the clock runs behind the Sun, a Fajr near the middle of the night belongs to the next day but falls before it begins. In 2026 this happens on 96 days in Kazan and Naberezhnye Chelny under the middle-of-the-night rule (as early as 23:45), on 45 in Oskemen, and on 19 to 31 in Jiamusi under the default rule with the Egyptian or MUIS method. Near the polar circles, sunrise can too.

SalahCore 0.1 accepts such events through `PrayerSource.maximumLead` (Core §4.3 rule 4, §10). `CalculationSource` declares 12 hours, SalahCore's maximum, which covers every place's clock offset and leaves room for large user adjustments. An instant earlier than that is missing (§4.3 step 4).

### 4.5 Reasons

| Situation | Answer |
|---|---|
| `D` isn't a real date | `.unavailable(.invalidData)` |
| Invalid coordinates or parameters | `.unavailable(.invalidData)` for every day |
| A year SalahTimes doesn't calculate, or a date the zone skips | `.unavailable(.calculationUnavailable)` |
| A kind that doesn't occur, lies outside `[start(D) − 12 h, start(D + 2))`, ties or inverts with the kind before it, or follows the next day's first event | that kind missing with `.calculationUnavailable` |
| No kind left | `.unavailable(.calculationUnavailable)` |

`.noPublishedData` and `.unresolvedWallTime` never come from a calculated source.

### 4.6 Opt-ins

Both are SalahTimes features (SalahTimes RFC 0001, decision 7); SalahCalculation exposes them and implements neither.

- **Ramadan Isha.** `CalculationSettings(method:madhab:ramadanIsha:)` and `parameters.ramadanIsha` select SalahTimes' `RamadanIshaRule`. It's off unless the app opts in. When on, SalahTimes replaces a positive Isha interval on days that fall in Ramadan in the Umm al-Qura calendar, shifted by the Hijri day offset; it changes nothing else, and never an angle-based Isha (§7.2, adhan-swift issue #23). Setting it changes only that one field of the settings.
- **Method suggestions.** `CalculationMethod.suggested(for:)` reads `location.countryCode` and returns `CalculationMethod.suggested(forCountryCode:)`, or `nil` without a country code or a sourced suggestion. Nothing applies a suggestion automatically. The table and its sources live in SalahTimes (`METHODS.md`, `Vectors/country-methods.json`), and corrections go there, as `calculation-method` issues.

### 4.7 Isolation and cost

- Every public type is `nonisolated` and `Sendable`, like SalahCore's (Core §3). A widget extension or a background task can calculate off the main actor.
- SalahTimes is used as SwiftPM builds it, with nonisolated default isolation. SalahKit's isolation checks apply MainActor default isolation to SalahKit's own targets only (Core §6.3).
- A day costs two SalahTimes calculations (`D` and `D + 1`), about 20 µs in release. A 400-day query reads about 403 owning days.

## 5. Changes from the proposal's sketch (§7.2)

| Sketch | Now | Why |
|---|---|---|
| `AdhanSettings` with `parameters` and a separate `ramadanIsha` | `CalculationSettings` with `parameters` only; `ramadanIsha` lives inside them | SalahTimes keeps the Ramadan rule in `CalculationParameters`, so a second copy could disagree with it. |
| `Codable, Equatable, Sendable`, no `Hashable` | also `Hashable` | adhan-swift's parameters weren't `Hashable`; SalahTimes' are, so synthesis is honest. |
| `AdhanSource` | `CalculationSource` | Named for what it does, next to `TimetableSource`. |
| An initializer failure is `.calculationUnavailable`; bad chronology is `.invalidData` | Bad input is `.invalidData`; an unsupported year is `.calculationUnavailable`; a time the contract can't hold makes only its kind missing | SalahTimes throws only for bad input or an unsupported year. Reporting single kinds keeps the rest of a polar day usable; the schedule would otherwise reject the whole day (Core §4.3). |
| `MethodSuggestions.method(forCountryCode:)` and `.table` | `CalculationMethod.suggested(for: PrayerLocation)` | The table and its sources are SalahTimes'; SalahCalculation only connects it to `PrayerLocation`. |
| `import Adhan`, the `Sendable` bridge, `@preconcurrency` | none | Amendment 3: SalahTimes is `Sendable` from the start. |
| A Fajr before its day: not considered | `PrayerSource.maximumLead` in Core, 12 hours here | §4.4. |

## 6. Dependency

SalahKit depends on SalahTimes `.upToNextMinor(from: "0.1.0")`. Before 1.0, a SalahTimes minor release may change its API, so a SalahKit release resolves only the SalahTimes patch releases of the minor version it was built and tested against. SalahKit's next minor release moves the range. Only SalahCalculation and its tests import SalahTimes.

## 7. Vectors

`Vectors/calculation/` holds language-neutral vectors for a calculated source, so a port of SalahCore and SalahCalculation to another language can check itself. They use the SalahCore vector schema (`Vectors/README.md`) with one difference in the input: `settings` (a `CalculationSettings` JSON value) replaces `source`, and the schedule is `PrayerSchedule(source: CalculationSource(settings), location:, iqama:)`. Query types and expected shapes are SalahCore's.

The expected instants come from SalahTimes' independent Python reference implementation (SalahTimes `Vectors/reference/`), not from the Swift engine; the rules of §4 decide which of them each answer holds. The vectors cover ordinary days, owning days across midnight in both directions, the lead, polar day and night, a disabled high-latitude rule, ties, an Isha after the next Fajr, every failure in §4.5, the Ramadan opt-in, Fridays, clock changes, state and refresh plans across these cases.

SalahTimes' own vectors (`Vectors/times/`, copied into `Tests/SalahCalculationTests/SalahTimesVectors/` at 0.1.0) also run through the adapter: every time SalahTimes expects comes out of `CalculationSource` unchanged, or its kind is missing for a reason in §4.5.

## 8. Evidence

- Unit tests: settings pass every parameter through, round-trip and hash honestly; the Ramadan opt-in changes only its field and only Isha on Ramadan days; every §4.5 case; a year of days at seven places and methods passes the schedule's contract checks with no invalid-data gap.
- Salah's `PrayerTimesInvarianceTests`, migrated.
- `docs/calculation-parity.md`: SalahCalculation against the times Salah computes today with adhan-swift, every difference over a minute explained.
- `Examples/CalculatedPhone`: an iPhone app on the public API, with XCUITest journeys (§2.3 #1).

## 9. Open questions

1. **Equal instants within a day.** SalahCore requires strictly increasing times within a day, so where SalahTimes legitimately puts Maghrib and Isha at the same instant (Tehran's method from 58°, both bounded by a seventh of the night), Isha is missing. A contract that allowed equal instants within a day would keep it.
2. **Which kind of an inverted pair is wrong.** The later kind is dropped. For a Fajr after sunrise (Diyanet's and Kemenag's precautionary minutes at 66° to 69°), the Fajr is arguably the doubtful one. Waiting for a consumer at those latitudes.
3. **Known non-occurrence.** A prayer that doesn't occur (polar day) is reported like an unknown one, so the state asserts nothing across its window. A "doesn't occur tonight" coverage reason would let a view say more. It would be a Core change.

## 10. Changes after review

None yet.
