import AppKit
import Foundation
import Observation
import SalahAlerts
import SalahWidgets
import UserNotifications
import os

/// The app's state, made once per launch: the settings, what plays, the display and the alerts.
@MainActor
@Observable
final class AppModel {
  /// The settings, as saved in the App Group.
  private(set) var settings: MenuBarSettings
  /// What plays, and the widget's Stop button.
  let live: LiveState
  /// The menu bar's title and the dropdown's schedule.
  let display: DisplayModel
  /// The engine, the notification plan and the scheduler.
  let alerts: AlertCoordinator
  /// The notification permission, when the app uses the system's notification center.
  private(set) var authorization: UNAuthorizationStatus?
  /// Whether notifications go to an in-memory center (`-notifications memory`).
  let usesMemoryNotifications: Bool

  @ObservationIgnored private let appClock: AppClock
  @ObservationIgnored private let diagnostics: Diagnostics
  @ObservationIgnored private var events: SystemEventObserver?
  @ObservationIgnored private var testEvents: [DarwinSignal.Observation] = []
  @ObservationIgnored private let logger = Logger(
    subsystem: MenuBarID.logSubsystem, category: "App")

  init(options: LaunchOptions) {
    let appClock = AppClock(start: options.now)
    self.appClock = appClock
    let diagnostics = Diagnostics()
    self.diagnostics = diagnostics
    let settings = options.applied(to: SharedValue.menuBarSettings.load() ?? .defaults)
    self.settings = settings
    let live = LiveState(player: AudioTonePlayer(muted: options.muted), diagnostics: diagnostics)
    self.live = live
    display = DisplayModel(settings: settings, clock: AppAlertClock(appClock: appClock))
    usesMemoryNotifications = options.inMemoryNotifications
    let center: any AlertNotificationCenter =
      options.inMemoryNotifications
      ? MemoryNotificationCenter(now: { appClock.now() }) : UNUserNotificationCenter.current()
    alerts = AlertCoordinator(
      settings: settings, live: live, center: center, clock: AppAlertClock(appClock: appClock),
      replanClock: AppAlertClock(appClock: appClock), schedulerNow: { appClock.now() },
      diagnostics: diagnostics)

    save()
    live.start()
    alerts.replan()
    events = SystemEventObserver(
      workspaceCenter: NSWorkspace.shared.notificationCenter, center: .default
    ) { [weak self] event in
      self?.handle(event)
    }
    if options.acceptsTestEvents {
      testEvents = [
        TestEventSignal.sleep.observe { [weak self] in self?.simulate(.wake) },
        TestEventSignal.clockChange.observe { [weak self] in self?.simulate(.clockChange) },
      ]
    }
    if let tone = options.testTone {
      live.play(nil, cycles: tone == .once ? 1 : nil)
    }
    Task { await readAuthorization() }
  }

  /// After the Mac wakes or the clock changes: the display plans again from now, the engine
  /// catches up and the alerts are planned again.
  func handle(_ event: SystemEvent) {
    diagnostics.record(.systemEvent, detail: "\(event)")
    display.refresh(replanning: true)
    diagnostics.record(.displayRefreshed, detail: display.content?.title.text ?? "none")
    alerts.handle(event)
  }

  /// A test run's simulated sleep or clock change (`-testEvents`): the app's clock moves
  /// forward without running what came due meanwhile, and the system's notification is posted
  /// in this process, where the app's observer receives it as it would the system's.
  private func simulate(_ event: SystemEvent) {
    switch event {
    case .wake:
      appClock.jump(by: TestEventSignal.sleepSeconds)
      NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
    case .clockChange:
      appClock.jump(by: TestEventSignal.clockChangeSeconds)
      NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
    case .timeZoneChange:
      NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
    }
  }

  /// Changes the settings, saves them for the widget, and updates the display and the alerts.
  func change(_ update: (inout MenuBarSettings) -> Void) {
    var changed = settings
    update(&changed)
    guard changed != settings else { return }
    settings = changed
    save()
    display.update(settings: changed)
    alerts.update(settings: changed)
  }

  /// Turns alerts on or off. Turning them on asks for notification permission, when the app
  /// uses the system's center and the user hasn't answered yet, and plans again once answered.
  func setAlertsEnabled(_ enabled: Bool) {
    change { $0.alerts.enabled = enabled }
    guard enabled, !usesMemoryNotifications else { return }
    Task {
      await readAuthorization()
      guard authorization == .notDetermined else { return }
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound,
      ])
      await readAuthorization()
      alerts.replan()
    }
  }

  /// Plays the test tone once.
  func playTestTone() {
    live.play(nil, cycles: 1)
  }

  private func readAuthorization() async {
    guard !usesMemoryNotifications else { return }
    authorization = await UNUserNotificationCenter.current().notificationSettings()
      .authorizationStatus
  }

  /// Saves the settings for the widget, which reloads only when they changed.
  private func save() {
    do {
      try SharedValue.menuBarSettings.save(settings, reloading: [MenuBarID.widgetKind])
    } catch {
      logger.error("Saving the settings failed: \(String(describing: error), privacy: .public)")
    }
  }
}
