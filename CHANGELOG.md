# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-13

The first release: the schedule core, calculated and published sources, and the two example
apps that prove them through the public API.

### Added

- **SalahCore**, the app layer's foundation, specified in [RFC 0001](docs/rfcs/0001-core.md):
  - Domain values: `CivilDay` with calendar arithmetic and zone-aware `start(in:)` and
    `interval(in:)`, `PrayerKind`, `PrayerEvent` with its owning day, `PrayerDay`,
    `PrayerLocation`.
  - The `PrayerSource` contract, enforced by the schedule on every answer: a day that breaks it
    becomes invalid data, never a guessed time. A source declares its `maximumLead`, how long
    before its owning day an event can occur: zero for published times, 12 hours for a
    calculated Fajr that falls before midnight where the clock runs behind the Sun.
  - `TimetableSource` for published timetables, with times after midnight (`"00:15+1"`),
    published iqama, declared Jumu'ah and explicit `WallTimeResolution` for clock changes.
  - `PrayerSchedule`: bounded day, event and state queries with coverage gaps that say which
    day and kinds are missing and why; `ScheduleState`, `PrayerState` and `PrayerEventStatus`;
    `IqamaRules` (Jumu'ah never borrows Dhuhr's rule); `StatePolicy`.
  - `refreshPlan`, the dates and states a widget timeline needs, with an entry budget and an
    explicit `validUntil` cutoff.
  - `PrayerNames` over a String Catalog in nine languages, `PrayerDurationFormat` (always rounds
    down), `PrayerLocale.resolved` (native digits) and `HijriDateFormat`.
  - The DocC article "Using a mosque timetable with iqama and incomplete coverage".
- **SalahCalculation**, specified in [RFC 0002](docs/rfcs/0002-calculation.md): calculated
  times from [SalahTimes](https://github.com/salah-kit/SalahTimes) 0.1 as a `PrayerSource`.
  - `CalculationSettings` holds SalahTimes' `CalculationParameters` whole (`Codable`,
    `Hashable`, `Sendable`), from a published method with a madhab and the opt-in Ramadan rule,
    or from parameters an app already has.
  - `CalculationSource` reports what SalahCore's contract can hold: a prayer that doesn't occur
    (a polar summer's Isha), a tie, an inversion or an Isha after the next Fajr is missing with
    `calculationUnavailable`; bad coordinates or parameters make the day `invalidData`. It never
    moves, reorders or borrows a time, and never declares Jumu'ah.
  - `CalculationMethod.suggested(for:)`: SalahTimes' sourced country suggestion for a
    `PrayerLocation`, opt-in.
  - The DocC article "A calculated prayer app with Core and Calculation".
  - `docs/calculation-parity.md`: SalahCalculation against the times the Salah app computed
    with adhan-swift, every difference over a minute explained.
- **SalahFixtures**: eight places and seven moments with exact, documented timetables for
  previews and tests (late Isha, events after midnight, a spring-forward day, declared Jumu'ah,
  Ramadan, a partial row, a missing day and the last published day).
- **Vectors**: 159 language-neutral JSON vectors for days, events, state and refresh plans in
  `Vectors/`, written from the RFC before the implementation and checked independently, and
  calculation vectors in `Vectors/calculation/` with instants from SalahTimes' independent
  reference implementation. SalahTimes' own vectors also run through the adapter.
- **MosqueBoard**, an iPad example that shows MUIS's 2026 Singapore timetable and a synthetic
  Edinburgh one, with iqama, coverage banners, Isha after midnight, clock changes and Arabic,
  and XCUITest journeys for each.
- **CalculatedPhone**, an iPhone example that calculates with SalahCalculation: every
  calculation parameter on screen and in its settings, the schedule and state across midnight,
  and polar days and invalid locations shown as they are, with XCUITest journeys for each.
- CI for macOS, Linux, both default-isolation settings, lint, MosqueBoard (including a check
  that it links no calculation code) and CalculatedPhone; documentation published to GitHub
  Pages.

[Unreleased]: https://github.com/salah-kit/SalahKit/compare/0.1.0...HEAD
[0.1.0]: https://github.com/salah-kit/SalahKit/releases/tag/0.1.0
