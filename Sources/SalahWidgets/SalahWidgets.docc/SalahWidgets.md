# ``SalahWidgets``

Widget timelines that the widget extension builds by itself, values shared through an App
Group, and signals to a running app.

## Overview

An iPhone app is usually suspended, so a widget can't wait for the app to publish each day's
times. With SalahWidgets the app shares its *inputs*, such as calculation settings or a mosque's
published timetable, and the widget extension builds the schedule and the timeline itself
whenever WidgetKit asks:

- ``SharedValue`` stores a `Codable` value in the App Group the app and its extensions share, and
  asks WidgetKit to reload a widget only when the stored value changed.
- ``PrayerTimelineBuilder`` turns a `PrayerSchedule` into a bounded timeline: an entry wherever
  the state or its coverage changes, and a final ``PrayerTimelineState/expired(knownThrough:)``
  entry, so a widget that WidgetKit doesn't reload in time says its times ran out instead of
  showing a stale countdown.
- ``DarwinSignal`` tells an app that is already running that something happened, such as the
  widget's stop button being tapped.

The package ships a privacy manifest for its use of App Group defaults (reason `1C8F.1`). The
timeline types build on every platform, Linux included; `SharedValue` reloads widgets where
WidgetKit exists, and `DarwinSignal` exists on Apple platforms.

## Topics

### Essentials

- <doc:BuildingWidgetTimelines>
- <doc:LessonsFromSalah>

### Sharing inputs

- ``SharedValue``
- ``SharedValueError``

### Timelines

- ``PrayerTimelineBuilder``
- ``PrayerTimeline``
- ``PrayerTimelineState``

### Signals to a running app

- ``DarwinSignal``
