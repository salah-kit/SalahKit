import Foundation

/// The schedule at one moment: what it knows about the prayers around it, or why it knows
/// nothing usable.
///
/// The state is ``available(_:coverage:)`` when any of ``PrayerState/previous``,
/// ``PrayerState/latestPrayer``, ``PrayerState/next`` or ``PrayerState/nextPrayer`` is known, and
/// ``unavailable(_:changesAt:)`` otherwise. Its coverage spans from the moment to the query's
/// bound, so a view can explain a gap.
nonisolated public enum ScheduleState: Hashable, Sendable {
  /// Known state, with the coverage from the moment to the bound.
  case available(PrayerState, coverage: ScheduleCoverage)
  /// No usable local state: no known event before or after the moment can be asserted.
  /// `changesAt` is when that ends within the bound, if it does.
  case unavailable(ScheduleCoverage, changesAt: Date?)

  /// The known state, when there is one.
  public var prayerState: PrayerState? {
    if case .available(let state, _) = self { return state }
    return nil
  }

  /// The coverage from the moment to the query's bound.
  public var coverage: ScheduleCoverage {
    switch self {
    case .available(_, let coverage): coverage
    case .unavailable(let coverage, _): coverage
    }
  }

  /// The next instant within the bound at which the state or its coverage changes, if any.
  public var changesAt: Date? {
    switch self {
    case .available(let state, _): state.changesAt
    case .unavailable(_, let changesAt): changesAt
    }
  }
}

/// The prayers around a moment, as far as the schedule can establish them.
///
/// A field is `nil` when the schedule can't assert it: an event is never named across an
/// interval in which an unknown event could occur. After Isha on a timetable's last published
/// day, ``previous`` and ``latestPrayer`` stay known while ``next`` and ``nextPrayer`` are `nil`.
nonisolated public struct PrayerState: Hashable, Sendable {
  /// The moment this state describes.
  public var date: Date
  /// The latest event at or before ``date``, sunrise included, if known.
  public var previous: PrayerEvent?
  /// The latest prayer that started at or before ``date``, if known.
  ///
  /// It's an occurrence, not a validity judgment: after sunrise, ``previous`` is sunrise and
  /// `latestPrayer` is still Fajr.
  public var latestPrayer: PrayerEvent?
  /// The next event after ``date``, sunrise included, when no unknown interval precedes it.
  public var next: PrayerEvent?
  /// The next prayer after ``date``, when no unknown interval precedes it.
  public var nextPrayer: PrayerEvent?
  /// ``latestPrayer`` while it counts as just started under the ``StatePolicy``.
  public var justStarted: PrayerEvent?
  /// Whether ``nextPrayer`` is within the policy's approaching duration. `false` when
  /// `nextPrayer` is unknown.
  public var isApproaching: Bool
  /// The next instant within the query's bound at which the state or its coverage changes.
  public var changesAt: Date?

  /// How an event relates to this state, for a row in a list of the day's events.
  ///
  /// Events are compared by ``PrayerEvent/id``:
  /// - ``PrayerEventStatus/justStarted`` if the event is ``justStarted``;
  /// - ``PrayerEventStatus/passed`` if it started at or before ``date``;
  /// - ``PrayerEventStatus/next(approaching:)`` if it's ``next``, or if `next` is unknown and
  ///   it's ``nextPrayer``; `approaching` is true when it's `nextPrayer` and ``isApproaching``;
  /// - ``PrayerEventStatus/upcoming`` otherwise.
  public func status(of event: PrayerEvent) -> PrayerEventStatus {
    if event.id == justStarted?.id { return .justStarted }
    if event.time <= date { return .passed }
    if event.id == next?.id || (next == nil && event.id == nextPrayer?.id) {
      return .next(approaching: event.id == nextPrayer?.id && isApproaching)
    }
    return .upcoming
  }
}

/// How one event relates to a ``PrayerState``.
nonisolated public enum PrayerEventStatus: Hashable, Sendable {
  /// The event started at or before the state's moment.
  case passed
  /// The event is the prayer that just started.
  case justStarted
  /// The event is the next one; `approaching` when it's the next prayer and it's near.
  case next(approaching: Bool)
  /// The event comes later.
  case upcoming
}
