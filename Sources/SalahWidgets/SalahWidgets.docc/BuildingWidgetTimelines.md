# Building widget timelines without daily app launches

Let the widget extension build its own schedule from shared inputs, so the widget stays right
for as long as WidgetKit keeps asking, whether or not the app runs.

## Overview

A prayer widget changes several times a day, and an iPhone app is usually suspended. A widget
that waits for its app to publish each day's times goes stale the first morning the app isn't
opened. SalahWidgets moves the work into the extension:

1. The app saves its **inputs** to the App Group: calculation settings, or a mosque's published
   rows with whatever coverage they have.
2. Whenever WidgetKit asks for a timeline, the extension loads the inputs, builds a
   `PrayerSchedule`, and lets ``PrayerTimelineBuilder`` turn it into entries.
3. The app asks for a reload only when the inputs change.

A calculated schedule never runs out, so the widget keeps going without the app for as long as
WidgetKit keeps asking. A published timetable runs as far as its rows, and the widget says so
when they end.

### Share the inputs

Put the inputs in one `Codable` value and declare where it's stored, in a file that both the app
and the extension compile. Give both targets the App Group capability. Link the `SalahCore`,
`SalahCalculation` and `SalahWidgets` products, and `SalahUI` if you use its views.

```swift
struct PrayerSettings: Codable, Equatable, Sendable {
  var location: PrayerLocation
  var calculation: CalculationSettings
}

extension SharedValue where Value == PrayerSettings {
  static var prayers: Self {
    SharedValue(appGroup: "group.com.example.prayers", key: "settings.v1")
  }
}
```

Put a version in the key. A stored value that no longer decodes reads as `nil`, so a widget
from an older build asks for setup instead of crashing; change the key when the value's shape
changes.

The app saves whenever the settings change. ``SharedValue/save(_:reloading:)`` reloads the given
widget kinds only when the stored value changed, so saving the same settings on every launch
costs nothing from the widget's daily reload budget:

```swift
func saveForWidgets(_ settings: PrayerSettings) {
  do {
    try SharedValue.prayers.save(settings, reloading: ["prayers"])
  } catch {
    print("The widgets' settings weren't saved: \(error)")
  }
}
```

The reload is a request: WidgetKit decides when to ask the extension for a new timeline. Don't
ask for a reload when the system's language or appearance changes; WidgetKit redraws the widget
then by itself.

### Build the timeline in the extension

The entry says what the widget shows: a setup prompt when there are no inputs yet, or a
``PrayerTimelineState``. The provider builds the schedule from the inputs every time:

```swift
struct PrayerEntry: TimelineEntry {
  enum Content {
    case setupRequired
    case timeline(PrayerTimelineState, timeZone: TimeZone)
  }

  var date: Date
  var content: Content
}

struct PrayerProvider: TimelineProvider {
  func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
    guard let settings = SharedValue.prayers.load() else {
      let entry = PrayerEntry(date: .now, content: .setupRequired)
      return completion(Timeline(entries: [entry], policy: .never))
    }
    let zone = settings.location.timeZone
    let schedule = PrayerSchedule(
      source: CalculationSource(settings.calculation), location: settings.location)
    completion(
      PrayerTimelineBuilder(schedule: schedule).timeline(from: .now) { date, state in
        PrayerEntry(date: date, content: .timeline(state, timeZone: zone))
      })
  }

  func placeholder(in context: Context) -> PrayerEntry {
    PrayerEntry(date: .now, content: .setupRequired)
  }

  func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
    completion(placeholder(in: context))
  }
}
```

The setup entry's `.never` policy waits for the app's reload after the first save. A calculation
takes microseconds, so building two days of entries fits easily within an extension's time and
memory; the `PhoneWidgets` example measures it inside its extension.

### What a timeline contains

``PrayerTimelineBuilder/timeline(from:horizon:entry:)`` covers the next 48 hours by default
(``PrayerTimelineBuilder/defaultHorizon``):

- An entry at `now`, and one wherever the schedule's known state or coverage changes: a prayer
  starts, becomes the next one, comes within the approaching window, leaves its just-started
  window, or a gap in the source begins or ends. Each entry's state looks a day past the
  horizon, so an entry near the end still knows the next prayer.
- A last entry, ``PrayerTimelineState/expired(knownThrough:)``, where the timeline's validity
  ends.
- The reload policy `.after(_:)` halfway through, ``PrayerTimeline/reloadDate``, which leaves the
  second half as slack for a late reload.

WidgetKit's documentation asks for entries "at least about 5 minutes apart". The default
strategy, `RefreshStrategy.stateChanges`, adds only the dates where the state changes: with the
default policy, a 48-hour timeline holds 34 entries, about 16 a day. It pairs with a countdown
that updates by itself, such as SalahUI's live `PrayerCountdown`. A widget that draws its
countdown as static text needs an entry every minute near a prayer: use
`RefreshStrategy.steps(fine:coarse:window:)`. The builder keeps at most
``PrayerTimelineBuilder/limit`` entries (96 by default) counting the expired one. When the dates
don't fit, the timeline ends at the first change it can't hold: ``PrayerTimeline/validUntil``
is that date, ``PrayerTimeline/isTruncated`` is `true`, and the reload comes sooner. One-minute
steps within half an hour of each prayer fill 96 entries in about three to five hours.

To inspect the entries, or to choose another reload policy, call
``PrayerTimelineBuilder/timeline(from:horizon:)``, which returns a ``PrayerTimeline`` and throws
for a horizon that isn't positive, a limit below 2 or an invalid `steps` strategy.

### Show each state honestly

The state of an entry answers one of three questions, and each needs its own words:

```swift
struct PrayerWidgetView: View {
  var entry: PrayerEntry

  var body: some View {
    switch entry.content {
    case .setupRequired:
      Text("Open the app to choose a place")
    case .timeline(.expired, _):
      Text("Open the app to refresh the prayer times")
    case .timeline(.schedule(.unavailable), _):
      Text("Prayer times aren't available for this place")
    case .timeline(.schedule(.available(let state, _)), let zone):
      NextPrayerView(state: state, names: PrayerNames(locale: .current), timeZone: zone)
    }
  }
}
```

- ``PrayerTimelineState/schedule(_:)`` with `ScheduleState.available` is what the schedule
  knows. It can be partial: after the last published Isha of a timetable, the previous prayer is
  known and the next one isn't, and SalahUI's views show no countdown for it.
- ``PrayerTimelineState/schedule(_:)`` with `ScheduleState.unavailable` means the source has no
  usable data at that moment: a timetable that has ended or skips a day, a polar day without
  Isha, coordinates the calculation rejects. Reloading can't fix it. Its coverage names the
  gaps, their days, kinds and reasons, so the widget can say why.
- ``PrayerTimelineState/expired(knownThrough:)`` means WidgetKit didn't ask for a new timeline
  before this one ran out. The source may be fine. The widget shows that the times need
  refreshing, never a countdown that ended long ago.

### Published timetables

A mosque app stores its published rows in the inputs as well: `TimetableSource` is `Codable`.
Fetching new rows stays the app's job. When it has them, it saves the new inputs, and the
changed value reloads the widget. Until then, the timeline's states show where the rows end:
the last evening keeps its known prayers with an unknown next one, and the days after it are
unavailable with `ScheduleGapReason.noPublishedData`. A reload can't make up rows, so word that
state as "new times are needed", distinct from the expired entry.

### What WidgetKit decides

The timeline says when the content changes; WidgetKit decides when it shows each entry and
when it asks for the next timeline. WidgetKit's documentation describes a budget of 40 to 70
reloads a day for a widget people often look at, reloads that don't count when the app is in
the foreground, and entries that may appear later than their dates. So:

- A timeline never assumes it will be replaced on time: its expired entry covers a late reload.
- The app reloads only on real changes, which is what ``SharedValue`` gates.
- Tests check the entries a timeline supplies, never WidgetKit's timing.

Test the timelines with a fixed clock: start at a known instant, ask for a timeline, ask again
at its reload date, delay one of the requests past its validity, and check at every few minutes
that the entry on show says what the schedule says at that moment, and that the expired entry
shows exactly while the late request is pending:

```swift
@Test func timelineEndsWithItsExpiry() throws {
  let timeline = try PrayerTimelineBuilder(schedule: schedule).timeline(from: now)
  #expect(timeline.entries.last?.state == .expired(knownThrough: timeline.validUntil))
  #expect(timeline.reloadDate < timeline.validUntil)
}
```

Only a device shows how WidgetKit actually behaves. The `PhoneWidgets` example records each
timeline its extension builds, so a run of several days on an iPhone, without opening the app,
shows when the reloads came.

### The Apple Watch

A watch app doesn't share App Group storage with its iPhone app. It keeps its own copy of the
inputs in its own App Group, received with WatchConnectivity, and its complications build their
timelines from that copy, so they keep working when the iPhone app is closed. The
`WatchComplication` example sends the inputs from a companion iPhone app and handles a watch
that has none yet.

### Signals to a running app

Some widget actions only make sense while the app runs, such as a stop button for playback the
app is doing. The widget's App Intent runs in the extension's process, so it reaches the app
with a ``DarwinSignal`` whose name the app owns:

```swift
extension DarwinSignal {
  static let stopPlayback = DarwinSignal(name: "com.example.prayers.stop")
}
```

The intent posts it, and the app observes it while it runs:

```swift
// In the widget's App Intent:
DarwinSignal.stopPlayback.post()

// In the app, on the main actor. Keep the observation for as long as you observe:
let observation = DarwinSignal.stopPlayback.observe { player.stop() }
```

The app acts on the signal itself. A value the intent writes to the App Group can reach the app
after the signal does, so an app that checks it when the signal arrives may read the old one
and do nothing. After stopping, the app saves the new state, which reloads the widget. A signal
never launches an app and isn't kept for one that isn't running: an action that must always
happen needs a way that doesn't depend on the app running.

## See Also

- ``PrayerTimelineBuilder``
- ``SharedValue``
- ``DarwinSignal``
