import Foundation
import SalahCore
import SalahFixtures
import Testing

@testable import SalahWidgets

#if canImport(WidgetKit)
  import WidgetKit
#endif

@Suite("PrayerTimelineBuilder")
struct PrayerTimelineBuilderTests {
  /// Makkah's schedule at the approaching moment, 2026-10-13 17:48 +03:00.
  let schedule = PrayerFixtures.makkah.schedule
  let now = PrayerFixtures.approaching.date

  @Test("the entries are the refresh plan's, then the expired entry at validUntil")
  func entriesFollowThePlan() throws {
    let builder = PrayerTimelineBuilder(schedule: schedule)
    let timeline = try builder.timeline(from: now, horizon: .seconds(24 * 3_600))
    let plan = try schedule.refreshPlan(from: now, through: now.addingTimeInterval(24 * 3_600))

    #expect(timeline.horizon == plan.horizon)
    #expect(timeline.validUntil == plan.validUntil)
    #expect(timeline.entries.dropLast().map(\.date) == plan.dates)
    #expect(timeline.entries.dropLast().map(\.state) == plan.entries.map { .schedule($0.state) })
    #expect(
      timeline.entries.last
        == .init(date: plan.validUntil, state: .expired(knownThrough: plan.validUntil)))
    #expect(timeline.entries.first?.date == now)
    #expect(timeline.isTruncated == false)
  }

  @Test("the default horizon is 48 hours and the reload is halfway")
  func defaultHorizonAndReload() throws {
    let timeline = try PrayerTimelineBuilder(schedule: schedule).timeline(from: now)
    #expect(PrayerTimelineBuilder.defaultHorizon == .seconds(172_800))
    #expect(timeline.horizon == DateInterval(start: now, duration: 172_800))
    #expect(timeline.validUntil == now.addingTimeInterval(172_800))
    #expect(timeline.reloadDate == now.addingTimeInterval(86_400))
  }

  @Test("the first state is the moment's state with the timeline's lookahead")
  func firstStateMatchesTheMoment() throws {
    let timeline = try PrayerTimelineBuilder(schedule: schedule).timeline(from: now)
    let state = try #require(timeline.entries.first?.state.prayerState)
    #expect(state.nextPrayer?.kind == .maghrib)
    #expect(state.isApproaching)
    #expect(state.latestPrayer?.kind == .asr)
  }

  @Test("a limit that can't hold every change ends the timeline at the first change left out")
  func truncatedTimeline() throws {
    let builder = PrayerTimelineBuilder(schedule: schedule, limit: 5)
    let timeline = try builder.timeline(from: now)
    let full = try schedule.refreshPlan(from: now, through: now.addingTimeInterval(172_800))

    #expect(timeline.entries.count == 5)
    #expect(timeline.isTruncated)
    #expect(timeline.validUntil == full.dates[4])
    #expect(timeline.entries.dropLast().map(\.date) == Array(full.dates.prefix(4)))
    #expect(timeline.entries.last?.state == .expired(knownThrough: full.dates[4]))
    #expect(timeline.horizon.end == now.addingTimeInterval(172_800))
    #expect(timeline.reloadDate == now.addingTimeInterval(full.dates[4].timeIntervalSince(now) / 2))
  }

  @Test("a steps strategy adds entries near prayers for static text")
  func stepsStrategy() throws {
    let builder = PrayerTimelineBuilder(
      schedule: schedule,
      strategy: .steps(fine: .seconds(60), coarse: .seconds(900), window: .seconds(1_800)))
    let timeline = try builder.timeline(from: now, horizon: .seconds(3_600))
    // From 17:48 to 18:48: every minute within 30 minutes of Maghrib at 17:58, then every
    // 15 minutes from the start outside that window.
    let dates = timeline.entries.dropLast().map { $0.date.timeIntervalSince(now) / 60 }
    #expect(dates.first == 0)
    #expect(dates.contains(1) && dates.contains(10) && dates.contains(40))
    #expect(dates.contains(41) == false)
    #expect(dates.contains(45))
    #expect(timeline.isTruncated == false)
  }

  @Test("a source with no data gives unavailable entries, then the expired entry")
  func emptySource() throws {
    let empty = PrayerSchedule(
      source: TimetableSource(rows: [], expectedKinds: Set(PrayerKind.allCases)),
      location: PrayerFixtures.makkah.location)
    let timeline = try PrayerTimelineBuilder(schedule: empty).timeline(from: now)
    #expect(timeline.entries.count >= 2)
    for entry in timeline.entries.dropLast() {
      guard case .schedule(.unavailable(let coverage, _)) = entry.state else {
        Issue.record("expected an unavailable state, got \(entry.state)")
        continue
      }
      #expect(coverage.gaps.allSatisfy { $0.reason == .noPublishedData })
    }
    #expect(timeline.entries.last?.state == .expired(knownThrough: timeline.validUntil))
  }

  @Test("invalid inputs throw the refresh plan's errors", arguments: [false, true])
  func invalidInputs(_ includeDayBoundaries: Bool) {
    #expect(throws: RefreshPlanError.nonPositiveHorizon) {
      try PrayerTimelineBuilder(schedule: schedule, includeDayBoundaries: includeDayBoundaries)
        .timeline(from: now, horizon: .zero)
    }
    #expect(throws: RefreshPlanError.limitTooSmall) {
      try PrayerTimelineBuilder(
        schedule: schedule, includeDayBoundaries: includeDayBoundaries, limit: 1
      ).timeline(from: now)
    }
    #expect(throws: RefreshPlanError.invalidStrategy) {
      try PrayerTimelineBuilder(
        schedule: schedule,
        strategy: .steps(fine: .milliseconds(500), coarse: .seconds(60), window: .seconds(60)),
        includeDayBoundaries: includeDayBoundaries
      ).timeline(from: now)
    }
  }

  @Test("prayerState reads through the schedule case only")
  func prayerStateAccessor() throws {
    let timeline = try PrayerTimelineBuilder(schedule: schedule).timeline(from: now)
    #expect(timeline.entries.first?.state.prayerState != nil)
    #expect(PrayerTimelineState.expired(knownThrough: now).prayerState == nil)
  }

  #if canImport(WidgetKit)
    /// A minimal WidgetKit entry.
    struct Entry: TimelineEntry {
      let date: Date
      let state: PrayerTimelineState
    }

    @Test("the WidgetKit timeline has the same entries and reloads after the reload date")
    func widgetKitTimeline() throws {
      let builder = PrayerTimelineBuilder(schedule: schedule, includeDayBoundaries: true)
      let expected = try builder.timeline(from: now)
      let timeline = builder.timeline(from: now) { Entry(date: $0, state: $1) }

      #expect(timeline.entries.map(\.date) == expected.entries.map(\.date))
      #expect(timeline.entries.map(\.state) == expected.entries.map(\.state))
      #expect(timeline.policy == .after(expected.reloadDate))
    }

    @Test("an invalid WidgetKit timeline is one expired entry that never reloads by itself")
    func widgetKitFallback() {
      let builder = PrayerTimelineBuilder(schedule: schedule, limit: 1)
      let timeline = builder.timeline(from: now) { Entry(date: $0, state: $1) }

      #expect(timeline.entries.map(\.date) == [now])
      #expect(timeline.entries.map(\.state) == [.expired(knownThrough: now)])
      #expect(timeline.policy == .never)
    }
  #endif
}

extension PrayerTimelineBuilderTests {
  @Test("day boundaries are opt-in and evaluate the exact midnight state with the given policy")
  func midnightState() throws {
    let zone = schedule.location.timeZone
    let day = CivilDay(containing: now, in: zone)
    let start = day.start(in: zone).addingTimeInterval(21 * 3_600 + 13 * 60)
    let midnight = day.adding(days: 1).start(in: zone)
    let policy = StatePolicy(
      approaching: .seconds(2 * 3_600), justStarted: .fixed(.seconds(6 * 3_600)))
    let ordinary = try PrayerTimelineBuilder(schedule: schedule, policy: policy)
      .timeline(from: start)
    let disabled = try PrayerTimelineBuilder(
      schedule: schedule, policy: policy, includeDayBoundaries: false
    ).timeline(from: start)
    #expect(ordinary == disabled)
    #expect(!ordinary.entries.contains { $0.date == midnight })

    let timeline = try PrayerTimelineBuilder(
      schedule: schedule, policy: policy, includeDayBoundaries: true
    ).timeline(from: start)
    let entry = try #require(timeline.entries.first { $0.date == midnight })
    let lookahead = CivilDay(containing: timeline.horizon.end, in: zone).adding(days: 2)
      .start(in: zone)
    #expect(
      entry.state == .schedule(schedule.state(at: midnight, through: lookahead, policy: policy)))
    #expect(entry.state.prayerState?.date == midnight)
    #expect(entry.state.prayerState?.justStarted?.kind == .isha)
    // Copying the preceding state would retain its date and coverage interval.
    #expect(entry.state != timeline.entries.last { $0.date < midnight }?.state)
  }

  @Test(
    "day boundaries honor 23-hour and 25-hour days in the schedule's zone",
    arguments: [
      (CivilDay(year: 2026, month: 3, day: 8), 23),
      (CivilDay(year: 2026, month: 11, day: 1), 25),
    ])
  func dstDayBoundaries(_ day: CivilDay, _ hours: Int) throws {
    let zone = try #require(TimeZone(identifier: "America/New_York"))
    let schedule = Self.dailySchedule(in: zone)
    let start = day.adding(days: -1).start(in: zone).addingTimeInterval(12 * 3_600 + 13 * 60)
    let timeline = try PrayerTimelineBuilder(schedule: schedule, includeDayBoundaries: true)
      .timeline(from: start, horizon: .seconds(3 * 86_400))
    let first = day.start(in: zone)
    let second = day.adding(days: 1).start(in: zone)
    #expect(second.timeIntervalSince(first) == TimeInterval(hours * 3_600))
    #expect(timeline.entries.contains { $0.date == first })
    #expect(timeline.entries.contains { $0.date == second })
    #expect(CivilDay(containing: first, in: zone) == day)
    #expect(timeline.entries.map(\.date) == Array(Set(timeline.entries.map(\.date))).sorted())
  }

  @Test(
    "repeated or skipped midnight and a skipped whole date produce one civil-day entry",
    arguments: [
      ("America/Havana", CivilDay(year: 2026, month: 3, day: 8)),
      ("America/Havana", CivilDay(year: 2026, month: 11, day: 1)),
      ("Pacific/Apia", CivilDay(year: 2011, month: 12, day: 30)),
    ])
  func unusualDayBoundaries(_ identifier: String, _ day: CivilDay) throws {
    let zone = try #require(TimeZone(identifier: identifier))
    let schedule = Self.dailySchedule(in: zone)
    let start = day.adding(days: -1).start(in: zone).addingTimeInterval(12 * 3_600 + 13 * 60)
    let timeline = try PrayerTimelineBuilder(schedule: schedule, includeDayBoundaries: true)
      .timeline(from: start, horizon: .seconds(3 * 86_400))
    let boundary = day.start(in: zone)
    let entry = try #require(timeline.entries.first { $0.date == boundary })
    #expect(timeline.entries.filter { $0.date == boundary }.count == 1)
    let lookahead = CivilDay(containing: timeline.horizon.end, in: zone).adding(days: 2)
      .start(in: zone)
    #expect(entry.state == .schedule(schedule.state(at: boundary, through: lookahead)))
    if identifier == "Pacific/Apia" {
      #expect(boundary == day.adding(days: 1).start(in: zone))
      #expect(CivilDay(containing: boundary, in: zone) == day.adding(days: 1))
    }
  }

  @Test(
    "the merged dates respect the budget and expire at the first omitted date",
    arguments: [
      RefreshStrategy.stateChanges,
      .steps(fine: .seconds(60), coarse: .seconds(17 * 60), window: .seconds(15 * 60)),
    ], [2, 3, 5, 96])
  func boundaryBudget(_ strategy: RefreshStrategy, _ limit: Int) throws {
    let zone = schedule.location.timeZone
    let day = CivilDay(containing: now, in: zone)
    let start = day.start(in: zone).addingTimeInterval(21 * 3_600 + 13 * 60)
    let complete = try PrayerTimelineBuilder(
      schedule: schedule, strategy: strategy, includeDayBoundaries: true, limit: 10_000
    ).timeline(from: start)
    let timeline = try PrayerTimelineBuilder(
      schedule: schedule, strategy: strategy, includeDayBoundaries: true, limit: limit
    ).timeline(from: start)
    let completeEntries = Array(complete.entries.dropLast())
    let cutoff =
      completeEntries.count >= limit ? completeEntries[limit - 1].date : complete.validUntil
    #expect(Array(timeline.entries.dropLast()) == Array(completeEntries.prefix(limit - 1)))
    #expect(timeline.entries.count <= limit)
    #expect(timeline.validUntil == cutoff)
    #expect(timeline.entries.last == .init(date: cutoff, state: .expired(knownThrough: cutoff)))
    #expect(timeline.reloadDate == start.addingTimeInterval(cutoff.timeIntervalSince(start) / 2))
    #expect(timeline.entries.dropLast().allSatisfy { $0.date < cutoff })
  }

  @Test("a midnight omitted for lack of room is the expired entry, not a schedule entry")
  func boundaryCutoff() throws {
    let zone = schedule.location.timeZone
    let day = CivilDay(containing: now, in: zone)
    let start = day.start(in: zone).addingTimeInterval(21 * 3_600 + 13 * 60)
    let midnight = day.adding(days: 1).start(in: zone)
    let ordinary = try PrayerTimelineBuilder(schedule: schedule, limit: 2).timeline(from: start)
    #expect(ordinary.validUntil > midnight)
    let timeline = try PrayerTimelineBuilder(
      schedule: schedule, includeDayBoundaries: true, limit: 2
    ).timeline(from: start)
    #expect(timeline.entries.map(\.date) == [start, midnight])
    #expect(timeline.entries.last?.state == .expired(knownThrough: midnight))
    #expect(timeline.isTruncated)
  }

  @Test("a boundary shared with a step, the first entry or expiration isn't duplicated")
  func boundaryCollisions() throws {
    let zone = schedule.location.timeZone
    let start = CivilDay(containing: now, in: zone).start(in: zone)
    let strategy = RefreshStrategy.steps(
      fine: .seconds(3_600), coarse: .seconds(3_600), window: .zero)
    let ordinary = try PrayerTimelineBuilder(schedule: schedule, strategy: strategy)
      .timeline(from: start)
    let timeline = try PrayerTimelineBuilder(
      schedule: schedule, strategy: strategy, includeDayBoundaries: true
    ).timeline(from: start)
    #expect(timeline == ordinary)
    for date in [start, start.addingTimeInterval(86_400), timeline.validUntil] {
      #expect(timeline.entries.filter { $0.date == date }.count == 1)
    }
    #expect(timeline.entries.last?.state == .expired(knownThrough: timeline.validUntil))
  }

  @Test("new boundary states use the clamped horizon's lookahead even when truncated")
  func clampedLookahead() throws {
    let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
    let schedule = Self.dailySchedule(in: zone)
    let day = CivilDay(year: 2026, month: 10, day: 13)
    let start = day.start(in: zone).addingTimeInterval(21 * 3_600 + 13 * 60)
    let timeline = try PrayerTimelineBuilder(
      schedule: schedule, includeDayBoundaries: true, limit: 20
    ).timeline(from: start, horizon: .seconds(1_000 * 86_400))
    #expect(timeline.horizon.end == day.adding(days: 400).start(in: zone))
    let midnight = day.adding(days: 3).start(in: zone)
    let entry = try #require(timeline.entries.first { $0.date == midnight })
    let lookahead = CivilDay(containing: timeline.horizon.end, in: zone).adding(days: 2)
      .start(in: zone)
    #expect(entry.state == .schedule(schedule.state(at: midnight, through: lookahead)))
    #expect(timeline.isTruncated)
  }

  /// A complete custom source, with one event per day well away from a day boundary.
  /// It avoids a fixture timetable's finite end when testing historical zones or long horizons.
  nonisolated private struct DailySource: PrayerSource {
    let expectedKinds: Set<PrayerKind> = [.isha]
    let maximumLead: Duration = .zero

    func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability {
      let event = PrayerEvent(
        scheduleDay: day, kind: .isha,
        time: day.start(in: location.timeZone).addingTimeInterval(12 * 3_600))
      return .available(
        PrayerDay(day: day, timeZone: location.timeZone, events: [event]), coverage: .complete)
    }
  }

  nonisolated private static func dailySchedule(in zone: TimeZone) -> PrayerSchedule {
    PrayerSchedule(
      source: DailySource(), location: PrayerLocation(latitude: 0, longitude: 0, timeZone: zone))
  }
}
