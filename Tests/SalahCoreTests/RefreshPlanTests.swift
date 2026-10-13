import Foundation
import Testing

@testable import SalahCore

/// Refresh plans beyond the vectors: the `steps` grid against a direct reading of RFC 0001
/// §4.8, strategies at the edges of the contract, and horizons at the query limit.
@Suite struct RefreshPlanTests {
  nonisolated static let schedule = ScheduleTests.schedule
  nonisolated static let zone = ScheduleTests.singapore
  nonisolated static let firstDay = ScheduleTests.firstDay

  /// An instant on `firstDay + day` at the given local time in Singapore.
  nonisolated static func local(day: Int, _ hour: Int, _ minute: Int) -> Date {
    firstDay.adding(days: day).start(in: zone)
      .addingTimeInterval(TimeInterval(hour * 3_600 + minute * 60))
  }

  nonisolated struct StepCase: Sendable, CustomTestStringConvertible {
    var name: String
    var start: Date
    var days: Double
    var fine: Int
    var coarse: Int
    var window: Int
    var limit: Int

    var testDescription: String { name }
  }

  nonisolated static let stepCases: [StepCase] = [
    StepCase(
      name: "no budget", start: local(day: 0, 9, 0), days: 2, fine: 60, coarse: 900, window: 600,
      limit: .max),
    StepCase(
      name: "start inside Dhuhr's window", start: local(day: 0, 12, 58), days: 1, fine: 300,
      coarse: 1_800, window: 900, limit: 40),
    StepCase(
      name: "overlapping windows", start: local(day: 0, 0, 10), days: 3, fine: 420, coarse: 3_600,
      window: 3 * 3_600, limit: 500),
    StepCase(
      name: "zero window", start: local(day: 1, 4, 0), days: 2, fine: 60, coarse: 2_700,
      window: 0, limit: .max),
    StepCase(
      name: "window wider than the gaps between prayers", start: local(day: 0, 9, 0), days: 2,
      fine: 3_600, coarse: 60, window: 2 * 86_400, limit: .max),
    StepCase(
      name: "one-second coarse steps inside long windows", start: local(day: 0, 9, 0), days: 2,
      fine: 3_600, coarse: 1, window: 6 * 3_600, limit: 96),
  ]

  /// The plan's dates exactly as §4.8 defines them, before the budget: `s`, the transitions,
  /// every fine date of every prayer in `[s − window, e + window]`, and the coarse dates outside
  /// the windows, all in `(s, e)`, sorted.
  static func definedDates(_ test: StepCase) throws -> [Date] {
    let end = test.start.addingTimeInterval(test.days * 86_400)
    let fine = TimeInterval(test.fine)
    let window = TimeInterval(test.window)
    let transitions = try schedule.refreshPlan(from: test.start, through: end, limit: .max).dates
    let prayers = schedule.events(
      from: test.start.addingTimeInterval(-window), through: end.addingTimeInterval(window)
    ).events.filter(\.kind.isPrayer).map(\.time)

    var dates = Set(transitions)
    let reach = test.window / test.fine
    for prayer in prayers {
      for step in -reach...reach {
        let date = prayer.addingTimeInterval(TimeInterval(step) * fine)
        if date > test.start, date < end { dates.insert(date) }
      }
    }
    for step in 1... {
      let date = test.start.addingTimeInterval(TimeInterval(step * test.coarse))
      guard date < end else { break }
      if !prayers.contains(where: { abs(date.timeIntervalSince($0)) <= window }) {
        dates.insert(date)
      }
    }
    return dates.sorted()
  }

  @Test(arguments: stepCases)
  func stepsMatchTheDefinition(_ test: StepCase) throws {
    let end = test.start.addingTimeInterval(test.days * 86_400)
    let plan = try Self.schedule.refreshPlan(
      from: test.start, through: end,
      strategy: .steps(
        fine: .seconds(test.fine), coarse: .seconds(test.coarse), window: .seconds(test.window)),
      limit: test.limit)
    let defined = try Self.definedDates(test)
    let fits = defined.count + 1 <= test.limit
    #expect(plan.dates == (fits ? defined : Array(defined.prefix(test.limit - 1))))
    #expect(plan.isTruncated == !fits)
    #expect(plan.validUntil == (fits ? end : defined[test.limit - 1]))
  }

  @Test func stepsShorterThanASecondAreInvalid() {
    let start = Self.local(day: 0, 12, 54)
    for strategy in [
      RefreshStrategy.steps(fine: .milliseconds(999), coarse: .seconds(60), window: .seconds(900)),
      .steps(fine: .seconds(60), coarse: .nanoseconds(1), window: .seconds(900)),
      .steps(fine: .nanoseconds(1) / 1_000_000_000, coarse: .seconds(3_600), window: .seconds(900)),
    ] {
      #expect(throws: RefreshPlanError.invalidStrategy) {
        try Self.schedule.refreshPlan(
          from: start, through: start.addingTimeInterval(86_400), strategy: strategy)
      }
    }
  }

  @Test func aWindowCountsAsAtMostTheQueryLimit() throws {
    // Ten published days before the start: an endless window still reaches only the prayers
    // within the query limit, so it plans what the longest window plans.
    let start = Self.local(day: 10, 9, 0)
    let end = start.addingTimeInterval(3 * 86_400)
    let endless = try Self.schedule.refreshPlan(
      from: start, through: end,
      strategy: .steps(
        fine: .seconds(86_400), coarse: .seconds(3_600), window: .seconds(Int64.max)),
      limit: 100_000)
    let longest = try Self.schedule.refreshPlan(
      from: start, through: end,
      strategy: .steps(
        fine: .seconds(86_400), coarse: .seconds(3_600),
        window: .seconds(PrayerSchedule.maximumQueryDays * 86_400)),
      limit: 100_000)
    #expect(endless.dates == longest.dates)
    #expect(!endless.dates.isEmpty)
  }

  @Test func stepsReachTheLastDayOfALongHorizon() throws {
    // Published only for the last days of a 400-day horizon that starts at 00:10, so the
    // window before the start falls on the previous civil day.
    let source = ScheduleTests.yearly(count: 405)
    let lastRows = TimetableSource(
      rows: source.rows.filter { Self.firstDay.adding(days: 397) <= $0.day },
      expectedKinds: source.expectedKinds)
    let schedule = PrayerSchedule(source: lastRows, location: Self.schedule.location)
    let start = Self.local(day: 0, 0, 10)
    let plan = try schedule.refreshPlan(
      from: start, through: start.addingTimeInterval(1_000 * 86_400),
      strategy: .steps(fine: .seconds(300), coarse: .seconds(30 * 86_400), window: .seconds(900)),
      limit: 100_000)
    let lastDay = PrayerSchedule.maximumQueryDays - 1
    #expect(plan.horizon.end == Self.firstDay.adding(days: lastDay + 1).start(in: Self.zone))
    #expect(!plan.isTruncated)
    for date in [
      Self.local(day: lastDay, 5, 35), Self.local(day: lastDay, 5, 45),
      Self.local(day: lastDay, 20, 14), Self.local(day: lastDay, 20, 24),
    ] {
      #expect(plan.dates.contains(date), "\(InstantText.format(date))")
    }
  }
}
