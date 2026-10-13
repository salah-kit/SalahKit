import Foundation

/// A prayer schedule for one location, built on a ``PrayerSource``.
///
/// The schedule asks its source for owning days, enforces the source contract on every answer
/// (turning a violation into ``ScheduleGapReason/invalidData`` for that day), applies the
/// mosque's ``IqamaRules``, and answers bounded questions: one day, the events in an interval,
/// the state at a moment and a widget's refresh plan. It never searches the source beyond the
/// days a query needs, and never fills a gap with another day's times.
///
/// ```swift
/// let schedule = PrayerSchedule(source: timetable, location: location, iqama: rules)
/// switch schedule.state(at: now, through: now.addingTimeInterval(2 * 86_400)) {
/// case .available(let state, _):
///   print(state.nextPrayer?.kind as Any)   // nil when the next prayer isn't known
/// case .unavailable(let coverage, _):
///   print(coverage.gaps.map(\.reason))
/// }
/// ```
///
/// Days are civil days in the location's time zone, never the device's. An event belongs to
/// the day whose row or calculation produced it, even when it occurs after midnight.
nonisolated public struct PrayerSchedule: Sendable {
  /// The longest span one query covers, in civil days; a later end is clamped to the start of
  /// the 400th day after the start's day.
  public static let maximumQueryDays = 400

  /// Where the schedule's days come from.
  public let source: any PrayerSource
  /// The location whose time zone defines the schedule's days.
  public let location: PrayerLocation
  /// The mosque's iqama rules, applied where the source provides no iqama.
  public let iqama: IqamaRules?

  /// Creates a schedule.
  ///
  /// - Parameters:
  ///   - source: Where the days come from: a ``TimetableSource``, a calculation or a custom
  ///     source.
  ///   - location: The location; its time zone defines the days.
  ///   - iqama: The mosque's rules for congregation times the source doesn't provide.
  public init(source: any PrayerSource, location: PrayerLocation, iqama: IqamaRules? = nil) {
    self.source = source
    self.location = location
    self.iqama = iqama
  }

  /// The events of an owning day, or the reason the schedule can't give them.
  ///
  /// The answer is the source's, checked against the source contract and with iqama rules
  /// applied. A day whose answer breaks the contract is unavailable with
  /// ``ScheduleGapReason/invalidData``; an iqama outside its event's span is dropped.
  public func day(_ day: CivilDay) -> PrayerDayAvailability {
    applyingIqamaRules(to: checked(source.prayerDay(day, at: location), for: day), on: day)
  }

  /// The owning day that is the civil date of `date` in the location's time zone.
  ///
  /// At 00:10 on Tuesday this is Tuesday, even while Monday's Isha is still to come: Monday's
  /// overnight events belong to Monday.
  public func day(containing date: Date) -> PrayerDayAvailability {
    day(CivilDay(containing: date, in: location.timeZone))
  }

  /// The known events from `start` through `end`, with the interval's coverage.
  ///
  /// An event after midnight appears once, in its owning day. Events of partial days are
  /// included. An end before the start counts as the start, and an end beyond
  /// ``maximumQueryDays`` is clamped.
  public func events(from start: Date, through end: Date) -> ScheduleEvents {
    let engine = ScheduleEngine(schedule: self)
    let end = engine.clampedEnd(from: start, through: end)
    let context = engine.context(at: start, through: end)
    return ScheduleEvents(
      events: context.events.filter { $0.time >= start && $0.time <= end },
      coverage: context.coverage(from: start, through: end))
  }

  /// The state at `date`, looking ahead no further than `end`.
  ///
  /// Pass the end of what your screen or entry shows: an event after `end` is never `next`, and
  /// ``ScheduleState/changesAt`` is never later than `end`. An end before `date` counts as
  /// `date`, and an end beyond ``maximumQueryDays`` is clamped.
  ///
  /// - Parameters:
  ///   - date: The moment.
  ///   - end: How far ahead the state may look.
  ///   - policy: When a prayer counts as approaching or just started.
  public func state(
    at date: Date, through end: Date, policy: StatePolicy = StatePolicy()
  ) -> ScheduleState {
    let engine = ScheduleEngine(schedule: self)
    return engine.state(
      at: date, through: engine.clampedEnd(from: date, through: end), policy: policy)
  }

  /// The source's answer for `requested`, checked against the source contract.
  func checked(
    _ availability: PrayerDayAvailability, for requested: CivilDay
  ) -> PrayerDayAvailability {
    let expected = source.expectedKinds
    guard !expected.isEmpty else { return .unavailable(.invalidData) }
    guard case .available(let day, let coverage) = availability else { return availability }
    let zone = location.timeZone
    guard requested.isValid, day.day == requested, day.timeZone.identifier == zone.identifier,
      !day.events.isEmpty
    else { return .unavailable(.invalidData) }

    let spanStart = requested.start(in: zone)
    let spanEnd = requested.adding(days: 2).start(in: zone)
    var events: [PrayerEvent] = []
    for event in day.events {
      guard event.scheduleDay == requested, expected.contains(event.kind),
        event.time >= spanStart, event.time < spanEnd
      else { return .unavailable(.invalidData) }
      if let previous = events.last, previous.kind >= event.kind || previous.time >= event.time {
        return .unavailable(.invalidData)
      }
      if event.observance == .jumuah, event.kind != .dhuhr || requested.weekday != 6 {
        return .unavailable(.invalidData)
      }
      var kept = event
      if let iqama = event.iqama, !(iqama >= event.time && iqama < spanEnd) {
        kept.iqama = nil
      }
      events.append(kept)
    }

    let absent = expected.subtracting(events.map(\.kind))
    switch coverage {
    case .complete:
      guard absent.isEmpty else { return .unavailable(.invalidData) }
    case .partial(let missing):
      guard !missing.isEmpty, Set(missing.keys) == absent else { return .unavailable(.invalidData) }
    }
    return .available(PrayerDay(day: requested, timeZone: zone, events: events), coverage: coverage)
  }

  /// Adds iqama from the rules to prayer events that have none.
  func applyingIqamaRules(
    to availability: PrayerDayAvailability, on requested: CivilDay
  ) -> PrayerDayAvailability {
    guard let rules = iqama, case .available(let day, let coverage) = availability else {
      return availability
    }
    let zone = location.timeZone
    let spanEnd = requested.adding(days: 2).start(in: zone)
    let events = day.events.map { event in
      guard event.iqama == nil, event.kind.isPrayer,
        let rule = event.observance == .jumuah ? rules.jumuah : rules.rules[event.kind],
        let time = iqamaTime(of: rule, for: event, rules: rules),
        time >= event.time, time < spanEnd
      else { return event }
      var updated = event
      updated.iqama = time
      return updated
    }
    return .available(
      PrayerDay(day: day.day, timeZone: day.timeZone, events: events), coverage: coverage)
  }

  private func iqamaTime(
    of rule: IqamaRules.Rule, for event: PrayerEvent, rules: IqamaRules
  ) -> Date? {
    switch rule {
    case .after(let minutes):
      guard minutes >= 0 else { return nil }
      return event.time.addingTimeInterval(TimeInterval(minutes) * 60)
    case .at(let wallTime):
      guard wallTime.isValid else { return nil }
      return WallTimeResolver.instant(
        of: wallTime, on: event.scheduleDay, in: location.timeZone,
        policy: rules.wallTimeResolution)
    }
  }
}
