import Foundation
import SalahAlerts
import SalahCore

#if canImport(UserNotifications) && !os(tvOS)
  import UserNotifications
#endif

/// The code of the DocC article "Alerts within the 64-notification limit" and of the README's
/// alerts section, as functions the tests compile, and run where they don't need an app's
/// notification center. `AlertsDocumentationTests` checks that every Swift block in those
/// documents appears here, line for line.
nonisolated enum AlertsDocumentationExamples {
  /// The settings of the article: a reminder before every prayer, longer for Fajr, and none
  /// for sunrise.
  static func reminderSettings() -> (AlertSubject) -> AlertSettings? {
    let settings: (AlertSubject) -> AlertSettings? = { subject in
      switch subject.prayer {
      case .sunrise: return nil
      case .fajr: return AlertSettings(before: .seconds(30 * 60))
      default: return AlertSettings(before: .seconds(10 * 60))
      }
    }
    return settings
  }

  /// Jumu'ah's own settings, when the source declares it.
  static func jumuahSettings(
    _ settings: @escaping (AlertSubject) -> AlertSettings?
  ) -> (AlertSubject) -> AlertSettings? {
    let withJumuah: (AlertSubject) -> AlertSettings? = { subject in
      if subject.observance == .jumuah {
        return AlertSettings(before: .seconds(45 * 60), sound: .named("jumuah.caf"))
      }
      return settings(subject)
    }
    return withJumuah
  }

  /// The article's plan: two weeks of alerts in the default budget.
  static func plan(
    _ schedule: PrayerSchedule, now: Date,
    settings: (AlertSubject) -> AlertSettings?
  ) throws -> (AlertSchedule, NotificationPlan) {
    let planner = AlertPlanner()
    let alerts = try planner.schedule(
      schedule, namespace: "prayers", from: now, to: now.addingTimeInterval(14 * 86_400),
      settings: settings)
    let plan = planner.notificationPlan(alerts, from: now)
    return (alerts, plan)
  }

  /// What the article prints about a plan's coverage.
  static func describe(_ plan: NotificationPlan) {
    print(plan.alerts.count, "requests, complete until", plan.coveredUntil)
    if let atTime = plan.coverageByKind[.atTime] {
      print("Prayer-time alerts complete until", atTime)
    }
  }

  /// The alert gaps a missing prayer time makes.
  static func explainGaps(_ alerts: AlertSchedule) {
    for gap in alerts.gaps {
      let prayers = gap.prayers.map(\.rawValue).sorted().joined(separator: ", ")
      print("\(gap.kind) alerts for \(prayers) on \(gap.day) unknown: \(gap.reason)")
    }
  }

  /// Ordinary replans preserve a future request during the engine's early report window.
  @MainActor
  static func ordinaryPlan(
    _ alerts: AlertSchedule, engine: InProcessAlertEngine, now: Date
  ) -> NotificationPlan {
    let planner = AlertPlanner()
    let handledAfterNow = engine.handledOccurrences.filter { now < $0.value }
    let normalPlan = planner.notificationPlan(
      alerts, from: now, excluding: Set(handledAfterNow.keys))
    return normalPlan
  }

  /// A clock change snapshots the engine's prior reports before resync marks new ones due.
  @MainActor
  static func planAfterClockChange(
    _ alerts: AlertSchedule, engine: InProcessAlertEngine, now: Date
  ) -> NotificationPlan {
    let planner = AlertPlanner()
    let previouslyHandled = Set(engine.handledOccurrences.keys)
    engine.resync(now: now)
    let refreshedPlan = planner.notificationPlan(
      alerts, from: now, excluding: previouslyHandled)
    return refreshedPlan
  }

  #if canImport(UserNotifications) && !os(tvOS)
    /// The article's installation of a plan on the app's notification center. Compiled, not
    /// run: a test process has no app to own notifications.
    static func install(_ plan: NotificationPlan, names: PrayerNames) async throws -> Date? {
      let scheduler = NotificationScheduler(
        identifierPrefix: "com.example.prayers.", namespace: "prayers",
        threadIdentifier: "prayers")
      let report = try await scheduler.apply(plan) { alert in
        let content = UNMutableNotificationContent()
        content.title = names.name(of: alert.event)
        content.body = alert.kind == .atTime ? "It's time to pray." : "The prayer is near."
        content.sound = alert.sound.notificationSound
        return content
      }
      for (identity, failure) in report.failures {
        print("\(identity.prayer) on \(identity.scheduleDay): \(failure)")
      }
      return report.confirmedCoveredUntil
    }

    /// A running app's engine, its catch-up deliveries and its wake-up hook.
    @MainActor
    static func runInProcess(
      _ schedule: PrayerSchedule, scheduler: NotificationScheduler,
      settings: @escaping (AlertSubject) -> AlertSettings?,
      makeContent: @escaping @Sendable (PlannedAlert) -> UNMutableNotificationContent,
      play: @escaping @MainActor (PlannedAlert) -> Void
    ) throws -> InProcessAlertEngine {
      let engine = InProcessAlertEngine { due in
        Task { _ = try? await scheduler.deliver(due, content: makeContent) }
        let ownSounds = due.filter { $0.sound != .system && $0.sound != .none }
        if let alert = InProcessAlertEngine.preferredAlert(among: ownSounds) {
          play(alert)
        }
      }
      let now = Date()
      engine.update(
        try AlertPlanner().schedule(
          schedule, namespace: "prayers", from: now.addingTimeInterval(-5 * 60),
          to: now.addingTimeInterval(2 * 86_400), settings: settings))
      // On wake, after a clock change and when the app becomes active:
      engine.resync()
      return engine
    }

    /// The README's quick start. Compiled, not run, like `install`.
    static func readmeQuickStart(schedule: PrayerSchedule) async throws {
      let planner = AlertPlanner()
      let now = Date()
      let alerts = try planner.schedule(
        schedule, namespace: "prayers", from: now, to: now.addingTimeInterval(14 * 86_400),
        settings: { subject in
          subject.prayer.isPrayer ? AlertSettings(before: .seconds(10 * 60)) : nil
        })
      let plan = planner.notificationPlan(alerts, from: now)

      let scheduler = NotificationScheduler(
        identifierPrefix: "com.example.prayers.", namespace: "prayers")
      let report = try await scheduler.apply(plan) { alert in
        let content = UNMutableNotificationContent()
        content.title = PrayerNames(locale: Locale(identifier: "en")).name(of: alert.event)
        content.sound = alert.sound.notificationSound
        return content
      }
      print("Alerts confirmed until", report.confirmedCoveredUntil ?? now)
    }
  #endif
}
