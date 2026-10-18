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
    // The verb agrees with وقت, so it fits every name, the feminine الجمعة included.
    #expect(english.body(alert(.after, 600)).filter(Self.isVisible) == "Dhuhr began 10 minutes ago")
    #expect(arabic.body(alert(.after, 600)).filter(Self.isVisible).hasPrefix("بدأ وقت الظهر منذ "))
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

  /// The scheduler adds only alerts after its own clock's now, which is the real one, so the
  /// coordinator tests plan from the real clock too.
  @MainActor
  @Test func theCoordinatorPlansInstallsAndReadsBack() async throws {
    let center = RecordingCenter()
    var options = LaunchOptions()
    options.alertFixtureIn = 100
    let launch = Date()
    let coordinator = AlertCoordinator(
      options: options, launch: launch, center: center, requestPermission: {})
    var settings = AppSettings.defaults
    settings.alerts.isOn = true
    await coordinator.replan(settings: settings, strings: PhoneStrings(language: "en"), now: launch)

    #expect(coordinator.usesFixture)
    #expect(coordinator.report?.confirmed.count == 60)
    #expect(coordinator.pending.count == 60)
    // The trigger names a whole second, rounded up from the fixture's first prayer.
    let first = (launch.timeIntervalSinceReferenceDate + 100 - 0.001).rounded(.up)
    #expect(coordinator.pending.first?.fireDate == Date(timeIntervalSinceReferenceDate: first))
    #expect(coordinator.authorization == .authorized)
    #expect(center.added.count == 60)
    // The card shows every request it lists as confirmed, though the fixture's times have
    // fractions of a second and the requests' triggers don't.
    let snapshot = AlertsSnapshot.make(
      options: settings.alerts, authorization: coordinator.authorization, plan: coordinator.plan,
      report: coordinator.report, pending: coordinator.pending, fromFixture: true,
      strings: PhoneStrings(language: "en"), timeZone: settings.place.location.timeZone,
      now: launch)
    #expect(snapshot.rows.count == AlertsSnapshot.shownRows)
    #expect(snapshot.rows.allSatisfy { $0.status == "Confirmed" })
  }

  /// The system can reject the requests added just after the user allows notifications; the
  /// coordinator tries them again after each retry delay until they're accepted.
  @MainActor
  @Test func theCoordinatorRetriesRejectedRequests() async throws {
    let center = RecordingCenter(rejecting: 120)
    var options = LaunchOptions()
    options.alertFixtureIn = 100
    let launch = Date()
    let coordinator = AlertCoordinator(
      options: options, launch: launch, center: center, requestPermission: {},
      retryDelays: [.milliseconds(10), .milliseconds(10), .milliseconds(10)])
    var settings = AppSettings.defaults
    settings.alerts.isOn = true
    await coordinator.replan(settings: settings, strings: PhoneStrings(language: "en"), now: launch)

    // Two rejected attempts, then one accepted; the third delay isn't needed.
    #expect(center.added.count == 180)
    #expect(coordinator.report?.failures.isEmpty == true)
    #expect(coordinator.report?.confirmed.count == 60)
    #expect(coordinator.pending.count == 60)
  }

  /// A request still rejected after the last retry stays failed, and the card says so.
  @MainActor
  @Test func aRequestRejectedOnEveryAttemptStaysFailed() async throws {
    let center = RecordingCenter(rejecting: 61)
    var options = LaunchOptions()
    options.alertFixtureIn = 100
    let launch = Date()
    let coordinator = AlertCoordinator(
      options: options, launch: launch, center: center, requestPermission: {},
      retryDelays: [.milliseconds(10)])
    var settings = AppSettings.defaults
    settings.alerts.isOn = true
    await coordinator.replan(settings: settings, strings: PhoneStrings(language: "en"), now: launch)

    #expect(center.added.count == 120)
    #expect(coordinator.report?.failures.count == 1)
    #expect(coordinator.report?.confirmed.count == 59)
    let reason = RecordingCenter.Rejected().localizedDescription
    #expect(coordinator.report?.failures.first?.value == .addFailed(reason))
    // The card names the system's reason.
    let snapshot = AlertsSnapshot.make(
      options: settings.alerts, authorization: coordinator.authorization, plan: coordinator.plan,
      report: coordinator.report, pending: coordinator.pending, fromFixture: true,
      strings: PhoneStrings(language: "en"), timeZone: settings.place.location.timeZone,
      now: launch)
    #expect(snapshot.failures.count == 1)
    #expect(snapshot.failures.first?.hasSuffix("Couldn't be scheduled (\(reason))") == true)
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

  /// The card knows the authorization before the first batch ends, so it doesn't say "not
  /// allowed yet" meanwhile.
  @MainActor
  @Test func theAuthorizationIsKnownBeforeTheFirstBatchEnds() async throws {
    let center = RecordingCenter()
    center.holdNextPendingRead()
    let coordinator = AlertCoordinator(
      options: LaunchOptions(), center: center, requestPermission: {})
    var settings = AppSettings.defaults
    settings.alerts.isOn = true
    let replan = Task {
      await coordinator.replan(settings: settings, strings: PhoneStrings(language: "en"))
    }
    for _ in 0..<2_000 where !center.isHolding {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(center.isHolding)
    #expect(coordinator.authorization == .authorized)
    #expect(coordinator.report == nil)
    center.release()
    await replan.value
    #expect(coordinator.report != nil)
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
      fromFixture: false, strings: PhoneStrings(language: "en"), timeZone: zone,
      now: Self.makkahNoon)
    #expect(snapshot.status == "Notifications are allowed.")
    #expect(
      snapshot.scheduledUntil?.filter(Self.isVisible)
        == "Scheduled until Wednesday, October 14, 2026 17:57")
    #expect(snapshot.pendingCount == "2 pending requests")
    #expect(snapshot.rows.map(\.status) == ["Confirmed", "Couldn't be scheduled"])
    #expect(snapshot.rows.map(\.id) == ["2026-10-14/asr/atTime", "2026-10-14/maghrib/atTime"])
    #expect(snapshot.rows.last?.time == "Wednesday 17:56")
    #expect(
      snapshot.failures.map { $0.filter(Self.isVisible) } == [
        "Isha, Wednesday, October 14, 2026: Not confirmed"
      ])

    // Alerts off: the app still applies an empty plan, whose coverage runs to the end of its
    // range, but the card claims none.
    let empty = NotificationPlan(
      namespace: PhoneAlertPlanning.namespace,
      effectiveRange: DateInterval(start: Self.makkahNoon, duration: 14 * 86_400), alerts: [],
      coveredUntil: Self.makkahNoon.addingTimeInterval(14 * 86_400), coverageByKind: [:])
    let emptyReport = NotificationApplyReport(
      verifiedAt: Self.makkahNoon, confirmed: [], failures: [:], superseded: false,
      confirmedCoveredUntil: empty.coveredUntil)
    let off = AlertsSnapshot.make(
      options: PhoneAlertOptions(), authorization: .authorized, plan: empty, report: emptyReport,
      pending: [], fromFixture: false, strings: PhoneStrings(language: "en"), timeZone: zone,
      now: Self.makkahNoon)
    #expect(off.status == "Alerts are off. Turn them on in Settings.")
    #expect(off.pendingCount == nil)
    #expect(off.scheduledUntil == nil)
    #expect(off.plannedUntil == nil)
  }

  /// Requests that fired since the read-back drop off the card; the count follows, in the
  /// language's plural, and a failure line uses the language's punctuation.
  @Test func theCardDropsRequestsThatHaveFired() throws {
    let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
    let day = CivilDay(year: 2026, month: 10, day: 14)
    func identity(_ prayer: PrayerKind) -> NotificationIdentity {
      NotificationIdentity(namespace: "prayers", scheduleDay: day, prayer: prayer, kind: .atTime)
    }
    let asr = Self.makkahNoon.addingTimeInterval(3 * 3_600 + 27 * 60)
    let maghrib = Self.makkahNoon.addingTimeInterval(5 * 3_600 + 57 * 60)
    let pending = [
      PendingAlert(identity: identity(.asr), fireDate: asr),
      PendingAlert(identity: identity(.maghrib), fireDate: maghrib),
    ]
    let report = NotificationApplyReport(
      verifiedAt: Self.makkahNoon, confirmed: [], failures: [identity(.isha): .unconfirmed],
      superseded: false, confirmedCoveredUntil: maghrib)
    func snapshot(_ language: String, at now: Date) -> AlertsSnapshot {
      AlertsSnapshot.make(
        options: PhoneAlertOptions(isOn: true), authorization: .authorized, plan: nil,
        report: report, pending: pending, fromFixture: false,
        strings: PhoneStrings(language: language), timeZone: zone, now: now)
    }
    let afterAsr = snapshot("en", at: asr.addingTimeInterval(1))
    #expect(afterAsr.rows.map(\.id) == ["2026-10-14/maghrib/atTime"])
    #expect(afterAsr.pendingCount == "1 pending request")
    #expect(snapshot("en", at: maghrib).rows.isEmpty)
    // "العشاء، الأربعاء، …: …": the title and the date joined by the Arabic comma (the date has
    // its own).
    let arabic = snapshot("ar", at: Self.makkahNoon)
    let isha = PhoneStrings(language: "ar").names.name(of: PrayerKind.isha)
    #expect(arabic.failures.count == 1)
    #expect(
      arabic.failures.first?.filter(Self.isVisible).hasPrefix("\(isha)، ") == true,
      "\(arabic.failures)")
  }

  /// A request's trigger names a whole second rounded up from its alert's fire date: the card
  /// takes a pending request within the second after a confirmed alert's time for that alert,
  /// and any other for an older one.
  @Test func theCardMatchesARequestToItsAlertsRoundedTime() throws {
    let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
    let identity = NotificationIdentity(
      namespace: "prayers", scheduleDay: CivilDay(year: 2026, month: 10, day: 14), prayer: .asr,
      kind: .atTime)
    let fireDate = Self.makkahNoon.addingTimeInterval(100.4)
    let report = NotificationApplyReport(
      verifiedAt: Self.makkahNoon,
      confirmed: [AlertOccurrenceID(notification: identity, fireDate: fireDate)], failures: [:],
      superseded: false, confirmedCoveredUntil: fireDate)
    for (seconds, status) in [(101.0, "Confirmed"), (100.0, "Pending"), (102.0, "Pending")] {
      let snapshot = AlertsSnapshot.make(
        options: PhoneAlertOptions(isOn: true), authorization: .authorized, plan: nil,
        report: report,
        pending: [
          PendingAlert(identity: identity, fireDate: Self.makkahNoon.addingTimeInterval(seconds))
        ],
        fromFixture: false, strings: PhoneStrings(language: "en"), timeZone: zone,
        now: Self.makkahNoon)
      #expect(snapshot.rows.map(\.status) == [status], "pending at +\(seconds) s")
    }
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
  private var rejecting: Int
  private var holdsNextRead = false
  private var gate: CheckedContinuation<Void, Never>?

  /// A center whose first `rejecting` adds fail.
  init(status: UNAuthorizationStatus = .authorized, rejecting: Int = 0) {
    currentStatus = status
    self.rejecting = rejecting
  }

  /// The error of a rejected add.
  struct Rejected: LocalizedError {
    var errorDescription: String? { "Rejected by the test center" }
  }

  var status: UNAuthorizationStatus {
    get { lock.withLock { currentStatus } }
    set { lock.withLock { currentStatus = newValue } }
  }

  var added: [String] { lock.withLock { identifiers } }

  func authorizationStatus() async -> UNAuthorizationStatus { status }

  /// Makes the next pending read wait for `release()`.
  func holdNextPendingRead() {
    lock.withLock { holdsNextRead = true }
  }

  /// Whether a pending read is waiting for `release()`.
  var isHolding: Bool { lock.withLock { gate != nil } }

  func release() {
    let gate = lock.withLock {
      defer { self.gate = nil }
      return self.gate
    }
    gate?.resume()
  }

  func pendingNotificationRequests() async throws -> [UNNotificationRequest] {
    let holds = lock.withLock {
      defer { holdsNextRead = false }
      return holdsNextRead
    }
    if holds {
      await withCheckedContinuation { continuation in
        lock.withLock { gate = continuation }
      }
    }
    return lock.withLock { Array(requests.values) }
  }

  func add(_ request: UNNotificationRequest) async throws {
    let rejected = lock.withLock {
      identifiers.append(request.identifier)
      if rejecting > 0 {
        rejecting -= 1
        return true
      }
      if request.trigger != nil { requests[request.identifier] = request }
      return false
    }
    if rejected { throw Rejected() }
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
    lock.withLock { for identifier in identifiers { requests[identifier] = nil } }
  }

  func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] { [] }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {}
}
