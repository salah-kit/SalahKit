import Foundation

/// The events of one owning day, as a source provides them.
///
/// Events are ordered by instant. Some may occur on the following civil day, such as an Isha
/// after midnight; they still belong to this day.
nonisolated public struct PrayerDay: Codable, Hashable, Sendable {
  /// The owning civil day.
  public var day: CivilDay
  /// The time zone the day is in: the location's zone.
  public var timeZone: TimeZone
  /// The day's events, ordered by instant.
  public var events: [PrayerEvent]

  /// Creates a day, ordering `events` by instant (then by canonical kind order).
  public init(day: CivilDay, timeZone: TimeZone, events: [PrayerEvent]) {
    self.day = day
    self.timeZone = timeZone
    self.events = events.sorted { ($0.time, $0.kind) < ($1.time, $1.kind) }
  }

  /// Whether the day is a Friday. This is a date fact: it never makes Dhuhr a Jumu'ah.
  public var isFriday: Bool { day.weekday == 6 }

  /// The day's event of the given kind, if the source provides it.
  public subscript(kind: PrayerKind) -> PrayerEvent? {
    events.first { $0.kind == kind }
  }
}
