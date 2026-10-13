import Foundation

/// An interval in which a schedule can't say what happens, with the owning day, the kinds that
/// may fall in it and the reason.
///
/// A gap is half-open: it starts at `interval.start` and ends just before `interval.end`. For a
/// missing day or kind, it spans everywhere the missing events could occur: from the latest
/// known event before them (or the owning day's start) to the earliest known event after them
/// (or the start of the day after the next). For data that contradicts the source contract, such
/// as an Isha later than the next day's Fajr, it spans the contradiction.
nonisolated public struct ScheduleGap: Hashable, Sendable {
  /// Where the unknown events may occur, from `start` up to but not including `end`.
  public var interval: DateInterval
  /// The owning day whose events are unknown.
  public var day: CivilDay
  /// The expected kinds that may fall in the interval.
  public var kinds: Set<PrayerKind>
  /// Why the events are unknown.
  public var reason: ScheduleGapReason
}

/// What a schedule knows about a requested interval: where it knows every event, and the gaps
/// where it doesn't.
nonisolated public struct ScheduleCoverage: Hashable, Sendable {
  /// The interval asked about, after the query limit of ``PrayerSchedule/maximumQueryDays``.
  public var requested: DateInterval
  /// The parts of `requested` outside every gap, in order.
  public var knownIntervals: [DateInterval]
  /// The gaps inside `requested`, clipped to it, ordered by start, then owning day, then reason.
  public var gaps: [ScheduleGap]

  /// Whether the schedule knows every event in the requested interval.
  public var isComplete: Bool { gaps.isEmpty }
}

/// The known events of an interval, with the interval's coverage.
nonisolated public struct ScheduleEvents: Hashable, Sendable {
  /// The known events in the interval, ordered by instant, then owning day, then kind.
  public var events: [PrayerEvent]
  /// What the schedule knows about the interval.
  public var coverage: ScheduleCoverage
}

nonisolated extension ScheduleGapReason {
  /// The position in declaration order, which orders gaps that share a start and a day.
  var order: Int {
    switch self {
    case .noPublishedData: 0
    case .calculationUnavailable: 1
    case .invalidData: 2
    case .unresolvedWallTime: 3
    }
  }
}
