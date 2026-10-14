#if canImport(UserNotifications) && !os(tvOS)
  import Foundation
  import SalahAlerts
  import SalahCore
  import Testing
  import UserNotifications

  /// The scheduler beyond the vectors (RFC 0003 §4.5): which content changes count, triggers,
  /// threads, the pump under load, and `deliver` beside `apply`.
  @Suite struct NotificationSchedulerTests {
    static let asr = Fixture.identity(.asr, .atTime)
    static let identifier = "salah.prayers/2026-06-02/asr/atTime"

    func plan(_ alerts: [PlannedAlert], at now: Date) -> NotificationPlan {
      NotificationPlan(
        namespace: "prayers", effectiveRange: DateInterval(start: now, end: now + 86_400),
        alerts: alerts, coveredUntil: now + 86_400, coverageByKind: [:])
    }

    func asrAlert(at fireDate: Date = Fixture.time(.asr)) -> PlannedAlert {
      PlannedAlert(
        id: Self.asr,
        event: PrayerEvent(scheduleDay: Fixture.day, kind: .asr, time: Fixture.time(.asr)),
        fireDate: fireDate, sound: .system)
    }

    func scheduler(
      _ center: ModelCenter, clock: TestClock, thread: String? = nil
    ) -> NotificationScheduler {
      NotificationScheduler(
        identifierPrefix: "salah.", namespace: "prayers", threadIdentifier: thread,
        center: center, now: { clock.now })
    }

    /// A content with every compared field set.
    nonisolated static func fullContent() -> UNMutableNotificationContent {
      let content = UNMutableNotificationContent()
      content.title = "Asr"
      content.subtitle = "Makkah"
      content.body = "It's time for Asr"
      content.sound = .default
      content.badge = 1
      content.threadIdentifier = "prayers"
      content.categoryIdentifier = "prayer"
      content.userInfo = ["prayer": "asr", "offset": 0]
      content.interruptionLevel = .timeSensitive
      content.relevanceScore = 1
      content.targetContentIdentifier = "asr"
      content.filterCriteria = "work"
      return content
    }

    nonisolated struct Change: Sendable, CustomTestStringConvertible {
      var testDescription: String
      var apply: @Sendable (UNMutableNotificationContent) -> Void
    }

    /// Changing any compared field of the content makes the pending request stale, so the
    /// scheduler adds it again; an unchanged content isn't added.
    @Test(arguments: [
      Change(testDescription: "nothing") { _ in },
      Change(testDescription: "title") { $0.title = "Asr prayer" },
      Change(testDescription: "subtitle") { $0.subtitle = "Madinah" },
      Change(testDescription: "body") { $0.body = "Asr has started" },
      Change(testDescription: "sound") { $0.sound = nil },
      Change(testDescription: "badge") { $0.badge = 2 },
      Change(testDescription: "thread") { $0.threadIdentifier = "reminders" },
      Change(testDescription: "category") { $0.categoryIdentifier = "reminder" },
      Change(testDescription: "user info") { $0.userInfo = ["prayer": "asr", "offset": 5] },
      Change(testDescription: "interruption level") { $0.interruptionLevel = .active },
      Change(testDescription: "relevance score") { $0.relevanceScore = 0.5 },
      Change(testDescription: "target content") { $0.targetContentIdentifier = "dhuhr" },
      Change(testDescription: "filter criteria") { $0.filterCriteria = "home" },
    ])
    func everyComparedFieldCounts(_ change: Change) async throws {
      let clock = TestClock(Fixture.date(6, 0))
      let existing = UNNotificationRequest(
        identifier: Self.identifier, content: Self.fullContent(),
        trigger: ModelCenter.request(
          Self.identifier, fireDate: Fixture.time(.asr), title: "", body: "", thread: ""
        ).trigger)
      let center = ModelCenter(clock: clock, pending: [existing])
      let report = try await scheduler(center, clock: clock).apply(
        plan([asrAlert()], at: clock.now),
        content: { _ in
          let content = Self.fullContent()
          change.apply(content)
          return content
        })
      let added = center.calls.contains { $0["add"] != nil }
      #expect(added == (change.testDescription != "nothing"))
      #expect(report.confirmed.map(\.notification) == [Self.asr])
    }

    /// A pending request with a repeating or a time-interval trigger never matches.
    @Test func onlyANonRepeatingCalendarTriggerMatches() async throws {
      let clock = TestClock(Fixture.date(6, 0))
      var components = Calendar(identifier: .gregorian).dateComponents(
        in: TimeZone(identifier: "UTC") ?? .gmt, from: Fixture.time(.asr))
      components.nanosecond = nil
      let triggers: [UNNotificationTrigger] = [
        UNCalendarNotificationTrigger(dateMatching: components, repeats: true),
        UNTimeIntervalNotificationTrigger(timeInterval: 3_600, repeats: false),
      ]
      for trigger in triggers {
        let content = UNMutableNotificationContent()
        content.title = "asr"
        let center = ModelCenter(
          clock: clock,
          pending: [
            UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
          ])
        _ = try await scheduler(center, clock: clock).apply(
          plan([asrAlert()], at: clock.now),
          content: { _ in
            let content = UNMutableNotificationContent()
            content.title = "asr"
            return content
          })
        #expect(center.calls.contains { $0["add"] != nil }, "\(trigger)")
      }
    }

    @Test func aThreadIsSetOnlyWhenTheSchedulerHasOne() async throws {
      let clock = TestClock(Fixture.date(6, 0))
      let content: @Sendable (PlannedAlert) -> UNMutableNotificationContent = { _ in
        let content = UNMutableNotificationContent()
        content.threadIdentifier = "from-the-app"
        return content
      }
      let plain = ModelCenter(clock: clock)
      _ = try await scheduler(plain, clock: clock).apply(
        plan([asrAlert()], at: clock.now), content: content)
      #expect(plain.pending[Self.identifier]?.content.threadIdentifier == "from-the-app")

      let threaded = ModelCenter(clock: clock)
      _ = try await scheduler(threaded, clock: clock, thread: "prayers").apply(
        plan([asrAlert()], at: clock.now), content: content)
      #expect(threaded.pending[Self.identifier]?.content.threadIdentifier == "prayers")
    }

    /// Triggers round up to a whole second, so they never fire early; a thousandth of a second
    /// of arithmetic noise doesn't add a second.
    @Test func triggersRoundUpToAWholeSecond() async throws {
      let cases: [(Double, Double)] = [(0, 0), (0.25, 1), (0.999, 1), (0.000_5, 0)]
      for (fraction, expected) in cases {
        let clock = TestClock(Fixture.date(6, 0))
        let center = ModelCenter(clock: clock)
        let fireDate = Fixture.time(.asr).addingTimeInterval(fraction)
        _ = try await scheduler(center, clock: clock).apply(
          plan([asrAlert(at: fireDate)], at: clock.now), content: { _ in .init() })
        let request = try #require(center.pending[Self.identifier])
        #expect(
          ModelCenter.fireDate(of: request) == Fixture.time(.asr).addingTimeInterval(expected),
          "fraction \(fraction)")
      }
    }

    /// Five plans arrive while the first batch is held: the first stops after its call in
    /// flight, the three in between make no call, and the center ends as the fifth plan says.
    @Test func theLatestOfManyOverlappingPlansWins() async throws {
      let clock = TestClock(Fixture.date(6, 0))
      let center = ModelCenter(clock: clock)
      let scheduler = scheduler(center, clock: clock)
      let plans = (0..<5).map { index in
        plan(
          [asrAlert(at: Fixture.time(.asr).addingTimeInterval(Double(index) * 60))], at: clock.now)
      }
      center.beginStep(readBackAt: nil, suspendAtCall: 1)
      let first = Task { try await scheduler.apply(plans[0], content: { _ in .init() }) }
      try await wait { center.isSuspended }
      var later: [Task<NotificationApplyReport, any Error>] = []
      for (offset, plan) in plans.dropFirst().enumerated() {
        later.append(Task { try await scheduler.apply(plan, content: { _ in .init() }) })
        try await wait { await scheduler.submittedApplies == offset + 2 }
      }
      center.release()
      var reports = [try await first.value]
      for task in later { reports.append(try await task.value) }

      #expect(reports.map(\.superseded) == [true, true, true, true, false])
      #expect(
        reports.last?.confirmed
          == [AlertOccurrenceID(notification: Self.asr, fireDate: Fixture.time(.asr) + 240)])
      #expect(center.pending.count == 1)
      #expect(
        center.pending[Self.identifier].flatMap(ModelCenter.fireDate) == Fixture.time(.asr) + 240)
      // Only the first and the last plan called the center: the first stopped after the
      // authorization read it was suspended in.
      #expect(center.calls.filter { $0 == "authorizationStatus" }.count == 2)
    }

    /// `deliver` waits for an apply in progress and doesn't supersede it.
    @Test func deliverWaitsForAnApplyAndDoesNotSupersedeIt() async throws {
      let clock = TestClock(Fixture.time(.isha).addingTimeInterval(-3_600))
      let center = ModelCenter(clock: clock)
      let scheduler = scheduler(center, clock: clock)
      let isha = PlannedAlert(
        id: Fixture.identity(.isha, .atTime),
        event: PrayerEvent(scheduleDay: Fixture.day, kind: .isha, time: Fixture.time(.isha)),
        fireDate: Fixture.time(.isha), sound: .system)
      center.beginStep(readBackAt: nil, suspendAtCall: 1)
      let apply = Task {
        try await scheduler.apply(plan([isha], at: clock.now), content: { _ in .init() })
      }
      try await wait { center.isSuspended }
      let reminder = PlannedAlert(
        id: Fixture.identity(.isha, .before),
        event: PrayerEvent(scheduleDay: Fixture.day, kind: .isha, time: Fixture.time(.isha)),
        fireDate: clock.now, sound: .system)
      let deliver = Task { try await scheduler.deliver([reminder], content: { _ in .init() }) }
      try await Task.sleep(for: .milliseconds(50))
      center.release()
      let applied = try await apply.value
      let delivered = try await deliver.value
      #expect(!applied.superseded)
      #expect(applied.confirmed == [isha.occurrenceID])
      #expect(delivered.posted == [reminder.occurrenceID])
      // The whole apply batch, read-back included, runs before the deliver's first call.
      let names = center.calls.map { $0.string ?? $0.object?.keys.first ?? "" }
      #expect(
        names == [
          "authorizationStatus", "pendingRequests", "deliveredNotifications", "add",
          "pendingRequests", "authorizationStatus", "pendingRequests", "deliveredNotifications",
          "addImmediate",
        ])
    }

    @Test func deliverValidatesTheAlerts() async throws {
      let clock = TestClock(Fixture.date(6, 0))
      let center = ModelCenter(clock: clock)
      let foreign = PlannedAlert(
        id: Fixture.identity(.asr, .atTime, namespace: "mosque"),
        event: PrayerEvent(scheduleDay: Fixture.day, kind: .asr, time: Fixture.time(.asr)),
        fireDate: Fixture.time(.asr), sound: .system)
      await #expect(
        throws: NotificationSchedulerError.namespaceMismatch(expected: "prayers", found: "mosque")
      ) {
        try await scheduler(center, clock: clock).deliver([foreign], content: { _ in .init() })
      }
      await #expect(throws: NotificationSchedulerError.duplicateIdentity(Self.asr)) {
        try await scheduler(center, clock: clock).deliver(
          [asrAlert(), asrAlert(at: Fixture.time(.asr) + 60)], content: { _ in .init() })
      }
      #expect(center.calls.isEmpty)
    }

    @Test func soundsMapToNotificationSounds() {
      #expect(AlertSound.none.notificationSound == nil)
      #expect(AlertSound.system.notificationSound == .default)
      #expect(
        AlertSound.named("tone.caf").notificationSound
          == UNNotificationSound(named: UNNotificationSoundName("tone.caf")))
    }

    /// The system center is a center the scheduler can use. (Type-level only: a test process
    /// has no app bundle, so `UNUserNotificationCenter.current()` isn't called here.)
    @Test func theSystemCenterConforms() {
      func accepts<Center: AlertNotificationCenter>(_: Center.Type) {}
      accepts(UNUserNotificationCenter.self)
    }

    func wait(_ condition: @Sendable () async -> Bool) async throws {
      for _ in 0..<2_000 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(5))
      }
      Issue.record("timed out")
    }
  }
#endif
