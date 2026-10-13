# ``SalahCore``

A typed prayer schedule with honest coverage, published timetables with iqama, and the words
and numbers to show them.

## Overview

SalahCore turns prayer-time data into a schedule an app can ask bounded questions: the events of
a day or a range, the state at a moment, and the dates at which a widget needs a new entry. It
calculates nothing itself. A ``PrayerSource`` answers, for a ``CivilDay`` at a
``PrayerLocation``, with that day's ``PrayerEvent`` values or the reason it has none; a
calculation engine such as SalahTimes plugs in through the same contract as a published
``TimetableSource``.

The schedule never invents a time. A day the source can't answer, a prayer a row leaves blank
and the end of a timetable all appear as a ``ScheduleGap`` with a reason, and the state names no
current or next prayer across a gap. A Friday is a date: Jumu'ah appears only where the source
or the app declares it.

Everything here is a `nonisolated`, `Sendable` value type with no UI and no dependencies, and it
builds on every Apple platform and on Linux. Prayer names come from a String Catalog read with
an explicit locale; durations, digits and Hijri dates use Foundation.

## Topics

### Essentials

- <doc:UsingAMosqueTimetable>
- ``PrayerSchedule``

### Days and events

- ``CivilDay``
- ``PrayerKind``
- ``PrayerObservance``
- ``PrayerEvent``
- ``PrayerDay``
- ``PrayerLocation``

### Sources

- ``PrayerSource``
- ``PrayerDayAvailability``
- ``DayCoverage``
- ``ScheduleGapReason``

### Published times

- ``TimetableSource``
- ``WallClockTime``
- ``TimetableTime``
- ``WallTimeResolution``
- ``IqamaRules``

### Coverage

- ``ScheduleEvents``
- ``ScheduleCoverage``
- ``ScheduleGap``

### State

- ``ScheduleState``
- ``PrayerState``
- ``PrayerEventStatus``
- ``StatePolicy``

### Refresh planning

- ``RefreshPlan``
- ``RefreshStrategy``
- ``RefreshPlanError``

### Words and numbers

- ``PrayerNames``
- ``PrayerDurationFormat``
- ``PrayerLocale``
- ``HijriDateFormat``
