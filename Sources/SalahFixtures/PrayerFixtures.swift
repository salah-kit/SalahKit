import Foundation
import SalahCore

/// Ready-made prayer data for previews and tests: places with published timetables, and
/// moments at which to ask them what is happening.
///
/// Every place is `TimetableSource` data written out in full, so the fixtures need no
/// calculation engine, no network and no clock. They give the same answers on every device
/// and on every day, whatever the date and time zone of the machine that runs them.
///
/// Each place stands for one case that a view of a schedule has to handle, such as a late Isha,
/// events after midnight, a clock change, a declared Jumu'ah or a gap in the timetable. Each
/// moment is an instant at which the state of a place shows one of the cases a countdown or a
/// widget has to handle. A place gives you a schedule, and a moment gives you the state of its
/// place's schedule at that instant:
///
/// ```swift
/// let place = PrayerFixtures.newYorkDSTChange
/// let day = place.schedule.day(place.featuredDay)
///
/// let moment = PrayerFixtures.beforeFajr
/// if case .available(let state, _) = moment.state(), let fajr = state.nextPrayer {
///   print(fajr.time.timeIntervalSince(moment.date))  // 12840.0
/// }
/// ```
///
/// The times are computed, not published by the places they are named for, so use them for
/// previews and tests and never as prayer times. `FixtureData.md` in the repository's
/// `Sources/SalahFixtures` folder records every number, the method that produced it and how it
/// was checked.
nonisolated public enum PrayerFixtures {
  /// A place with a published timetable, built around one featured day.
  ///
  /// The timetable has a row for the featured day and for the two days on either side of it,
  /// except where the place demonstrates a gap. Its location carries the time zone that defines
  /// the place's days.
  nonisolated public struct Place: Hashable, Sendable {
    /// The place's name for a test or a menu, the same as the name of the static property that
    /// holds it, such as `"newYorkDSTChange"`.
    public let id: String

    /// Where the place is: its coordinates, the time zone that defines its civil days, its
    /// country code and its name.
    public let location: PrayerLocation

    /// The published rows, which expect all six kinds.
    public let source: TimetableSource

    /// Iqama rules, or `nil` where the rows publish their own iqama or none, which is the case
    /// for every fixture. A published iqama always wins over a rule.
    public let iqama: IqamaRules?

    /// The day the place is built around. Its rows cover this day and the two days before and
    /// after it, except where the place demonstrates a missing day.
    public let featuredDay: CivilDay

    /// A schedule over the place's timetable and location, with its iqama rules applied.
    public var schedule: PrayerSchedule {
      PrayerSchedule(source: source, location: location, iqama: iqama)
    }
  }

  /// An instant at a place, at which the place's state shows one case.
  ///
  /// A moment names what to ask, and ``PrayerFixtures/Moment/state(policy:)`` asks it with the
  /// lookahead a widget timeline uses.
  nonisolated public struct Moment: Hashable, Sendable {
    /// The moment's name for a test or a menu, the same as the name of the static property that
    /// holds it, such as `"beforeFajr"`.
    public let id: String

    /// The place whose schedule the moment asks.
    public let place: Place

    /// The instant.
    public let date: Date

    /// The schedule of the moment's place.
    public var schedule: PrayerSchedule { place.schedule }

    /// The state of the moment's schedule at its instant.
    ///
    /// The state looks ahead to the start of the second civil day after the instant's civil day
    /// in the place's time zone, so the next prayer is known even late in the evening. That is
    /// the bound that `PrayerSchedule.refreshPlan(from:through:strategy:policy:limit:)` gives
    /// each of its entries.
    ///
    /// - Parameter policy: When a prayer counts as approaching or just started.
    /// - Returns: The state at ``date``, with the coverage from ``date`` to that bound.
    public func state(policy: StatePolicy = StatePolicy()) -> ScheduleState {
      let zone = place.location.timeZone
      let bound = CivilDay(containing: date, in: zone).adding(days: 2).start(in: zone)
      return schedule.state(at: date, through: bound, policy: policy)
    }
  }
}

nonisolated extension PrayerFixtures {
  /// Every place, in this order: ``makkah``, ``londonSummer``, ``reykjavikJune``,
  /// ``newYorkDSTChange``, ``jakarta``, ``friday``, ``ramadan`` and ``incomplete``.
  public static let places: [Place] = [
    makkah, londonSummer, reykjavikJune, newYorkDSTChange, jakarta, friday, ramadan, incomplete,
  ]

  /// Every moment, in this order: ``approaching``, ``justStarted``, ``afterIsha``,
  /// ``beforeFajr``, ``partialDay``, ``missingDay`` and ``afterLastPublishedDay``.
  public static let moments: [Moment] = [
    approaching, justStarted, afterIsha, beforeFajr, partialDay, missingDay,
    afterLastPublishedDay,
  ]
}
