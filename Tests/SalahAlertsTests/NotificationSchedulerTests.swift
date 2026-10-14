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
      let content: @Sendable (PlannedAlert) -> UNMutableNotificationContent = { alert in
        let content = UNMutableNotificationContent()
        content.title = alert.id.prayer.rawValue
        content.body = "It's time"
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

      // `deliver` posts the closure's content under the identifier, with the thread, as
      // `apply` adds it.
      let posting = ModelCenter(clock: clock)
      _ = try await scheduler(posting, clock: clock).deliver([asrAlert()], content: content)
      #expect(posting.posted.map(\.identifier) == [Self.identifier])
      #expect(posting.posted.first?.trigger == nil)
      #expect(posting.posted.first?.content.title == "asr")
      #expect(posting.posted.first?.content.body == "It's time")
      #expect(posting.posted.first?.content.threadIdentifier == "from-the-app")
      let threadedPosting = ModelCenter(clock: clock)
      _ = try await scheduler(threadedPosting, clock: clock, thread: "prayers").deliver(
        [asrAlert()], content: content)
      #expect(threadedPosting.posted.map(\.identifier) == [Self.identifier])
      #expect(threadedPosting.posted.first?.content.threadIdentifier == "prayers")
    }

    /// A pending trigger is read with its components' calendar in their time zone (Foundation
    /// keeps the calendar's zone equal to theirs). Without a calendar or a zone it names no
    /// instant and never matches, whatever zone its wall-clock time was written in (RFC 0003
    /// §4.5 Matching).
    @Test func aPendingTriggerIsReadWithItsOwnCalendarAndZone() async throws {
      let utc = try #require(TimeZone(identifier: "UTC"))
      let riyadh = try #require(TimeZone(identifier: "Asia/Riyadh"))
      let kiritimati = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
      #expect(
        try await addsOver(
          Self.components(wallClockIn: riyadh, calendarZone: riyadh, zone: riyadh)) == false)
      #expect(
        try await addsOver(Self.components(wallClockIn: utc, calendarZone: riyadh, zone: riyadh)))
      #expect(
        try await addsOver(Self.components(wallClockIn: utc, calendarZone: utc, zone: utc))
          == false)
      // A trigger written in another calendar is read in it: Asr's time as a Hijri date.
      var hijri = Calendar(identifier: .islamicUmmAlQura)
      hijri.timeZone = utc
      var written = hijri.dateComponents(
        [.era, .year, .month, .day, .hour, .minute, .second], from: Fixture.time(.asr))
      written.calendar = hijri
      written.timeZone = utc
      #expect(written.year == 1447)
      #expect(try await addsOver(written) == false)
      for wallClock in [utc, riyadh, kiritimati, TimeZone.current] {
        #expect(
          try await addsOver(
            Self.components(wallClockIn: wallClock, calendarZone: wallClock, zone: nil)))
        #expect(
          try await addsOver(
            Self.components(wallClockIn: wallClock, calendarZone: nil, zone: wallClock)))
        #expect(
          try await addsOver(Self.components(wallClockIn: wallClock, calendarZone: nil, zone: nil)))
      }
    }

    /// Asr's time as the wall-clock time of `zone`, with a Gregorian calendar in
    /// `calendarZone` and the time zone `zone`, each left out when `nil`.
    static func components(
      wallClockIn wallClock: TimeZone, calendarZone: TimeZone?, zone: TimeZone?
    ) -> DateComponents {
      var gregorian = Calendar(identifier: .gregorian)
      gregorian.timeZone = wallClock
      var components = gregorian.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: Fixture.time(.asr))
      components.calendar = calendarZone.map { calendarZone in
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = calendarZone
        return calendar
      }
      components.timeZone = zone
      return components
    }

    /// Whether `apply` adds Asr's request over a pending one with these trigger components and
    /// the same content.
    func addsOver(_ components: DateComponents) async throws -> Bool {
      let clock = TestClock(Fixture.date(6, 0))
      let pending = UNNotificationRequest(
        identifier: Self.identifier, content: Self.fullContent(),
        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
      let center = ModelCenter(clock: clock, pending: [pending])
      _ = try await scheduler(center, clock: clock).apply(
        plan([asrAlert()], at: clock.now), content: { _ in Self.fullContent() })
      return center.calls.contains { $0["add"] != nil }
    }

    /// Triggers round up to a whole second, so they never fire early; a thousandth of a second
    /// of arithmetic noise doesn't add a second (RFC 0003 §4.5 Requests).
    @Test func triggersRoundUpToAWholeSecond() async throws {
      let cases: [(Double, Double)] = [
        (0, 0), (0.25, 1), (0.999, 1), (0.000_5, 0), (0.000_9, 0), (0.001, 0), (0.001_000_3, 0),
        (0.001_000_7, 1), (0.001_001, 1),
        (0.001_1, 1), (0.001_5, 1), (-0.000_5, 0), (-0.25, 0),
      ]
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
      #expect(
        Self.names(center.calls) == [
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

    /// Validation names the first offender in the given order (RFC 0003 §4.5 Validation).
    @Test func validationErrorsNameTheFirstOffender() async throws {
      let clock = TestClock(Fixture.date(6, 0))
      let center = ModelCenter(clock: clock)
      let scheduler = scheduler(center, clock: clock)
      func alert(_ prayer: PrayerKind, namespace: String = "prayers") -> PlannedAlert {
        PlannedAlert(
          id: Fixture.identity(prayer, .atTime, namespace: namespace),
          event: PrayerEvent(scheduleDay: Fixture.day, kind: prayer, time: Fixture.time(prayer)),
          fireDate: Fixture.time(prayer), sound: .system)
      }
      let a = alert(.asr)
      let b = alert(.maghrib)
      await #expect(throws: NotificationSchedulerError.duplicateIdentity(b.id)) {
        try await scheduler.apply(plan([a, b, b, a], at: clock.now), content: { _ in .init() })
      }
      await #expect(
        throws: NotificationSchedulerError.namespaceMismatch(expected: "prayers", found: "one")
      ) {
        try await scheduler.apply(
          plan(
            [a, alert(.isha, namespace: "one"), alert(.fajr, namespace: "two"), a], at: clock.now),
          content: { _ in .init() })
      }
      var foreignPlan = plan([alert(.isha, namespace: "one")], at: clock.now)
      foreignPlan.namespace = "mosque"
      await #expect(
        throws: NotificationSchedulerError.namespaceMismatch(expected: "prayers", found: "mosque")
      ) {
        try await scheduler.apply(foreignPlan, content: { _ in .init() })
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

    /// A superseded batch reports the instant it stopped, and a queued batch's `t` is the clock
    /// when the pump reaches it, not when `apply` was called (RFC 0003 §4.5).
    @Test func queuedBatchesReadTheClockWhenThePumpReachesThem() async throws {
      let clock = TestClock(Fixture.date(6, 0))
      let center = ModelCenter(clock: clock)
      let scheduler = scheduler(center, clock: clock)
      func alert(_ prayer: PrayerKind, at fireDate: Date) -> PlannedAlert {
        PlannedAlert(
          id: Fixture.identity(prayer, .atTime),
          event: PrayerEvent(scheduleDay: Fixture.day, kind: prayer, time: fireDate),
          fireDate: fireDate, sound: .system)
      }
      let early = alert(.dhuhr, at: Fixture.date(6, 3))
      let later = alert(.asr, at: Fixture.date(6, 10))
      center.beginStep(readBackAt: nil, suspendAtCall: 1)
      let first = Task {
        try await scheduler.apply(plan([later], at: clock.now), content: { _ in .init() })
      }
      try await wait { center.isSuspended }
      let second = Task {
        try await scheduler.apply(plan([later], at: clock.now), content: { _ in .init() })
      }
      try await wait { await scheduler.submittedApplies == 2 }
      let third = Task {
        try await scheduler.apply(plan([early, later], at: clock.now), content: { _ in .init() })
      }
      try await wait { await scheduler.submittedApplies == 3 }
      clock.set(Fixture.date(6, 5))
      center.release()
      let reports = [try await first.value, try await second.value, try await third.value]

      #expect(reports.map(\.superseded) == [true, true, false])
      #expect(reports.map(\.verifiedAt) == Array(repeating: Fixture.date(6, 5), count: 3))
      // Dhuhr's 06:03 alert fired before the third batch started at 06:05: not desired, so
      // not added, confirmed or failed.
      #expect(reports[2].confirmed == [later.occurrenceID])
      #expect(reports[2].failures.isEmpty)
      #expect(
        center.calls.compactMap { $0["add"]?.string } == ["salah.prayers/2026-06-02/asr/atTime"])
    }

    /// `deliver` takes its turn in the pump in arrival order: after the batch in progress and
    /// before an `apply` that arrived after it, which still supersedes the first batch.
    @Test func deliverTakesItsTurnInArrivalOrder() async throws {
      let clock = TestClock(Fixture.time(.isha).addingTimeInterval(-3_600))
      let center = ModelCenter(clock: clock)
      let scheduler = scheduler(center, clock: clock)
      let isha = PlannedAlert(
        id: Fixture.identity(.isha, .atTime),
        event: PrayerEvent(scheduleDay: Fixture.day, kind: .isha, time: Fixture.time(.isha)),
        fireDate: Fixture.time(.isha), sound: .system)
      let reminder = PlannedAlert(
        id: Fixture.identity(.isha, .before),
        event: PrayerEvent(scheduleDay: Fixture.day, kind: .isha, time: Fixture.time(.isha)),
        fireDate: clock.now, sound: .system)
      center.beginStep(readBackAt: nil, suspendAtCall: 1)
      let first = Task {
        try await scheduler.apply(plan([isha], at: clock.now), content: { _ in .init() })
      }
      try await wait { center.isSuspended }
      let deliver = Task { try await scheduler.deliver([reminder], content: { _ in .init() }) }
      try await wait { await scheduler.waitingCalls == 1 }
      let second = Task {
        try await scheduler.apply(plan([isha], at: clock.now), content: { _ in .init() })
      }
      try await wait { await scheduler.waitingCalls == 2 }
      center.release()
      let reports = [try await first.value, try await second.value]
      let delivered = try await deliver.value

      #expect(reports.map(\.superseded) == [true, false])
      #expect(reports[1].confirmed == [isha.occurrenceID])
      #expect(delivered.posted == [reminder.occurrenceID])
      #expect(
        Self.names(center.calls) == [
          "authorizationStatus",
          "authorizationStatus", "pendingRequests", "deliveredNotifications", "addImmediate",
          "authorizationStatus", "pendingRequests", "deliveredNotifications", "add",
          "pendingRequests",
        ])
    }

    /// An `apply` that arrives while a `deliver` is held doesn't stop it.
    @Test func anApplyDoesNotSupersedeADeliver() async throws {
      let clock = TestClock(Fixture.time(.isha).addingTimeInterval(-3_600))
      let center = ModelCenter(clock: clock)
      let scheduler = scheduler(center, clock: clock)
      let isha = PlannedAlert(
        id: Fixture.identity(.isha, .atTime),
        event: PrayerEvent(scheduleDay: Fixture.day, kind: .isha, time: Fixture.time(.isha)),
        fireDate: Fixture.time(.isha), sound: .system)
      let reminder = PlannedAlert(
        id: Fixture.identity(.isha, .before),
        event: PrayerEvent(scheduleDay: Fixture.day, kind: .isha, time: Fixture.time(.isha)),
        fireDate: clock.now, sound: .system)
      center.beginStep(readBackAt: nil, suspendAtCall: 1)
      let deliver = Task { try await scheduler.deliver([reminder], content: { _ in .init() }) }
      try await wait { center.isSuspended }
      let apply = Task {
        try await scheduler.apply(plan([isha], at: clock.now), content: { _ in .init() })
      }
      try await wait { await scheduler.waitingCalls == 1 }
      center.release()
      let delivered = try await deliver.value
      let applied = try await apply.value

      #expect(delivered.posted == [reminder.occurrenceID])
      #expect(!applied.superseded)
      #expect(applied.confirmed == [isha.occurrenceID])
      #expect(
        Self.names(center.calls) == [
          "authorizationStatus", "pendingRequests", "deliveredNotifications", "addImmediate",
          "authorizationStatus", "pendingRequests", "deliveredNotifications", "add",
          "pendingRequests",
        ])
    }

    /// Attachments aren't compared: the system moves their files, so a pending request with
    /// one matches content without it, and the other way round (RFC 0003 §4.5 Matching).
    @Test func attachmentsAreNotCompared() async throws {
      let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("SalahAlertsTests-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      // A one-pixel PNG.
      let png = try #require(
        Data(
          base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        ))
      let file = folder.appendingPathComponent("star.png")
      try png.write(to: file)
      #expect(Self.content(attachment: file).attachments.count == 1)

      let trigger = ModelCenter.request(
        Self.identifier, fireDate: Fixture.time(.asr), title: "", body: "", thread: ""
      ).trigger
      for (pendingFile, desiredFile) in [(file, nil), (nil, file)] as [(URL?, URL?)] {
        let clock = TestClock(Fixture.date(6, 0))
        let center = ModelCenter(
          clock: clock,
          pending: [
            UNNotificationRequest(
              identifier: Self.identifier, content: Self.content(attachment: pendingFile),
              trigger: trigger)
          ])
        let report = try await scheduler(center, clock: clock).apply(
          plan([asrAlert()], at: clock.now), content: { _ in Self.content(attachment: desiredFile) }
        )
        #expect(!center.calls.contains { $0["add"] != nil })
        #expect(report.confirmed.map(\.notification) == [Self.asr])
      }
    }

    /// The full content, with an attachment of `file` when there is one.
    nonisolated static func content(attachment file: URL?) -> UNMutableNotificationContent {
      let content = fullContent()
      if let file, let attachment = try? UNNotificationAttachment(identifier: "star", url: file) {
        content.attachments = [attachment]
      }
      return content
    }

    /// A negative delivered-notification retention counts as zero: only notifications dated
    /// before the batch's start are removed.
    @Test func aNegativeRetentionCountsAsZero() async throws {
      let clock = TestClock(Fixture.date(6, 0))
      let past = "salah.prayers/2026-06-01/isha/atTime"
      let ahead = "salah.prayers/2026-06-02/fajr/atTime"
      let center = ModelCenter(
        clock: clock,
        delivered: [
          DeliveredNotificationRecord(identifier: past, date: Fixture.date(5, 59)),
          DeliveredNotificationRecord(identifier: ahead, date: Fixture.date(6, 0) + 30),
        ])
      let scheduler = NotificationScheduler(
        identifierPrefix: "salah.", namespace: "prayers", center: center,
        deliveredRetention: .seconds(-60), now: { clock.now })
      _ = try await scheduler.apply(plan([], at: clock.now), content: { _ in .init() })
      #expect(center.delivered.map(\.identifier) == [ahead])
    }

    /// The calls' names, adds and removals by their kind.
    static func names(_ calls: [JSON]) -> [String] {
      calls.map { call in
        call.string
          ?? ["add", "addImmediate", "removePending", "removeDelivered"].first { call[$0] != nil }
          ?? "?"
      }
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
