import Foundation
import SalahCore

// What the components show, as plain values: the SwiftUI layer only wraps these in views. Keeping
// the decisions here lets them be tested on every platform, Linux included.

/// A countdown from a moment to an event's start.
nonisolated struct CountdownContent: Hashable, Sendable {
  /// The moment the countdown is shown for: the state's date.
  var start: Date
  /// The event's start, never before `start`.
  var end: Date

  /// A countdown from `start` to `end`; an end before the start counts as the start.
  init(from start: Date, to end: Date) {
    self.start = start
    self.end = max(start, end)
  }

  /// The time left at `start`, in seconds.
  var seconds: TimeInterval { end.timeIntervalSince(start) }

  /// Compact text for a static countdown, such as `12m`.
  func compactText(locale: Locale) -> String {
    PrayerDurationFormat.string(seconds, locale: locale)
  }

  /// Spoken text for VoiceOver, such as "12 minutes".
  func spokenText(locale: Locale) -> String {
    PrayerDurationFormat.string(seconds, width: .spoken, locale: locale)
  }
}

/// Clock times in a schedule's time zone.
nonisolated enum ScheduleTimeText {
  /// The time of `date` as the locale writes a short time, in `timeZone` rather than the
  /// device's zone: a Makkah schedule reads Makkah's clock on a phone set to London.
  static func string(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    let style = Date.FormatStyle(
      date: .omitted, time: .shortened, locale: locale, calendar: locale.calendar,
      timeZone: timeZone)
    return date.formatted(style)
  }

  /// The civil days from an event's owning day to the date it occurs on, in the schedule's
  /// zone: 1 for an Isha after midnight, -1 for a Fajr before it, 0 otherwise.
  static func dayOffset(of event: PrayerEvent, timeZone: TimeZone) -> Int {
    event.scheduleDay.days(to: CivilDay(containing: event.time, in: timeZone))
  }

  /// A day offset as signed text in the locale's digits, such as `+1`, or `nil` for 0.
  static func dayOffsetText(_ offset: Int, locale: Locale) -> String? {
    guard offset != 0 else { return nil }
    return offset.formatted(.number.sign(strategy: .always()).locale(locale))
  }
}

/// One row of a day's list.
nonisolated struct RowContent: Hashable, Sendable {
  var event: PrayerEvent
  /// The event's status in the state, or `nil` when the state isn't known.
  var status: PrayerEventStatus?
  var name: String
  var time: String
  var dayOffset: Int
  var dayOffsetText: String?
  /// A countdown on the next event's row only, from the state's date.
  var countdown: CountdownContent?

  /// The rows of `day`'s events, in their order.
  static func rows(
    day: PrayerDay, state: PrayerState?, names: PrayerNames, locale: Locale
  ) -> [RowContent] {
    day.events.map { event in
      let status = state?.status(of: event)
      let offset = ScheduleTimeText.dayOffset(of: event, timeZone: day.timeZone)
      var countdown: CountdownContent?
      if let state, case .next = status {
        countdown = CountdownContent(from: state.date, to: event.time)
      }
      return RowContent(
        event: event, status: status, name: names.name(of: event),
        time: ScheduleTimeText.string(event.time, timeZone: day.timeZone, locale: locale),
        dayOffset: offset, dayOffsetText: ScheduleTimeText.dayOffsetText(offset, locale: locale),
        countdown: countdown)
    }
  }
}

/// What a next-prayer view shows.
nonisolated struct NextPrayerContent: Hashable, Sendable {
  /// The next prayer's name, Jumu'ah when declared; `nil` when the next prayer isn't known.
  var name: String?
  /// The next prayer's abbreviation; `nil` when the next prayer isn't known.
  var abbreviation: String?
  /// The next prayer's time in the schedule's zone; `nil` when the next prayer isn't known.
  var time: String?
  /// The countdown to the next prayer; `nil` when it isn't known, never invented.
  var countdown: CountdownContent?
  /// The name of the prayer that just started, while it's inside its window.
  var justStarted: String?

  init(state: PrayerState, names: PrayerNames, timeZone: TimeZone, locale: Locale) {
    if let next = state.nextPrayer {
      name = names.name(of: next)
      abbreviation = names.abbreviation(of: next)
      time = ScheduleTimeText.string(next.time, timeZone: timeZone, locale: locale)
      countdown = CountdownContent(from: state.date, to: next.time)
    }
    justStarted = state.justStarted.map { names.name(of: $0) }
  }
}
