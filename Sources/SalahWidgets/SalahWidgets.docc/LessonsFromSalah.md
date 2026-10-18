# Lessons from Salah

Three things the Salah app learned the hard way, and how SalahKit builds them in: act on the
signal instead of the stored flag, reload widgets only for real changes, and keep the
language's digits.

## Overview

SalahKit grew out of Salah, a macOS menu-bar app for prayer times that began as Guidance. Its
schedule, widget, alert and formatting code moved into the packages, and with it three lessons
that each cost a bug or a workaround. Each section says what happened in Salah, what SalahKit
does about it, and which example shows it working.

### Act on the signal, not on the stored flag

Salah's desktop widget has a Stop button for the adhan. The button runs an App Intent, and the
intent runs in the widget extension's process, which can't touch the app's audio. Salah's first
version declared the intent as an audio intent, hoping the system would run it inside the app;
it ran in the extension anyway. The intent then wrote a "stop" flag to the App Group and posted
a Darwin notification, and the app, on the notification, checked the flag before stopping. The
flag often hadn't reached the app's process yet: a value written in one process reaches another
through the system's preferences daemon, on the daemon's schedule. The app read the old value
and kept playing, and the button did nothing.

What works is the pattern SalahKit documents. The app publishes what it plays in a
``SharedValue``, and the widget shows a Stop button while something plays:

```swift
nonisolated struct NowPlaying: Codable, Equatable, Sendable {
  var prayer: PrayerKind
  var startedAt: Date
}

nonisolated extension SharedValue where Value == NowPlaying {
  static var nowPlaying: Self {
    SharedValue(appGroup: "group.com.example.prayers", key: "nowPlaying.v1")
  }
}
```

The intent clears the value, so the widget redraws without the button at once, and posts a
``DarwinSignal`` whose name the app owns:

```swift
nonisolated struct StopPlaybackIntent: AppIntent {
  static var title: LocalizedStringResource { "Stop" }

  func perform() async throws -> some IntentResult {
    _ = try? SharedValue.nowPlaying.save(nil, reloading: ["prayers"])
    DarwinSignal.stopPlayback.post()
    return .result()
  }
}
```

The running app stops when the signal arrives, without reading the stored value, and then
publishes what it really plays. That confirms the stop to the widget, or corrects it when the
stored value still said something played:

```swift
// In the app, on the main actor, for as long as it runs:
stopObservation = DarwinSignal.stopPlayback.observe {
  player.stop()
  _ = try? SharedValue.nowPlaying.save(player.nowPlaying, reloading: ["prayers"])
}
```

The intent and the app both write the value, which breaks ``SharedValue``'s one-writer rule on
purpose: the app's write after every signal settles any race between the two.

A Darwin notification carries no data, isn't kept for a process that isn't observing, and never
launches an app. Keep this pattern for actions that only matter while the app runs, such as
stopping playback; an action that must always happen needs a way that doesn't depend on the
app running.

`Examples/MenuBar` is a menu-bar app built this way, with a desktop widget and its Stop button.
Its stop harness, a separate sandboxed process signed like the widget extension, runs the
intent's own code against the running app. The app stops and republishes; and when the harness
posts the signal without clearing the value, the app stops anyway, and its own republish clears
the value that still said a tone was playing.

### Reload a widget only when its content changed

WidgetKit gives each widget a limited number of reloads a day. Salah publishes its widget's
content from a menu-bar app, which macOS doesn't treat as in the foreground, so its reload
requests are deferred and coalesced, and a burst of them can lose the one that mattered. Salah
asks for a reload only when what the widget shows changed.

``SharedValue/save(_:reloading:)`` does the comparison: it reads the stored value, and writes and
reloads only when the new value differs by `==`. It returns whether it did:

```swift
let changed = try SharedValue.prayers.save(settings, reloading: ["prayers"])
```

So an app can save on every launch, every activation and every settings screen without
spending reloads. The comparison reads the App Group's own storage only, never a default
registered in the app's process, which the extension doesn't see.

`Examples/PhoneWidgets` checks this in the real extension: its log records one timeline per
changed save and none for an unchanged one.

### Keep the language's digits

Arabic, Urdu, Persian and Bengali usually write numbers with their own digits: ١٢:٣٠, ۱۲:۳۰,
১২:৩০. A locale made from the bare language code doesn't always keep them. On macOS,
`Locale(identifier: "ar")` formats numbers with Latin digits, and some Linux toolchains differ,
so Salah builds its Arabic locale with the `arab` numbering system, its Urdu and Persian
locales with `arabext`, and its Bengali locale with `beng`.

SalahCore does the same for any identifier: `PrayerLocale.resolved(_:)` applies the language's
numbering system unless the identifier names one, such as `ar@numbers=latn`. Arabic follows
CLDR's default for the country the identifier names: `ar-MA`, `ar-DZ`, `ar-TN`, `ar-LY`, `ar-EH`
and `ar-AE` get Latin digits, and every other Arabic locale, a bare `ar` included, gets
Arabic-Indic digits. Use the resolved locale for every name, duration and time you show:

```swift
let locale = PrayerLocale.resolved("ar")
let countdown = PrayerDurationFormat.string(720, locale: locale)  // "١٢د"
let isha = PrayerNames(locale: locale).name(of: .isha)  // "العشاء"
```

In SwiftUI, set it on the environment, `.environment(\.locale, locale)`, and SalahUI's
components follow it.

A widget extension runs in the system's language, not the language the user chose in your app.
Put the chosen language in the shared inputs, and build the locale from it in the extension,
as PhoneWidgets and MenuBar do.

## See Also

- <doc:BuildingWidgetTimelines>
- ``DarwinSignal``
- ``SharedValue``
