# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-10-14

Widgets that build their own timelines, SwiftUI building blocks you restyle, and prayer
alerts within the system's notification limit, each with working examples.

### Added

- **SalahWidgets**, specified in [RFC 0004](docs/rfcs/0004-widgets-and-ui.md): widget timelines
  that the widget extension builds by itself from shared inputs.
  - `SharedValue` keeps a `Codable` value in an App Group and asks WidgetKit to reload only when
    the stored value changed; it throws instead of silently dropping a value it can't encode,
    and takes an injected reloader for tests.
  - `PrayerTimelineBuilder` turns a schedule's refresh plan into a bounded 48-hour timeline that
    ends with an explicit `.expired(knownThrough:)` entry and reloads halfway; `PrayerTimeline`
    exposes the entries, `validUntil`, `isTruncated` and the reload date, and the WidgetKit
    `Timeline` is built from it.
  - `DarwinSignal` signals a running app from a widget's App Intent, with an observation that
    stops delivery on cancel or release.
  - A privacy manifest declaring App Group `UserDefaults` access (`1C8F.1`).
  - The DocC article "Building widget timelines without daily app launches".
- **SalahUI**, specified in [RFC 0004](docs/rfcs/0004-widgets-and-ui.md): SwiftUI building
  blocks with styles you replace.
  - `PrayerTimesList`, `NextPrayerView` and `PrayerCountdown` (live or static): times in the
    schedule's zone, statuses and countdowns only where the state knows them, day offsets for
    times after or before midnight.
  - `PrayerRowStyle` and `NextPrayerStyle` with `PlainPrayerRowStyle` and
    `PlainNextPrayerStyle` defaults that follow Dynamic Type and mirror right to left.
  - `ThemeColor` and `ContrastCheck`, Salah's WCAG contrast and reserved-color guardrails.
  - Previews of every component at every SalahFixtures moment, and snapshot tests of the
    default styles in English and Arabic.
  - The DocC article "Styling rows and cards".
- **SalahAlerts**, specified in [RFC 0003](docs/rfcs/0003-alerts.md): prayer alerts within the
  system's notification limit.
  - `AlertPlanner` plans every enabled alert of a range from a `PrayerSchedule` and per-prayer
    `AlertSettings` (at the prayer's time, a reminder before, a reminder after, each with its
    sound), moves source gaps by each kind's offset, and selects a `NotificationPlan` within an
    `AlertBudget`: every alert of the next two days, then prayer-time alerts, nearest first.
    `coveredUntil` and `coverageByKind` say until when the plan is complete.
  - `NotificationScheduler` installs a plan under stable identifiers (namespace, owning day,
    prayer, kind), replaces changed requests by adding them, removes only its own obsolete
    ones, serializes overlapping calls toward the latest plan, and reports what the read-back
    confirmed (`NotificationApplyReport`). `deliver` posts due alerts a plan left out.
  - `InProcessAlertEngine` follows the whole schedule in a running app, catches up after sleep
    (five minutes at prayer time, two for reminders), never fires a before-reminder after its
    prayer has begun, reports each occurrence once, and offers the default audio precedence.
  - The DocC article "Alerts within the 64-notification limit".
- **Vectors**: 60 alert-planning vectors in `Vectors/alerts/` and 60 scheduler vectors in
  `Vectors/reconciliation/`, against a modelled notification center, written from RFC 0003 and
  reviewed independently before the implementation.
- **CalculatedPhone** schedules prayer alerts through SalahAlerts: alerts and a reminder in
  Settings, an Alerts card that shows the pending requests read back and until when they're
  confirmed, and an XCUITest journey that allows notifications through Springboard, watches an
  alert arrive with the app closed, and reads the requests back after a time change and an
  injected failure.
- **Examples/PhoneWidgets**, an iPhone app and widget extension sharing an App Group, with a
  calculated source: Home Screen and Lock Screen widgets with a live countdown, setup-required,
  partial, unavailable and expired views in English and Arabic, a log of every timeline the
  extension builds (for a device soak), fixed-clock tests over seven days of timelines, and
  journeys that add the widget to the Home Screen and check the catalog lookup and reload
  gating in the real extension.
- **Examples/WatchComplication**, a watch app and complication with a companion iPhone app that
  sends calculated or published inputs over WatchConnectivity: the watch keeps its own copy,
  shows missing-settings, ended-timetable and expired views, and keeps working with the iPhone
  app closed; checked on a paired iPhone and Watch simulator pair.
- **CI** for PhoneWidgets and WatchComplication (generation check, both isolation builds, unit
  tests, and the journeys that hosted runners can run), a MainActor-isolation build on macOS,
  SalahUI's snapshots rendered again at UTC+14, and documentation for all six modules.

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
  calculation parameter on screen; settings for the place, the method or a custom method's Fajr
  angle, Isha rule and night span, the madhab, the high-latitude rule, rounding, Ramadan's Isha
  and the user's minutes; the schedule and state across midnight; and polar days and invalid
  locations shown as they are, with XCUITest journeys for each.
- CI for macOS, Linux, both default-isolation settings, lint, MosqueBoard (including a check
  that it links no calculation code) and CalculatedPhone; documentation published to GitHub
  Pages.

[Unreleased]: https://github.com/salah-kit/SalahKit/compare/0.2.0...HEAD
[0.2.0]: https://github.com/salah-kit/SalahKit/releases/tag/0.2.0
[0.1.0]: https://github.com/salah-kit/SalahKit/releases/tag/0.1.0
