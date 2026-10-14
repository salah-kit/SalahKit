# ``SalahUI``

SwiftUI building blocks for prayer times, with plain looks you replace by supplying styles,
and tools for checking a theme's colors.

## Overview

SalahUI's components decide *what* to show from a SalahCore state: which prayer comes next,
which rows have passed, whether a countdown can be shown at all, and which clock and digits the
times are written in. Styles decide *how* it looks:

- ``PrayerTimesList`` shows one owning day's events, a row each, styled by a ``PrayerRowStyle``.
- ``NextPrayerView`` shows the next prayer, its time and countdown, and the prayer that just
  started, styled by a ``NextPrayerStyle``. Select a sunrise countdown or a just-started
  count-up with ``PrayerFocus/Selection``.
- ``PrayerCountdown`` counts down to a prayer, live with `Text(timerInterval:)` or as static text.

The components never invent a time or a countdown: where the state doesn't know the next
prayer, the styles receive `nil`. Times are written in the schedule's time zone, whatever the
device's zone, in the environment's locale. The defaults, ``PlainPrayerRowStyle`` and
``PlainNextPrayerStyle``, use the system's fonts and colors, mirror for right-to-left languages
and read as one element each in VoiceOver.

``ThemeColor`` and ``ContrastCheck`` check a theme's colors against WCAG contrast and against
colors an app reserves, with the thresholds of Salah's theme editor. They're plain values, so
they work in tests on every platform, Linux included.

## Topics

### Essentials

- <doc:StylingRowsAndCards>

### Components

- ``PrayerTimesList``
- ``NextPrayerView``
- ``PrayerFocus``
- ``PrayerCountdown``

### Row styles

- ``PrayerRowStyle``
- ``PrayerRowConfiguration``
- ``PlainPrayerRowStyle``

### Next-prayer styles

- ``NextPrayerStyle``
- ``NextPrayerConfiguration``
- ``PlainNextPrayerStyle``

### Theme colors

- ``ThemeColor``
- ``ContrastCheck``
