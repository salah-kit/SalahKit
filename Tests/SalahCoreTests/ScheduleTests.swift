import Foundation
import Testing

@testable import SalahCore

/// Schedule behavior outside the vectors' reach: day starts, coding, query limits on refresh
/// plans and the cost of large queries.
@Suite struct ScheduleTests {
  static let singapore = TimeZone(identifier: "Asia/Singapore") ?? .gmt
  static let london = TimeZone(identifier: "Europe/London") ?? .gmt
  static let firstDay = CivilDay(year: 2026, month: 1, day: 1)

  /// A timetable with the same six times every day for `count` days from 2026-01-01.
  static func yearly(count: Int) -> TimetableSource {
    let times: [PrayerKind: TimetableTime] = [
      .fajr: .local(WallClockTime(hour: 5, minute: 40)),
      .sunrise: .local(WallClockTime(hour: 7, minute: 2)),
      .dhuhr: .local(WallClockTime(hour: 13, minute: 4)),
      .asr: .local(WallClockTime(hour: 16, minute: 25)),
      .maghrib: .local(WallClockTime(hour: 19, minute: 5)),
      .isha: .local(WallClockTime(hour: 20, minute: 19)),
    ]
    return TimetableSource(
      rows: (0..<count).map { TimetableSource.Row(day: firstDay.adding(days: $0), times: times) },
      expectedKinds: Set(PrayerKind.allCases))
  }

  static let schedule = PrayerSchedule(
    source: yearly(count: 420),
    location: PrayerLocation(latitude: 1.35, longitude: 103.82, timeZone: singapore))

  // MARK: Civil days

  @Test func dayIntervalsFollowClockChanges() {
    let normal = CivilDay(year: 2026, month: 6, day: 21).interval(in: Self.london)
    let spring = CivilDay(year: 2026, month: 3, day: 29).interval(in: Self.london)
    let autumn = CivilDay(year: 2026, month: 10, day: 25).interval(in: Self.london)
    #expect(normal.duration == 24 * 3_600)
    #expect(spring.duration == 23 * 3_600)
    #expect(autumn.duration == 25 * 3_600)
    // 2026-06-21 00:00 at UTC+1 is 2026-06-20 23:00 UTC.
    #expect(normal.start == Date(timeIntervalSince1970: 1_781_996_400))
  }

  @Test func aSkippedDateHasAnEmptyInterval() throws {
    let apia = try #require(TimeZone(identifier: "Pacific/Apia"))
    let skipped = CivilDay(year: 2011, month: 12, day: 30)
    let interval = skipped.interval(in: apia)
    #expect(interval.duration == 0)
    #expect(interval.start == skipped.adding(days: 1).start(in: apia))
    // 2011-12-31 00:00 at UTC+14 is 2011-12-30 10:00 UTC.
    #expect(interval.start == Date(timeIntervalSince1970: 1_325_239_200))
  }

  @Test func dayStartIsLocalMidnight() {
    let day = CivilDay(year: 2026, month: 10, day: 16)
    // 2026-10-16 00:00 at UTC+8 is 2026-10-15 16:00 UTC.
    #expect(day.start(in: Self.singapore) == Date(timeIntervalSince1970: 1_792_080_000))
    #expect(CivilDay(containing: day.start(in: Self.singapore), in: Self.singapore) == day)
    #expect(
      CivilDay(containing: day.start(in: Self.singapore).addingTimeInterval(-1), in: Self.singapore)
        == day.adding(days: -1))
  }

  // MARK: Coding

  @Test func timetablesRoundTripThroughJSON() throws {
    let row = TimetableSource.Row(
      day: CivilDay(year: 2026, month: 10, day: 16),
      times: [
        .fajr: .local(WallClockTime(hour: 5, minute: 31)),
        .dhuhr: .instant(Date(timeIntervalSince1970: 1_792_126_320)),
        .isha: .local(WallClockTime(hour: 0, minute: 15, dayOffset: 1)),
      ],
      iqama: [.fajr: .local(WallClockTime(hour: 6, minute: 0))],
      observances: [.dhuhr: .jumuah])
    let source = TimetableSource(
      rows: [row, TimetableSource.Row(day: row.day.adding(days: -1), times: row.times)],
      expectedKinds: [.isha, .fajr, .dhuhr],
      wallTimeResolution: WallTimeResolution(repeated: .later, nonexistent: .nextValid))
    let data = try JSONEncoder().encode(source)
    #expect(try JSONDecoder().decode(TimetableSource.self, from: data) == source)

    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains(#""expectedKinds":["fajr","dhuhr","isha"]"#))
    #expect(json.contains(#""isha":"00:15+1""#))
    #expect(json.contains(#""dhuhr":"2026-10-16T04:52:00Z""#))
    #expect(source.firstDay == CivilDay(year: 2026, month: 10, day: 15))
    #expect(source.lastDay == CivilDay(year: 2026, month: 10, day: 16))
  }

  @Test func optionalTimetableFieldsTakeTheirDefaults() throws {
    let json = #"""
      {"expectedKinds": ["fajr"], "rows": [{"day": "2026-10-16", "times": {"fajr": "5:31"}}]}
      """#
    let source = try JSONDecoder().decode(TimetableSource.self, from: Data(json.utf8))
    #expect(source.wallTimeResolution == WallTimeResolution())
    #expect(source.rows.first?.iqama == [:])
    #expect(source.rows.first?.observances == [:])
    #expect(source.rows.first?.times[.fajr] == .local(WallClockTime(hour: 5, minute: 31)))
    let encoded = try #require(String(data: try JSONEncoder().encode(source), encoding: .utf8))
    #expect(!encoded.contains("iqama"))
    #expect(!encoded.contains("observances"))
  }

  @Test func malformedValuesFailDecoding() {
    for json in [
      #"{"expectedKinds": ["fajr"], "rows": [{"day": "16-10-2026", "times": {}}]}"#,
      #"{"expectedKinds": ["noon"], "rows": []}"#,
      #"{"expectedKinds": ["fajr"], "rows": [{"day": "2026-10-16", "times": {"fajr": "5h31"}}]}"#,
    ] {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(TimetableSource.self, from: Data(json.utf8))
      }
    }
  }

  // MARK: Query limits and cost

  @Test func refreshHorizonsAreClampedToTheQueryLimit() throws {
    let start = Self.firstDay.start(in: Self.singapore).addingTimeInterval(12 * 3_600)
    let plan = try Self.schedule.refreshPlan(
      from: start, through: start.addingTimeInterval(1_000 * 86_400), limit: 4)
    #expect(plan.horizon.start == start)
    #expect(
      plan.horizon.end
        == Self.firstDay.adding(days: PrayerSchedule.maximumQueryDays).start(in: Self.singapore))
    #expect(plan.entries.count == 3)
    #expect(plan.isTruncated)
    #expect(plan.validUntil < plan.horizon.end)
  }

  @Test func aYearOfEventsIsOneQuery() {
    let start = Self.firstDay.start(in: Self.singapore)
    let result = Self.schedule.events(from: start, through: .distantFuture)
    #expect(
      result.coverage.requested.end
        == Self.firstDay.adding(days: PrayerSchedule.maximumQueryDays).start(in: Self.singapore))
    #expect(result.events.count == 400 * 6)
    // Nothing is published for 2025-12-31, so its events could fall until 2026-01-01's Fajr.
    #expect(
      result.coverage.gaps.map(\.interval)
        == [DateInterval(start: start, end: start.addingTimeInterval((5 * 60 + 40) * 60))])
    #expect(result.coverage.gaps.map(\.day) == [Self.firstDay.adding(days: -1)])
  }

  @Test func fineStepsOverALongHorizonStayWithinTheBudget() throws {
    let start = Self.firstDay.start(in: Self.singapore).addingTimeInterval(9 * 3_600)
    let plan = try Self.schedule.refreshPlan(
      from: start, through: start.addingTimeInterval(300 * 86_400),
      strategy: .steps(fine: .seconds(1), coarse: .seconds(1), window: .seconds(86_400)),
      limit: 96)
    #expect(plan.entries.count == 95)
    #expect(plan.dates == (0..<95).map { start.addingTimeInterval(TimeInterval($0)) })
    #expect(plan.validUntil == start.addingTimeInterval(95))
  }

  @Test func stateAccessorsMatchTheCase() {
    let noon = Self.firstDay.start(in: Self.singapore).addingTimeInterval(12 * 3_600)
    let state = Self.schedule.state(at: noon, through: noon.addingTimeInterval(86_400))
    #expect(state.prayerState?.date == noon)
    #expect(state.changesAt == state.prayerState?.changesAt)
    #expect(
      state.coverage.requested == DateInterval(start: noon, end: noon.addingTimeInterval(86_400)))

    let empty = PrayerSchedule(
      source: TimetableSource(rows: [], expectedKinds: [.fajr]),
      location: PrayerLocation(latitude: 0, longitude: 0, timeZone: Self.singapore))
    let unavailable = empty.state(at: noon, through: noon.addingTimeInterval(3_600))
    #expect(unavailable.prayerState == nil)
    #expect(!unavailable.coverage.isComplete)
  }
}
