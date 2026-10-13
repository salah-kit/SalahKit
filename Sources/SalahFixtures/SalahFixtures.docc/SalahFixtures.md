# ``SalahFixtures``

Ready-made prayer data for previews and tests.

## Overview

SalahFixtures supplies ready-made timetable data built from SalahCore's types, so tests, previews
and examples don't depend on the current date, the device's location or a network. Everything is
`TimetableSource` data written out in full, which means the module needs no calculation engine and
gives the same answers on every device and on every day.

The data comes in two kinds. A ``PrayerFixtures/Place`` is a place with a published timetable.
The eight places cover the cases that a view of a schedule has to handle: a complete timetable with
published iqama (Makkah and Jakarta), a late Isha (London), events after midnight (Reykjavik), a
clock change (New York), a declared Jumu'ah, a Ramadan day, and an incomplete timetable
(Singapore). A ``PrayerFixtures/Moment`` is an instant at one of those places, picked so that the
state of its schedule shows a case that a countdown or a widget has to handle: a prayer that is
approaching or has just started, the evening after Isha, the night before Fajr, and the three ways
a timetable leaves something unknown, which are a row without Isha, a day without a row and the end
of the timetable.

A place gives you a schedule, and a moment gives you the state of its place's schedule:

```swift
let place = PrayerFixtures.newYorkDSTChange
let day = place.schedule.day(place.featuredDay)

let moment = PrayerFixtures.beforeFajr
if case .available(let state, _) = moment.state(), let fajr = state.nextPrayer {
  print(fajr.time.timeIntervalSince(moment.date))  // 12840.0
}
```

The times are computed, not published by the places they are named for. Use them for previews and
tests and never as prayer times. `FixtureData.md`, in the `Sources/SalahFixtures` folder of the
repository, records every number, the method that produced it and how it was checked.

## Topics

### Places and moments

- ``PrayerFixtures``
- ``PrayerFixtures/Place``
- ``PrayerFixtures/Moment``

### Places

- ``PrayerFixtures/places``
- ``PrayerFixtures/makkah``
- ``PrayerFixtures/londonSummer``
- ``PrayerFixtures/reykjavikJune``
- ``PrayerFixtures/newYorkDSTChange``
- ``PrayerFixtures/jakarta``
- ``PrayerFixtures/friday``
- ``PrayerFixtures/ramadan``
- ``PrayerFixtures/incomplete``

### Moments

- ``PrayerFixtures/moments``
- ``PrayerFixtures/approaching``
- ``PrayerFixtures/justStarted``
- ``PrayerFixtures/afterIsha``
- ``PrayerFixtures/beforeFajr``
- ``PrayerFixtures/partialDay``
- ``PrayerFixtures/missingDay``
- ``PrayerFixtures/afterLastPublishedDay``
