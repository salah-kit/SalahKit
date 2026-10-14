import Foundation
import SalahCore

/// The logical identity of an alert: its namespace, the owning day, the prayer and the alert
/// kind.
///
/// The identity excludes the fire date, the calculation settings, the reminder offset and the
/// text, so moving a reminder, changing a calculation or rewording an alert keeps it. A
/// notification request uses it as its identifier (``requestIdentifier(prefix:)``), so adding
/// the changed request replaces the old one. The owning day is the event's: Monday's Isha at
/// 00:15 on Tuesday, and its reminders, belong to Monday.
///
/// Identities are ordered by namespace, then owning day, then prayer in canonical order, then
/// alert kind. With the fire date first, that order sorts every alert list in SalahAlerts.
nonisolated public struct NotificationIdentity: Codable, Hashable, Comparable, Sendable {
  /// The namespace of the schedule that planned the alert. Not empty, and no `/`.
  public var namespace: String
  /// The event's owning day.
  public var scheduleDay: CivilDay
  /// The prayer, or sunrise.
  public var prayer: PrayerKind
  /// The kind of alert.
  public var kind: AlertKind

  /// Creates an identity.
  public init(namespace: String, scheduleDay: CivilDay, prayer: PrayerKind, kind: AlertKind) {
    self.namespace = namespace
    self.scheduleDay = scheduleDay
    self.prayer = prayer
    self.kind = kind
  }

  /// Whether a string can be a namespace: it isn't empty and has no `/`.
  public static func isValidNamespace(_ namespace: String) -> Bool {
    // Scalars, not characters: a scalar such as U+0600 joins a following "/" into one character.
    !namespace.isEmpty && !namespace.unicodeScalars.contains("/")
  }

  /// The identifier of the notification request for this identity:
  /// `<prefix><namespace>/<scheduleDay>/<prayer>/<kind>`, such as
  /// `salah.prayers/2026-06-02/dhuhr/before`.
  public func requestIdentifier(prefix: String) -> String {
    "\(prefix)\(namespace)/\(scheduleDay)/\(prayer.rawValue)/\(kind.rawValue)"
  }

  /// The identity a request identifier names, or `nil` when it doesn't name one under
  /// `prefix`.
  ///
  /// The identifier must start with the prefix, and the rest must be exactly four parts
  /// separated by `/`: a valid namespace, a valid day as `YYYY-MM-DD`, a `PrayerKind` raw value
  /// and an ``AlertKind`` raw value.
  public init?(requestIdentifier: String, prefix: String) {
    // Scalar by scalar: a namespace can start with a combining mark that joins the prefix's last
    // character, or end with a scalar that joins the next "/", so characters would miss either.
    let scalars = requestIdentifier.unicodeScalars
    guard scalars.starts(with: prefix.unicodeScalars) else { return nil }
    let parts = scalars.dropFirst(prefix.unicodeScalars.count)
      .split(separator: "/", omittingEmptySubsequences: false)
      .map { String(Substring($0)) }
    guard parts.count == 4, Self.isValidNamespace(String(parts[0])),
      let day = CivilDay(String(parts[1])), day.isValid,
      let prayer = PrayerKind(rawValue: String(parts[2])),
      let kind = AlertKind(rawValue: String(parts[3]))
    else { return nil }
    self.init(namespace: String(parts[0]), scheduleDay: day, prayer: prayer, kind: kind)
  }

  /// Orders identities by namespace, owning day, prayer and kind.
  public static func < (lhs: NotificationIdentity, rhs: NotificationIdentity) -> Bool {
    if lhs.namespace != rhs.namespace { return lhs.namespace < rhs.namespace }
    if lhs.scheduleDay != rhs.scheduleDay { return lhs.scheduleDay < rhs.scheduleDay }
    if lhs.prayer != rhs.prayer { return lhs.prayer < rhs.prayer }
    return lhs.kind < rhs.kind
  }
}

/// One concrete delivery of an alert: its identity and its fire date.
///
/// When a prayer's time changes, its identity stays and its occurrence changes, so
/// ``InProcessAlertEngine`` can tell a new occurrence from one it has handled.
nonisolated public struct AlertOccurrenceID: Codable, Hashable, Sendable {
  /// The alert's identity.
  public var notification: NotificationIdentity
  /// When this occurrence fires.
  public var fireDate: Date

  /// Creates an occurrence.
  public init(notification: NotificationIdentity, fireDate: Date) {
    self.notification = notification
    self.fireDate = fireDate
  }
}

/// An alert the planner placed: its identity, the event it's about, when it fires and its
/// sound.
nonisolated public struct PlannedAlert: Hashable, Identifiable, Sendable {
  /// The alert's identity.
  public var id: NotificationIdentity
  /// The prayer event the alert is about.
  public var event: PrayerEvent
  /// When the alert fires: the event's time, or that time moved by the reminder's offset.
  public var fireDate: Date
  /// The sound the settings chose for this kind of alert.
  public var sound: AlertSound

  /// Creates a planned alert.
  public init(id: NotificationIdentity, event: PrayerEvent, fireDate: Date, sound: AlertSound) {
    self.id = id
    self.event = event
    self.fireDate = fireDate
    self.sound = sound
  }

  /// The kind of alert.
  public var kind: AlertKind { id.kind }

  /// This occurrence: the identity and the fire date.
  public var occurrenceID: AlertOccurrenceID {
    AlertOccurrenceID(notification: id, fireDate: fireDate)
  }

  /// Fire date, then identity: the order of every alert list in SalahAlerts.
  static func precedes(_ lhs: PlannedAlert, _ rhs: PlannedAlert) -> Bool {
    lhs.fireDate != rhs.fireDate ? lhs.fireDate < rhs.fireDate : lhs.id < rhs.id
  }
}
