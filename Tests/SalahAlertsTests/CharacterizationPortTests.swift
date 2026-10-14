import Foundation
import SalahAlerts
import SalahCore
import Testing

#if canImport(UserNotifications) && !os(tvOS)
  import UserNotifications
#endif

/// A2's characterization of Salah's `PrayerAlertScheduler` (Salah `a0206dd`,
/// `GuidanceTests/PrayerAlertSchedulerCharacterizationTests.swift`), ported to SalahAlerts.
///
/// Behavior the proposal retains (§7.5 "Behavior retained and corrected") is tested as it was.
/// Each `characterizes…` test that pinned a defect becomes a regression for the corrected
/// contract. RFC 0003 §6 maps every test. The fixture is A2's: Makkah, 2 June 2026.
@Suite struct CharacterizationPortTests {
  // MARK: The window and the budget

  /// Was `characterizesTheAlertWindowIsYesterdayTodayAndTomorrow` (defect F2): alerts ran out
  /// two days after the app last ran. A plan now covers a horizon within the budget.
  @Test func plansAHorizonNotThreeDays() throws {
    let now = Fixture.date(13, 0)
    let schedule = try Fixture.alerts(
      from: now, to: now.addingTimeInterval(14 * 86_400),
      settings: Fixture.settings(AlertSettings()))
    let plan = AlertPlanner().notificationPlan(schedule, from: now)
    #expect(plan.alerts.count == 60)
    // Twelve days of at-time alerts, from today's Asr: far beyond tomorrow.
    #expect(plan.alerts.last?.id == Fixture.identity(.dhuhr, .atTime, dayOffset: 12))
    #expect(plan.coveredUntil == Fixture.time(.asr, dayOffset: 12))
  }

  /// Retained (`alertWindowDaysAreCivilDaysInThePrayerZone`): days are civil days in the
  /// location's zone. At 01:30 in Makkah it is still 1 June in UTC, yet the next alert belongs
  /// to 2 June.
  @Test func identitiesUseOwningDaysInTheLocationZone() throws {
    let now = Fixture.date(1, 30)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    #expect(utc.component(.day, from: now) == 1)
    let schedule = try Fixture.alerts(
      from: now, to: Fixture.date(12, 0), settings: Fixture.settings(AlertSettings()))
    #expect(schedule.alerts.first?.id == Fixture.identity(.fajr, .atTime))
    #expect(schedule.alerts.first?.id.scheduleDay == CivilDay(year: 2026, month: 6, day: 2))
  }

  /// Was `characterizesTheThreeDayWindowNeverReachesTheCap` (defect F2): the cap never bound.
  /// With every kind on for six events over the horizon, the budget binds at 60.
  @Test func theBudgetBinds() throws {
    let now = Fixture.date(0, 0, dayOffset: -1)
    let every = AlertSettings(before: Fixture.minutes(10), after: Fixture.minutes(5))
    let schedule = try Fixture.alerts(
      from: now, to: now.addingTimeInterval(14 * 86_400),
      settings: Fixture.settings(every, for: Set(PrayerKind.allCases)))
    #expect(schedule.alerts.count == 14 * 18)
    #expect(AlertPlanner().notificationPlan(schedule, from: now).alerts.count == 60)
  }

  /// Was `characterizesFirstSixtyRequestsByFireDateWithoutKindPriority` (defect F2): the first
  /// 60 by fire date crowded out the fourth day's adhans with its reminders. Now the two
  /// near-term days are reserved and the rest of the budget goes to at-time alerts: the fourth
  /// day's Dhuhr is requested, its reminders aren't.
  @Test func nearTermFirstThenAtTimeAlerts() throws {
    let now = Fixture.date(0, 0)
    let every = AlertSettings(before: Fixture.minutes(10), after: Fixture.minutes(5))
    let schedule = try Fixture.alerts(
      from: now, to: Fixture.date(0, 0, dayOffset: 5),
      settings: Fixture.settings(every, for: Set(PrayerKind.allCases)))
    #expect(schedule.alerts.count == 90)
    let plan = AlertPlanner().notificationPlan(schedule, from: now)
    // 36 near-term requests (two days of six events with three kinds), then the 18 at-time
    // alerts of the next three days: 54, within the budget of 60.
    #expect(plan.alerts.count == 54)
    let ids = Set(plan.alerts.map(\.id))
    #expect(ids.contains(Fixture.identity(.dhuhr, .atTime, dayOffset: 3)))
    #expect(!ids.contains(Fixture.identity(.dhuhr, .before, dayOffset: 3)))
    #expect(!ids.contains(Fixture.identity(.sunrise, .after, dayOffset: 3)))
    #expect(plan.coveredUntil == Fixture.time(.fajr, dayOffset: 2).addingTimeInterval(-600))
    #expect(plan.coverageByKind[.atTime] == Fixture.date(0, 0, dayOffset: 5))
  }

  /// Retained (`schedulesEveryEnabledAlertStillAheadInTheWindow`): every enabled alert still
  /// ahead is requested, in fire order; passed ones aren't.
  @Test func plansEveryEnabledAlertStillAhead() throws {
    let now = Fixture.date(13, 0)
    let schedule = try Fixture.alerts(
      from: Fixture.date(0, 0, dayOffset: -1), to: Fixture.date(0, 0, dayOffset: 2),
      settings: Fixture.settings(AlertSettings()))
    let plan = AlertPlanner().notificationPlan(schedule, from: now)
    #expect(
      plan.alerts.map(\.id) == [
        Fixture.identity(.asr, .atTime), Fixture.identity(.maghrib, .atTime),
        Fixture.identity(.isha, .atTime), Fixture.identity(.fajr, .atTime, dayOffset: 1),
        Fixture.identity(.dhuhr, .atTime, dayOffset: 1),
        Fixture.identity(.asr, .atTime, dayOffset: 1),
        Fixture.identity(.maghrib, .atTime, dayOffset: 1),
        Fixture.identity(.isha, .atTime, dayOffset: 1),
      ])
  }

  // MARK: Catch-up

  nonisolated struct CatchUpCase: Sendable, CustomTestStringConvertible {
    enum Kind: Sendable { case atTime, before, after }
    var name: String
    var kind: Kind
    /// The reminder offset in minutes; ignored for the at-time alert.
    var offset: Int = 0
    /// Seconds after the fire date that the engine checks; negative is early.
    var lateness: Double
    var due: Bool

    var testDescription: String { name }
  }

  /// Retained (`catchUpWindows`, `PrayerAlertScheduler.swift:133-146`): at-time alerts are
  /// caught up for 5 minutes and reminders for 2, inclusive; a before-reminder never once its
  /// prayer has started; up to 1.5 s ahead counts as due, 2 s ahead is armed instead.
  @Test(arguments: [
    CatchUpCase(name: "adhan 2 s ahead, not yet due", kind: .atTime, lateness: -2, due: false),
    CatchUpCase(name: "adhan due 1.5 s ahead", kind: .atTime, lateness: -1.5, due: true),
    CatchUpCase(name: "adhan due 1 s ahead", kind: .atTime, lateness: -1, due: true),
    CatchUpCase(name: "adhan on time", kind: .atTime, lateness: 0, due: true),
    CatchUpCase(name: "adhan 299 s late", kind: .atTime, lateness: 299, due: true),
    CatchUpCase(name: "adhan 300 s late", kind: .atTime, lateness: 300, due: true),
    CatchUpCase(name: "adhan 301 s late", kind: .atTime, lateness: 301, due: false),
    CatchUpCase(
      name: "after-reminder 120 s late", kind: .after, offset: 5, lateness: 120, due: true),
    CatchUpCase(
      name: "after-reminder 121 s late", kind: .after, offset: 5, lateness: 121, due: false),
    CatchUpCase(
      name: "before-reminder 120 s late", kind: .before, offset: 10, lateness: 120, due: true),
    CatchUpCase(
      name: "before-reminder 121 s late", kind: .before, offset: 10, lateness: 121, due: false),
    CatchUpCase(
      name: "before-reminder 59 s late, prayer not started", kind: .before, offset: 1,
      lateness: 59, due: true),
    CatchUpCase(
      name: "before-reminder at its prayer's start", kind: .before, offset: 1, lateness: 60,
      due: false),
    CatchUpCase(
      name: "before-reminder 90 s late, prayer started", kind: .before, offset: 1, lateness: 90,
      due: false),
  ])
  @MainActor func catchUpWindows(_ testCase: CatchUpCase) throws {
    let settings: AlertSettings
    let kind: AlertKind
    let dhuhr = Fixture.time(.dhuhr)
    let fireDate: Date
    switch testCase.kind {
    case .atTime:
      settings = AlertSettings()
      kind = .atTime
      fireDate = dhuhr
    case .before:
      settings = AlertSettings(atTime: false, before: Fixture.minutes(testCase.offset))
      kind = .before
      fireDate = dhuhr.addingTimeInterval(-Double(testCase.offset * 60))
    case .after:
      settings = AlertSettings(atTime: false, after: Fixture.minutes(testCase.offset))
      kind = .after
      fireDate = dhuhr.addingTimeInterval(Double(testCase.offset * 60))
    }
    let now = fireDate.addingTimeInterval(testCase.lateness)
    // An in-process caller includes its catch-up interval in the range (RFC 0003 §4.6).
    let schedule = try Fixture.alerts(
      from: now.addingTimeInterval(-600), to: now.addingTimeInterval(86_400),
      settings: Fixture.settings(settings, for: [.dhuhr]))
    let clock = ManualAlertClock(now)
    var reported: [PlannedAlert] = []
    let engine = InProcessAlertEngine(clock: clock) { reported += $0 }
    engine.update(schedule)

    let id = Fixture.identity(.dhuhr, kind)
    #expect(reported.map(\.id).contains(id) == testCase.due)
    if !testCase.due && testCase.lateness < 0 {
      // Not yet due: the engine wakes just after the fire date instead.
      #expect(clock.armed == fireDate.addingTimeInterval(0.15))
    }
    // An alert that is already late isn't in a plan, which starts at now; one still ahead is.
    let plan = AlertPlanner().notificationPlan(schedule, from: now)
    #expect(plan.alerts.contains { $0.id == id } == (testCase.lateness <= 0))
  }

  // MARK: Audio precedence

  /// Retained (`latestDueAlertPlays`, `:549-558`): of the alerts due together, the latest fire
  /// date is preferred; both are reported.
  @Test @MainActor func latestDueAlertIsPreferred() throws {
    let now = Fixture.time(.dhuhr).addingTimeInterval(61)
    let schedule = try Fixture.alerts(
      from: now.addingTimeInterval(-600), to: now.addingTimeInterval(3_600),
      settings: Fixture.settings(AlertSettings(after: Fixture.minutes(1)), for: [.dhuhr]))
    var reported: [PlannedAlert] = []
    let engine = InProcessAlertEngine(clock: ManualAlertClock(now)) { reported += $0 }
    engine.update(schedule)
    #expect(reported.map(\.kind) == [.atTime, .after])
    #expect(InProcessAlertEngine.preferredAlert(among: reported)?.kind == .after)
  }

  /// Retained (`adhanBeatsABeforeReminderAtTheSameInstant`): at one instant the at-time alert
  /// beats a before-reminder, whatever the order it's given in.
  @Test func atTimeBeatsBeforeAtTheSameInstant() {
    let instant = Fixture.time(.isha)
    let isha = PlannedAlert(
      id: Fixture.identity(.isha, .atTime), event: event(.isha, instant), fireDate: instant,
      sound: .named("adhan.caf"))
    let fajrReminder = PlannedAlert(
      id: Fixture.identity(.fajr, .before, dayOffset: 1),
      event: event(.fajr, instant.addingTimeInterval(7_200), dayOffset: 1), fireDate: instant,
      sound: .named("reminder.caf"))
    #expect(InProcessAlertEngine.preferredAlert(among: [fajrReminder, isha]) == isha)
    #expect(InProcessAlertEngine.preferredAlert(among: [isha, fajrReminder]) == isha)
  }

  /// Retained (`beforeReminderBeatsAnAfterReminderAtTheSameInstant`): Maghrib + 45 and Isha − 45
  /// are both 19:45; the before-reminder wins.
  @Test func beforeBeatsAfterAtTheSameInstant() throws {
    let instant = Fixture.date(19, 45)
    let schedule = try Fixture.alerts(
      from: Fixture.date(19, 0), to: Fixture.date(20, 0),
      settings: { subject in
        switch subject.prayer {
        case .maghrib: AlertSettings(atTime: false, after: Fixture.minutes(45))
        case .isha: AlertSettings(atTime: false, before: Fixture.minutes(45))
        default: nil
        }
      })
    #expect(schedule.alerts.map(\.fireDate) == [instant, instant])
    #expect(
      InProcessAlertEngine.preferredAlert(among: schedule.alerts)?.id
        == Fixture.identity(.isha, .before))
    #expect(
      InProcessAlertEngine.preferredAlert(among: schedule.alerts.reversed())?.id
        == Fixture.identity(.isha, .before))
    #expect(InProcessAlertEngine.preferredAlert(among: []) == nil)
  }

  /// Retained (`systemSoundsAndSilentModePlayNoAppAudio`), as the engine's half of it: `onDue`
  /// reports every due alert with its sound, system and silent ones too, so the app plays only
  /// the sounds it owns.
  @Test @MainActor func onDueReportsEveryDueAlertWithItsSound() throws {
    let now = Fixture.time(.maghrib)
    let schedule = try Fixture.alerts(
      from: now.addingTimeInterval(-600), to: now.addingTimeInterval(3_600),
      settings: { subject in
        switch subject.prayer {
        case .maghrib: AlertSettings(sound: .system)
        default: nil
        }
      })
    var reported: [PlannedAlert] = []
    let engine = InProcessAlertEngine(clock: ManualAlertClock(now)) { reported += $0 }
    engine.update(schedule)
    #expect(reported.map(\.sound) == [.system])
    let silent = reported.filter { $0.sound != .system && $0.sound != .none }
    #expect(InProcessAlertEngine.preferredAlert(among: silent) == nil)
  }

  // MARK: Deduplication and the timer

  /// Retained (`aHandledAlertIsNotRepeated`): a handled occurrence isn't reported again by a
  /// later update or check.
  @Test @MainActor func aHandledAlertIsNotRepeated() throws {
    let now = Fixture.time(.dhuhr).addingTimeInterval(10)
    let schedule = try Fixture.alerts(
      from: now.addingTimeInterval(-600), to: now.addingTimeInterval(86_400),
      settings: Fixture.settings(AlertSettings(), for: [.dhuhr]))
    let clock = ManualAlertClock(now)
    var reports = 0
    let engine = InProcessAlertEngine(clock: clock) { reports += $0.count }
    engine.update(schedule)
    #expect(reports == 1)
    engine.update(schedule)
    clock.now = Fixture.time(.dhuhr).addingTimeInterval(180)
    engine.resync()
    #expect(reports == 1)
  }

  /// Retained (`armsTheAlertTimerJustAfterTheNextAlert`): the engine wakes 0.15 s after the
  /// next alert.
  @Test @MainActor func armsTheWakeJustAfterTheNextAlert() throws {
    let now = Fixture.date(6, 0)
    let schedule = try Fixture.alerts(
      from: now, to: now.addingTimeInterval(86_400),
      settings: Fixture.settings(AlertSettings(), for: [.dhuhr]))
    let clock = ManualAlertClock(now)
    let engine = InProcessAlertEngine(clock: clock) { _ in }
    engine.update(schedule)
    #expect(clock.armed == Fixture.time(.dhuhr).addingTimeInterval(0.15))
  }

  func event(_ kind: PrayerKind, _ time: Date, dayOffset: Int = 0) -> PrayerEvent {
    PrayerEvent(scheduleDay: Fixture.day.adding(days: dayOffset), kind: kind, time: time)
  }
}

#if canImport(UserNotifications) && !os(tvOS)
  /// The scheduler half of A2's characterization, against the modelled center.
  @Suite struct SchedulerCharacterizationPortTests {
    nonisolated static let prefix = "guidance.prayer."

    func scheduler(
      _ center: ModelCenter, clock: TestClock, thread: String? = "guidance-prayers"
    ) -> NotificationScheduler {
      NotificationScheduler(
        identifierPrefix: Self.prefix, namespace: "prayers", threadIdentifier: thread,
        center: center, now: { clock.now })
    }

    func plan(
      at now: Date, days: Int = 2, settings: @escaping (AlertSubject) -> AlertSettings?
    ) throws -> NotificationPlan {
      let schedule = try Fixture.alerts(
        from: now, to: now.addingTimeInterval(Double(days) * 86_400), settings: settings)
      return AlertPlanner().notificationPlan(schedule, from: now)
    }

    /// Salah's content per kind (`:526-544`): the prayer as title, time-sensitive at-time and
    /// before alerts, an active after alert, relevance 1.0 / 0.7 / 0.5, and the kind in user info.
    nonisolated static let salahContent: @Sendable (PlannedAlert) -> UNMutableNotificationContent = { alert in
      let content = UNMutableNotificationContent()
      content.title = alert.id.prayer.rawValue.capitalized
      content.body = "\(alert.kind.rawValue)"
      content.userInfo = ["prayer": alert.id.prayer.rawValue, "kind": alert.kind.rawValue]
      switch alert.kind {
      case .atTime:
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0
      case .before:
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 0.7
      case .after:
        content.interruptionLevel = .active
        content.relevanceScore = 0.5
      }
      content.sound = alert.sound.notificationSound
      return content
    }

    /// Was `characterizesIdentifiersCarryTheFireTimestamp` (defect, §7.5 identity): the
    /// identifier was prefix, prayer, kind and the fire date's Unix time. Now it is the prefix,
    /// namespace, owning day, prayer and kind, and moving a reminder keeps it.
    @Test func identifiersAreStable() async throws {
      let clock = TestClock(Fixture.date(6, 0))
      let center = ModelCenter(clock: clock)
      let scheduler = scheduler(center, clock: clock)
      let ten = AlertSettings(before: Fixture.minutes(10), after: Fixture.minutes(5))
      _ = try await scheduler.apply(
        try plan(at: clock.now, days: 1, settings: Fixture.settings(ten, for: [.dhuhr])),
        content: Self.salahContent)
      #expect(
        center.pending.keys.sorted() == [
          "guidance.prayer.prayers/2026-06-02/dhuhr/after",
          "guidance.prayer.prayers/2026-06-02/dhuhr/atTime",
          "guidance.prayer.prayers/2026-06-02/dhuhr/before",
        ])
      let fifteen = AlertSettings(before: Fixture.minutes(15), after: Fixture.minutes(5))
      let report = try await scheduler.apply(
        try plan(at: clock.now, days: 1, settings: Fixture.settings(fifteen, for: [.dhuhr])),
        content: Self.salahContent)
      let before = "guidance.prayer.prayers/2026-06-02/dhuhr/before"
      let pending = center.pending
      #expect(pending.count == 3)
      #expect(pending[before].flatMap(ModelCenter.fireDate) == Fixture.date(12, 4))
      #expect(
        report.confirmed.contains(
          AlertOccurrenceID(
            notification: Fixture.identity(.dhuhr, .before), fireDate: Fixture.date(12, 4))))
    }

    /// Was `characterizesAMovedAlertIsRemovedBeforeItsReplacementIsAdded` (defect, A-30): a moved
    /// alert's request was removed before its replacement was added. Now it's replaced by an
    /// add under its identifier and never removed.
    @Test func aMovedAlertIsReplacedNotRemoved() async throws {
      let clock = TestClock(Fixture.date(6, 0))
      let center = ModelCenter(clock: clock)
      let scheduler = scheduler(center, clock: clock)
      for minutes in [10, 15] {
        _ = try await scheduler.apply(
          try plan(
            at: clock.now, days: 1,
            settings: Fixture.settings(
              AlertSettings(atTime: false, before: Fixture.minutes(minutes)), for: [.dhuhr])),
          content: Self.salahContent)
      }
      let calls = center.calls
      #expect(!calls.contains { $0["removePending"] != nil })
      #expect(calls.filter { $0["add"] != nil }.count == 2)
      #expect(center.pending.count == 1)
    }

    /// Retained (`requestContentPerKind`, interruption levels `:638-643`): the content is the
    /// closure's, unchanged; the scheduler sets only the thread.
    @Test func requestContentComesFromTheClosure() async throws {
      let clock = TestClock(Fixture.date(6, 0))
      let center = ModelCenter(clock: clock)
      let settings = AlertSettings(
        before: Fixture.minutes(10), after: Fixture.minutes(5), sound: .named("adhan.caf"),
        beforeSound: .system, afterSound: .none)
      _ = try await scheduler(center, clock: clock).apply(
        try plan(at: clock.now, days: 1, settings: Fixture.settings(settings, for: [.dhuhr])),
        content: Self.salahContent)
      let pending = center.pending
      let request = { (kind: String) in pending["guidance.prayer.prayers/2026-06-02/dhuhr/\(kind)"]
      }
      let (before, atTime, after) = (request("before"), request("atTime"), request("after"))
      #expect(before?.content.interruptionLevel == .timeSensitive)
      #expect(atTime?.content.interruptionLevel == .timeSensitive)
      #expect(after?.content.interruptionLevel == .active)
      #expect(
        [before, atTime, after].map { $0?.content.relevanceScore } == [0.7, 1.0, 0.5])
      #expect(
        Set([before, atTime, after].compactMap { $0?.content.threadIdentifier })
          == ["guidance-prayers"])
      #expect(before?.content.userInfo["kind"] as? String == "before")
      #expect(atTime?.content.title == "Dhuhr")
      // Each kind's sound: system, a named file, none.
      #expect(before?.content.sound == UNNotificationSound.default)
      #expect(atTime?.content.sound == AlertSound.named("adhan.caf").notificationSound)
      #expect(after?.content.sound == nil)
    }

    /// Retained as app policy (`silentModeSchedulesSilentRequests`): a closure that drops the
    /// sound gives silent requests.
    @Test func silentContentStaysSilent() async throws {
      let clock = TestClock(Fixture.date(6, 0))
      let center = ModelCenter(clock: clock)
      _ = try await scheduler(center, clock: clock).apply(
        try plan(
          at: clock.now, days: 1, settings: Fixture.settings(AlertSettings(), for: [.dhuhr])),
        content: { alert in
          let content = Self.salahContent(alert)
          content.sound = nil
          return content
        })
      #expect(center.pending.values.allSatisfy { $0.content.sound == nil })
      #expect(AlertSound.none.notificationSound == nil)
    }

    /// Retained (`triggersAreNonRepeatingUTCCalendarDates`, `:492-504`): Gregorian UTC calendar
    /// triggers that never repeat, so a time-zone change doesn't move a pending request.
    @Test func triggersAreNonRepeatingUTCCalendarDates() async throws {
      let clock = TestClock(Fixture.date(6, 0))
      let center = ModelCenter(clock: clock)
      _ = try await scheduler(center, clock: clock).apply(
        try plan(
          at: clock.now, days: 1, settings: Fixture.settings(AlertSettings(), for: [.dhuhr])),
        content: Self.salahContent)
      let request = try #require(center.pending.values.first)
      let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
      let utc = TimeZone(identifier: "UTC")
      #expect(!trigger.repeats)
      #expect(trigger.dateComponents.timeZone == utc)
      #expect(trigger.dateComponents.calendar?.identifier == .gregorian)
      #expect(trigger.dateComponents.calendar?.timeZone == utc)
      // Dhuhr 12:19 in Riyadh is 09:19 UTC.
      #expect(trigger.dateComponents.year == 2026)
      #expect(trigger.dateComponents.month == 6)
      #expect(trigger.dateComponents.day == 2)
      #expect(trigger.dateComponents.hour == 9)
      #expect(trigger.dateComponents.minute == 19)
      #expect(trigger.dateComponents.second == 0)
    }

    /// Retained (`launchHousekeepingRemovesOnlyOldOwnDeliveredNotifications`, `:378-416`): own
    /// delivered notifications older than the retention go, strictly older; nothing else does.
    @Test func retentionRemovesOnlyOldOwnDeliveredNotifications() async throws {
      let now = Fixture.date(13, 0)
      let cutoff = now.addingTimeInterval(-2 * 86_400)
      let own = { (day: String) in "guidance.prayer.prayers/\(day)/fajr/atTime" }
      let old = own("2026-05-29")
      let atCutoff = own("2026-05-30")
      let recent = own("2026-06-02")
      let otherNamespace = "guidance.prayer.mosque/2026-05-29/fajr/atTime"
      let foreign = "com.example.other"
      let clock = TestClock(now)
      let center = ModelCenter(
        clock: clock,
        delivered: [
          DeliveredNotificationRecord(identifier: old, date: cutoff.addingTimeInterval(-1)),
          DeliveredNotificationRecord(identifier: atCutoff, date: cutoff),
          DeliveredNotificationRecord(identifier: recent, date: now.addingTimeInterval(-3_600)),
          DeliveredNotificationRecord(
            identifier: otherNamespace, date: cutoff.addingTimeInterval(-60)),
          DeliveredNotificationRecord(identifier: foreign, date: cutoff.addingTimeInterval(-3_600)),
        ])
      _ = try await scheduler(center, clock: clock).apply(
        try plan(at: now, settings: { _ in nil }), content: Self.salahContent)
      #expect(
        center.delivered.map(\.identifier) == [atCutoff, recent, otherNamespace, foreign])
    }

    /// Changed (`rescheduleRemovesOwnDeliveredNotificationsThatNoLongerMatch`, RFC 0003 §6): a
    /// plan holds only upcoming alerts, so delivered notifications stay until their retention
    /// ends, even when their alert is gone or reworded.
    @Test func deliveredNotificationsStayWithinTheirRetention() async throws {
      let now = Fixture.date(13, 0)
      let fajr = "guidance.prayer.prayers/2026-06-02/fajr/atTime"
      let clock = TestClock(now)
      let center = ModelCenter(
        clock: clock,
        delivered: [DeliveredNotificationRecord(identifier: fajr, date: Fixture.time(.fajr))])
      _ = try await scheduler(center, clock: clock).apply(
        try plan(at: now, settings: { _ in nil }), content: Self.salahContent)
      #expect(center.delivered.map(\.identifier) == [fajr])
    }

    /// Retained (`obsoleteOwnRequestsAreRemovedAndOthersKept`): own requests that are no longer
    /// wanted are removed in one call; wanted ones and other apps' requests stay.
    @Test func obsoleteOwnRequestsAreRemovedAndOthersKept() async throws {
      let now = Fixture.date(13, 0)
      let stale = "guidance.prayer.prayers/2026-06-02/asr/atTime"
      let foreign = "com.example.other"
      let clock = TestClock(now)
      let center = ModelCenter(
        clock: clock,
        pending: [
          ModelCenter.request(
            stale, fireDate: Fixture.time(.asr), title: "Asr", body: "", thread: ""),
          ModelCenter.request(
            foreign, fireDate: Fixture.time(.asr), title: "", body: "", thread: ""),
        ])
      _ = try await scheduler(center, clock: clock).apply(
        try plan(
          at: now, days: 1, settings: Fixture.settings(AlertSettings(), for: [.maghrib, .isha])),
        content: Self.salahContent)
      let removals = center.calls.compactMap { $0["removePending"] }
      #expect(removals == [.array([.string(stale)])])
      #expect(
        Set(center.pending.keys) == [
          foreign, "guidance.prayer.prayers/2026-06-02/maghrib/atTime",
          "guidance.prayer.prayers/2026-06-02/isha/atTime",
        ])
    }

    /// Retained for pending requests (`emptyScheduleClearsOwnRequestsAndDeliveries`): an empty
    /// plan removes every own pending request; delivered ones follow their retention.
    @Test func emptyPlanClearsOwnRequests() async throws {
      let now = Fixture.date(13, 0)
      let own = "guidance.prayer.prayers/2026-06-02/isha/atTime"
      let clock = TestClock(now)
      let center = ModelCenter(
        clock: clock,
        pending: [
          ModelCenter.request(own, fireDate: Fixture.time(.isha), title: "", body: "", thread: ""),
          ModelCenter.request(
            "com.example.other", fireDate: Fixture.time(.isha), title: "", body: "", thread: ""),
        ],
        delivered: [DeliveredNotificationRecord(identifier: own, date: Fixture.date(12, 0))])
      _ = try await scheduler(center, clock: clock).apply(
        try plan(at: now, settings: { _ in nil }), content: Self.salahContent)
      #expect(Array(center.pending.keys) == ["com.example.other"])
      #expect(center.delivered.map(\.identifier) == [own])
    }

    /// Retained (`deniedAuthorizationRemovesOwnRequestsAndAddsNone`): denied, the own pending
    /// requests are removed and nothing is added.
    @Test func deniedAuthorizationRemovesOwnRequestsAndAddsNone() async throws {
      let now = Fixture.date(13, 0)
      let own = "guidance.prayer.prayers/2026-06-02/isha/atTime"
      let clock = TestClock(now)
      let center = ModelCenter(
        clock: clock, authorization: .denied,
        pending: [
          ModelCenter.request(own, fireDate: Fixture.time(.isha), title: "", body: "", thread: "")
        ])
      let report = try await scheduler(center, clock: clock).apply(
        try plan(at: now, settings: Fixture.settings(AlertSettings(), for: [.isha])),
        content: Self.salahContent)
      #expect(center.pending.isEmpty)
      #expect(!(center.calls).contains { $0["add"] != nil })
      #expect(report.confirmed.isEmpty)
      #expect(report.failures[Fixture.identity(.isha, .atTime)] == .notAuthorized)
    }

    /// App policy (`authorizationIsRequestedOnlyWithSomethingToSchedule`): the scheduler never
    /// asks for authorization (`AlertNotificationCenter` has no way to); undetermined, it adds
    /// nothing.
    @Test func undeterminedAuthorizationAddsNothing() async throws {
      let now = Fixture.date(13, 0)
      let clock = TestClock(now)
      let center = ModelCenter(clock: clock, authorization: .notDetermined)
      let report = try await scheduler(center, clock: clock).apply(
        try plan(at: now, settings: Fixture.settings(AlertSettings(), for: [.isha])),
        content: Self.salahContent)
      #expect(center.pending.isEmpty)
      #expect(report.failures.values.allSatisfy { $0 == .notAuthorized })
      #expect(report.failures.count == 2)
    }

    /// Retained (`catchUpWindows`: caught-up alerts get an immediate request): `deliver` posts a
    /// due alert at once when no request will deliver it.
    @Test func caughtUpAlertsArePostedAtOnce() async throws {
      let now = Fixture.time(.dhuhr).addingTimeInterval(60)
      let clock = TestClock(now)
      let center = ModelCenter(clock: clock)
      let schedule = try Fixture.alerts(
        from: now.addingTimeInterval(-600), to: now.addingTimeInterval(600),
        settings: Fixture.settings(AlertSettings(), for: [.dhuhr]))
      let report = try await scheduler(center, clock: clock).deliver(
        schedule.alerts, content: Self.salahContent)
      #expect(report.posted.map(\.notification) == [Fixture.identity(.dhuhr, .atTime)])
      #expect(center.calls.contains { $0["addImmediate"] != nil })
      #expect(center.pending.isEmpty)
    }
  }
#endif
