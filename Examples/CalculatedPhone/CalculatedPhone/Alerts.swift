import Foundation
import SalahAlerts
import SalahCore
import UserNotifications

/// The alerts the user chose: an alert at each of the five prayers, and an optional reminder
/// before each one.
nonisolated struct PhoneAlertOptions: Codable, Hashable, Sendable {
  /// Whether the five prayers get alerts.
  var isOn = false
  /// How many minutes before each prayer its reminder fires, or `nil` for none.
  var reminderMinutes: Int?

  /// The reminders Settings offers.
  static let reminderChoices: [Int?] = [nil, 5, 10, 15, 30]
  /// The longest reminder the app allows, which the planner enforces.
  static let maximumReminder = Duration.seconds(30 * 60)

  /// The settings for a subject: the five prayers, never sunrise.
  func settings(for subject: AlertSubject) -> AlertSettings? {
    guard isOn, subject.prayer.isPrayer else { return nil }
    return AlertSettings(before: reminderMinutes.map { .seconds($0 * 60) })
  }
}

/// A timetable for the alert journeys: the five prayers a minute apart from `firstPrayer`,
/// owned by `day`, and the same times on the days around it.
///
/// `-alertFixtureIn <seconds>` puts the first prayer that long after launch, so a test or a
/// person can watch alerts arrive without waiting for a real prayer. Only alerts use it; the
/// screen keeps showing the calculated times.
nonisolated struct AlertFixture: Hashable, Sendable {
  var firstPrayer: Date
  var day: CivilDay

  static let kinds: [PrayerKind] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

  /// Rows from two days before `day` to thirteen after, each a whole number of days from the
  /// fixture's own times.
  var source: TimetableSource {
    let rows = (-2...13).map { offset in
      var times: [PrayerKind: TimetableTime] = [:]
      for (index, kind) in Self.kinds.enumerated() {
        times[kind] = .instant(
          firstPrayer.addingTimeInterval(Double(index * 60) + Double(offset) * 86_400))
      }
      return TimetableSource.Row(day: day.adding(days: offset), times: times)
    }
    return TimetableSource(rows: rows, expectedKinds: Set(Self.kinds))
  }
}

/// How the app plans its alerts: one namespace, a 14-day range, the default budget.
nonisolated enum PhoneAlertPlanning {
  /// The namespace of the app's prayer alerts.
  static let namespace = "prayers"
  /// The prefix of every request identifier the app writes.
  static let identifierPrefix = "io.github.salah-kit.CalculatedPhone."
  /// The thread that groups the app's notifications.
  static let thread = "prayers"
  /// How far ahead the app plans.
  static let range: TimeInterval = 14 * 86_400

  /// The prayer schedule the alerts follow: the settings' calculation, or the fixture.
  static func prayerSchedule(settings: AppSettings, fixture: AlertFixture?) -> PrayerSchedule {
    guard let fixture else { return settings.schedule }
    return PrayerSchedule(source: fixture.source, location: settings.place.location)
  }

  /// The notification plan at `now`.
  static func plan(
    settings: AppSettings, fixture: AlertFixture?, at now: Date
  ) throws(AlertPlanningError) -> NotificationPlan {
    let planner = AlertPlanner()
    let alerts = try planner.schedule(
      prayerSchedule(settings: settings, fixture: fixture), namespace: namespace, from: now,
      to: now.addingTimeInterval(range),
      maximumReminderOffset: PhoneAlertOptions.maximumReminder,
      settings: settings.alerts.settings(for:))
    return planner.notificationPlan(alerts, from: now)
  }
}

/// The text of the app's notifications, in the app's language and the place's time zone.
nonisolated struct PhoneAlertContent: Sendable {
  let strings: PhoneStrings
  let format: PhoneFormat

  init(strings: PhoneStrings, timeZone: TimeZone) {
    self.strings = strings
    format = PhoneFormat(strings: strings, timeZone: timeZone)
  }

  /// The title: the prayer's name.
  func title(_ alert: PlannedAlert) -> String {
    strings.names.name(of: alert.event)
  }

  /// The body: "It's time for Dhuhr (12:19)" or "Dhuhr in 10 minutes".
  func body(_ alert: PlannedAlert) -> String {
    let name = strings.names.name(of: alert.event)
    switch alert.kind {
    case .atTime:
      return strings("It's time for \(name) (\(format.time(alert.event.time)))")
    case .before, .after:
      let minutes = PrayerDurationFormat.string(
        abs(alert.event.time.timeIntervalSince(alert.fireDate)), width: .spoken,
        locale: strings.locale)
      return alert.kind == .before
        ? strings("\(name) in \(minutes)") : strings("\(name) began \(minutes) ago")
    }
  }

  /// The notification content the scheduler installs.
  func make(_ alert: PlannedAlert) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = title(alert)
    content.body = body(alert)
    content.sound = alert.sound.notificationSound
    return content
  }
}

/// A pending request the app read back: its identity and when it fires.
nonisolated struct PendingAlert: Hashable, Sendable {
  var identity: NotificationIdentity
  var fireDate: Date

  /// The app's own requests among `requests`, by fire date and identity.
  static func owned(_ requests: [UNNotificationRequest]) -> [PendingAlert] {
    requests.compactMap { request in
      guard
        let identity = NotificationIdentity(
          requestIdentifier: request.identifier, prefix: PhoneAlertPlanning.identifierPrefix),
        identity.namespace == PhoneAlertPlanning.namespace,
        let trigger = request.trigger as? UNCalendarNotificationTrigger,
        let fireDate = trigger.instant
      else { return nil }
      return PendingAlert(identity: identity, fireDate: fireDate)
    }
    .sorted { ($0.fireDate, $0.identity) < ($1.fireDate, $1.identity) }
  }
}

nonisolated extension UNCalendarNotificationTrigger {
  /// The instant the trigger names, in its own calendar and time zone.
  var instant: Date? {
    var components = dateComponents
    var calendar = components.calendar ?? Calendar(identifier: .gregorian)
    calendar.timeZone = components.timeZone ?? components.calendar?.timeZone ?? .current
    components.calendar = nil
    components.timeZone = nil
    return calendar.date(from: components)
  }
}

/// The system's notification center, with adds that fail for chosen prayers.
///
/// `-failAlertAdds dhuhr` makes the journeys' scheduling failure: the scheduler's add of
/// Dhuhr's request throws, so its old request stays and the report says so.
nonisolated final class FailingNotificationCenter: AlertNotificationCenter {
  struct InjectedFailure: LocalizedError {
    var errorDescription: String? { "An injected scheduling failure." }
  }

  let base: any AlertNotificationCenter
  let failing: Set<PrayerKind>

  init(base: any AlertNotificationCenter, failing: Set<PrayerKind>) {
    self.base = base
    self.failing = failing
  }

  func authorizationStatus() async -> UNAuthorizationStatus {
    await base.authorizationStatus()
  }

  func pendingNotificationRequests() async throws -> [UNNotificationRequest] {
    try await base.pendingNotificationRequests()
  }

  func add(_ request: UNNotificationRequest) async throws {
    if let identity = NotificationIdentity(
      requestIdentifier: request.identifier, prefix: PhoneAlertPlanning.identifierPrefix),
      failing.contains(identity.prayer)
    {
      throw InjectedFailure()
    }
    try await base.add(request)
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
    await base.removePendingNotificationRequests(withIdentifiers: identifiers)
  }

  func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] {
    await base.deliveredNotificationRecords()
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
    await base.removeDeliveredNotifications(withIdentifiers: identifiers)
  }
}

/// What the Alerts card shows, as text in the app's language.
nonisolated struct AlertsSnapshot: Equatable, Sendable {
  /// One pending request the read-back found.
  struct Row: Equatable, Identifiable, Sendable {
    /// `2026-10-14/dhuhr/atTime`: the identity without its namespace.
    var id: String
    var title: String
    var time: String
    var status: String
  }

  /// "Alerts are off" or the authorization.
  var status: String
  /// "Scheduled until …" from the confirmed coverage, when there is a report.
  var scheduledUntil: String?
  /// "Planned until …" from the plan.
  var plannedUntil: String?
  /// "60 pending requests".
  var pendingCount: String?
  /// The first pending requests.
  var rows: [Row]
  /// Failures of alerts that have no pending request.
  var failures: [String]
  /// Whether the alerts come from the fixture timetable.
  var fromFixture: Bool
  /// "The system kept 64 of 70 probe requests."
  var probe: String?

  /// How many pending requests the card lists.
  static let shownRows = 6

  static func make(
    options: PhoneAlertOptions, authorization: UNAuthorizationStatus?, plan: NotificationPlan?,
    report: NotificationApplyReport?, pending: [PendingAlert], fromFixture: Bool,
    probe: (kept: Int, added: Int)? = nil, strings: PhoneStrings, timeZone: TimeZone
  ) -> AlertsSnapshot {
    let format = PhoneFormat(strings: strings, timeZone: timeZone)
    func when(_ date: Date) -> String {
      let day = CivilDay(containing: date, in: timeZone)
      return "\(format.weekday(day)) \(format.time(date))"
    }
    let status: String =
      if !options.isOn {
        strings("Alerts are off. Turn them on in Settings.")
      } else {
        switch authorization {
        case .authorized?, .provisional?: strings("Notifications are allowed.")
        case .denied?: strings("Notifications are turned off in the Settings app.")
        default: strings("Notifications aren't allowed yet.")
        }
      }
    let confirmed = Set(report?.confirmed ?? [])
    func statusText(_ identity: NotificationIdentity, fireDate: Date) -> String {
      if confirmed.contains(AlertOccurrenceID(notification: identity, fireDate: fireDate)) {
        return strings("Confirmed")
      }
      switch report?.failures[identity] {
      case .notAuthorized?: return strings("Notifications aren't allowed")
      case .addFailed?: return strings("Couldn't be scheduled")
      case .unconfirmed?: return strings("Not confirmed")
      case nil: return strings("Pending")
      }
    }
    func title(_ identity: NotificationIdentity) -> String {
      let name = strings.names.name(of: identity.prayer)
      switch identity.kind {
      case .atTime: return name
      case .before: return strings("\(name) reminder")
      case .after: return strings("After \(name)")
      }
    }
    let shown = pending.prefix(shownRows).map { alert in
      Row(
        id:
          "\(alert.identity.scheduleDay)/\(alert.identity.prayer.rawValue)/\(alert.identity.kind.rawValue)",
        title: title(alert.identity), time: when(alert.fireDate),
        status: statusText(alert.identity, fireDate: alert.fireDate))
    }
    let pendingIdentities = Set(pending.map(\.identity))
    let failures = (report?.failures ?? [:])
      .filter { !pendingIdentities.contains($0.key) }
      .sorted { $0.key < $1.key }
      .prefix(shownRows)
      .map { identity, _ in
        "\(title(identity)), \(format.longDate(identity.scheduleDay)): \(statusText(identity, fireDate: .distantPast))"
      }
    return AlertsSnapshot(
      status: status,
      scheduledUntil: report?.confirmedCoveredUntil.map {
        strings("Scheduled until \(when($0))")
      },
      plannedUntil: plan.map { strings("Planned until \(when($0.coveredUntil))") },
      pendingCount: options.isOn ? strings("\(pending.count) pending requests") : nil,
      rows: shown, failures: failures, fromFixture: fromFixture,
      probe: probe.map { strings("The system kept \($0.kept) of \($0.added) probe requests.") })
  }
}
