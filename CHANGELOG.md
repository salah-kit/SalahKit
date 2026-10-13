# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **SalahCore**, the app layer's foundation, specified in [RFC 0001](docs/rfcs/0001-core.md):
  - Domain values: `CivilDay` with calendar arithmetic and zone-aware `start(in:)` and
    `interval(in:)`, `PrayerKind`, `PrayerEvent` with its owning day, `PrayerDay`,
    `PrayerLocation`.
  - The `PrayerSource` contract, enforced by the schedule on every answer: a day that breaks it
    becomes invalid data, never a guessed time.
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
- **SalahFixtures**: eight places and seven moments with exact, documented timetables for
  previews and tests (late Isha, events after midnight, a spring-forward day, declared Jumu'ah,
  Ramadan, a partial row, a missing day and the last published day).
- **Vectors**: 159 language-neutral JSON vectors for days, events, state and refresh plans in
  `Vectors/`, written from the RFC before the implementation and checked independently.
- **MosqueBoard**, an iPad example that shows MUIS's 2026 Singapore timetable and a synthetic
  Edinburgh one, with iqama, coverage banners, Isha after midnight, clock changes and Arabic,
  and XCUITest journeys for each.
- CI for macOS, Linux, both default-isolation settings, lint and MosqueBoard; documentation
  published to GitHub Pages.
