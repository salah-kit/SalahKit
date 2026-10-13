# ``SalahCalculation``

Calculated prayer times as a SalahCore source, from the SalahTimes engine.

## Overview

SalahCalculation connects [SalahTimes](https://salah-kit.github.io/SalahTimes/documentation/salahtimes),
the salah-kit prayer-time engine, to SalahCore. ``CalculationSource`` calculates each owning day
with SalahTimes and answers as a `PrayerSource`, so a `PrayerSchedule` built on it gives a
calculated app the same days, coverage, state and refresh plans a timetable app gets.

``CalculationSettings`` carries SalahTimes' parameters whole, so every published method and
every customization reaches the engine unchanged. The source passes the results through
unchanged too: a prayer that doesn't occur, such as Isha in a polar summer, or a time SalahCore's
contract can't place is missing with a reason, never moved, reordered or borrowed from another
day. Jumu'ah and iqama stay your app's policy.

Every type is `nonisolated` and `Sendable`, builds on every Apple platform and on Linux, and
calculates a day in microseconds, so widget extensions and background tasks can use it directly.

## Topics

### Essentials

- <doc:CalculatedPrayerApp>
- ``CalculationSource``
- ``CalculationSettings``
