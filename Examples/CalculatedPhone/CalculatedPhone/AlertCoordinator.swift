import Foundation
import SalahAlerts
import SalahCore
import UserNotifications
import os

/// Plans the app's alerts and installs them through `NotificationScheduler`, then reads the
/// pending requests back for the Alerts card.
///
/// The app replans when it launches or becomes active and whenever the settings change. It
/// asks for notification permission itself, when the user turns alerts on: the package never
/// does. Alerts always follow the real clock, even when `-now` moves the screen's.
@MainActor
@Observable
final class AlertCoordinator {
  private(set) var authorization: UNAuthorizationStatus?
  private(set) var plan: NotificationPlan?
  private(set) var report: NotificationApplyReport?
  private(set) var pending: [PendingAlert] = []
  /// How many of the probe's requests the system kept, and how many it added
  /// (`-probeNotificationLimit`).
  private(set) var probe: (kept: Int, added: Int)?
  /// Whether the alerts come from the `-alertFixtureIn` timetable.
  let usesFixture: Bool

  @ObservationIgnored private let center: any AlertNotificationCenter
  @ObservationIgnored private let scheduler: NotificationScheduler
  @ObservationIgnored private let fixtureStart: Date?
  @ObservationIgnored private let fixtureDay: CivilDay?
  @ObservationIgnored private let requestPermission: @MainActor () async -> Void
  @ObservationIgnored private let retryDelays: [Duration]
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var probeCount: Int?
  @ObservationIgnored private let log = Logger(
    subsystem: "io.github.salah-kit.CalculatedPhone", category: "alerts")

  /// Creates a coordinator on `center`, the system's by default, wrapped in a failing center
  /// when `-failAlertAdds` asks for one. Requests the center rejects are tried again after
  /// each of `retryDelays`.
  init(
    options: LaunchOptions, launch: Date = Date(),
    center base: (any AlertNotificationCenter)? = nil,
    requestPermission: (@MainActor () async -> Void)? = nil,
    retryDelays: [Duration] = [2, 4, 8, 16, 32, 64].map { .seconds($0) }
  ) {
    let system = base ?? UNUserNotificationCenter.current()
    let center: any AlertNotificationCenter =
      options.failAlertAdds.isEmpty
      ? system : FailingNotificationCenter(base: system, failing: options.failAlertAdds)
    self.center = center
    scheduler = NotificationScheduler(
      identifierPrefix: PhoneAlertPlanning.identifierPrefix,
      namespace: PhoneAlertPlanning.namespace, threadIdentifier: PhoneAlertPlanning.thread,
      center: center)
    probeCount = options.probeNotificationLimit
    fixtureStart = options.alertFixtureIn.map { launch.addingTimeInterval($0) }
    fixtureDay = options.alertFixtureDay
    usesFixture = fixtureStart != nil
    self.retryDelays = retryDelays
    self.requestPermission =
      requestPermission ?? {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [
          .alert, .sound,
        ])
      }
  }

  /// Asks for notification permission if the user hasn't answered yet.
  func requestPermissionIfNeeded() async {
    if await center.authorizationStatus() == .notDetermined {
      await requestPermission()
    }
    authorization = await center.authorizationStatus()
  }

  /// Plans the alerts of `settings` at `now`, installs the plan and reads it back.
  ///
  /// A later call supersedes an earlier one still in flight, as the scheduler's own pump
  /// does; only the latest call's results are shown.
  func replan(settings: AppSettings, strings: PhoneStrings, now: Date = Date()) async {
    generation += 1
    let mine = generation
    let zone = settings.place.location.timeZone
    let fixture = fixtureStart.map { start in
      AlertFixture(firstPrayer: start, day: fixtureDay ?? CivilDay(containing: start, in: zone))
    }
    let plan: NotificationPlan
    do {
      plan = try PhoneAlertPlanning.plan(settings: settings, fixture: fixture, at: now)
    } catch {
      // The options never break the planner's rules; an empty plan keeps the center tidy.
      plan = NotificationPlan(
        namespace: PhoneAlertPlanning.namespace, effectiveRange: DateInterval(start: now, end: now),
        alerts: [], coveredUntil: now, coverageByKind: [:])
    }
    let content = PhoneAlertContent(strings: strings, timeZone: zone)
    // The authorization first, so the card doesn't say "not allowed yet" while the first batch
    // runs.
    let current = await center.authorizationStatus()
    guard mine == generation else { return }
    authorization = current
    // The system can reject requests after the user allows notifications ("Source is not
    // authorized"); the iOS 27.0 simulator did until it restarted. Rejected requests are tried
    // again after each retry delay, and the card shows every attempt; what still fails stays
    // failed until the next replan, when the app next becomes active.
    var delays = retryDelays[...]
    while true {
      let report = try? await scheduler.apply(plan, content: { content.make($0) })
      let authorization = await center.authorizationStatus()
      let pending = PendingAlert.owned((try? await center.pendingNotificationRequests()) ?? [])
      guard mine == generation else { return }
      self.plan = plan
      self.report = report
      self.authorization = authorization
      self.pending = pending
      guard let rejected = report.flatMap(Self.addFailures), let reason = rejected.first,
        let delay = delays.popFirst()
      else { break }
      log.error(
        "\(rejected.count, privacy: .public) alert requests failed: \(reason, privacy: .public); trying again in \(String(describing: delay), privacy: .public)"
      )
      try? await Task.sleep(for: delay)
      guard mine == generation, !Task.isCancelled else { return }
    }
    if let count = probeCount {
      probeCount = nil
      probe = await probeLimit(count)
    }
  }

  /// The system's reasons for the requests it rejected, or `nil` when it rejected none.
  private static func addFailures(_ report: NotificationApplyReport) -> [String]? {
    let reasons = report.failures.values.compactMap { failure -> String? in
      if case .addFailed(let reason) = failure { return reason }
      return nil
    }
    return reasons.isEmpty ? nil : reasons
  }

  /// Adds `count` requests under a separate prefix, a day apart, reads back how many the system
  /// kept, and removes them. iOS keeps a limited number of pending requests per app.
  private func probeLimit(_ count: Int) async -> (kept: Int, added: Int) {
    let prefix = "\(PhoneAlertPlanning.identifierPrefix)probe."
    let identifiers = (0..<count).map { "\(prefix)\($0)" }
    var added = 0
    for (index, identifier) in identifiers.enumerated() {
      let content = UNMutableNotificationContent()
      content.title = "Probe \(index)"
      let trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: Double(index + 1) * 86_400, repeats: false)
      if (try? await center.add(
        UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))) != nil
      {
        added += 1
      }
    }
    let kept = ((try? await center.pendingNotificationRequests()) ?? [])
      .filter { $0.identifier.hasPrefix(prefix) }.count
    await center.removePendingNotificationRequests(withIdentifiers: identifiers)
    return (kept, added)
  }
}

/// Shows the app's notifications while it's in front, as banners in the list with their sound.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }
}
