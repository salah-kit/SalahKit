import Foundation

/// How a prayer is observed on its day.
///
/// Friday is a date fact; Jumu'ah is declared policy. A source marks Dhuhr as ``jumuah`` only
/// when its data or the app says so, never because the day is a Friday.
nonisolated public enum PrayerObservance: String, Codable, Hashable, Sendable {
  /// The ordinary daily prayer.
  case ordinary
  /// Friday's congregational prayer in place of Dhuhr, as declared by the source.
  case jumuah
}

/// One occurrence of a prayer or of sunrise.
///
/// An event belongs to the civil day of its source row, its ``scheduleDay``, even when it
/// occurs after midnight: Monday's Isha at 00:15 on Tuesday belongs to Monday.
nonisolated public struct PrayerEvent: Codable, Hashable, Identifiable, Sendable {
  /// The owning day: the row the event comes from, even if the event occurs after midnight.
  public var scheduleDay: CivilDay
  /// The kind of event.
  public var kind: PrayerKind
  /// The instant the event starts.
  public var time: Date
  /// The congregation (iqama) time, or `nil` when neither the source nor the iqama rules
  /// provide one.
  public var iqama: Date?
  /// How the prayer is observed: ``PrayerObservance/jumuah`` only when declared.
  public var observance: PrayerObservance

  /// Creates an event.
  public init(
    scheduleDay: CivilDay, kind: PrayerKind, time: Date, iqama: Date? = nil,
    observance: PrayerObservance = .ordinary
  ) {
    self.scheduleDay = scheduleDay
    self.kind = kind
    self.time = time
    self.iqama = iqama
    self.observance = observance
  }

  /// The occurrence identity: owning day, kind and instant, such as
  /// `"2026-06-21/isha/2026-06-21T23:15:00Z"`.
  ///
  /// The identity changes when the instant changes, so an app can use it to play an adhan
  /// once per occurrence. Notification requests use a separate logical identity.
  public var id: String {
    "\(scheduleDay)/\(kind.rawValue)/\(InstantText.format(time))"
  }
}
