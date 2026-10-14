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
  ///
  /// This is the locale's own short time format, as `DateFormatter`'s `.short` time style
  /// gives it. `Date.FormatStyle`'s `.shortened` time drops the hour's leading zero in 24-hour
  /// locales: French writes "04:11", not "4:11".
  static func string(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = locale.calendar
    formatter.timeZone = timeZone
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
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
  /// The selected known event and timer direction.
  var focus: PrayerFocus?
  /// The selected event's name, Jumu'ah when declared.
  var name: String?
  /// The next prayer's abbreviation; `nil` when the next prayer isn't known.
  var abbreviation: String?
  /// The next prayer's time in the schedule's zone; `nil` when the next prayer isn't known.
  var time: String?
  /// The countdown to the next prayer; `nil` when it isn't known, never invented.
  var countdown: CountdownContent?
  /// The elapsed interval of a count-up, when selected.
  var countUp: CountdownContent?
  /// The name of the prayer that just started, while it's inside its window.
  var justStarted: String?

  init(
    state: PrayerState, names: PrayerNames, timeZone: TimeZone, locale: Locale,
    selection: PrayerFocus.Selection = .nextPrayer
  ) {
    focus = PrayerFocus(state: state, selection: selection)
    if let focus {
      let event = focus.event
      name = names.name(of: event)
      abbreviation = names.abbreviation(of: event)
      time = ScheduleTimeText.string(event.time, timeZone: timeZone, locale: locale)
      if focus.isCountUp {
        countUp = CountdownContent(from: event.time, to: state.date)
      } else {
        countdown = CountdownContent(from: state.date, to: event.time)
      }
    }
    justStarted = state.justStarted.map { names.name(of: $0) }
  }
}
