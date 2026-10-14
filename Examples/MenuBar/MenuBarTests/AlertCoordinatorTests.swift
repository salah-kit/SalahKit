import AppKit
import Foundation
import SalahAlerts
import SalahCore
import Testing
import UserNotifications

@testable import MenuBar

/// The app's wiring of SalahAlerts: the engine gets the uncapped schedule, the scheduler the
/// budgeted plan, the tone follows the engine's precedence, and a wake or a clock change, posted
/// to injected notification centers, catches up and replans.
@Suite("Alerts")
@MainActor
struct AlertCoordinatorTests {
  /// One coordinator with its clocks, center, player and system-event observer.
  @MainActor
  struct Rig {
    let clock: ManualClock
    let replanClock: ManualClock
    let center: MemoryNotificationCenter
    let player = FakeTonePlayer()
    let live: LiveState
    let coordinator: AlertCoordinator
    let workspaceCenter = NotificationCenter()
    let systemCenter = NotificationCenter()
    let observer: SystemEventObserver

    init(at date: Date, settings: MenuBarSettings, budget: AlertBudget = AlertBudget()) {
      // One time for both clocks, as the app's two clocks share its AppClock.
      let time = TestTime(date)
      clock = time.makeClock()
      replanClock = time.makeClock()
      let shared = time.shared
      center = MemoryNotificationCenter(now: { shared.value })
      live = LiveState(
        player: player, storage: TestStorage.nowPlaying(), signal: TestStorage.signal(),
        widgetKinds: [], diagnostics: Diagnostics(storage: nil))
      coordinator = AlertCoordinator(
        settings: settings, live: live, center: center, clock: clock, replanClock: replanClock,
        schedulerNow: { shared.value }, budget: budget)
      let coordinator = coordinator
      observer = SystemEventObserver(workspaceCenter: workspaceCenter, center: systemCenter) {
        coordinator.handle($0)
      }
    }
  }

  /// Makkah with alerts on and a reminder `reminder` minutes before each prayer.
  static func settings(reminder: Int? = 10, playsTone: Bool = true) -> MenuBarSettings {
    var settings = Fixture.makkah
    settings.alerts = AlertPreferences(
      enabled: true, reminderMinutes: reminder, playsTone: playsTone)
    return settings
  }

  static func identifier(_ alert: PlannedAlert) -> String {
    alert.id.requestIdentifier(prefix: "io.github.salah-kit.MenuBar.")
  }

  @Test("the engine gets every alert of two days; the scheduler gets the budgeted plan")
  func engineAndScheduler() async throws {
    let asr = try Fixture.event(.asr)
    let now = asr.time.addingTimeInterval(-3_600)
    let rig = Rig(at: now, settings: Self.settings())
    rig.coordinator.replan()
    await rig.coordinator.waitForApply()

    let expected = try AlertPlanner().schedule(
      Fixture.makkah.schedule, namespace: "prayers", from: now.addingTimeInterval(-5 * 60),
      to: now.addingTimeInterval(2 * 86_400),
      settings: Self.settings().alerts.settings(for:))
    #expect(rig.coordinator.engineSchedule?.alerts == expected.alerts)
    #expect(expected.alerts.count == 20, "five prayers, at their time and ten minutes before")

    let plan = try #require(rig.coordinator.plan)
    #expect(plan.alerts.count == 60)
    #expect(try #require(plan.coverageByKind[.atTime]) > plan.coveredUntil)
    #expect(rig.center.pendingIdentifiers.count == 60)
    #expect(rig.coordinator.report?.confirmed.count == 60)
    #expect(rig.coordinator.report?.confirmedCoveredUntil == plan.coveredUntil)
  }

  @Test("a reminder the plan leaves out still comes due, with a banner and the tone")
  func remindersBeyondTheBudget() async throws {
    let asr = try Fixture.event(.asr)
    let maghrib = try Fixture.event(.maghrib)
    let rig = Rig(
      at: asr.time.addingTimeInterval(-30 * 60), settings: Self.settings(),
      budget: AlertBudget(maxPending: 2))
    rig.coordinator.replan()
    await rig.coordinator.waitForApply()
    let plan = try #require(rig.coordinator.plan)
    #expect(plan.alerts.map(\.event.kind) == [.asr, .asr])
    let reminder = try #require(
      rig.coordinator.engineSchedule?.alerts.first {
        $0.event.kind == .maghrib && $0.kind == .before
      })
    #expect(!plan.alerts.contains(reminder))

    // The engine wakes just after a fire date.
    rig.clock.advance(to: maghrib.time.addingTimeInterval(-10 * 60 + 1))
    #expect(rig.coordinator.lastDue == [reminder])
    #expect(
      rig.live.nowPlaying?.alert == .init(prayer: .maghrib, observance: .ordinary, kind: .before))
    #expect(
      await eventually { rig.center.deliveredIdentifiers.contains(Self.identifier(reminder)) })
  }

  @Test("alerts due together play the tone the engine's precedence picks")
  func precedence() async throws {
    // Umm al-Qura's Isha is 90 minutes after Maghrib, so a 90-minute reminder for Isha falls
    // due with Maghrib's own alert.
    let maghrib = try Fixture.event(.maghrib)
    let rig = Rig(at: maghrib.time.addingTimeInterval(-60), settings: Self.settings(reminder: 90))
    rig.coordinator.replan()
    rig.clock.advance(to: maghrib.time.addingTimeInterval(1))
    let due = rig.coordinator.lastDue
    try #require(due.count == 2, "Maghrib's alert and Isha's reminder: \(due)")
    let preferred = try #require(InProcessAlertEngine.preferredAlert(among: due))
    #expect(preferred.event.kind == .maghrib && preferred.kind == .atTime)
    #expect(
      rig.live.nowPlaying?.alert == .init(prayer: .maghrib, observance: .ordinary, kind: .atTime))
    #expect(rig.player.plays.count == 1)
  }

  @Test("without the app's tone, alerts get banners and nothing plays")
  func noTone() async throws {
    let asr = try Fixture.event(.asr)
    let rig = Rig(at: asr.time.addingTimeInterval(-60), settings: Self.settings(playsTone: false))
    rig.coordinator.replan()
    rig.clock.advance(to: asr.time.addingTimeInterval(1))
    #expect(rig.coordinator.lastDue.map(\.event.kind) == [.asr])
    #expect(rig.player.plays.isEmpty)
  }

  /// Asr's at-time alert in the engine's schedule, and its request's identifier.
  static func asrAlert(_ rig: Rig) throws -> String {
    let alert = try #require(
      rig.coordinator.engineSchedule?.alerts.first { $0.event.kind == .asr && $0.kind == .atTime })
    return identifier(alert)
  }

  @Test("after a sleep through a prayer, the wake notification catches it up and replans")
  func wake() async throws {
    let asr = try Fixture.event(.asr)
    let rig = Rig(at: asr.time.addingTimeInterval(-5 * 60), settings: Self.settings(reminder: nil))
    rig.coordinator.replan()
    await rig.coordinator.waitForApply()
    let request = try Self.asrAlert(rig)
    #expect(rig.center.pendingIdentifiers.contains(request))
    #expect(rig.clock.wakeDate.map { $0 > asr.time } == true)
    // The Mac sleeps through Asr: the engine's wake-up doesn't run, and the system still holds
    // Asr's request as pending (the in-memory center never delivers by itself).
    rig.clock.jump(to: asr.time.addingTimeInterval(2 * 60))
    rig.workspaceCenter.post(name: SystemEventObserver.didWake, object: nil)
    #expect(await eventually { rig.coordinator.lastDue.map(\.event.kind) == [.asr] })
    #expect(rig.live.nowPlaying?.alert?.prayer == .asr)
    #expect(rig.coordinator.replanCount == 2)
    #expect(rig.coordinator.plan?.effectiveRange.start == rig.clock.now)
    // The replan removes the past request, and Asr's banner is posted after it.
    #expect(await eventually { rig.center.deliveredIdentifiers == [request] })
    #expect(!rig.center.pendingIdentifiers.contains(request))
  }

  @Test("a clock change within the grace catches up; beyond it, the alert is skipped")
  func clockChange() async throws {
    let asr = try Fixture.event(.asr)
    let late = Rig(at: asr.time.addingTimeInterval(-60), settings: Self.settings(reminder: nil))
    late.coordinator.replan()
    late.clock.jump(to: asr.time.addingTimeInterval(6 * 60))
    late.systemCenter.post(name: .NSSystemClockDidChange, object: nil)
    #expect(await eventually { late.coordinator.replanCount == 2 })
    #expect(late.coordinator.lastDue.isEmpty, "five minutes is the at-time grace")
    #expect(late.player.plays.isEmpty)

    let onTime = Rig(at: asr.time.addingTimeInterval(-60), settings: Self.settings(reminder: nil))
    onTime.coordinator.replan()
    await onTime.coordinator.waitForApply()
    let request = try Self.asrAlert(onTime)
    #expect(onTime.center.pendingIdentifiers.contains(request))
    onTime.clock.jump(to: asr.time.addingTimeInterval(3 * 60))
    onTime.systemCenter.post(name: .NSSystemClockDidChange, object: nil)
    #expect(await eventually { onTime.coordinator.lastDue.map(\.event.kind) == [.asr] })
    #expect(onTime.player.plays.count == 1)
    #expect(await eventually { onTime.center.deliveredIdentifiers == [request] })
  }

  @Test("a time zone change replans")
  func timeZoneChange() async throws {
    let rig = Rig(at: try Fixture.event(.asr).time, settings: Self.settings())
    rig.coordinator.replan()
    rig.systemCenter.post(name: .NSSystemTimeZoneDidChange, object: nil)
    #expect(await eventually { rig.coordinator.replanCount == 2 })
  }

  @Test("the observer listens for NSWorkspace's wake notification by its real name")
  func wakeName() {
    #expect(SystemEventObserver.didWake == NSWorkspace.didWakeNotification)
  }

  @Test("a wake posted to another center does nothing")
  func otherCenters() async throws {
    let rig = Rig(at: try Fixture.event(.asr).time, settings: Self.settings())
    rig.coordinator.replan()
    rig.systemCenter.post(name: SystemEventObserver.didWake, object: nil)
    rig.workspaceCenter.post(name: .NSSystemClockDidChange, object: nil)
    try await Task.sleep(for: .milliseconds(100))
    #expect(rig.coordinator.replanCount == 1)
    rig.observer.cancel()
    rig.workspaceCenter.post(name: SystemEventObserver.didWake, object: nil)
    try await Task.sleep(for: .milliseconds(100))
    #expect(rig.coordinator.replanCount == 1)
  }

  @Test("turning alerts off empties the engine and removes the app's requests")
  func alertsOff() async throws {
    // An hour before Asr: an alert due at the planning instant itself isn't installed, because
    // the scheduler adds only alerts after its batch starts.
    let rig = Rig(
      at: try Fixture.event(.asr).time.addingTimeInterval(-3_600), settings: Self.settings())
    rig.coordinator.replan()
    await rig.coordinator.waitForApply()
    #expect(rig.center.pendingIdentifiers.count == 60)
    rig.coordinator.update(settings: Fixture.makkah)
    await rig.coordinator.waitForApply()
    #expect(rig.center.pendingIdentifiers.isEmpty)
    #expect(rig.coordinator.engineSchedule == nil)
    #expect(rig.coordinator.plan?.alerts.isEmpty == true)
  }

  @Test("the app replans every twelve hours")
  func periodicReplan() async throws {
    let now = try Fixture.event(.asr).time
    let rig = Rig(at: now, settings: Self.settings())
    rig.coordinator.replan()
    #expect(rig.replanClock.wakeDate == now.addingTimeInterval(12 * 3_600))
    rig.replanClock.fire()
    #expect(rig.coordinator.replanCount == 2)
  }

  @Test("notifications carry no sound for the app's tone, and the system's otherwise")
  func content() throws {
    let asr = try Fixture.event(.asr)
    let identity = NotificationIdentity(
      namespace: "prayers", scheduleDay: asr.scheduleDay, prayer: .asr, kind: .atTime)
    let tone = PlannedAlert(
      id: identity, event: asr, fireDate: asr.time, sound: .named(MenuBarTone.soundName))
    let english = AlertContent(strings: MenuBarStrings(language: .english))
    let toneContent = english.make(tone)
    #expect(toneContent.title == "Asr")
    #expect(toneContent.body == "It's time for Asr.")
    #expect(toneContent.sound == nil)

    var system = tone
    system.sound = .system
    #expect(english.make(system).sound == .default)

    let reminder = PlannedAlert(
      id: NotificationIdentity(
        namespace: "prayers", scheduleDay: asr.scheduleDay, prayer: .asr, kind: .before),
      event: asr, fireDate: asr.time.addingTimeInterval(-600), sound: .system)
    #expect(english.make(reminder).body == "Asr in 10 minutes.")

    let arabic = AlertContent(strings: MenuBarStrings(language: .arabic)).make(tone)
    #expect(arabic.title == "العصر")
  }
}
