# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- `PrayerLocale.resolved` follows CLDR's default digits for the country an Arabic identifier
  names: `ar-AE`, `ar-DZ`, `ar-EH`, `ar-LY`, `ar-MA` and `ar-TN` now get Latin digits instead of
  Arabic-Indic ones. A bare `ar` and every other Arabic region keep Arabic-Indic digits, and an
  explicit numbering system still wins, such as `ar-MA-u-nu-arab`
  ([RFC 0001](docs/rfcs/0001-core.md), §10.4;
  [#42](https://github.com/salah-kit/SalahKit/issues/42)).

### Fixed

- `PrayerLocale.resolved` gives back an identifier or a locale that names its digits in a BCP 47
  extension, such as `ar-MA-u-nu-arab` or `bn-u-nu-beng`, rebuilt in ICU form
  (`ar_MA@numbers=arab`) on every platform, and one in ICU form unchanged. Foundation on macOS 27
  drops a `-u-nu-` value that matches the language's script when it parses the identifier, which
  left a locale that formatted no digits, and on Linux `NumberFormatter` crashes on a locale made
  from a `-u-nu-` identifier. A `Locale` already made on macOS 27 from an identifier whose
  `-u-nu-` value matches the script has lost the value; build it with `Locale.Components` or
  `@numbers=` instead.

## [0.4.1] - 2026-10-23

### Fixed

- The English name of Friday's congregational prayer is "Jumu’ah", with its apostrophe, in
  `PrayerNames` and the catalog.
- MenuBar's medium widget keeps its full prayer list and Stop control within the widget while
  a tone plays ([#59](https://github.com/salah-kit/SalahKit/issues/59)).
- `PrayerLocale.resolved` takes an explicit numbering system from the `nu` key of an
  identifier's Unicode (`-u-`) extension or an `@numbers=` keyword, and no longer from a `nu`
  subtag in a private-use (`-x-`) or transformed (`-t-`) part. `ar-u-ca-islamic-x-nu-latn` now
  gets Arabic-Indic digits, as `ar-u-ca-islamic` does
  ([#54](https://github.com/salah-kit/SalahKit/issues/54)).
- The examples keep their words whole at the largest text sizes. CalculatedPhone stacks a row,
  the next prayer or the latest prayer that doesn't fit on one line
  ([#50](https://github.com/salah-kit/SalahKit/issues/50)). MosqueBoard's iPad board stacks
  each row's name, times and status at the accessibility sizes, puts the next-prayer panel
  above the table and the clock below the mosque's name when they don't fit
  ([#51](https://github.com/salah-kit/SalahKit/issues/51)). PhoneWidgets' Widget states screen
  and preview draw the widgets at the largest text size WidgetKit uses, so they look as the
  real widgets do ([#52](https://github.com/salah-kit/SalahKit/issues/52)).
- The examples' VoiceOver labels read once, in words and in reading order
  ([#53](https://github.com/salah-kit/SalahKit/issues/53)). CalculatedPhone reads each
  calculation parameter's title once, minutes in words, a stepper's name and value once each,
  and "Latest prayer" as a header. MosqueBoard labels the sunrise's empty iqama "No iqama" and
  reads each row's times before its status, and in landscape the table and the next-prayer
  panel each in one piece.
  PhoneWidgets' countdowns say "Time remaining", the medium widget reads its card before its
  list, Arabic labels use the Arabic comma, the circular widget reads "Next prayer unknown"
  instead of "–, Unknown", and the notices' symbols are hidden from VoiceOver.
- MenuBar no longer loses the banner of an alert that came due during a sleep when the engine's
  wake-up reports it before the app sees the wake notification. A report more than a second late
  now replans first, so `deliver` still runs after an `apply` planned from after the alert, and
  the article on the notification limit says to do the same
  ([#45](https://github.com/salah-kit/SalahKit/issues/45)).
- `docs/calculation-parity.md` is now a guide for apps moving from adhan-swift: how its settings
  map onto `CalculationSettings`, which times change and why, and which an app must show as
  missing, with Salah's Ramadan, tie and country-table choices as an example of app policy.
- MosqueBoard's synthetic summer timetable is identified as a day-offset test fixture rather
  than evidence of a real Scottish mosque's practice, with links to a primary comparison.
  The MUIS notes record the confirmed SODL distribution grant and date interpretation.
- CalculatedPhone's README now describes its shipped alert settings, launch arguments and
  notification journey, and lists all linked SalahKit products. Its and MosqueBoard's
  contrast notes document the retained semantic-color policy and its body-text contrast limit.
- DocC comments describe SalahUI's public view and style implementations and the preview
  galleries' view bodies.
- The README explains the examples' naming and platform differences, the original Core and
  Calculation RFCs identify their shipped status, and MenuBar's pending device checks can be
  followed from a standalone clone.
- The RFCs state their design decisions and their reasons directly, and the vectors' notes cite
  the RFC section behind each expectation; no input or expected output changed.
- The examples' pending device and language checks link the help-wanted issues that give their
  steps, and CONTRIBUTING describes how the vectors are regenerated and how a release is made.

## [0.4.0] - 2026-10-14

### Added

- `PrayerTimesList(missing:)` includes missing expected kinds in canonical order, with their
  gap reasons. Its `rows` view places rows directly in an app's own stack. CalculatedPhone
  adopts it for partial calculated days.
- `PrayerFocus` and `NextPrayerView(selection:)` select the next prayer, the next event
  including sunrise, or a just-started count-up before either. Styles receive the selected
  focus and elapsed text; MenuBar uses the same selection for its title and cards.
- `PrayerTimelineBuilder(includeDayBoundaries:)` adds civil-day starts within the timeline's
  entry budget. PhoneWidgets and MenuBar use it so day lists turn over at midnight.
- `InProcessAlertEngine.excludeHandledOccurrencesFromNotifications()`,
  `notificationExclusions(at:)` and the planner's `excluding:` input let an app avoid
  requesting an alert again after its clock moves back, including on later refreshes.

### Changed

- **Style migration:** `PrayerRowConfiguration.event` and `time` are optional. Use `kind`
  for every row, handle `gapReason` on missing rows, and unwrap the event before reading its
  time or observance. Known-only lists keep their existing order and appearance.
- Handled alerts are retained in memory for one day after they were reported, or longer
  for a longer catch-up grace. The planner excludes the supplied exact occurrence set.
  The engine retains clock-change exclusions alongside that record; MenuBar uses them on
  every replan. Normal early reports keep their pending system requests.

### Fixed

- An always-running alert consumer can now replan after a clock reversal without requesting
  the same handled occurrence again within retention. A changed fire date remains eligible.
- Documentation and example clock text use the locale's short time format, matching SalahUI's
  leading zero in 24-hour locales.

## [0.3.0] - 2026-10-14

An always-running macOS example whose desktop widget stops the app's tone, MosqueBoard on
Apple TV, the article "Lessons from Salah", and the RFC process. The public API is unchanged.

### Added

- **Examples/MenuBar**, a macOS menu-bar app that keeps running: the next prayer in the menu
  bar, refreshed at the dates of a `.steps` refresh plan; prayer alerts with
  `InProcessAlertEngine` following the uncapped `AlertSchedule`, `NotificationScheduler`
  installing the budgeted `NotificationPlan`, and the engine's default audio precedence for a
  generated tone; catch-up and replanning after a wake, a clock change and a time zone change;
  and a desktop widget whose Stop button follows the live-state pattern: the intent clears the
  shared value and posts a `DarwinSignal`, and the app acts on the signal and republishes.
  `MenuBarStopHarness`, signed and sandboxed like the widget extension, runs the intent's own
  code in a separate process against the running app, which covers the cross-process stop
  round trip that 0.2.0 left pending; a real tap on the desktop widget, and real sleep and
  wake, are still to observe. Unit tests with a manual clock and injected notification
  centers, round-trip tests that start the app and the harness, and XCUITest journeys on the
  Mac.
- **MosqueBoard for tvOS** (`MosqueBoardTV`, tvOS 17): the same board on a mosque's Apple TV,
  built from the iPad app's shared code. It links only SalahCore, fits the whole board inside
  the TV's safe area and keeps the screen saver off. Its unit tests and journeys (a normal day,
  Jumu'ah, the expired timetable, Isha after midnight, a partial row, Arabic, and the tallest
  board, from Isha to its iqama) run on an Apple TV simulator.
- The DocC article "Lessons from Salah": acting on the Darwin signal instead of the stored
  flag, reloading widgets only for real changes, and keeping the language's digits.
- Governance: an RFC process in CONTRIBUTING.md, a GitHub Discussion for each RFC, and
  CODEOWNERS for each product.
- `.spi.yml`, which points the Swift Package Index to the documentation on GitHub Pages.
- CI for MenuBar (the generation check, both isolation builds, the unit tests, the round
  trip and the journeys, unsigned) and for MosqueBoard on tvOS (both isolation builds, the
  check that it links no calculation code, and its tests on an Apple TV simulator).

### Changed

- MosqueBoard's code, String Catalog and timetables moved to `Examples/MosqueBoard/Shared`,
  which the iPad and tvOS apps both compile.
- RFC 0003 and RFC 0004 record MenuBar's evidence and findings, and every RFC links its
  discussion.
- "Alerts within the 64-notification limit" says to deliver the engine's alerts after the
  `apply` of a replan made at the same moment: otherwise a caught-up alert whose request is
  still pending can lose its notification.
- The stop signal's declaration in "Building widget timelines" is `nonisolated`, so an intent
  that isn't on the main actor can post it in a module that defaults to the main actor.

### Fixed

- SalahUI writes times in the locale's own short time format, as its documentation says: in
  24-hour locales such as French, Turkish and Indonesian, the hour keeps its leading zero
  ("04:11", not "4:11") ([#11](https://github.com/salah-kit/SalahKit/issues/11)).
- `docs/calculation-parity.md` names adhan-swift 1.5.0 as the version compared, and 1.4.0 as
  the one Salah pinned ([#15](https://github.com/salah-kit/SalahKit/issues/15)).

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
  `Vectors/reconciliation/`, against a modelled notification center, generated from a model of
  RFC 0003 and checked as its section 7 describes.
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
  `Vectors/`, written from the RFC before the implementation and recomputed with a separate
  model, and calculation vectors in `Vectors/calculation/` with instants from SalahTimes'
  independent reference implementation. SalahTimes' own vectors also run through the adapter.
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

[Unreleased]: https://github.com/salah-kit/SalahKit/compare/0.4.1...HEAD
[0.4.1]: https://github.com/salah-kit/SalahKit/compare/0.4.0...0.4.1
[0.4.0]: https://github.com/salah-kit/SalahKit/compare/0.3.0...0.4.0
[0.3.0]: https://github.com/salah-kit/SalahKit/releases/tag/0.3.0
[0.2.0]: https://github.com/salah-kit/SalahKit/releases/tag/0.2.0
[0.1.0]: https://github.com/salah-kit/SalahKit/releases/tag/0.1.0
