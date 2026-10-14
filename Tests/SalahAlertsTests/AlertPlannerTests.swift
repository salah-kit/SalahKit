import Foundation
import SalahAlerts
import SalahCore
import Testing

/// Settings, identities and the planner beyond what the vectors pin (RFC 0003 §4.1–§4.4).
@Suite struct AlertPlannerTests {
  // MARK: Settings JSON

  @Test func settingsEncodeOffsetsAsSeconds() throws {
    let settings = AlertSettings(
      before: .seconds(600), after: .milliseconds(90_500), sound: .named("adhan.caf"),
      beforeSound: .none, afterSound: .system)
    let data = try JSONEncoder().encode(settings)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["atTime"] as? Bool == true)
    #expect(object["before"] as? Double == 600)
    #expect(object["after"] as? Double == 90.5)
    #expect(object["sound"] as? [String: String] == ["named": "adhan.caf"])
    #expect(object["beforeSound"] as? String == "none")
    #expect(object["afterSound"] as? String == "system")
    #expect(try JSONDecoder().decode(AlertSettings.self, from: data) == settings)
  }

  @Test func settingsDecodeWithDefaults() throws {
    let empty = try JSONDecoder().decode(AlertSettings.self, from: Data("{}".utf8))
    #expect(empty == AlertSettings())
    #expect(empty.atTime)
    #expect(empty.before == nil && empty.after == nil)
    #expect(empty.sound == .system && empty.beforeSound == .system && empty.afterSound == .system)
    let reminder = try JSONDecoder().decode(
      AlertSettings.self, from: Data(#"{"atTime": false, "before": 300, "after": null}"#.utf8))
    #expect(reminder == AlertSettings(atTime: false, before: .seconds(300)))
  }

  @Test func settingsClampHugeOffsetsInsteadOfTrapping() throws {
    let settings = try JSONDecoder().decode(
      AlertSettings.self, from: Data(#"{"before": 1e300}"#.utf8))
    let before = try #require(settings.before)
    #expect(before > .seconds(1e13))
  }

  @Test func soundsDecodeTheirThreeShapes() throws {
    let sounds = try JSONDecoder().decode(
      [AlertSound].self, from: Data(#"["none", "system", {"named": "a.caf"}]"#.utf8))
    #expect(sounds == [.none, .system, .named("a.caf")])
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(AlertSound.self, from: Data(#""loud""#.utf8))
    }
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(AlertSound.self, from: Data(#"{"file": "a.caf"}"#.utf8))
    }
  }

  // MARK: Identities

  let identity = NotificationIdentity(
    namespace: "prayers", scheduleDay: CivilDay(year: 2026, month: 6, day: 2), prayer: .dhuhr,
    kind: .before)

  @Test func requestIdentifiersAreTheIdentity() {
    #expect(
      identity.requestIdentifier(prefix: "salah.") == "salah.prayers/2026-06-02/dhuhr/before")
    #expect(
      NotificationIdentity(
        requestIdentifier: "salah.prayers/2026-06-02/dhuhr/before", prefix: "salah.") == identity)
    #expect(
      NotificationIdentity(requestIdentifier: "prayers/2026-06-02/dhuhr/before", prefix: "")
        == identity)
    // A namespace that starts with a combining mark joins the prefix's last character, and
    // still parses back.
    let combining = NotificationIdentity(
      namespace: "\u{301}x", scheduleDay: CivilDay(year: 2026, month: 6, day: 2), prayer: .dhuhr,
      kind: .before)
    #expect(NotificationIdentity.isValidNamespace(combining.namespace))
    #expect(
      NotificationIdentity(
        requestIdentifier: combining.requestIdentifier(prefix: "salah."), prefix: "salah.")
        == combining)
    // One that ends with a prepended scalar joins the following "/", and parses back too; a
    // "/" hidden in such a character still makes a namespace invalid.
    let prepended = NotificationIdentity(
      namespace: "x\u{600}", scheduleDay: CivilDay(year: 2026, month: 6, day: 2), prayer: .dhuhr,
      kind: .before)
    #expect(
      NotificationIdentity(
        requestIdentifier: prepended.requestIdentifier(prefix: "salah."), prefix: "salah.")
        == prepended)
    #expect(!NotificationIdentity.isValidNamespace("x\u{600}/y"))
  }

  @Test(arguments: [
    "other.prayers/2026-06-02/dhuhr/before",  // another prefix
    "salah.prayers/2026-06-02/dhuhr",  // three parts
    "salah.prayers/2026-06-02/dhuhr/before/x",  // five parts
    "salah./2026-06-02/dhuhr/before",  // no namespace
    "salah.prayers/2026-6-2/dhuhr/before",  // not a day
    "salah.prayers/2026-02-30/dhuhr/before",  // not a real day
    "salah.prayers/2026-06-02/zuhr/before",  // not a prayer
    "salah.prayers/2026-06-02/dhuhr/early",  // not an alert kind
    "salah.prayers",
    "",
  ])
  func otherIdentifiersAreNotIdentities(_ text: String) {
    #expect(NotificationIdentity(requestIdentifier: text, prefix: "salah.") == nil)
  }

  @Test func namespaces() {
    #expect(NotificationIdentity.isValidNamespace("prayers"))
    #expect(NotificationIdentity.isValidNamespace("mosque.edinburgh"))
    #expect(!NotificationIdentity.isValidNamespace(""))
    #expect(!NotificationIdentity.isValidNamespace("a/b"))
  }

  @Test func identitiesOrderByNamespaceDayPrayerAndKind() {
    let day = CivilDay(year: 2026, month: 6, day: 2)
    let ordered = [
      NotificationIdentity(
        namespace: "a", scheduleDay: day.adding(days: 1), prayer: .fajr, kind: .after),
      NotificationIdentity(namespace: "b", scheduleDay: day, prayer: .fajr, kind: .atTime),
      NotificationIdentity(namespace: "b", scheduleDay: day, prayer: .fajr, kind: .before),
      NotificationIdentity(namespace: "b", scheduleDay: day, prayer: .fajr, kind: .after),
      NotificationIdentity(namespace: "b", scheduleDay: day, prayer: .isha, kind: .atTime),
      NotificationIdentity(
        namespace: "b", scheduleDay: day.adding(days: 1), prayer: .fajr, kind: .atTime),
    ]
    #expect(ordered.shuffled().sorted() == ordered)
    #expect(AlertKind.allCases.sorted() == [.atTime, .before, .after])
  }

  @Test func identitiesAndOccurrencesAreCodable() throws {
    let occurrence = AlertOccurrenceID(notification: identity, fireDate: Fixture.date(12, 9))
    let data = try JSONEncoder().encode(occurrence)
    #expect(try JSONDecoder().decode(AlertOccurrenceID.self, from: data) == occurrence)
    let text = String(decoding: try JSONEncoder().encode(identity), as: UTF8.self)
    #expect(text.contains(#""scheduleDay":"2026-06-02""#))
    #expect(text.contains(#""kind":"before""#))
  }

  @Test func aPlannedAlertKnowsItsOccurrence() {
    let alert = PlannedAlert(
      id: identity,
      event: PrayerEvent(scheduleDay: Fixture.day, kind: .dhuhr, time: Fixture.time(.dhuhr)),
      fireDate: Fixture.date(12, 9), sound: .system)
    #expect(alert.kind == .before)
    #expect(
      alert.occurrenceID == AlertOccurrenceID(notification: identity, fireDate: Fixture.date(12, 9))
    )
  }

  // MARK: Planning

  /// One query covers at most 400 civil days (RFC 0001 §4.10): a longer range ends earlier,
  /// and the requested range says where.
  @Test func longRangesEndAtTheQueryLimit() throws {
    let start = Fixture.date(0, 0, dayOffset: -2)
    let long = PrayerSchedule(
      source: TimetableSource(rows: [], expectedKinds: Set(PrayerKind.allCases)),
      location: Fixture.location)
    let schedule = try AlertPlanner().schedule(
      long, namespace: "prayers", from: start, to: start.addingTimeInterval(500 * 86_400),
      settings: Fixture.settings(AlertSettings(before: .seconds(3_600))))
    let queryStart = start.addingTimeInterval(-7_200)
    let limit = CivilDay(containing: queryStart, in: Fixture.zone).adding(days: 400)
      .start(in: Fixture.zone)
    #expect(schedule.requestedRange.end == limit.addingTimeInterval(-7_200))
    #expect(schedule.alerts.isEmpty)
    #expect(schedule.gaps.allSatisfy { $0.interval.end <= schedule.requestedRange.end })
  }

  /// A plan from a schedule made by hand: an app can use the planner's second step alone.
  @Test func aHandMadeScheduleCanBePlanned() {
    let alert = PlannedAlert(
      id: identity,
      event: PrayerEvent(scheduleDay: Fixture.day, kind: .dhuhr, time: Fixture.time(.dhuhr)),
      fireDate: Fixture.date(12, 9), sound: .system)
    let gap = AlertGap(
      interval: DateInterval(start: Fixture.date(15, 0), end: Fixture.date(16, 0)), kind: .atTime,
      day: Fixture.day, prayers: [.asr], reason: .noPublishedData)
    let schedule = AlertSchedule(
      namespace: "prayers", alerts: [alert],
      requestedRange: DateInterval(start: Fixture.date(6, 0), end: Fixture.date(23, 0)), gaps: [gap]
    )
    let plan = AlertPlanner().notificationPlan(schedule, from: Fixture.date(6, 0))
    #expect(plan.alerts == [alert])
    #expect(plan.coverageByKind == [.before: Fixture.date(23, 0), .atTime: Fixture.date(15, 0)])
    #expect(plan.coveredUntil == Fixture.date(15, 0))
    #expect(
      plan.effectiveRange == DateInterval(start: Fixture.date(6, 0), end: Fixture.date(23, 0)))
  }

  @Test func budgetDefaults() {
    let budget = AlertBudget()
    #expect(budget.maxPending == 60)
    #expect(budget.nearTermWindow == .seconds(2 * 86_400))
    #expect(budget.horizon == .seconds(14 * 86_400))
    #expect(AlertPlanner.reminderOffsetLimit == .seconds(7 * 86_400))
  }

  /// The settings closure is asked about known events and about the prayers a gap hides,
  /// with both observances for a Friday's Dhuhr (RFC 0003 §4.3).
  @Test func settingsAreAskedForEventsAndGaps() throws {
    let friday = CivilDay(year: 2026, month: 6, day: 5)
    let source = Fixture.source(dropping: [friday: [.dhuhr]])
    let asked = SubjectLog()
    _ = try AlertPlanner().schedule(
      PrayerSchedule(source: source, location: Fixture.location), namespace: "prayers",
      from: Fixture.date(10, 0, dayOffset: 3), to: Fixture.date(14, 0, dayOffset: 3),
      settings: { subject in
        asked.subjects.append(subject)
        return AlertSettings()
      })
    let dhuhr = asked.subjects.filter { $0.prayer == .dhuhr && $0.scheduleDay == friday }
    #expect(dhuhr.map(\.observance) == [.ordinary, .jumuah])
    // Asr (15:35) is a known event inside the query (08:00 to 16:00); sunrise (05:38) isn't.
    #expect(asked.subjects.contains { $0.prayer == .asr && $0.scheduleDay == friday })
    #expect(!asked.subjects.contains { $0.prayer == .sunrise && $0.scheduleDay == friday })
  }

  final class SubjectLog: @unchecked Sendable {
    // @unchecked: used from one test, synchronously.
    var subjects: [AlertSubject] = []
  }
}
