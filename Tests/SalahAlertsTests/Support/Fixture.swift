import Foundation
import SalahAlerts
import SalahCore

/// Salah's characterization fixture (A2, Salah `a0206dd`): Makkah, Tuesday 2 June 2026, with
/// Fajr 04:11, Sunrise 05:38, Dhuhr 12:19, Asr 15:35, Maghrib 19:00 and Isha 20:30. Every day of
/// the timetable repeats those times, so day arithmetic stays checkable.
nonisolated enum Fixture {
  static let zone = TimeZone(identifier: "Asia/Riyadh") ?? .gmt
  static let location = PrayerLocation(
    latitude: 21.4225, longitude: 39.8262, timeZone: zone, countryCode: "SA", name: "Makkah")
  static let day = CivilDay(year: 2026, month: 6, day: 2)
  static let times: [PrayerKind: (Int, Int)] = [
    .fajr: (4, 11), .sunrise: (5, 38), .dhuhr: (12, 19), .asr: (15, 35), .maghrib: (19, 0),
    .isha: (20, 30),
  ]

  /// Rows from 25 May to 30 June 2026.
  static func source(dropping dropped: [CivilDay: Set<PrayerKind>] = [:]) -> TimetableSource {
    var rows: [TimetableSource.Row] = []
    var current = CivilDay(year: 2026, month: 5, day: 25)
    while current <= CivilDay(year: 2026, month: 6, day: 30) {
      var row: [PrayerKind: TimetableTime] = [:]
      for (kind, time) in times where !(dropped[current]?.contains(kind) ?? false) {
        row[kind] = .local(WallClockTime(hour: time.0, minute: time.1))
      }
      rows.append(TimetableSource.Row(day: current, times: row))
      current = current.adding(days: 1)
    }
    return TimetableSource(rows: rows, expectedKinds: Set(PrayerKind.allCases))
  }

  static let schedule = PrayerSchedule(source: source(), location: location)

  /// The instant of a wall-clock time in Makkah, `dayOffset` days after 2 June.
  static func date(_ hour: Int, _ minute: Int, second: Double = 0, dayOffset: Int = 0) -> Date {
    day.adding(days: dayOffset).start(in: zone)
      .addingTimeInterval(TimeInterval(hour * 3_600 + minute * 60) + second)
  }

  /// The prayer's time on 2 June, or `dayOffset` days after.
  static func time(_ kind: PrayerKind, dayOffset: Int = 0) -> Date {
    let (hour, minute) = times[kind] ?? (0, 0)
    return date(hour, minute, dayOffset: dayOffset)
  }

  /// Settings that give each listed prayer the same settings, and the others none.
  static func settings(
    _ settings: AlertSettings,
    for prayers: Set<PrayerKind> = [.fajr, .dhuhr, .asr, .maghrib, .isha]
  ) -> (AlertSubject) -> AlertSettings? {
    { subject in prayers.contains(subject.prayer) ? settings : nil }
  }

  /// An alert schedule of the fixture.
  static func alerts(
    from start: Date, to end: Date, namespace: String = "prayers",
    schedule: PrayerSchedule = Fixture.schedule,
    settings: (AlertSubject) -> AlertSettings?
  ) throws -> AlertSchedule {
    try AlertPlanner().schedule(
      schedule, namespace: namespace, from: start, to: end, settings: settings)
  }

  static func identity(
    _ prayer: PrayerKind, _ kind: AlertKind, dayOffset: Int = 0, namespace: String = "prayers"
  ) -> NotificationIdentity {
    NotificationIdentity(
      namespace: namespace, scheduleDay: day.adding(days: dayOffset), prayer: prayer, kind: kind)
  }

  static func minutes(_ value: Int) -> Duration { .seconds(value * 60) }
}

/// An alert clock that only moves when a test moves it, and keeps the wake-ups it was asked for.
@MainActor final class ManualAlertClock: AlertClock {
  var now: Date
  private(set) var wakes: [Date?] = []
  private var action: (@MainActor @Sendable () -> Void)?

  init(_ now: Date) {
    self.now = now
  }

  /// The wake-up armed last, if any.
  var armed: Date? { wakes.last ?? nil }

  func wake(at date: Date?, perform action: @escaping @MainActor @Sendable () -> Void) {
    wakes.append(date)
    self.action = date == nil ? nil : action
  }

  /// Moves the clock to the armed instant and fires the wake-up, as a timer would.
  func fire() {
    guard let armed, let action else { return }
    now = armed
    self.action = nil
    action()
  }
}
