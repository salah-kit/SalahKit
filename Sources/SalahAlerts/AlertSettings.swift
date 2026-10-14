import Foundation
import SalahCore

/// The kinds of alert a prayer can have: at its time, before it, after it.
///
/// `AlertKind` is `Comparable` in declaration order (`atTime`, `before`, `after`), the order
/// that breaks ties between identities (RFC 0003 §4.2).
nonisolated public enum AlertKind: String, Codable, Hashable, CaseIterable, Comparable, Sendable {
  /// At the prayer's time.
  case atTime
  /// A reminder before the prayer.
  case before
  /// A reminder after the prayer.
  case after

  /// Orders kinds as declared: at-time, before, after.
  public static func < (lhs: AlertKind, rhs: AlertKind) -> Bool {
    lhs.order < rhs.order
  }

  var order: Int {
    switch self {
    case .atTime: 0
    case .before: 1
    case .after: 2
    }
  }
}

/// The sound an alert asks for.
///
/// The app decides what the sound means: on a notification, `AlertSound.notificationSound`
/// maps it to the system's sounds; an app that plays its own audio reads it in
/// ``InProcessAlertEngine``'s `onDue`. Encodes as `"none"`, `"system"` or
/// `{"named": "<file>"}`.
nonisolated public enum AlertSound: Codable, Hashable, Sendable {
  /// No sound.
  case none
  /// The system's default sound.
  case system
  /// A sound file the app supplies; the platform's limits on notification sounds still apply.
  case named(String)

  /// Decodes `"none"`, `"system"` or `{"named": "<file>"}`.
  public init(from decoder: any Decoder) throws {
    if let container = try? decoder.singleValueContainer(),
      let text = try? container.decode(String.self)
    {
      switch text {
      case "none": self = .none
      case "system": self = .system
      default:
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Expected \"none\", \"system\" or {\"named\": file}, found \"\(text)\"."
        )
      }
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self = .named(try container.decode(String.self, forKey: .named))
  }

  /// Encodes `"none"`, `"system"` or `{"named": "<file>"}`.
  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .none:
      var container = encoder.singleValueContainer()
      try container.encode("none")
    case .system:
      var container = encoder.singleValueContainer()
      try container.encode("system")
    case .named(let name):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(name, forKey: .named)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case named
  }
}

/// Which alerts one prayer gets, and their sounds.
///
/// An at-time alert fires at the prayer's time, a before-reminder `before` earlier and an
/// after-reminder `after` later. Offsets are elapsed time, unaffected by clock changes. The
/// planner rejects an offset that isn't positive or is longer than its
/// `maximumReminderOffset` (``AlertPlanningError/reminderOffsetOutOfRange(_:_:_:)``).
///
/// Encodes with offsets in seconds:
///
/// ```json
/// {"atTime": true, "before": 600, "after": null,
///  "sound": "system", "beforeSound": "none", "afterSound": {"named": "chime.caf"}}
/// ```
///
/// Every key is optional when decoding, with the initializer's defaults. An offset must be a
/// finite number; a larger one is clamped to the date limit instead of trapping.
nonisolated public struct AlertSettings: Codable, Hashable, Sendable {
  /// Whether the prayer gets an alert at its time.
  public var atTime: Bool
  /// How long before the prayer its reminder fires, or `nil` for no reminder.
  public var before: Duration?
  /// How long after the prayer its reminder fires, or `nil` for no reminder.
  public var after: Duration?
  /// The at-time alert's sound.
  public var sound: AlertSound
  /// The before-reminder's sound.
  public var beforeSound: AlertSound
  /// The after-reminder's sound.
  public var afterSound: AlertSound

  /// Creates settings; by default an at-time alert with the system sound and no reminders.
  public init(
    atTime: Bool = true, before: Duration? = nil, after: Duration? = nil,
    sound: AlertSound = .system, beforeSound: AlertSound = .system,
    afterSound: AlertSound = .system
  ) {
    self.atTime = atTime
    self.before = before
    self.after = after
    self.sound = sound
    self.beforeSound = beforeSound
    self.afterSound = afterSound
  }

  private enum CodingKeys: String, CodingKey {
    case atTime, before, after, sound, beforeSound, afterSound
  }

  /// Decodes settings whose offsets are seconds; missing keys take the defaults.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      atTime: try container.decodeIfPresent(Bool.self, forKey: .atTime) ?? true,
      before: try container.decodeOffsetIfPresent(forKey: .before),
      after: try container.decodeOffsetIfPresent(forKey: .after),
      sound: try container.decodeIfPresent(AlertSound.self, forKey: .sound) ?? .system,
      beforeSound: try container.decodeIfPresent(AlertSound.self, forKey: .beforeSound) ?? .system,
      afterSound: try container.decodeIfPresent(AlertSound.self, forKey: .afterSound) ?? .system)
  }

  /// Encodes the settings with offsets in seconds.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(atTime, forKey: .atTime)
    try container.encode(before?.timeInterval, forKey: .before)
    try container.encode(after?.timeInterval, forKey: .after)
    try container.encode(sound, forKey: .sound)
    try container.encode(beforeSound, forKey: .beforeSound)
    try container.encode(afterSound, forKey: .afterSound)
  }

  /// The enabled alerts, in kind order, with their offsets from the prayer's time in seconds
  /// (negative before it) and their sounds.
  var enabledAlerts: [(kind: AlertKind, offset: TimeInterval, sound: AlertSound)] {
    var alerts: [(kind: AlertKind, offset: TimeInterval, sound: AlertSound)] = []
    if atTime { alerts.append((.atTime, 0, sound)) }
    if let before { alerts.append((.before, -before.timeInterval, beforeSound)) }
    if let after { alerts.append((.after, after.timeInterval, afterSound)) }
    return alerts
  }
}

/// What the planner asks settings for: a prayer of an owning day, with its observance.
///
/// A known event supplies its own day, kind and observance. A gap in the source supplies its
/// day and each kind it hides; on a Friday's Dhuhr, whose observance the source could have
/// declared either way, the planner asks for both (RFC 0003 §4.3).
nonisolated public struct AlertSubject: Hashable, Sendable {
  /// The owning day: the day the prayer belongs to, even when it falls after midnight.
  public var scheduleDay: CivilDay
  /// The prayer, or sunrise.
  public var prayer: PrayerKind
  /// How the prayer is observed: Jumu'ah only when the source declares it.
  public var observance: PrayerObservance

  /// Creates a subject.
  public init(
    scheduleDay: CivilDay, prayer: PrayerKind, observance: PrayerObservance = .ordinary
  ) {
    self.scheduleDay = scheduleDay
    self.prayer = prayer
    self.observance = observance
  }
}

nonisolated extension Duration {
  /// The duration in seconds, as a `TimeInterval`.
  var timeInterval: TimeInterval {
    let parts = components
    return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
  }
}

nonisolated extension KeyedDecodingContainer {
  /// An offset in seconds: a finite number, clamped to the date limit so that
  /// `Duration.seconds(_:)` can't trap.
  fileprivate func decodeOffsetIfPresent(forKey key: Key) throws -> Duration? {
    guard let seconds = try decodeIfPresent(Double.self, forKey: key) else { return nil }
    guard seconds.isFinite else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: self, debugDescription: "Expected a finite number of seconds.")
    }
    // About 2.7 million years, the date limit SalahCore uses for durations.
    let limit = 86_400_000_000_000.0
    return .seconds(Swift.min(Swift.max(seconds, -limit), limit))
  }
}
