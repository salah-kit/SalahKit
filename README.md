# SalahKit

Swift packages for building prayer-time apps on Apple platforms: a typed prayer schedule with honest coverage, from calculated times or published timetables with iqama, the words and numbers to show them, widget timelines that don't need the app to run, SwiftUI building blocks you restyle, and prayer alerts that fit the system's notification limit.

[![CI](https://github.com/salah-kit/SalahKit/actions/workflows/ci.yml/badge.svg)](https://github.com/salah-kit/SalahKit/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/salah-kit/SalahKit?include_prereleases&sort=semver)](https://github.com/salah-kit/SalahKit/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## What it is

SalahKit is the app layer of the [salah-kit](https://github.com/salah-kit) ecosystem. Settings or published timetable data go in; typed prayer events with explicit coverage come out. An app, a widget or a watch complication can build the schedule from data it has locally, and ask it bounded questions: a day, the events in a range, the state at a moment, or when a widget needs its next entry.

| Product | What it gives an app |
|---|---|
| **SalahCore** | The schedule model and the `PrayerSource` contract; `TimetableSource` for published times, with wall-time resolution around clock changes; optional iqama rules; the prayer state at any moment; refresh planning; prayer names in a String Catalog; duration, numbering and Hijri formatting on Foundation |
| **SalahCalculation** | Calculated times from [SalahTimes](https://github.com/salah-kit/SalahTimes) as a `PrayerSource`: `CalculationSettings` carries every calculation parameter to the engine unchanged, `CalculationSource` reports a time it can't calculate (a polar summer's Isha) as missing instead of guessing, and `CalculationMethod.suggested(for:)` offers a sourced starting method |
| **SalahWidgets** | Widget timelines the extension builds by itself from shared inputs: `SharedValue` keeps a `Codable` value in an App Group and reloads widgets only when it changed, `PrayerTimelineBuilder` turns a schedule into a bounded timeline that ends with an explicit expired entry, and `DarwinSignal` reaches a running app from a widget's button |
| **SalahUI** | SwiftUI components (`PrayerTimesList`, `NextPrayerView`, `PrayerCountdown`) that decide what to show, with row and next-prayer styles you replace; `ThemeColor` and `ContrastCheck` for checking a theme's colors |
| **SalahFixtures** | Ready-made timetables and moments for previews and tests |
| **SalahAlerts** | Prayer alerts: `AlertPlanner` plans every alert of a range and selects the requests that fit an app's notification budget, two complete days first; `NotificationScheduler` installs them under stable identifiers and reports what it confirmed; `InProcessAlertEngine` follows every alert in a running app, with catch-up after sleep |

SalahKit never invents a time. A timetable that ends on 31 December, skips a day or leaves Isha blank produces a schedule that says so: the state after the last published Isha has no next prayer, and a missing day is a gap with a reason, not yesterday's times. A calculation that has no Isha in a polar summer says so too. A Friday is a date; Jumu'ah appears only where your data or your app declares it.

What it deliberately isn't:
- **Not a calculation engine.** SalahCalculation connects [SalahTimes](https://github.com/salah-kit/SalahTimes), the salah-kit engine, through `PrayerSource`. Any other engine or data feed can plug in the same way, and a timetable app that links only SalahCore never links SalahTimes.
- **No UI, notifications or location services in the core.** Words and colors live at the edges: SalahUI's components come with plain styles that you replace, and interface text other than prayer names belongs to your app. SalahAlerts plans and installs alerts, but your app asks for notification permission, writes the alerts' text and plays their sounds.
- **No adhan recordings.** Your app ships its own sounds.

## Installation

Add the package with Swift Package Manager:

```swift
dependencies: [
  .package(url: "https://github.com/salah-kit/SalahKit.git", from: "0.4.0"),
  // For calculated times, when your code names a method or another calculation rule.
  .package(url: "https://github.com/salah-kit/SalahTimes.git", .upToNextMinor(from: "0.1.0")),
],
targets: [
  .target(
    name: "YourApp",
    dependencies: [
      .product(name: "SalahCore", package: "SalahKit"),
      // For calculated times. A timetable app needs only SalahCore.
      .product(name: "SalahCalculation", package: "SalahKit"),
      // For prayer alerts.
      .product(name: "SalahAlerts", package: "SalahKit"),
      .product(name: "SalahTimes", package: "SalahTimes"),
      // For widget timelines and SwiftUI views.
      .product(name: "SalahWidgets", package: "SalahKit"),
      .product(name: "SalahUI", package: "SalahKit"),
    ])
]
```

SalahCalculation doesn't re-export SalahTimes, so a package that writes `import SalahTimes` lists it, as above, in the range SalahKit uses. In Xcode, choose File > Add Package Dependencies, enter `https://github.com/salah-kit/SalahKit.git`, and add the products you use; SalahCalculation brings the SalahTimes module along, so an app target can `import SalahTimes` without adding it.

## Quick start

### Calculated times

Today's prayer times in Istanbul, calculated with the method SalahTimes suggests for Turkey:

```swift
import Foundation
import SalahCalculation
import SalahCore
import SalahTimes

guard let zone = TimeZone(identifier: "Europe/Istanbul") else { return }
let istanbul = PrayerLocation(
  latitude: 41.0082, longitude: 28.9784, timeZone: zone, countryCode: "TR", name: "Istanbul")

// Diyanet's method, which SalahTimes suggests for Turkey, with Hanafi Asr.
let settings = CalculationSettings(
  method: CalculationMethod.suggested(for: istanbul) ?? .muslimWorldLeague, madhab: .hanafi)
let schedule = PrayerSchedule(source: CalculationSource(settings), location: istanbul)

let today = CivilDay(containing: Date(), in: zone)
if case .available(let day, _) = schedule.day(today) {
  let clock = DateFormatter()
  clock.locale = .current
  clock.calendar = Calendar.current
  clock.timeZone = zone
  clock.dateStyle = .none
  clock.timeStyle = .short
  for event in day.events {
    print(event.kind, clock.string(from: event.time))
  }
}
```

`CalculationSettings` holds SalahTimes' parameters whole: change any angle, the madhab, the high-latitude rule, rounding or the minutes on `settings.parameters`. `Examples/CalculatedPhone` is a complete iPhone app built this way. It shows every parameter behind its times and has settings for the place, the method or a custom method's Fajr angle, Isha rule and night span, the madhab, the high-latitude rule, rounding, Ramadan's Isha and the user's minutes. It shows the state across midnight, and polar days as they are.

### A published timetable

A mosque board that runs on its published timetable:

```swift
import Foundation
import SalahCore

// Published times, as JSON your app downloaded or bundled (see TimetableSource).
let source = try JSONDecoder().decode(TimetableSource.self, from: timetableJSON)

guard let zone = TimeZone(identifier: "Asia/Singapore") else { return }
let location = PrayerLocation(latitude: 1.3521, longitude: 103.8198, timeZone: zone)

// The mosque's own iqama times, where the timetable publishes none.
let iqama = IqamaRules(
  rules: [.fajr: .after(minutes: 20), .dhuhr: .after(minutes: 10), .isha: .after(minutes: 10)],
  jumuah: .at(WallClockTime(hour: 13, minute: 15)))

let schedule = PrayerSchedule(source: source, location: location, iqama: iqama)
let names = PrayerNames(locale: PrayerLocale.resolved("ar"))
let now = Date()

switch schedule.state(at: now, through: now.addingTimeInterval(2 * 86_400)) {
case .available(let state, _):
  if let next = state.nextPrayer {
    let remaining = PrayerDurationFormat.string(
      next.time.timeIntervalSince(now), locale: names.locale)
    print("\(names.name(of: next)) in \(remaining)")
  } else {
    print("The next prayer isn't published yet.")
  }
case .unavailable(let coverage, _):
  print("No published times here:", coverage.gaps.map(\.reason))
}
```

`Examples/MosqueBoard` is a complete iPad and Apple TV app built this way, from one shared codebase, with a real published timetable, overnight times, a clock change and declared Jumu'ah.

### Prayer alerts

Two weeks of alerts, with a reminder ten minutes before each prayer, on any `PrayerSchedule`:

```swift
import SalahAlerts
import UserNotifications

let planner = AlertPlanner()
let now = Date()
let alerts = try planner.schedule(
  schedule, namespace: "prayers", from: now, to: now.addingTimeInterval(14 * 86_400),
  settings: { subject in
    subject.prayer.isPrayer ? AlertSettings(before: .seconds(10 * 60)) : nil
  })
let plan = planner.notificationPlan(alerts, from: now)

let scheduler = NotificationScheduler(
  identifierPrefix: "com.example.prayers.", namespace: "prayers")
let report = try await scheduler.apply(plan) { alert in
  let content = UNMutableNotificationContent()
  content.title = PrayerNames(locale: Locale(identifier: "en")).name(of: alert.event)
  content.sound = alert.sound.notificationSound
  return content
}
print("Alerts confirmed until", report.confirmedCoveredUntil ?? now)
```

iOS keeps a limited number of pending notification requests per app, so the plan spends a budget (60 by default): every alert of the next two days, then prayer-time alerts as far as the budget reaches. The plan and the report say until when the alerts are complete; a missing prayer time, a failed request or denied permission shortens that, and nothing is invented. Ask for notification permission yourself, and replan when your app launches or becomes active and when the settings change. An always-running app also gives the whole schedule to `InProcessAlertEngine`, which reports every alert when it's due, reminders the plan left out included. `Examples/CalculatedPhone` schedules its alerts this way, and `Examples/MenuBar`, a macOS menu-bar app, also follows every alert with the engine, plays a generated tone for the alert the engine's default precedence picks, and catches up after the Mac wakes or the clock changes.

### A widget that doesn't need its app

The app saves its inputs to the App Group it shares with its widget extension, and the extension builds the schedule itself whenever WidgetKit asks, so the widget stays right on the days the app isn't opened:

```swift
import SalahCalculation
import SalahCore
import SalahWidgets

// Compiled into the app and the widget extension, which both have the App Group capability.
// nonisolated: in a target that defaults to main-actor isolation, SharedValue needs it.
nonisolated struct PrayerSettings: Codable, Equatable, Sendable {
  var location: PrayerLocation
  var calculation: CalculationSettings
}

nonisolated extension SharedValue where Value == PrayerSettings {
  static var prayers: Self {
    SharedValue(appGroup: "group.com.example.prayers", key: "settings.v1")
  }
}

// In the extension: two days of entries, ending with one that says the times ran out.
nonisolated func prayerTimeline(from now: Date) throws -> PrayerTimeline? {
  guard let settings = SharedValue.prayers.load() else { return nil }
  let schedule = PrayerSchedule(
    source: CalculationSource(settings.calculation), location: settings.location)
  return try PrayerTimelineBuilder(schedule: schedule).timeline(from: now)
}
```

The app calls `SharedValue.prayers.save(settings, reloading: ["prayers"])` when the settings change; an unchanged value reloads nothing. The article "Building widget timelines without daily app launches" shows the whole provider and the states a widget has to word. `Examples/PhoneWidgets` is an iPhone app with Home Screen and Lock Screen widgets built this way, and `Examples/WatchComplication` gives a watch complication its own copy of the inputs over WatchConnectivity. `Examples/MenuBar` has a desktop widget with a Stop button that reaches the running app through a `DarwinSignal`; the article "Lessons from Salah" says why the app acts on the signal rather than on the stored value.

For day lists, set `PrayerTimelineBuilder(includeDayBoundaries: true)` so the bounded timeline
changes at civil-day starts as well as prayer-state changes. PhoneWidgets and MenuBar use it.
An always-running alert consumer can snapshot the keys of `engine.handledOccurrences`
before resyncing after a clock change, then pass that set to
`planner.notificationPlan(_:from:budget:excluding:)`. Normal replans keep requests that are
still pending during an early engine report. MenuBar demonstrates both paths and the
scheduler/engine ordering; the handled record is retained in memory for one day.

### Your own look

SalahUI's components decide which prayer is next, which rows have passed and whether a countdown can be shown; your styles decide how they look:

```swift
import SalahUI
import SwiftUI

// The day's times with your row style. Unknown times get no status and no countdown.
PrayerTimesList(day: day, state: state, names: names)
  .prayerRowStyle(LanternRow())
```

Pass a partial day's `missing:` dictionary to `PrayerTimesList` to keep unknown kinds
visible. Its `rows` view fits an app's own stack. `NextPrayerView` accepts
`selection: .justStartedOrNextEvent` for a just-started count-up followed by the next event,
sunrise included; `PrayerFocus` shares that selection with non-view surfaces. CalculatedPhone
uses missing rows, and MenuBar uses the focus API alongside Salah.

A `PrayerRowStyle` or `NextPrayerStyle` gets ready-made text for the name, the time in the schedule's zone and the countdown, or `nil` where the schedule doesn't know. The article "Styling rows and cards" covers cards, complications, digits and right-to-left layouts, and checking colors with `ContrastCheck`.

## Documentation

The DocC documentation is at <https://salah-kit.github.io/SalahKit/>. Start with "A calculated prayer app with Core and Calculation", "Using a mosque timetable with iqama and incomplete coverage" or "Alerts within the 64-notification limit", then "Building widget timelines without daily app launches", "Styling rows and cards" and "Lessons from Salah". The design and its contracts are in [RFC 0001](docs/rfcs/0001-core.md) (SalahCore), [RFC 0002](docs/rfcs/0002-calculation.md) (SalahCalculation), [RFC 0003](docs/rfcs/0003-alerts.md) (SalahAlerts) and [RFC 0004](docs/rfcs/0004-widgets-and-ui.md) (SalahWidgets and SalahUI); the behavior every implementation must reproduce is in [`Vectors/`](Vectors/README.md). [`docs/calculation-parity.md`](docs/calculation-parity.md) compares SalahCalculation with the times Salah computed with adhan-swift.

The examples are complete apps on the public API, each with its own README, tests and CI job:

| Example | Platform | What it shows |
|---|---|---|
| [CalculatedPhone](Examples/CalculatedPhone) | iPhone | Calculated times with every parameter, the state across midnight, polar days, and alerts within the notification limit |
| [MosqueBoard](Examples/MosqueBoard) | iPad, Apple TV | A mosque's published timetable with iqama, clock changes, declared Jumu'ah and incomplete coverage, with no calculation code |
| [PhoneWidgets](Examples/PhoneWidgets) | iPhone | Home Screen and Lock Screen widgets that build their own timelines from shared inputs |
| [WatchComplication](Examples/WatchComplication) | Apple Watch, iPhone | A complication with its own copy of the inputs, which keeps working with the iPhone app closed |
| [MenuBar](Examples/MenuBar) | Mac | An app that keeps running: a menu-bar title refreshed with `.steps`, in-process alerts with a generated tone, and a desktop widget whose Stop button reaches the app |

## Supported platforms

- iOS 16, macOS 13, watchOS 9, tvOS 16 and visionOS 1 or later.
- SalahWidgets reloads widgets with WidgetKit on iOS, macOS, watchOS and visionOS 26 or later; tvOS has no widgets, so there `SharedValue` only stores values. SalahUI's components need SwiftUI.
- Linux: SalahCore, SalahCalculation and SalahFixtures build and pass their tests on Ubuntu with Swift 6.2 or later, and so do SalahAlerts' planner and in-process engine, SalahWidgets' shared values and timelines, and SalahUI's `ThemeColor` and `ContrastCheck`. `NotificationScheduler` needs UserNotifications: it's on iOS, macOS, watchOS and visionOS, and not on tvOS, whose notifications carry no text or sound.
- Swift 6.2 or later (Xcode 26 or later), in Swift 6 language mode. The API is `nonisolated` and `Sendable`, so it works the same in modules that default to `MainActor` isolation.

## Status and versioning

SalahKit is pre-1.0 and follows [Semantic Versioning](https://semver.org). Until 1.0, a minor release may change the API; every change goes through an RFC in [`docs/rfcs/`](docs/rfcs/), discussed in [GitHub Discussions](https://github.com/salah-kit/SalahKit/discussions), and is listed in [CHANGELOG.md](CHANGELOG.md). Version 1.0 waits for two shipped apps that differ in platform and data source, at least one maintained outside this organization, and for native-speaker review of the prayer names.

Prayer names come from a String Catalog seeded from the Salah app. English, Arabic and French are reviewed; Urdu, Persian, Bengali, Turkish, Indonesian and Malay are marked `needs_review` until a native speaker checks them. Corrections are welcome.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for building, testing and formatting, and for the RFC process that public API changes go through. Questions and RFC discussions are in [GitHub Discussions](https://github.com/salah-kit/SalahKit/discussions). The org-wide code of conduct and security policy live in [salah-kit/.github](https://github.com/salah-kit/.github).

## License

MIT. See [LICENSE](LICENSE). Third-party data in the examples is listed in [NOTICE](NOTICE).
