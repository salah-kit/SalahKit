# SalahKit

Swift packages for building prayer-time apps on Apple platforms: a typed prayer schedule with honest coverage, from calculated times or published timetables with iqama, and the words and numbers to show them.

[![CI](https://github.com/salah-kit/SalahKit/actions/workflows/ci.yml/badge.svg)](https://github.com/salah-kit/SalahKit/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/salah-kit/SalahKit?include_prereleases&sort=semver)](https://github.com/salah-kit/SalahKit/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## What it is

SalahKit is the app layer of the [salah-kit](https://github.com/salah-kit) ecosystem. Settings or published timetable data go in; typed prayer events with explicit coverage come out. An app, a widget or a watch complication can build the schedule from data it has locally, and ask it bounded questions: a day, the events in a range, the state at a moment, or when a widget needs its next entry.

| Product | What it gives an app |
|---|---|
| **SalahCore** | The schedule model and the `PrayerSource` contract; `TimetableSource` for published times, with wall-time resolution around clock changes; optional iqama rules; the prayer state at any moment; refresh planning; prayer names in a String Catalog; duration, numbering and Hijri formatting on Foundation |
| **SalahCalculation** | Calculated times from [SalahTimes](https://github.com/salah-kit/SalahTimes) as a `PrayerSource`: `CalculationSettings` carries every calculation parameter to the engine unchanged, `CalculationSource` reports a time it can't calculate (a polar summer's Isha) as missing instead of guessing, and `CalculationMethod.suggested(for:)` offers a sourced starting method |
| **SalahFixtures** | Ready-made timetables and moments for previews and tests |

SalahKit never invents a time. A timetable that ends on 31 December, skips a day or leaves Isha blank produces a schedule that says so: the state after the last published Isha has no next prayer, and a missing day is a gap with a reason, not yesterday's times. A calculation that has no Isha in a polar summer says so too. A Friday is a date; Jumu'ah appears only where your data or your app declares it.

What it deliberately isn't:
- **Not a calculation engine.** SalahCalculation connects [SalahTimes](https://github.com/salah-kit/SalahTimes), the salah-kit engine, through `PrayerSource`. Any other engine or data feed can plug in the same way, and a timetable app that links only SalahCore never links SalahTimes.
- **No UI, notifications or location services in the core.** Words and colors live at the edges; interface text other than prayer names belongs to your app.
- **No adhan recordings.** Your app ships its own sounds.

## Installation

Add the package with Swift Package Manager:

```swift
dependencies: [
  .package(url: "https://github.com/salah-kit/SalahKit.git", from: "0.1.0")
],
targets: [
  .target(
    name: "YourApp",
    dependencies: [
      .product(name: "SalahCore", package: "SalahKit"),
      // For calculated times. A timetable app needs only SalahCore.
      .product(name: "SalahCalculation", package: "SalahKit"),
    ])
]
```

In Xcode, choose File > Add Package Dependencies, enter `https://github.com/salah-kit/SalahKit.git`, and add the products you use. SalahCalculation brings SalahTimes along; `import SalahTimes` where your code names a method or another calculation rule.

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
  let clock = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)
  for event in day.events {
    print(event.kind, event.time.formatted(clock))
  }
}
```

`CalculationSettings` holds SalahTimes' parameters whole: change any angle, the madhab, the high-latitude rule, rounding or the minutes on `settings.parameters`. `Examples/CalculatedPhone` is a complete iPhone app built this way, with settings for every parameter, the state across midnight, and polar days shown as they are.

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

`Examples/MosqueBoard` is a complete iPad app built this way, with a real published timetable, overnight times, a clock change and declared Jumu'ah.

## Documentation

The DocC documentation is at <https://salah-kit.github.io/SalahKit/>. Start with "A calculated prayer app with Core and Calculation" or "Using a mosque timetable with iqama and incomplete coverage". The design and its contracts are in [RFC 0001](docs/rfcs/0001-core.md) (SalahCore) and [RFC 0002](docs/rfcs/0002-calculation.md) (SalahCalculation); the behavior every implementation must reproduce is in [`Vectors/`](Vectors/README.md). [`docs/calculation-parity.md`](docs/calculation-parity.md) compares SalahCalculation with the times Salah computed with adhan-swift.

## Supported platforms

- iOS 16, macOS 13, watchOS 9, tvOS 16 and visionOS 1 or later.
- Linux: SalahCore, SalahCalculation and SalahFixtures build and pass their tests on Ubuntu with Swift 6.2 or later.
- Swift 6.2 or later (Xcode 26 or later), in Swift 6 language mode. The API is `nonisolated` and `Sendable`, so it works the same in modules that default to `MainActor` isolation.

## Status and versioning

SalahKit is pre-1.0 and follows [Semantic Versioning](https://semver.org). Until 1.0, a minor release may change the API; every change goes through an RFC in [`docs/rfcs/`](docs/rfcs/) and is listed in [CHANGELOG.md](CHANGELOG.md). Version 1.0 waits for two shipped apps that differ in platform and data source, at least one maintained outside this organization, and for native-speaker review of the prayer names.

Prayer names come from a String Catalog seeded from the Salah app. English, Arabic and French are reviewed; Urdu, Persian, Bengali, Turkish, Indonesian and Malay are marked `needs_review` until a native speaker checks them. Corrections are welcome.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The org-wide code of conduct and security policy live in [salah-kit/.github](https://github.com/salah-kit/.github).

## License

MIT. See [LICENSE](LICENSE). Third-party data in the examples is listed in [NOTICE](NOTICE).
