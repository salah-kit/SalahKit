# Styling rows and cards

Give prayer times your app's look by supplying styles, and keep the logic of what to show
in SalahUI.

## Overview

A prayer app's look is its own: its fonts, colors, cards and complications. What it shows is
the same in every app: the day's times, which prayer comes next, how long until it starts, and
nothing at all where the schedule doesn't know. SalahUI's components make the second part, and
styles, the way SwiftUI's `ButtonStyle` works, make the first.

### Show a day and the next prayer

Ask the schedule for a day and a state, and give them to the components with the names in the
language you show:

```swift
struct TodayView: View {
  let schedule: PrayerSchedule
  let now: Date
  let names = PrayerNames(locale: Locale(identifier: "en"))

  var body: some View {
    let zone = schedule.location.timeZone
    let bound = CivilDay(containing: now, in: zone).adding(days: 2).start(in: zone)
    let state = schedule.state(at: now, through: bound).prayerState
    VStack {
      if let state {
        NextPrayerView(state: state, names: names, timeZone: zone)
      } else {
        Text("Prayer times aren't available right now")
      }
      if let day = schedule.day(containing: now).day {
        PrayerTimesList(day: day, state: state, names: names)
      }
    }
  }
}
```

The list shows the day's events, sunrise included. Its rows know whether each event has passed,
just started, comes next or later; the next one carries a countdown. A time that falls on
another civil date than its owning day, such as an Isha after midnight, carries its offset
(`+1`). When the schedule can't establish a state, as while it's unavailable, pass `nil`: the
rows then show their times without a status or a countdown, and your own words say why.

``NextPrayerView`` needs a known state. Its style receives the next prayer's name, time and
countdown, or `nil` for each where the state doesn't know the next prayer, as after the last
published day of a timetable.

### Write a row style

A ``PrayerRowStyle`` makes one row from a ``PrayerRowConfiguration``: the event, its status,
and ready-made text for the name, the time, the day offset and the countdown.

```swift
struct LanternRow: PrayerRowStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack {
      configuration.name.font(.title3)
      Spacer()
      (configuration.time ?? Text(verbatim: "–")).monospacedDigit()
    }
    .padding(8)
    .background(
      configuration.status == .next(approaching: true) ? Color.orange.opacity(0.2) : .clear,
      in: Capsule())
  }
}
```

Apply it to a list, or to a whole screen, with ``SwiftUICore/View/prayerRowStyle(_:)``:

```swift
PrayerTimesList(day: day, state: state, names: names)
  .prayerRowStyle(LanternRow())
```

The status is `nil` when the list has no state. A style that colors rows by status should leave
such rows neutral.

### Write a card or a complication

A ``NextPrayerStyle`` makes the next-prayer view from a ``NextPrayerConfiguration``. Handle the
unknown case in your own words; never fill it with a time of your own:

```swift
struct CardStyle: NextPrayerStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if let justStarted = configuration.justStarted {
        justStarted.font(.caption).foregroundStyle(.secondary)
      }
      if let name = configuration.name, let time = configuration.time {
        HStack(alignment: .firstTextBaseline) {
          name.font(.title2.bold())
          Spacer()
          time.monospacedDigit()
        }
      } else {
        Text("The next prayer isn't known yet")
      }
      configuration.countdown?.font(.largeTitle).monospacedDigit()
    }
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}
```

A small space, such as a circular complication, takes the abbreviation instead of the name.
VoiceOver still reads the full name, because the abbreviation carries it as its label:

```swift
struct CircularStyle: NextPrayerStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(spacing: 0) {
      configuration.abbreviation ?? Text(verbatim: "–")
      configuration.countdown?.font(.caption2).monospacedDigit()
    }
  }
}
```

Apply it with ``SwiftUICore/View/nextPrayerStyle(_:)``. One style can serve every widget family,
or each family can have its own.

### Live and static countdowns

A countdown is live by default: a `Text(timerInterval:)` that SwiftUI updates every second, in a
widget too, so the widget's timeline needs an entry only where the state changes. A widget that
shows the countdown as text, such as `12m`, asks for ``PrayerCountdown/Mode/staticText`` and a
timeline with entries every minute near a prayer:

```swift
NextPrayerView(state: state, names: names, timeZone: zone, countdown: .staticText)
```

The static text is SalahCore's compact duration, always rounded down, so the screen never shows
a minute that hasn't passed. Both kinds stop at zero once the prayer has started.

### Language, digits and direction

The names come from the `PrayerNames` you pass, in their own locale; times and
countdowns use the environment's locale. Set both to the language your app shows. A bare
identifier such as `ar` can lose its native digits, so resolve it first:

```swift
let locale = PrayerLocale.resolved("ar")
NextPrayerView(state: state, names: PrayerNames(locale: locale), timeZone: zone)
  .environment(\.locale, locale)
```

The default styles mirror for right-to-left layouts, as SwiftUI's stacks do. The time zone is
always the schedule's: a Makkah timetable reads Makkah's clock on a phone set to London.

### Check your colors

``ThemeColor`` holds a color as sRGB components, and ``ContrastCheck`` applies Salah's
guardrails: a contrast of at least 3:1 against the surface, WCAG's floor for large text such as a
countdown, and a distance of at least 0.28 from the colors you reserve, such as an alert's red.
Check your palette in a unit test:

```swift
@Test func accentPassesTheContrastCheck() {
  let accent = ThemeColor(red: 0.04, green: 0.52, blue: 1.00)
  let surface = ThemeColor(red: 0.075, green: 0.094, blue: 0.180)
  let alertRed = ThemeColor(red: 1.00, green: 0.27, blue: 0.23)
  let check = ContrastCheck()
  #expect(check.problems(foreground: accent, background: surface, reserved: [alertRed]).isEmpty)
}
```

Body text needs WCAG's 4.5:1: use `ContrastCheck(minimumContrast: 4.5)` for it. When a color a
person picks fails, ``ThemeColor/adjustedForContrast(against:ratio:)`` suggests the nearest color
of the same hue that passes, and ``ThemeColor/color`` gives the SwiftUI color to draw.

### Preview every case

SalahFixtures has moments for every case a view of a schedule has to handle: a prayer that's
approaching or just started, the evening after Isha, the night before Fajr, a day without Isha,
a day without a row and the end of a timetable. Preview your styles at each, so the unknown
cases look as deliberate as the ordinary ones:

```swift
#Preview("After the last published day") {
  let moment = PrayerFixtures.afterLastPublishedDay
  if let state = moment.state().prayerState {
    NextPrayerView(
      state: state, names: PrayerNames(locale: .current), timeZone: moment.place.location.timeZone
    )
    .nextPrayerStyle(CardStyle())
  }
}
```

SalahKit's own previews and snapshot tests render every component at every moment with the
default styles, left to right in English and right to left in Arabic.

## See Also

- ``PrayerTimesList``
- ``NextPrayerView``
- ``PrayerCountdown``


### Select the focus

`NextPrayerView` keeps its next-prayer default. Pass `selection: .justStartedOrNextEvent` to
emphasize the just-started prayer, then count down to the next event, sunrise included.
`.nextEvent` includes sunrise without preferring the count-up; `.justStartedOrNextPrayer`
keeps sunrise out. The schedule decides the just-started window through `StatePolicy`.

The configuration's `focus` gives the selected event and timer direction. Its name, time and
abbreviation describe that event; `countdown` and `countUp` are mutually exclusive, and both
are nil without a known focus. The count-up uses the same live/static mode as the countdown,
with unsigned elapsed text so the style supplies its own “since” or plus sign. The plain style
shows it without repeating the just-started name. `PrayerFocus(state:selection:)` makes the
same selection for a string-based surface such as MenuBar's status-item title.

### Missing times and row layout

Pass the available day's partial-coverage dictionary as `missing:` to `PrayerTimesList`.
It merges those kinds with known events in canonical order; a known event wins a conflicting
missing key. A missing row's configuration has `kind` and `gapReason`, with nil event, time,
status and countdown. The plain row displays a dash; a custom style can explain the reason.
No prayer time is invented. Existing known-only lists keep their event order.

A list normally supplies its own vertical stack. Its `rows` view supplies transparent rows
for a consumer's own stack, so flexible heights and a focus row's layout priority belong to
that stack. CalculatedPhone uses the missing-row API; Salah uses the same rows inside its
widget and dropdown stacks.
