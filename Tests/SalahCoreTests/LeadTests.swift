import Foundation
import SalahCore
import Testing

/// A source's ``PrayerSource/maximumLead`` lets an event come before its owning day (RFC 0001,
/// section 4.3, rule 4): Kazan's Fajr under the middle-of-the-night rule falls at 23:4x on the
/// previous evening, because Moscow time runs behind the Sun there.
@Suite struct LeadTests {
  /// A source that answers from a fixed table, with a chosen lead.
  nonisolated struct LeadSource: PrayerSource {
    var answers: [CivilDay: PrayerDayAvailability]
    var maximumLead: Duration
    var expectedKinds: Set<PrayerKind> { Set(PrayerKind.allCases) }

    func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability {
      answers[day] ?? .unavailable(.noPublishedData)
    }
  }

  static let zone = TimeZone(identifier: "Europe/Moscow") ?? .gmt
  static let kazan = PrayerLocation(latitude: 55.7963, longitude: 49.1088, timeZone: zone)
  static let saturday = CivilDay(year: 2026, month: 6, day: 20)
  static let sunday = CivilDay(year: 2026, month: 6, day: 21)
  static let monday = CivilDay(year: 2026, month: 6, day: 22)

  /// A local time on `day` in Moscow, which keeps UTC+3 all year. A negative hour is on the
  /// evening before.
  static func at(_ day: CivilDay, _ hour: Int, _ minute: Int) -> Date {
    day.start(in: zone).addingTimeInterval(TimeInterval(hour * 3_600 + minute * 60))
  }

  /// A summer day whose Fajr falls at 23:40 the evening before and whose Isha is at 23:00.
  static func events(on day: CivilDay, fajr: Date? = nil) -> [PrayerEvent] {
    [
      PrayerEvent(scheduleDay: day, kind: .fajr, time: fajr ?? at(day, -1, 40)),
      PrayerEvent(scheduleDay: day, kind: .sunrise, time: at(day, 3, 40)),
      PrayerEvent(scheduleDay: day, kind: .dhuhr, time: at(day, 12, 15)),
      PrayerEvent(scheduleDay: day, kind: .asr, time: at(day, 16, 40)),
      PrayerEvent(scheduleDay: day, kind: .maghrib, time: at(day, 20, 50)),
      PrayerEvent(scheduleDay: day, kind: .isha, time: at(day, 23, 0)),
    ]
  }

  static func complete(_ day: CivilDay, fajr: Date? = nil) -> PrayerDayAvailability {
    .available(
      PrayerDay(day: day, timeZone: zone, events: events(on: day, fajr: fajr)),
      coverage: .complete)
  }

  static func schedule(
    lead: Duration = .seconds(12 * 3_600), _ answers: [CivilDay: PrayerDayAvailability]
  ) -> PrayerSchedule {
    PrayerSchedule(source: LeadSource(answers: answers, maximumLead: lead), location: kazan)
  }

  static let threeDays = schedule([
    saturday: complete(saturday), sunday: complete(sunday), monday: complete(monday),
  ])

  @Test func anEventWithinTheLeadIsKept() {
    let day = Self.threeDays.day(Self.sunday)
    #expect(day == Self.complete(Self.sunday))
    #expect(day.day?[.fajr]?.time == Self.at(Self.saturday, 23, 40))
  }

  @Test func anEventBeforeTheLeadMakesTheDayInvalid() {
    let early = Self.at(Self.sunday, -1, 30)
    let oneHour = Self.schedule(
      lead: .seconds(3_600), [Self.sunday: Self.complete(Self.sunday, fajr: early)])
    #expect(oneHour.day(Self.sunday).day?[.fajr]?.time == early)

    let tooEarly = Self.at(Self.sunday, -2, 59)
    let rejected = Self.schedule(
      lead: .seconds(3_600), [Self.sunday: Self.complete(Self.sunday, fajr: tooEarly)])
    #expect(rejected.day(Self.sunday) == .unavailable(.invalidData))
  }

  @Test func aZeroLeadKeepsEveryEventOnOrAfterItsDay() {
    let zero = Self.schedule(lead: .zero, [Self.sunday: Self.complete(Self.sunday)])
    #expect(zero.day(Self.sunday) == .unavailable(.invalidData))
    let negative = Self.schedule(lead: .seconds(-600), [Self.sunday: Self.complete(Self.sunday)])
    #expect(negative.day(Self.sunday) == .unavailable(.invalidData))
  }

  /// A negative lead counts as zero, so an event shortly after its day starts is still kept.
  @Test func aLeadBelowZeroCountsAsZero() {
    let afterMidnight = Self.at(Self.sunday, 0, 5)
    let negative = Self.schedule(
      lead: .seconds(-600), [Self.sunday: Self.complete(Self.sunday, fajr: afterMidnight)])
    #expect(negative.day(Self.sunday).day?[.fajr]?.time == afterMidnight)
  }

  @Test func aLeadAboveTwelveHoursCountsAsTwelve() {
    let elevenHours = Self.at(Self.sunday, -11, 0)
    let thirteenHours = Self.at(Self.sunday, -13, 0)
    let kept = Self.schedule(
      lead: .seconds(30 * 3_600), [Self.sunday: Self.complete(Self.sunday, fajr: elevenHours)])
    #expect(kept.day(Self.sunday).day?[.fajr]?.time == elevenHours)
    let rejected = Self.schedule(
      lead: .seconds(30 * 3_600), [Self.sunday: Self.complete(Self.sunday, fajr: thirteenHours)])
    #expect(rejected.day(Self.sunday) == .unavailable(.invalidData))
  }

  @Test func eventsOfAnEveningIncludeTheNextDaysEarlyFajr() {
    let result = Self.threeDays.events(
      from: Self.at(Self.saturday, 22, 0), through: Self.at(Self.saturday, 23, 50))
    #expect(
      result.events.map { "\($0.scheduleDay)/\($0.kind)" } == [
        "2026-06-20/isha", "2026-06-21/fajr",
      ])
    #expect(result.coverage.isComplete)
  }

  /// The bound falls on Saturday, but Sunday's Fajr comes before it: the context reads Sunday.
  @Test func aBoundBeforeMidnightStillSeesTheNextDaysFajr() {
    let state = Self.threeDays.state(
      at: Self.at(Self.saturday, 23, 30), through: Self.at(Self.saturday, 23, 50))
    #expect(state.prayerState?.previous?.kind == .isha)
    #expect(state.prayerState?.next?.scheduleDay == Self.sunday)
    #expect(state.prayerState?.next?.kind == .fajr)
    #expect(state.prayerState?.nextPrayer?.kind == .fajr)
    #expect(state.changesAt == Self.at(Self.saturday, 23, 40))
    #expect(state.coverage.isComplete)
  }

  @Test func afterTheEarlyFajrItIsTheLatestPrayer() {
    let now = Self.at(Self.saturday, 23, 45)
    let state = Self.threeDays.state(at: now, through: Self.monday.start(in: Self.zone))
    let prayerState = state.prayerState
    #expect(prayerState?.previous?.id == Self.events(on: Self.sunday)[0].id)
    #expect(prayerState?.latestPrayer?.id == Self.events(on: Self.sunday)[0].id)
    #expect(prayerState?.next?.kind == .sunrise)
    #expect(prayerState?.nextPrayer?.kind == .dhuhr)
    // The civil date is still Saturday; Sunday's Fajr belongs to Sunday's day.
    #expect(Self.threeDays.day(containing: now).day?.day == Self.saturday)
  }

  @Test func aMissingFajrsIntervalStartsWithinTheLead() {
    var sunday = Self.events(on: Self.sunday)
    sunday.removeFirst()
    let schedule = Self.schedule([
      Self.saturday: Self.complete(Self.saturday),
      Self.sunday: .available(
        PrayerDay(day: Self.sunday, timeZone: Self.zone, events: sunday),
        coverage: .partial(missing: [.fajr: .calculationUnavailable])),
    ])
    let coverage = schedule.events(
      from: Self.at(Self.saturday, 20, 0), through: Self.at(Self.sunday, 6, 0)
    ).coverage
    #expect(coverage.gaps.count == 1)
    let gap = coverage.gaps.first
    // From Saturday's Isha, not from midnight: the lead lets Fajr come before Sunday starts.
    #expect(gap?.interval.start == Self.at(Self.saturday, 23, 0))
    #expect(gap?.interval.end == Self.at(Self.sunday, 3, 40))
    #expect(gap?.day == Self.sunday)
    #expect(gap?.kinds == [.fajr])
    #expect(gap?.reason == .calculationUnavailable)

    let state = schedule.state(
      at: Self.at(Self.saturday, 23, 30), through: Self.monday.start(in: Self.zone))
    #expect(state.prayerState == nil)
  }

  @Test func aMissingDaysIntervalsStartWithinTheLead() {
    let schedule = Self.schedule([Self.saturday: Self.complete(Self.saturday)])
    let gaps = schedule.events(
      from: Self.at(Self.saturday, 22, 0), through: Self.at(Self.sunday, 2, 0)
    ).coverage.gaps
    #expect(gaps.map(\.interval.start) == [Self.at(Self.saturday, 23, 0)])
    #expect(gaps.map(\.day) == [Self.sunday])
    #expect(gaps.first?.kinds == Set(PrayerKind.allCases))
    #expect(gaps.first?.reason == .noPublishedData)
  }

  /// Sunday has no events, and Monday's early Fajr comes before Saturday's late Isha: the days on
  /// either side cross (section 4.3, rule 6). The schedule compares them and reports the
  /// crossing as an invalid-data gap, so it asserts neither event while they contradict.
  @Test func daysThatCrossPastADayWithoutEventsBecomeAGap() {
    let lateIsha = Self.at(Self.sunday, 23, 59)
    let earlyFajr = Self.at(Self.sunday, 12, 30)
    var saturday = Self.events(on: Self.saturday)
    saturday[5] = PrayerEvent(scheduleDay: Self.saturday, kind: .isha, time: lateIsha)
    let schedule = Self.schedule([
      Self.saturday: .available(
        PrayerDay(day: Self.saturday, timeZone: Self.zone, events: saturday), coverage: .complete),
      Self.sunday: .unavailable(.calculationUnavailable),
      Self.monday: Self.complete(Self.monday, fajr: earlyFajr),
    ])
    // Each day holds the contract on its own.
    #expect(schedule.day(Self.saturday).day?[.isha]?.time == lateIsha)
    #expect(schedule.day(Self.monday).day?[.fajr]?.time == earlyFajr)

    let result = schedule.events(
      from: Self.sunday.start(in: Self.zone), through: Self.monday.start(in: Self.zone))
    #expect(
      result.events.map { "\($0.scheduleDay)/\($0.kind)" } == [
        "2026-06-22/fajr", "2026-06-20/isha",
      ])
    let gaps = result.coverage.gaps
    #expect(gaps.count == 1)
    #expect(gaps.first?.interval == DateInterval(start: earlyFajr, end: lateIsha))
    #expect(gaps.first?.day == Self.saturday)
    #expect(gaps.first?.kinds == [.isha])
    #expect(gaps.first?.reason == .invalidData)

    let state = schedule.state(at: Self.at(Self.sunday, 13, 0), through: lateIsha)
    #expect(state.prayerState == nil)
    #expect(state.coverage.gaps.map(\.reason) == [.invalidData])
  }

  @Test func aRefreshPlanChangesAtTheEarlyFajr() throws {
    let plan = try Self.threeDays.refreshPlan(
      from: Self.at(Self.saturday, 22, 0), through: Self.at(Self.sunday, 4, 0))
    #expect(plan.dates.contains(Self.at(Self.saturday, 23, 40)))
    let entry = plan.entries.first { $0.date == Self.at(Self.saturday, 23, 40) }
    #expect(entry?.state.prayerState?.latestPrayer?.scheduleDay == Self.sunday)
    #expect(entry?.state.prayerState?.latestPrayer?.kind == .fajr)
  }
}
