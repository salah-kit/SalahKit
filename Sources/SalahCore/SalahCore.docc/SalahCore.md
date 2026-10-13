# ``SalahCore``

The value types and contracts that every SalahKit module shares.

## Overview

SalahCore describes a prayer schedule without calculating it or showing it. A ``PrayerSource``
answers, for a ``CivilDay`` at a ``PrayerLocation``, with a ``PrayerDay`` of ``PrayerEvent``
values, or says why it can't through ``PrayerDayAvailability`` and ``ScheduleGapReason``. A
published timetable gives local ``WallClockTime`` values, which a ``WallTimeResolution`` turns into
instants across clock changes, and ``IqamaRules`` add congregation times. Everything here is a
`Sendable` value type that builds on every Apple platform and on Linux, with no UI and no
dependencies.

## Topics

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

- ``WallClockTime``
- ``TimetableTime``
- ``WallTimeResolution``
- ``IqamaRules``

### State

- ``StatePolicy``
