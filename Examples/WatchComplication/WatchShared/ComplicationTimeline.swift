import Foundation
import SalahCore
import SalahWidgets
import WidgetKit

/// What one complication entry shows: the setup prompt, or a state from SalahWidgets.
nonisolated enum ComplicationContent: Hashable, Sendable {
  /// The watch has no inputs yet: the iPhone app must send them.
  case setupRequired
  /// A schedule state, or the end of the timeline's validity.
  case timeline(PrayerTimelineState)
}

/// One complication entry.
nonisolated struct ComplicationEntry: TimelineEntry, Hashable, Sendable {
  /// When WidgetKit may start showing the entry.
  var date: Date
  /// What it shows.
  var content: ComplicationContent
  /// The schedule's time zone, the place's; the device's when there are no inputs.
  var timeZone: TimeZone
  /// The place's name, if the inputs have one.
  var placeName: String?
  /// The day of a timetable's last row, or `nil` for a calculated source.
  var lastPublishedDay: CivilDay?
}

/// The complication's timeline, built from the watch's stored inputs alone.
nonisolated enum ComplicationTimeline {
  /// The timeline from `now`.
  ///
  /// Without inputs, a single setup entry that never reloads by itself: the watch app reloads
  /// the complication when inputs arrive. With inputs, SalahWidgets' bounded timeline: an
  /// entry wherever the state changes, a final timeline-expired entry, and a reload halfway to
  /// it.
  static func make(
    inputs: WatchInputs?, now: Date,
    horizon: Duration = PrayerTimelineBuilder.defaultHorizon
  ) -> Timeline<ComplicationEntry> {
    guard let inputs else {
      return Timeline(
        entries: [
          ComplicationEntry(date: now, content: .setupRequired, timeZone: .current)
        ], policy: .never)
    }
    let builder = PrayerTimelineBuilder(schedule: inputs.schedule)
    return builder.timeline(from: now, horizon: horizon) { date, state in
      ComplicationEntry(
        date: date, content: .timeline(state), timeZone: inputs.location.timeZone,
        placeName: inputs.location.name, lastPublishedDay: inputs.lastPublishedDay)
    }
  }

  /// The entry WidgetKit would show at `date`: the latest one that starts at or before it, or
  /// the first.
  static func entry(at date: Date, in entries: [ComplicationEntry]) -> ComplicationEntry? {
    entries.last { $0.date <= date } ?? entries.first
  }
}

/// How a view presents one entry, decided apart from SwiftUI so tests can check it.
///
/// The two "no times" cases need different actions, and the wording keeps them apart:
/// - ``timetableEnded(day:)`` is a source gap with no published data, such as a timetable past
///   its last row. Reloading can't fix it; the iPhone must send new times.
/// - ``timelineExpired(knownThrough:)`` is the end of a timeline that WidgetKit didn't replace
///   in time. The source may be fine; the next timeline fixes it.
nonisolated enum ComplicationDisplay: Hashable, Sendable {
  /// No inputs yet.
  case setupRequired
  /// The next prayer is known: its name, time and countdown.
  case next(PrayerState)
  /// The latest prayer is known but the next one isn't, for `reason`.
  case partial(PrayerState, reason: ScheduleGapReason?)
  /// No published times from `day` on: new times must come from the iPhone.
  case timetableEnded(day: CivilDay?)
  /// No times, for a reason other than missing published data.
  case unavailable(ScheduleGapReason?)
  /// The timeline ran out at `knownThrough`; a reload fixes it.
  case timelineExpired(knownThrough: Date)

  /// The display of an entry's content at the entry's date.
  init(_ content: ComplicationContent, at date: Date) {
    switch content {
    case .setupRequired:
      self = .setupRequired
    case .timeline(.expired(let knownThrough)):
      self = .timelineExpired(knownThrough: knownThrough)
    case .timeline(.schedule(.available(let state, let coverage))):
      if state.nextPrayer != nil {
        self = .next(state)
      } else {
        self = .partial(state, reason: coverage.gaps.first?.reason)
      }
    case .timeline(.schedule(.unavailable(let coverage, _))):
      let gap = coverage.gaps.first { $0.interval.start <= date && date < $0.interval.end }
      let current = gap ?? coverage.gaps.first
      if current?.reason == .noPublishedData {
        self = .timetableEnded(day: current?.day)
      } else {
        self = .unavailable(current?.reason)
      }
    }
  }

  /// A short name for logs and diagnostics.
  var summary: String {
    switch self {
    case .setupRequired: "setup"
    case .next: "next"
    case .partial: "partial"
    case .timetableEnded: "timetableEnded"
    case .unavailable: "unavailable"
    case .timelineExpired: "timelineExpired"
    }
  }
}
