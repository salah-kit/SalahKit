import Foundation
import SalahCore
import SalahFixtures
import Testing

/// The moments: their instants, and the state each one shows.
@Suite struct MomentTests {
  @Test func everyMomentIsListedOnceInOrder() {
    let ids = [
      "approaching", "justStarted", "afterIsha", "beforeFajr", "partialDay", "missingDay",
      "afterLastPublishedDay",
    ]
    #expect(PrayerFixtures.moments.map(\.id) == ids)
    #expect(Set(PrayerFixtures.moments.map(\.id)).count == ids.count)
    #expect(Set(PrayerFixtures.moments).count == ids.count)
    #expect(
      PrayerFixtures.moments == [
        PrayerFixtures.approaching, PrayerFixtures.justStarted, PrayerFixtures.afterIsha,
        PrayerFixtures.beforeFajr, PrayerFixtures.partialDay, PrayerFixtures.missingDay,
        PrayerFixtures.afterLastPublishedDay,
      ])
    #expect(MomentCheck.all.map(\.id) == ids)
  }

  @Test(arguments: MomentCheck.all)
  func instantsAreExactAtTheirPlace(_ check: MomentCheck) throws {
    let moment = try fixtureMoment(check.id)
    #expect(moment.place == (try fixturePlace(check.place)))
    #expect(moment.date == (try instant(check.local)))
    #expect(moment.date == (try instant(check.utc)))
    // A whole minute, as every begin time is.
    #expect(moment.date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0)
    #expect(moment.schedule.location == moment.place.location)
    // The moment falls inside the days its place publishes, or in a hole between them.
    let zone = moment.place.location.timeZone
    let day = CivilDay(containing: moment.date, in: zone)
    let first = try #require(moment.place.source.firstDay)
    let last = try #require(moment.place.source.lastDay)
    #expect(first <= day && day <= last)
  }

  @Test func stateLooksAheadToTheSecondCivilDayAfterTheMoment() throws {
    for moment in PrayerFixtures.moments {
      let zone = moment.place.location.timeZone
      let bound = CivilDay(containing: moment.date, in: zone).adding(days: 2).start(in: zone)
      let state = moment.state()
      #expect(
        state.coverage.requested == DateInterval(start: moment.date, end: bound), "\(moment.id)")
      #expect(state == moment.schedule.state(at: moment.date, through: bound), "\(moment.id)")
      if let changesAt = state.changesAt {
        #expect(changesAt > moment.date && changesAt <= bound, "\(moment.id)")
      }
    }
  }

  @Test func theStatePolicyReachesTheState() throws {
    // Ten minutes before Maghrib: approaching within 10 minutes, but not within 5.
    let approaching = PrayerFixtures.approaching
    #expect(
      approaching.state(policy: StatePolicy(approaching: .seconds(600))).prayerState?.isApproaching
        == true)
    #expect(
      approaching.state(policy: StatePolicy(approaching: .seconds(300))).prayerState?.isApproaching
        == false)

    // Four minutes after Dhuhr: just started for 241 seconds, but not for 240 or 60.
    let justStarted = PrayerFixtures.justStarted
    for (seconds, started) in [(241.0, true), (240.0, false), (60.0, false)] {
      let policy = StatePolicy(justStarted: .fixed(.seconds(seconds)))
      let expected: PrayerKind? = started ? .dhuhr : nil
      #expect(justStarted.state(policy: policy).prayerState?.justStarted?.kind == expected)
    }
  }

  // MARK: The state each moment shows

  @Test func approachingIsTenMinutesBeforeMaghribInMakkah() throws {
    let state = try #require(PrayerFixtures.approaching.state().prayerState)
    let asr = try expectedEvent(
      "2026-10-13", .asr, "2026-10-13T15:28:00+03:00", iqama: "2026-10-13T15:48:00+03:00")
    let maghrib = try expectedEvent(
      "2026-10-13", .maghrib, "2026-10-13T17:58:00+03:00", iqama: "2026-10-13T18:08:00+03:00")

    #expect(state.previous == asr)
    #expect(state.latestPrayer == asr)
    #expect(state.next == maghrib)
    #expect(state.nextPrayer == maghrib)
    #expect(state.isApproaching)
    #expect(state.justStarted == nil)
    let tenMinutes: TimeInterval = 600
    #expect(state.nextPrayer?.time.timeIntervalSince(state.date) == tenMinutes)
    #expect(state.changesAt == maghrib.time)
    #expect(PrayerFixtures.approaching.state().coverage.isComplete)
    #expect(state.status(of: maghrib) == .next(approaching: true))
    #expect(state.status(of: asr) == .passed)
  }

  @Test func justStartedIsFourMinutesAfterDhuhrInLondon() throws {
    let state = try #require(PrayerFixtures.justStarted.state().prayerState)
    let dhuhr = try expectedEvent("2026-06-21", .dhuhr, "2026-06-21T13:07:00+01:00")
    let asr = try expectedEvent("2026-06-21", .asr, "2026-06-21T17:25:00+01:00")

    #expect(state.justStarted == dhuhr)
    #expect(state.previous == dhuhr)
    #expect(state.latestPrayer == dhuhr)
    #expect(state.next == asr)
    #expect(state.nextPrayer == asr)
    #expect(!state.isApproaching)
    // No iqama, so the window is the 15-minute fallback, from 13:07 to 13:22.
    #expect(state.changesAt == (try instant("2026-06-21T13:22:00+01:00")))
    #expect(state.status(of: dhuhr) == .justStarted)
  }

  @Test func afterIshaIsThirtyMinutesAfterIshaInJakarta() throws {
    let state = try #require(PrayerFixtures.afterIsha.state().prayerState)
    let isha = try expectedEvent(
      "2026-10-13", .isha, "2026-10-13T18:56:00+07:00", iqama: "2026-10-13T19:06:00+07:00")
    let fajr = try expectedEvent(
      "2026-10-14", .fajr, "2026-10-14T04:14:00+07:00", iqama: "2026-10-14T04:24:00+07:00")

    #expect(state.previous == isha)
    #expect(state.latestPrayer == isha)
    // Isha's iqama has passed, so nothing counts as just started.
    #expect(state.justStarted == nil)
    // The next day's Fajr is known, and owned by that day.
    #expect(state.next == fajr)
    #expect(state.nextPrayer == fajr)
    #expect(!state.isApproaching)
    // The countdown starts approaching 15 minutes before Fajr.
    #expect(state.changesAt == (try instant("2026-10-14T03:59:00+07:00")))
  }

  @Test func beforeFajrIsBeforeTheSpringForwardJumpInNewYork() throws {
    let moment = PrayerFixtures.beforeFajr
    let state = try #require(moment.state().prayerState)
    let isha = try expectedEvent("2026-03-07", .isha, "2026-03-07T19:09:00-05:00")
    let fajr = try expectedEvent("2026-03-08", .fajr, "2026-03-08T06:04:00-04:00")

    #expect(state.previous == isha)
    #expect(state.latestPrayer == isha)
    #expect(state.next == fajr)
    #expect(state.nextPrayer == fajr)
    #expect(!state.isApproaching)
    #expect(state.justStarted == nil)

    // 01:30 EST to 06:04 EDT: the wall clock suggests 4 h 34 min, but 3 h 34 min elapse.
    let elapsed: TimeInterval = 3 * 3_600 + 34 * 60
    let wallClockDifference: TimeInterval = 4 * 3_600 + 34 * 60
    #expect(state.nextPrayer?.time.timeIntervalSince(moment.date) == elapsed)
    #expect(state.nextPrayer?.time.timeIntervalSince(moment.date) != wallClockDifference)
    #expect(state.changesAt == (try instant("2026-03-08T05:49:00-04:00")))
  }

  @Test func partialDayHasNoStateBecauseIshaIsUnknown() throws {
    let moment = PrayerFixtures.partialDay
    guard case .unavailable(let coverage, let changesAt) = moment.state() else {
      Issue.record("Expected an unavailable state")
      return
    }
    let end = try instant("2026-11-12T00:00:00+08:00")
    // Until Isha's window closes, nothing is asserted: the next change is the missing day.
    #expect(changesAt == (try instant("2026-11-11T00:00:00+08:00")))
    #expect(coverage.requested == DateInterval(start: moment.date, end: end))
    #expect(coverage.knownIntervals.isEmpty)
    #expect(!coverage.isComplete)

    #expect(coverage.gaps.map(\.day) == [try civilDay("2026-11-10"), try civilDay("2026-11-11")])
    #expect(coverage.gaps.map(\.reason) == [.noPublishedData, .noPublishedData])
    #expect(coverage.gaps.map(\.kinds) == [[.isha], Set(PrayerKind.allCases)])
    // Isha's gap runs from the moment to the end of the lookahead, and the missing day's from
    // its start.
    #expect(
      coverage.gaps.map(\.interval) == [
        DateInterval(start: moment.date, end: end),
        DateInterval(start: try instant("2026-11-11T00:00:00+08:00"), end: end),
      ])
  }

  @Test func missingDayHasNoStateBecauseTheDayHasNoRow() throws {
    let moment = PrayerFixtures.missingDay
    guard case .unavailable(let coverage, let changesAt) = moment.state() else {
      Issue.record("Expected an unavailable state")
      return
    }
    let fajr = try instant("2026-11-12T05:27:00+08:00")
    #expect(changesAt == (try instant("2026-11-12T00:00:00+08:00")))
    #expect(
      coverage.requested
        == DateInterval(start: moment.date, end: try instant("2026-11-13T00:00:00+08:00")))
    // The schedule knows everything from the next day's Fajr on, and nothing before it.
    #expect(
      coverage.knownIntervals == [
        DateInterval(start: fajr, end: try instant("2026-11-13T00:00:00+08:00"))
      ])

    #expect(coverage.gaps.map(\.day) == [try civilDay("2026-11-10"), try civilDay("2026-11-11")])
    #expect(coverage.gaps.map(\.reason) == [.noPublishedData, .noPublishedData])
    #expect(coverage.gaps.map(\.kinds) == [[.isha], Set(PrayerKind.allCases)])
    #expect(
      coverage.gaps.map(\.interval) == [
        DateInterval(start: moment.date, end: try instant("2026-11-12T00:00:00+08:00")),
        DateInterval(start: moment.date, end: fajr),
      ])
  }

  @Test func afterLastPublishedDayKnowsIshaAndNothingAfterIt() throws {
    let moment = PrayerFixtures.afterLastPublishedDay
    guard case .available(let state, let coverage) = moment.state() else {
      Issue.record("Expected an available state")
      return
    }
    let isha = try expectedEvent("2026-11-13", .isha, "2026-11-13T20:04:00+08:00")
    #expect(state.previous == isha)
    #expect(state.latestPrayer == isha)
    #expect(state.next == nil)
    #expect(state.nextPrayer == nil)
    #expect(state.justStarted == nil)
    #expect(!state.isApproaching)

    // The state changes when the next, unpublished day begins.
    let nextDay = try instant("2026-11-14T00:00:00+08:00")
    #expect(state.changesAt == nextDay)
    #expect(coverage.knownIntervals == [DateInterval(start: moment.date, end: nextDay)])
    #expect(coverage.gaps.map(\.day) == [try civilDay("2026-11-14")])
    #expect(coverage.gaps.map(\.reason) == [.noPublishedData])
    #expect(coverage.gaps.map(\.kinds) == [Set(PrayerKind.allCases)])
    #expect(
      coverage.gaps.map(\.interval) == [
        DateInterval(start: nextDay, end: try instant("2026-11-15T00:00:00+08:00"))
      ])
  }
}
