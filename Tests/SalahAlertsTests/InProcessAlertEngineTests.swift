import Foundation
import SalahAlerts
import SalahCore
import Testing

/// The in-process engine (RFC 0003 §4.6) with an injected clock: timers, sleep and wake, clock
/// changes, changed fire times and the reminders a notification plan leaves out.
@MainActor @Suite struct InProcessAlertEngineTests {
  /// Records what the engine reports.
  final class Recorder {
    var batches: [[PlannedAlert]] = []
    var ids: [NotificationIdentity] { batches.flatMap { $0.map(\.id) } }
  }

  func engine(
    at now: Date, catchUp: CatchUpPolicy = CatchUpPolicy()
  ) -> (InProcessAlertEngine, ManualAlertClock, Recorder) {
    let clock = ManualAlertClock(now)
    let recorder = Recorder()
    let engine = InProcessAlertEngine(catchUp: catchUp, clock: clock) {
      recorder.batches.append($0)
    }
    return (engine, clock, recorder)
  }

  let dhuhrAll = Fixture.settings(
    AlertSettings(before: Fixture.minutes(10), after: Fixture.minutes(5)), for: [.dhuhr])

  @Test func theTimerReportsEachAlertWhenItComes() throws {
    let start = Fixture.date(12, 0)
    let (engine, clock, recorder) = engine(at: start)
    engine.update(try Fixture.alerts(from: start, to: Fixture.date(13, 0), settings: dhuhrAll))
    #expect(recorder.batches.isEmpty)
    #expect(clock.armed == Fixture.date(12, 9).addingTimeInterval(0.15))
    clock.fire()
    #expect(recorder.ids == [Fixture.identity(.dhuhr, .before)])
    #expect(clock.armed == Fixture.date(12, 19).addingTimeInterval(0.15))
    clock.fire()
    clock.fire()
    #expect(
      recorder.ids == [
        Fixture.identity(.dhuhr, .before), Fixture.identity(.dhuhr, .atTime),
        Fixture.identity(.dhuhr, .after),
      ])
    #expect(clock.armed == nil, "nothing is left to wake for")
  }

  /// The D7 fixture: the notification plan holds only two days of reminders, but the engine
  /// gets the whole schedule and reports a reminder on the third day.
  @Test func retainsRemindersTheNotificationPlanLeavesOut() throws {
    let now = Fixture.date(0, 0, dayOffset: -1)
    let every = AlertSettings(before: Fixture.minutes(10), after: Fixture.minutes(5))
    let schedule = try Fixture.alerts(
      from: now, to: now.addingTimeInterval(14 * 86_400), settings: Fixture.settings(every))
    let plan = AlertPlanner().notificationPlan(schedule, from: now)
    let reminder = Fixture.identity(.fajr, .before, dayOffset: 1)
    #expect(!plan.alerts.contains { $0.id == reminder })

    let (engine, clock, recorder) = engine(at: now)
    engine.update(schedule)
    clock.now = Fixture.time(.fajr, dayOffset: 1).addingTimeInterval(-600)
    engine.resync()
    #expect(recorder.ids == [reminder])
  }

  /// Asleep through Dhuhr: on wake three minutes later the at-time alert is caught up (5-minute
  /// grace); its after-reminder isn't due yet; the before-reminder's grace has passed.
  @Test func wakingWithinTheGraceCatchesUp() throws {
    let start = Fixture.date(12, 0)
    let (engine, clock, recorder) = engine(at: start)
    engine.update(try Fixture.alerts(from: start, to: Fixture.date(13, 0), settings: dhuhrAll))
    // Asleep: no timer fires. The device wakes at 12:22.
    clock.now = Fixture.date(12, 22)
    engine.resync()
    #expect(recorder.batches.count == 1)
    #expect(recorder.ids == [Fixture.identity(.dhuhr, .atTime)])
    #expect(clock.armed == Fixture.date(12, 24).addingTimeInterval(0.15))
  }

  @Test func wakingAfterTheGraceDropsTheAlert() throws {
    let start = Fixture.date(12, 0)
    let (engine, clock, recorder) = engine(at: start)
    engine.update(try Fixture.alerts(from: start, to: Fixture.date(13, 0), settings: dhuhrAll))
    clock.now = Fixture.date(12, 30)
    engine.resync()
    #expect(recorder.batches.isEmpty)
    #expect(clock.armed == nil)
  }

  /// The clock is set back two hours after Dhuhr was handled: the engine re-arms for the
  /// earliest alert ahead, and doesn't repeat the occurrence it handled.
  @Test func aClockSetBackRearmsWithoutRepeating() throws {
    let start = Fixture.date(12, 19)
    let (engine, clock, recorder) = engine(at: start)
    let schedule = try Fixture.alerts(
      from: Fixture.date(9, 0), to: Fixture.date(13, 0),
      settings: Fixture.settings(AlertSettings(), for: [.dhuhr]))
    engine.update(schedule)
    #expect(recorder.ids == [Fixture.identity(.dhuhr, .atTime)])
    clock.now = Fixture.date(10, 19)
    engine.resync()
    #expect(clock.armed == nil, "Dhuhr was handled; nothing else is ahead in range")
    clock.now = Fixture.date(12, 19)
    engine.resync()
    #expect(recorder.batches.count == 1)
  }

  @Test func aHandledOccurrenceIsRecordedBeforeItsCallback() throws {
    let now = Fixture.date(12, 19, second: 30)
    let clock = ManualAlertClock(now)
    var sawRecord = false
    var engine: InProcessAlertEngine?
    engine = InProcessAlertEngine(clock: clock) { due in
      sawRecord = due.allSatisfy { engine?.handledOccurrences[$0.occurrenceID] == now }
    }
    let schedule = try Fixture.alerts(
      from: Fixture.date(12, 0), to: Fixture.date(13, 0), settings: dhuhrAll)
    engine?.update(schedule)
    #expect(sawRecord)
    let alert = try #require(schedule.alerts.first { $0.kind == .atTime })
    #expect(engine?.handledOccurrences == [alert.occurrenceID: now])
    engine?.resync()
    #expect(engine?.handledOccurrences[alert.occurrenceID] == now)
    engine = nil
  }

  @Test(arguments: [-1.5, 300.0])
  func handledOccurrencesLastADayAfterTheirReport(_ lateness: TimeInterval) throws {
    let reportedAt = Fixture.time(.dhuhr).addingTimeInterval(lateness)
    let (engine, clock, _) = engine(at: reportedAt)
    let schedule = try Fixture.alerts(
      from: Fixture.date(12, 0), to: Fixture.date(13, 0),
      settings: Fixture.settings(AlertSettings(), for: [.dhuhr]))
    let occurrence = try #require(schedule.alerts.first).occurrenceID
    engine.update(schedule)
    #expect(engine.handledOccurrences == [occurrence: reportedAt])

    clock.now = reportedAt.addingTimeInterval(86_399)
    engine.resync()
    #expect(engine.handledOccurrences == [occurrence: reportedAt])
    clock.now = reportedAt.addingTimeInterval(86_400)
    engine.resync()
    #expect(engine.handledOccurrences.isEmpty, "pruned at exactly one day after its report")
  }

  @Test func aClockRollbackAfterFourHoursStillKeepsTheHandledOccurrence() throws {
    let now = Fixture.time(.dhuhr)
    let (engine, clock, recorder) = engine(at: now)
    let schedule = try Fixture.alerts(
      from: Fixture.date(12, 0), to: Fixture.date(13, 0),
      settings: Fixture.settings(AlertSettings(), for: [.dhuhr]))
    engine.update(schedule)
    clock.now = now.addingTimeInterval(4 * 3_600)
    engine.resync()
    clock.now = Fixture.date(12, 0)
    engine.update(schedule)
    let plan = AlertPlanner().notificationPlan(
      schedule, from: clock.now, excluding: Set(engine.handledOccurrences.keys))
    #expect(plan.alerts.isEmpty)
    #expect(plan.coveredUntil == Fixture.date(13, 0))
    clock.now = now
    engine.resync()
    #expect(recorder.batches.count == 1)
  }

  @Test func aLongGraceKeepsTheRecordBeyondADay() throws {
    let reportedAt = Fixture.time(.dhuhr)
    let (engine, clock, _) = engine(
      at: reportedAt, catchUp: CatchUpPolicy(atTimeGrace: .seconds(2 * 86_400)))
    engine.update(
      try Fixture.alerts(
        from: Fixture.date(12, 0), to: Fixture.date(13, 0),
        settings: Fixture.settings(AlertSettings(), for: [.dhuhr])))
    clock.now = reportedAt.addingTimeInterval(2 * 86_400 + 59)
    engine.resync()
    #expect(engine.handledOccurrences.count == 1)
    clock.now = reportedAt.addingTimeInterval(2 * 86_400 + 60)
    engine.resync()
    #expect(engine.handledOccurrences.isEmpty)
  }

  @Test func aClockSetForwardCatchesUp() throws {
    let start = Fixture.date(11, 0)
    let (engine, clock, recorder) = engine(at: start)
    engine.update(try Fixture.alerts(from: start, to: Fixture.date(13, 0), settings: dhuhrAll))
    clock.now = Fixture.date(12, 20)
    engine.resync()
    // The before-reminder's two minutes have passed; the at-time alert is a minute late.
    #expect(recorder.ids == [Fixture.identity(.dhuhr, .atTime)])
  }

  /// A recalculation moves Dhuhr from 12:19 to 12:21 after its alert was handled: the new
  /// occurrence is a different one, and is reported when it comes.
  @Test func aChangedFireTimeIsANewOccurrence() throws {
    let start = Fixture.date(12, 19)
    let (engine, clock, recorder) = engine(at: start)
    let settings = Fixture.settings(AlertSettings(), for: [.dhuhr])
    engine.update(
      try Fixture.alerts(from: Fixture.date(12, 0), to: Fixture.date(13, 0), settings: settings))
    #expect(recorder.batches.count == 1)

    let moved = try Fixture.alerts(
      from: Fixture.date(12, 0), to: Fixture.date(13, 0),
      schedule: PrayerSchedule(source: movedDhuhr(), location: Fixture.location),
      settings: settings)
    engine.update(moved)
    #expect(recorder.batches.count == 1)
    #expect(clock.armed == Fixture.date(12, 21).addingTimeInterval(0.15))
    clock.fire()
    #expect(recorder.batches.count == 2)
    #expect(recorder.batches[1].first?.fireDate == Fixture.date(12, 21))
  }

  @Test func repeatedReplansReportOnce() throws {
    let now = Fixture.date(12, 19, second: 30)
    let (engine, _, recorder) = engine(at: now)
    let schedule = try Fixture.alerts(
      from: Fixture.date(12, 0), to: Fixture.date(13, 0), settings: dhuhrAll)
    for _ in 0..<5 {
      engine.update(schedule)
      engine.resync()
    }
    #expect(recorder.ids == [Fixture.identity(.dhuhr, .atTime)])
  }

  /// Due alerts are reported together, by fire date and identity.
  @Test func alertsDueTogetherArriveInOneBatch() throws {
    let start = Fixture.date(19, 0)
    let (engine, clock, recorder) = engine(at: start)
    engine.update(
      try Fixture.alerts(
        from: start, to: Fixture.date(21, 0),
        settings: { subject in
          switch subject.prayer {
          case .maghrib: AlertSettings(atTime: false, after: Fixture.minutes(45))
          case .isha: AlertSettings(atTime: false, before: Fixture.minutes(45))
          default: nil
          }
        }))
    clock.fire()
    #expect(recorder.batches.count == 1)
    #expect(
      recorder.ids == [Fixture.identity(.maghrib, .after), Fixture.identity(.isha, .before)])
  }

  @Test func gracesAreConfigurable() throws {
    let start = Fixture.date(12, 0)
    let (engine, clock, recorder) = engine(
      at: start, catchUp: CatchUpPolicy(atTimeGrace: .seconds(30), reminderGrace: .seconds(-5)))
    engine.update(try Fixture.alerts(from: start, to: Fixture.date(13, 0), settings: dhuhrAll))
    clock.now = Fixture.date(12, 19, second: 31)
    engine.resync()
    #expect(recorder.batches.isEmpty, "31 s late is past a 30 s grace")
    clock.now = Fixture.date(12, 24)
    engine.resync()
    #expect(
      recorder.ids == [Fixture.identity(.dhuhr, .after)],
      "a negative grace counts as zero, which still includes the fire date itself")
    #expect(CatchUpPolicy().atTimeGrace == .seconds(300))
    #expect(CatchUpPolicy().reminderGrace == .seconds(120))
  }

  /// An app that replans inside `onDue` doesn't get the alert twice.
  @Test func replanningInsideOnDueDoesNotRepeat() throws {
    let now = Fixture.date(12, 19)
    let clock = ManualAlertClock(now)
    let schedule = try Fixture.alerts(
      from: Fixture.date(12, 0), to: Fixture.date(13, 0),
      settings: Fixture.settings(AlertSettings(), for: [.dhuhr]))
    var reports = 0
    var engine: InProcessAlertEngine?
    engine = InProcessAlertEngine(clock: clock) { _ in
      reports += 1
      engine?.update(schedule)
    }
    engine?.update(schedule)
    #expect(reports == 1)
  }

  /// The real clock wakes the engine at a wall-clock date.
  @Test func theSystemClockWakes() async throws {
    let clock = SystemAlertClock()
    let woke = Woke()
    clock.wake(at: Date().addingTimeInterval(0.2)) { woke.value = true }
    for _ in 0..<200 where !woke.value {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(woke.value)

    let cancelled = Woke()
    clock.wake(at: Date().addingTimeInterval(0.2)) { cancelled.value = true }
    clock.wake(at: nil) { cancelled.value = true }
    try await Task.sleep(for: .milliseconds(600))
    #expect(!cancelled.value)
  }

  /// A wake-up whose sleep ends while the main actor is busy, and which is replaced before the
  /// main actor is free, doesn't run: its sleep has already finished, so only the replacement's
  /// cancellation can stop it.
  @Test func aReplacedWakeUpDoesNotRun() async throws {
    let clock = SystemAlertClock()
    let replaced = Woke()
    clock.wake(at: Date().addingTimeInterval(0.05)) { replaced.value = true }
    // Let the wake-up's task start its sleep, then keep the main actor busy past its date and
    // tolerance.
    try await Task.sleep(for: .milliseconds(10))
    Self.blockTheMainActor(for: 1.0)
    clock.wake(at: Date().addingTimeInterval(3_600)) {}
    try await Task.sleep(for: .milliseconds(300))
    #expect(!replaced.value)
    clock.wake(at: nil) {}
  }

  /// A before-reminder whose prayer begins within the timer's margin wakes the engine a second
  /// before its prayer, so it's reported rather than dropped once its prayer has begun.
  @Test func aReminderJustBeforeItsPrayerIsReported() throws {
    let start = Fixture.date(12, 0)
    let (engine, clock, recorder) = engine(at: start)
    let close = Fixture.settings(
      AlertSettings(atTime: false, before: .milliseconds(100)), for: [.dhuhr])
    engine.update(try Fixture.alerts(from: start, to: Fixture.date(13, 0), settings: close))
    #expect(clock.armed == Fixture.time(.dhuhr).addingTimeInterval(-1))
    clock.fire()
    #expect(recorder.ids == [Fixture.identity(.dhuhr, .before)])
  }

  /// Blocks the main actor, as long synchronous work would.
  static func blockTheMainActor(for seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
  }

  /// A before-reminder dated after its prayer, which only a hand-made schedule can hold, arms
  /// one wake-up within its early leeway rather than a past one the timer would fire at once,
  /// again and again.
  @Test func aReminderDatedAfterItsPrayerArmsNoPastWakeUp() throws {
    let prayer = Fixture.time(.dhuhr)
    let fireDate = prayer.addingTimeInterval(11 * 60)
    let now = prayer.addingTimeInterval(60)
    let (engine, clock, recorder) = engine(at: now)
    let late = PlannedAlert(
      id: Fixture.identity(.dhuhr, .before),
      event: PrayerEvent(scheduleDay: Fixture.day, kind: .dhuhr, time: prayer),
      fireDate: fireDate, sound: .system)
    engine.update(
      AlertSchedule(
        namespace: "prayers", alerts: [late],
        requestedRange: DateInterval(start: now, end: fireDate.addingTimeInterval(3_600)),
        gaps: []))
    // The 1.5-second early leeway.
    #expect(clock.armed == fireDate.addingTimeInterval(-1.5))
    clock.fire()
    #expect(recorder.batches.isEmpty, "its prayer has begun")
    #expect(clock.armed == nil)
  }

  @MainActor final class Woke {
    var value = false
  }

  /// The fixture with Dhuhr on 2 June moved to 12:21.
  func movedDhuhr() -> TimetableSource {
    let source = Fixture.source()
    let rows = source.rows.map { row in
      guard row.day == Fixture.day else { return row }
      var times = row.times
      times[.dhuhr] = .local(WallClockTime(hour: 12, minute: 21))
      return TimetableSource.Row(day: row.day, times: times)
    }
    return TimetableSource(rows: rows, expectedKinds: source.expectedKinds)
  }
}
