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

  @Test("invalid inputs throw the refresh plan's errors")
  func invalidInputs() {
    #expect(throws: RefreshPlanError.nonPositiveHorizon) {
      try PrayerTimelineBuilder(schedule: schedule).timeline(from: now, horizon: .zero)
    }
    #expect(throws: RefreshPlanError.limitTooSmall) {
      try PrayerTimelineBuilder(schedule: schedule, limit: 1).timeline(from: now)
    }
    #expect(throws: RefreshPlanError.invalidStrategy) {
      try PrayerTimelineBuilder(
        schedule: schedule,
        strategy: .steps(fine: .milliseconds(500), coarse: .seconds(60), window: .seconds(60))
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
      let builder = PrayerTimelineBuilder(schedule: schedule)
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
