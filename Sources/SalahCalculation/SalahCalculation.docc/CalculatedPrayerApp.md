# A calculated prayer app with Core and Calculation

Calculate prayer times with SalahTimes, show them across midnight, let your users change every
parameter, and say plainly when a time can't be calculated.

## Overview

Most prayer apps calculate their times from the user's location and a method. SalahCalculation
connects SalahTimes, the salah-kit calculation engine, to SalahCore: ``CalculationSource`` is a
`PrayerSource`, so a calculated app asks a `PrayerSchedule` the same questions a timetable app
does, and gets answers with the same owning days, coverage and state.

The source never invents a time. Where the Sun doesn't set, or a method's rules put two prayers
at the same instant, the kind is missing with a reason, and the state stops naming a current or
next prayer across the gap.

### Add the package

Link the `SalahCore` and `SalahCalculation` products of the SalahKit package. SalahKit brings
SalahTimes along; import it too when your code names a method, a madhab or another calculation
rule.

### Choose the settings

``CalculationSettings`` holds SalahTimes' `CalculationParameters` whole. Start from a published
method and change what your users change:

```swift
var settings = CalculationSettings(method: .muslimWorldLeague, madhab: .hanafi)
settings.parameters.highLatitudeRule = .seventhOfTheNight
settings.parameters.adjustments.isha = 2
```

Every control SalahTimes has stays available: the Fajr, Maghrib and Isha rules, the madhab, the
high-latitude rule, the method's and the user's minutes, rounding and the night span.
``CalculationSource`` passes them to SalahTimes exactly as they are.

The opt-ins are off until you choose them. `CalculationMethod.suggested(for:)`
suggests a method from the location's country, as a starting point your users can change:

```swift
guard let zone = TimeZone(identifier: "Asia/Riyadh") else { return }
let location = PrayerLocation(
  latitude: 21.4225, longitude: 39.8262, timeZone: zone, countryCode: "SA", name: "Makkah")

let method = CalculationMethod.suggested(for: location) ?? .muslimWorldLeague  // .ummAlQura
let makkah = CalculationSettings(
  method: method, ramadanIsha: .interval(minutes: 120, hijriDayOffset: 0))
```

The Ramadan rule replaces Umm al-Qura's 90-minute Isha with 120 minutes on days in Ramadan, as
the Umm al-Qura calendar prints it; many mosques don't, so it's the user's choice.

Settings are `Codable`. Keep them with the location in your app's settings or an App Group, so a
widget extension can build the same schedule:

```swift
let saved = try JSONEncoder().encode(makkah)
let restored = try JSONDecoder().decode(CalculationSettings.self, from: saved)
```

### Build the schedule

```swift
let schedule = PrayerSchedule(source: CalculationSource(restored), location: location)
```

That's the whole integration. The rest of SalahCore works as it does for a published timetable:
`PrayerSchedule.day(_:)` for a day's events, `PrayerSchedule.state(at:through:policy:)`
for what's happening now, and `PrayerSchedule.refreshPlan(from:through:strategy:policy:limit:)`
for a widget's timeline.

### Show today and what's next

Format times in the location's time zone, and ask for the state with a bound: two days ahead
always reaches the next prayer.

```swift
let names = PrayerNames(locale: Locale(identifier: "en_GB"))
let clock = Date.FormatStyle(
  date: .omitted, time: .shortened, locale: names.locale, timeZone: location.timeZone)

func headline(at now: Date) -> String {
  switch schedule.state(at: now, through: now.addingTimeInterval(2 * 86_400)) {
  case .available(let state, _):
    guard let next = state.nextPrayer else { return "The next prayer can't be calculated" }
    let remaining = PrayerDurationFormat.string(
      next.time.timeIntervalSince(now), locale: names.locale)
    return "\(names.name(of: next)) at \(next.time.formatted(clock)), in \(remaining)"
  case .unavailable:
    return "Prayer times can't be calculated here now"
  }
}
```

### Across midnight

A calculated event belongs to the day it was calculated for, its owning day, even when it
happens on a neighboring date:

- Where a place's clock runs far ahead of the Sun, or in a high-latitude summer, Isha comes after
  midnight. Kashgar keeps Beijing time, so on 21 June 2026 its Isha is at 00:19 on 22 June. It
  belongs to 21 June, and it's the next prayer at 00:05 on 22 June.
- Where the clock runs behind the Sun, a Fajr bounded by the middle of the night comes before
  midnight. In Kazan, under that rule, 21 June's Fajr is at 23:45 on 20 June.

A day lists its own events, wherever they fall. Mark the ones on another date, so a reader isn't
surprised by an Isha at 00:19 under 21 June:

```swift
func row(_ event: PrayerEvent) -> String {
  let date = CivilDay(containing: event.time, in: location.timeZone)
  var note = ""
  if date > event.scheduleDay { note = " (next day)" }
  if date < event.scheduleDay { note = " (previous evening)" }
  return "\(names.name(of: event)) \(event.time.formatted(clock))\(note)"
}
```

The state follows instants, not dates, so after midnight the latest prayer can belong to the day
before, and before midnight the next one can belong to the day after. Check
`PrayerEvent.scheduleDay` when your screen names a day.

### When a time can't be calculated

Some days have no time for some prayers:
- In a polar summer the Sun doesn't set, so there's no sunrise, Maghrib or Isha, and with no
  night there's no Fajr; in a polar winter it doesn't rise.
- With `HighLatitudeRule.disabled`, a twilight angle the Sun never reaches leaves
  Fajr or Isha without a time.
- A method's rules can put two prayers at the same instant, or an interval Isha after the next
  day's Fajr near the polar circles. SalahCore needs strict order, so the later one is missing.

Each such kind is missing with `ScheduleGapReason.calculationUnavailable`. Coordinates or
parameters SalahTimes rejects make the day unavailable with `invalidData`. Show the reason
instead of a time:

```swift
func lines(for day: CivilDay) -> [String] {
  switch schedule.day(day) {
  case .available(let prayerDay, let coverage):
    var missing: [PrayerKind: ScheduleGapReason] = [:]
    if case .partial(let kinds) = coverage { missing = kinds }
    return PrayerKind.allCases.map { kind in
      if let event = prayerDay[kind] { return row(event) }
      let reason = missing[kind] == .invalidData ? "invalid input" : "can't be calculated"
      return "\(names.name(of: kind)): \(reason)"
    }
  case .unavailable(let reason):
    return ["No prayer times for this day (\(reason))"]
  }
}
```

In Tromsø on 21 June 2026 that gives Dhuhr and Asr, and "can't be calculated" for the other
four. Don't fill the gap with yesterday's times or another method's: the state already tells your
users what's known.

### Jumu'ah and iqama are your app's policy

A calculated Friday has an ordinary Dhuhr: SalahCalculation never declares Jumu'ah, because a
weekday isn't a congregation. If your app holds Jumu'ah, declare it in a small source that wraps
the calculated one. Pass the wrapped source's expected kinds and lead through, so its early
Fajr stays valid:

```swift
nonisolated struct FridayJumuah: PrayerSource {
  let base: CalculationSource

  var expectedKinds: Set<PrayerKind> { base.expectedKinds }
  var maximumLead: Duration { base.maximumLead }

  func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability {
    let availability = base.prayerDay(day, at: location)
    guard day.weekday == 6, case .available(var prayerDay, let coverage) = availability else {
      return availability
    }
    prayerDay.events = prayerDay.events.map { event in
      var event = event
      if event.kind == .dhuhr { event.observance = .jumuah }
      return event
    }
    return .available(prayerDay, coverage: coverage)
  }
}
```

Congregation times come from the mosque, through `IqamaRules`:

```swift
let mosque = PrayerSchedule(
  source: FridayJumuah(base: CalculationSource(restored)), location: location,
  iqama: IqamaRules(
    rules: [.fajr: .after(minutes: 20), .isha: .after(minutes: 15)],
    jumuah: .at(WallClockTime(hour: 12, minute: 45))))
```

### Calculate off the main actor

Every type is `nonisolated` and `Sendable`, and a calculation takes microseconds, so a widget
extension's timeline provider or a background task can build a schedule from the saved settings
and ask it for a refresh plan directly. Declare your own wrapping sources `nonisolated`, as
above, when your module defaults to the main actor.

### See it in an app

`Examples/CalculatedPhone` in the SalahKit repository is an iPhone app built this way, with
settings for every parameter, the state across midnight, and polar days shown as they are.
