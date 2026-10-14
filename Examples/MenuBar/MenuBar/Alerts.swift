import Foundation
import Observation
import SalahAlerts
import SalahCore
import UserNotifications
import os

/// The app's alerts, wired the way SalahAlerts' article "Alerts within the 64-notification
/// limit" describes for apps that keep running:
///
/// - ``InProcessAlertEngine`` gets the whole `AlertSchedule`, uncapped, from five minutes ago
///   (its catch-up) to two days ahead, so every alert comes due while the app runs, reminders
///   the notification plan leaves out included.
/// - ``NotificationScheduler`` gets the budgeted `NotificationPlan` of the next two weeks, so
///   alerts still arrive when the app isn't running.
/// - When alerts come due, the engine's report goes to `deliver` (a banner for each alert the
///   system won't show by itself) and the tone plays for the one alert that
///   `InProcessAlertEngine.preferredAlert(among:)`, the engine's default precedence, picks.
///
/// The app replans when it starts, when the settings change, after the Mac wakes and when the
/// clock changes (``handle(_:)``), and every twelve hours.
@MainActor
@Observable
final class AlertCoordinator {
  /// The namespace the app's requests live in.
  static let namespace = "prayers"
  /// How often the app replans while nothing else makes it.
  static let replanInterval: TimeInterval = 12 * 3_600

  /// The latest schedule the engine follows; `nil` with alerts off.
  private(set) var engineSchedule: AlertSchedule?
  /// The latest plan given to the scheduler.
  private(set) var plan: NotificationPlan?
  /// What the scheduler confirmed of the latest plan.
  private(set) var report: NotificationApplyReport?
  /// The alerts the engine reported last.
  private(set) var lastDue: [PlannedAlert] = []
  /// Why the last replan failed, if it did.
  private(set) var planningError: String?
  /// How many times the app replanned, for tests.
  private(set) var replanCount = 0

  @ObservationIgnored private var settings: MenuBarSettings
  @ObservationIgnored private let live: LiveState
  @ObservationIgnored private let scheduler: NotificationScheduler
  @ObservationIgnored private let clock: any AlertClock
  @ObservationIgnored private let replanClock: any AlertClock
  @ObservationIgnored private var engine: InProcessAlertEngine?
  @ObservationIgnored private var applyTask: Task<Void, Never>?
  @ObservationIgnored private let diagnostics: Diagnostics?
  @ObservationIgnored private let budget: AlertBudget
  @ObservationIgnored private let logger = Logger(
    subsystem: MenuBarID.logSubsystem, category: "Alerts")

  /// Creates the coordinator. Call ``replan()`` to start.
  ///
  /// - Parameters:
  ///   - settings: The schedule's inputs and the alert preferences.
  ///   - live: Plays the tone.
  ///   - center: The notification center: the system's, or an in-memory one for tests.
  ///   - clock: The engine's clock.
  ///   - replanClock: A second clock for the twelve-hour replan; each clock holds one wake-up.
  ///   - schedulerNow: The scheduler's clock.
  ///   - budget: The notification plan's budget: 60 requests by default, which leaves four of
  ///     the system's 64 for anything else the app schedules.
  ///   - diagnostics: Where to record each replan, for the stop harness.
  init(
    settings: MenuBarSettings, live: LiveState, center: any AlertNotificationCenter,
    clock: any AlertClock, replanClock: any AlertClock,
    schedulerNow: @escaping @Sendable () -> Date, budget: AlertBudget = AlertBudget(),
    diagnostics: Diagnostics? = nil
  ) {
    self.settings = settings
    self.live = live
    self.clock = clock
    self.replanClock = replanClock
    self.budget = budget
    self.diagnostics = diagnostics
    scheduler = NotificationScheduler(
      identifierPrefix: "io.github.salah-kit.MenuBar.", namespace: Self.namespace,
      threadIdentifier: "prayers", center: center, now: schedulerNow)
    engine = InProcessAlertEngine(clock: clock) { [weak self] due in self?.alertsCameDue(due) }
  }

  /// Uses new settings and replans.
  func update(settings: MenuBarSettings) {
    self.settings = settings
    replan()
  }

  /// Reacts to the Mac waking or the clock changing: the engine catches up on what came due
  /// meanwhile, then the app replans from the new moment.
  func handle(_ event: SystemEvent) {
    logger.log("System event: \(String(describing: event), privacy: .public)")
    engine?.resync()
    replan()
  }

  /// Plans the engine's schedule and the notification plan from the clock's moment, and applies
  /// the plan. With alerts off, both are empty, which removes the app's pending requests.
  func replan() {
    let now = clock.now
    replanCount += 1
    let planner = AlertPlanner()
    let schedule = settings.schedule
    let preferences = settings.alerts
    do {
      // The engine: every alert from its catch-up interval to two days ahead, uncapped.
      let engineSchedule = try planner.schedule(
        schedule, namespace: Self.namespace, from: now.addingTimeInterval(-5 * 60),
        to: now.addingTimeInterval(2 * 86_400), settings: preferences.settings(for:))
      engine?.update(engineSchedule)
      self.engineSchedule = preferences.enabled ? engineSchedule : nil
      // The system: two weeks of alerts, as many as the budget holds.
      let longSchedule = try planner.schedule(
        schedule, namespace: Self.namespace, from: now, to: now.addingTimeInterval(14 * 86_400),
        settings: preferences.settings(for:))
      let plan = planner.notificationPlan(longSchedule, from: now, budget: budget)
      self.plan = plan
      planningError = nil
      diagnostics?.record(
        .replanned,
        detail:
          "at=\(now.formatted(.iso8601)) engine=\(engineSchedule.alerts.count) plan=\(plan.alerts.count)"
      )
      apply(plan)
    } catch {
      planningError = String(describing: error)
      logger.error("Planning failed: \(String(describing: error), privacy: .public)")
    }
    replanClock.wake(at: now.addingTimeInterval(Self.replanInterval)) { [weak self] in
      self?.replan()
    }
  }

  /// Waits for the latest plan's application to finish, for tests.
  func waitForApply() async {
    await applyTask?.value
  }

  private func apply(_ plan: NotificationPlan) {
    let content = AlertContent(strings: MenuBarStrings(language: settings.language))
    let previous = applyTask
    applyTask = Task { [weak self, scheduler] in
      // The scheduler serializes its batches; waiting for the previous task only keeps the
      // reports in order.
      await previous?.value
      do {
        let report = try await scheduler.apply(plan, content: content.make)
        self?.report = report
      } catch {
        self?.planningError = String(describing: error)
      }
    }
  }

  private func alertsCameDue(_ due: [PlannedAlert]) {
    lastDue = due
    let content = AlertContent(strings: MenuBarStrings(language: settings.language))
    Task { [scheduler] in
      _ = try? await scheduler.deliver(due, content: content.make)
    }
    // The tone plays for the alerts whose sound is the app's own, by the engine's precedence.
    let toneAlerts = due.filter { $0.sound == .named(MenuBarTone.soundName) }
    if let alert = InProcessAlertEngine.preferredAlert(among: toneAlerts) {
      live.play(
        NowPlaying.Alert(
          prayer: alert.event.kind, observance: alert.event.observance, kind: alert.kind))
    }
  }
}

/// The notifications' wording, in the chosen language.
nonisolated struct AlertContent: Sendable {
  let strings: MenuBarStrings

  /// The content of one alert's notification.
  func make(_ alert: PlannedAlert) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    let name = strings.names.name(of: alert.event)
    content.title = name
    switch alert.kind {
    case .atTime:
      content.body = strings("It's time for \(name).")
    case .before:
      let lead = strings.spoken(alert.event.time.timeIntervalSince(alert.fireDate))
      content.body = strings("\(name) in \(lead).")
    case .after:
      let lag = strings.spoken(alert.fireDate.timeIntervalSince(alert.event.time))
      content.body = strings("\(name) began \(lag) ago.")
    }
    // The running app plays its tone for these alerts; their notifications carry no sound, or
    // the system would play its own beside it. Other alerts use the system's sound.
    content.sound =
      alert.sound == .named(MenuBarTone.soundName) ? nil : alert.sound.notificationSound
    return content
  }
}

/// The system events the app reacts to.
enum SystemEvent: Equatable, Sendable {
  /// The Mac woke from sleep.
  case wake
  /// The system clock was set.
  case clockChange
  /// The system time zone changed.
  case timeZoneChange
}

/// Observes the system events in the given notification centers.
///
/// The app passes NSWorkspace's center (which posts `didWakeNotification`) and the default
/// center (which posts `NSSystemClockDidChange` and `NSSystemTimeZoneDidChange`); tests pass
/// their own centers and post the same names.
@MainActor
final class SystemEventObserver {
  private var tokens: [(NotificationCenter, any NSObjectProtocol)] = []

  /// Starts observing; the handler runs on the main actor for each event.
  init(
    workspaceCenter: NotificationCenter, center: NotificationCenter,
    handler: @escaping @MainActor (SystemEvent) -> Void
  ) {
    func observe(_ name: Notification.Name, in center: NotificationCenter, as event: SystemEvent) {
      let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
        // The main queue's blocks run on the main thread.
        MainActor.assumeIsolated { handler(event) }
      }
      tokens.append((center, token))
    }
    observe(Self.didWake, in: workspaceCenter, as: .wake)
    observe(.NSSystemClockDidChange, in: center, as: .clockChange)
    observe(.NSSystemTimeZoneDidChange, in: center, as: .timeZoneChange)
  }

  /// `NSWorkspace.didWakeNotification`, by name, so this file needs no AppKit.
  static let didWake = Notification.Name("NSWorkspaceDidWakeNotification")

  /// Stops observing. The app observes for as long as it runs; tests stop.
  func cancel() {
    for (center, token) in tokens {
      center.removeObserver(token)
    }
    tokens = []
  }
}

/// The app's clock as an `AlertClock`: its moment, and wake-ups at its dates, which a clock
/// started with `-now` translates to real time.
@MainActor
final class AppAlertClock: AlertClock {
  private let appClock: AppClock
  private let system = SystemAlertClock()

  init(appClock: AppClock) {
    self.appClock = appClock
  }

  var now: Date { appClock.now() }

  func wake(at date: Date?, perform action: @escaping @MainActor @Sendable () -> Void) {
    system.wake(at: date.map { appClock.real(at: $0) }, perform: action)
  }
}

/// A notification center in memory: it allows alerts, keeps pending requests and delivered
/// records, and shows nothing. For test runs (`-notifications memory`) and unit tests.
///
/// `@unchecked Sendable`: every stored property is read and written only while `lock` is held.
nonisolated final class MemoryNotificationCenter: AlertNotificationCenter, @unchecked Sendable {
  private let lock = NSLock()
  private var pending: [String: UNNotificationRequest] = [:]
  private var delivered: [DeliveredNotificationRecord] = []
  private var order: [String] = []
  private let now: @Sendable () -> Date

  init(now: @escaping @Sendable () -> Date = { Date() }) {
    self.now = now
  }

  /// The pending requests' identifiers, in the order they were first added.
  var pendingIdentifiers: [String] {
    lock.withLock { order.filter { pending[$0] != nil } }
  }

  /// The identifiers of the requests posted at once (without a trigger), in order.
  var deliveredIdentifiers: [String] {
    lock.withLock { delivered.map(\.identifier) }
  }

  func authorizationStatus() async -> UNAuthorizationStatus { .authorized }

  func pendingNotificationRequests() async throws -> [UNNotificationRequest] {
    lock.withLock { order.compactMap { pending[$0] } }
  }

  func add(_ request: UNNotificationRequest) async throws {
    let date = now()
    lock.withLock {
      if request.trigger == nil {
        delivered.append(DeliveredNotificationRecord(identifier: request.identifier, date: date))
      } else {
        if pending[request.identifier] == nil { order.append(request.identifier) }
        pending[request.identifier] = request
      }
    }
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
    lock.withLock {
      for identifier in identifiers { pending[identifier] = nil }
      order.removeAll { pending[$0] == nil }
    }
  }

  func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] {
    lock.withLock { delivered }
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
    lock.withLock { delivered.removeAll { identifiers.contains($0.identifier) } }
  }
}
