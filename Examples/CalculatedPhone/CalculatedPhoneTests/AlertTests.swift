import Foundation
import SalahAlerts
import SalahCore
import Testing
import UserNotifications

@testable import CalculatedPhone

/// The app's alerts below the UI: options, planning, the fixture, content, the failing center,
/// the coordinator and the Alerts card's text.
struct AlertTests {
  static let makkahNoon = Date(timeIntervalSince1970: 1_791_968_400)  // 2026-10-14 12:00 +03:00

  // MARK: Options and settings

  @Test func optionsGiveTheFivePrayersTheirAlerts() {
    let day = CivilDay(year: 2026, month: 10, day: 14)
    var options = PhoneAlertOptions()
    #expect(options.settings(for: AlertSubject(scheduleDay: day, prayer: .dhuhr)) == nil)
    options.isOn = true
    #expect(
      options.settings(for: AlertSubject(scheduleDay: day, prayer: .dhuhr)) == AlertSettings())
    #expect(options.settings(for: AlertSubject(scheduleDay: day, prayer: .sunrise)) == nil)
    options.reminderMinutes = 10
    #expect(
      options.settings(for: AlertSubject(scheduleDay: day, prayer: .isha))
        == AlertSettings(before: .seconds(600)))
  }

  @Test func settingsStoredBeforeAlertsDecodeWithAlertsOff() throws {
    var object = try #require(
      try JSONSerialization.jsonObject(with: AppSettings.defaults.encoded()) as? [String: Any])
    object["alerts"] = nil
    let old = try JSONSerialization.data(withJSONObject: object)
    #expect(AppSettings.decoded(from: old) == .defaults)
    #expect(AppSettings.decoded(from: old)?.alerts.isOn == false)

    var settings = AppSettings.defaults
    settings.alerts = PhoneAlertOptions(isOn: true, reminderMinutes: 15)
    #expect(AppSettings.decoded(from: try settings.encoded()) == settings)
  }

  @Test func launchArgumentsForAlerts() throws {
    let options = LaunchOptions(arguments: [
      "-alerts", "on", "-alertReminder", "10", "-alertFixtureIn", "90", "-alertFixtureDay",
      "2026-10-14", "-failAlertAdds", "dhuhr,asr,nope",
    ])
    #expect(options.alerts == true)
    #expect(options.alertReminder == 10)
    #expect(options.alertFixtureIn == 90)
    #expect(options.alertFixtureDay == CivilDay(year: 2026, month: 10, day: 14))
    #expect(options.failAlertAdds == [.dhuhr, .asr])
    var settings = AppSettings.defaults
    options.apply(to: &settings)
    #expect(settings.alerts == PhoneAlertOptions(isOn: true, reminderMinutes: 10))

    let off = LaunchOptions(arguments: ["-alerts", "off", "-alertReminder", "0"])
    off.apply(to: &settings)
    #expect(settings.alerts == PhoneAlertOptions(isOn: false, reminderMinutes: nil))

    let unreadable = LaunchOptions(arguments: [
      "-alerts", "maybe", "-alertReminder", "7", "-alertFixtureIn", "-5", "-alertFixtureDay",
      "2026-02-30",
    ])
    #expect(unreadable == LaunchOptions())
  }

  // MARK: Planning

  /// Makkah with alerts and a 10-minute reminder, planned at noon: the near term fills two days
  /// with ten alerts a day, the rest of the budget goes to at-time alerts, and coverage ends at
  /// the third day's first reminder.
  @Test func theMakkahPlanFillsTheBudget() throws {
    var settings = AppSettings.defaults
    settings.alerts = PhoneAlertOptions(isOn: true, reminderMinutes: 10)
    let plan = try PhoneAlertPlanning.plan(settings: settings, fixture: nil, at: Self.makkahNoon)
    #expect(plan.alerts.count == 60)
    #expect(plan.namespace == PhoneAlertPlanning.namespace)
    let reminders = plan.alerts.filter { $0.kind == .before }
    #expect(reminders.count == 10)
    #expect(reminders.allSatisfy { $0.fireDate < Self.makkahNoon.addingTimeInterval(2 * 86_400) })
    #expect(
      plan.coverageByKind[.before] ?? .distantFuture < plan.coverageByKind[.atTime] ?? .distantPast)
    #expect(plan.coveredUntil == plan.coverageByKind[.before])
  }

  @Test func alertsOffPlanNothing() throws {
    let plan = try PhoneAlertPlanning.plan(
      settings: .defaults, fixture: nil, at: Self.makkahNoon)
    #expect(plan.alerts.isEmpty)
  }

  /// The fixture: five prayers a minute apart from its first prayer, owned by its day, and the
  /// same times on the days around it.
  @Test func theFixtureIsFivePrayersAMinuteApart() throws {
    let first = Self.makkahNoon.addingTimeInterval(100)
    let fixture = AlertFixture(firstPrayer: first, day: CivilDay(year: 2026, month: 10, day: 14))
    var settings = AppSettings.defaults
    settings.alerts.isOn = true
    let schedule = PhoneAlertPlanning.prayerSchedule(settings: settings, fixture: fixture)
    let today = try #require(schedule.day(fixture.day).day)
    #expect(today.events.map(\.kind) == AlertFixture.kinds)
    #expect(today.events.map(\.time) == (0..<5).map { first.addingTimeInterval(Double($0) * 60) })
    #expect(schedule.day(fixture.day.adding(days: 1)).day?.events.first?.time == first + 86_400)

    let plan = try PhoneAlertPlanning.plan(
      settings: settings, fixture: fixture, at: Self.makkahNoon)
    #expect(plan.alerts.prefix(5).map(\.fireDate) == today.events.map(\.time))
    #expect(plan.alerts.first?.id.scheduleDay == fixture.day)
  }

  // MARK: Content

  @Test func contentInEnglishAndArabic() throws {
    let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
    let day = CivilDay(year: 2026, month: 10, day: 14)
    let dhuhr = PrayerEvent(
      scheduleDay: day, kind: .dhuhr, time: Self.makkahNoon.addingTimeInterval(420))
    func alert(_ kind: AlertKind, _ offset: TimeInterval) -> PlannedAlert {
      PlannedAlert(
        id: NotificationIdentity(
          namespace: "prayers", scheduleDay: day, prayer: .dhuhr, kind: kind),
        event: dhuhr, fireDate: dhuhr.time.addingTimeInterval(offset), sound: .system)
    }
    let english = PhoneAlertContent(strings: PhoneStrings(language: "en"), timeZone: zone)
    #expect(english.title(alert(.atTime, 0)) == "Dhuhr")
    #expect(english.body(alert(.atTime, 0)).filter(Self.isVisible) == "It's time for Dhuhr (12:07)")
    #expect(english.body(alert(.before, -600)).filter(Self.isVisible) == "Dhuhr in 10 minutes")
    let content = english.make(alert(.before, -600))
    #expect(content.sound == .default)
    #expect(content.title == "Dhuhr")

    let arabic = PhoneAlertContent(strings: PhoneStrings(language: "ar"), timeZone: zone)
    #expect(arabic.title(alert(.atTime, 0)) == "الظهر")
    #expect(arabic.body(alert(.atTime, 0)).filter(Self.isVisible) == "حان وقت الظهر (١٢:٠٧)")
  }

  /// Foundation wraps interpolated arguments in directional isolates (U+2068, U+2069).
  static func isVisible(_ character: Character) -> Bool {
    character != "\u{2068}" && character != "\u{2069}"
  }

  // MARK: The failing center

  @Test nonisolated func theFailingCenterRejectsTheChosenPrayers() async throws {
    let base = RecordingCenter()
    let center = FailingNotificationCenter(base: base, failing: [.dhuhr])
    func request(_ prayer: String) -> UNNotificationRequest {
      UNNotificationRequest(
        identifier: "\(PhoneAlertPlanning.identifierPrefix)prayers/2026-10-14/\(prayer)/atTime",
        content: UNMutableNotificationContent(), trigger: nil)
    }
    await #expect(throws: FailingNotificationCenter.InjectedFailure.self) {
      try await center.add(request("dhuhr"))
    }
    try await center.add(request("asr"))
    #expect(base.added == ["\(PhoneAlertPlanning.identifierPrefix)prayers/2026-10-14/asr/atTime"])
  }

  // MARK: The coordinator

  @MainActor
  @Test func theCoordinatorPlansInstallsAndReadsBack() async throws {
    let center = RecordingCenter()
    var options = LaunchOptions()
    options.alertFixtureIn = 100
    let coordinator = AlertCoordinator(
      options: options, launch: Self.makkahNoon, center: center, requestPermission: {})
    var settings = AppSettings.defaults
    settings.alerts.isOn = true
    await coordinator.replan(
      settings: settings, strings: PhoneStrings(language: "en"), now: Self.makkahNoon)

    #expect(coordinator.usesFixture)
    #expect(coordinator.report?.confirmed.count == 60)
    #expect(coordinator.pending.count == 60)
    #expect(coordinator.pending.first?.fireDate == Self.makkahNoon.addingTimeInterval(100))
    #expect(coordinator.authorization == .authorized)
  }

  @MainActor
  @Test func theCoordinatorAsksOnlyWhenUndetermined() async {
    let center = RecordingCenter(status: .notDetermined)
    let asked = Counter()
    let coordinator = AlertCoordinator(
      options: LaunchOptions(), center: center,
      requestPermission: {
        asked.value += 1
        center.status = .authorized
      })
    await coordinator.requestPermissionIfNeeded()
    await coordinator.requestPermissionIfNeeded()
    #expect(asked.value == 1)
    #expect(coordinator.authorization == .authorized)
  }

  @MainActor final class Counter {
    var value = 0
  }

  // MARK: The card

  @Test func theCardShowsStatusesAndCoverage() throws {
    let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
    let day = CivilDay(year: 2026, month: 10, day: 14)
    func identity(_ prayer: PrayerKind) -> NotificationIdentity {
      NotificationIdentity(namespace: "prayers", scheduleDay: day, prayer: prayer, kind: .atTime)
    }
    let asr = Self.makkahNoon.addingTimeInterval(3 * 3_600 + 27 * 60)
    let maghrib = Self.makkahNoon.addingTimeInterval(5 * 3_600 + 57 * 60)
    let report = NotificationApplyReport(
      verifiedAt: Self.makkahNoon,
      confirmed: [AlertOccurrenceID(notification: identity(.asr), fireDate: asr)],
      failures: [identity(.maghrib): .addFailed("injected"), identity(.isha): .unconfirmed],
      superseded: false, confirmedCoveredUntil: maghrib)
    let snapshot = AlertsSnapshot.make(
      options: PhoneAlertOptions(isOn: true), authorization: .authorized, plan: nil,
      report: report,
      pending: [
        PendingAlert(identity: identity(.asr), fireDate: asr),
        PendingAlert(identity: identity(.maghrib), fireDate: maghrib.addingTimeInterval(-60)),
      ],
      fromFixture: false, strings: PhoneStrings(language: "en"), timeZone: zone)
    #expect(snapshot.status == "Notifications are allowed.")
    #expect(snapshot.scheduledUntil?.filter(Self.isVisible) == "Scheduled until Wednesday 17:57")
    #expect(snapshot.rows.map(\.status) == ["Confirmed", "Couldn't be scheduled"])
    #expect(snapshot.rows.map(\.id) == ["2026-10-14/asr/atTime", "2026-10-14/maghrib/atTime"])
    #expect(snapshot.rows.last?.time == "Wednesday 17:56")
    #expect(
      snapshot.failures.map { $0.filter(Self.isVisible) } == [
        "Isha, Wednesday, October 14, 2026: Not confirmed"
      ])

    let off = AlertsSnapshot.make(
      options: PhoneAlertOptions(), authorization: nil, plan: nil, report: nil, pending: [],
      fromFixture: false, strings: PhoneStrings(language: "en"), timeZone: zone)
    #expect(off.status == "Alerts are off. Turn them on in Settings.")
    #expect(off.pendingCount == nil)
  }
}

/// A notification center that keeps what's added, authorized unless told otherwise.
nonisolated final class RecordingCenter: AlertNotificationCenter, @unchecked Sendable {
  // @unchecked: every stored property is read and written while holding `lock`, and the
  // requests it keeps are immutable.
  private let lock = NSLock()
  private var requests: [String: UNNotificationRequest] = [:]
  private var identifiers: [String] = []
  private var currentStatus: UNAuthorizationStatus

  init(status: UNAuthorizationStatus = .authorized) {
    currentStatus = status
  }

  var status: UNAuthorizationStatus {
    get { lock.withLock { currentStatus } }
    set { lock.withLock { currentStatus = newValue } }
  }

  var added: [String] { lock.withLock { identifiers } }

  func authorizationStatus() async -> UNAuthorizationStatus { status }

  func pendingNotificationRequests() async throws -> [UNNotificationRequest] {
    lock.withLock { Array(requests.values) }
  }

  func add(_ request: UNNotificationRequest) async throws {
    lock.withLock {
      identifiers.append(request.identifier)
      if request.trigger != nil { requests[request.identifier] = request }
    }
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
    lock.withLock { for identifier in identifiers { requests[identifier] = nil } }
  }

  func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] { [] }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {}
}
