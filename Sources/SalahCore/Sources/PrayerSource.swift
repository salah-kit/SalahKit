import Foundation

/// Why a schedule can't say what happens for a day, a kind or an interval.
nonisolated public enum ScheduleGapReason: String, Codable, Hashable, Sendable {
  /// The source has no data for the day or the kind, such as a date past a timetable's last
  /// row or a time the publisher left blank.
  case noPublishedData
  /// A calculated source can't produce the day or the kind, such as Isha in a polar summer.
  case calculationUnavailable
  /// The data contradicts the source contract, such as times out of order.
  case invalidData
  /// A published local time is repeated or nonexistent because of a clock change, and the
  /// source's ``WallTimeResolution`` rejects it.
  case unresolvedWallTime
}

/// How much of a day's expected events a source provides.
///
/// Iqama never affects coverage: it's optional.
nonisolated public enum DayCoverage: Hashable, Sendable {
  /// Every expected kind is present.
  case complete
  /// Some expected kinds are missing, each with the reason it's missing. At least one event
  /// is present.
  case partial(missing: [PrayerKind: ScheduleGapReason])
}

/// What a source knows about one owning day: its events and coverage, or an explicit gap.
nonisolated public enum PrayerDayAvailability: Hashable, Sendable {
  /// The day's known events and how complete they are.
  case available(PrayerDay, coverage: DayCoverage)
  /// The source can't provide the day.
  case unavailable(ScheduleGapReason)

  /// The day, when it's available.
  public var day: PrayerDay? {
    if case .available(let day, _) = self { return day }
    return nil
  }

  /// The coverage, when the day is available.
  public var coverage: DayCoverage? {
    if case .available(_, let coverage) = self { return coverage }
    return nil
  }
}

/// A provider of prayer days: published timetable data, a calculation, or any custom source.
///
/// A source answers one question: what are the events of owning day `day` at `location`?
/// ``PrayerSchedule`` builds every query on that answer, and enforces the contract below on
/// every source, turning a violation into ``PrayerDayAvailability/unavailable(_:)`` with
/// ``ScheduleGapReason/invalidData`` for that day. RFC 0001, section 4.3, has the full rules.
///
/// - The same day and location always give the same answer, without blocking on I/O.
///   Fetching new data is the app's job. A source may be called concurrently.
/// - ``expectedKinds`` never changes and isn't empty.
/// - An available day has at least one event; every event belongs to the requested day, has an
///   expected kind, and no kind appears twice; the day's time zone is the location's.
/// - Every event of owning day D occurs in [start of D, start of D+2) in the location's zone:
///   Monday's Isha at 00:15 on Tuesday belongs to Monday. Never earlier than its owning day.
/// - Instants strictly increase in canonical kind order within a day, and no event of a day
///   occurs after an event of the next day (equal instants are allowed).
/// - Coverage names exactly the expected kinds that are missing, with their reasons.
/// - A source never fills a day or kind from another day or a computed fallback, and never
///   infers Jumu'ah: ``PrayerObservance/jumuah`` appears only on a declared Friday Dhuhr.
///
/// In a module whose code defaults to main-actor isolation, declare a custom source
/// `nonisolated` (`nonisolated struct MosqueFeed: PrayerSource`), because the schedule calls it
/// from whatever thread asks the question.
nonisolated public protocol PrayerSource: Sendable {
  /// The event kinds this source promises; a five-prayer timetable can exclude sunrise.
  var expectedKinds: Set<PrayerKind> { get }

  /// The events of owning day `day` at `location`, or the reason the source can't provide
  /// them. Never substitutes another day's data or a computed fallback.
  func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability
}
