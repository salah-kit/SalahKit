import Foundation
import Testing

@testable import SalahCore

/// `PrayerSchedule` enforces the source contract (RFC 0001, section 4.3) on custom sources,
/// which the vectors can't reach because they use `TimetableSource`.
@Suite struct SourceContractTests {
  /// A source that answers from a fixed table.
  struct FixedSource: PrayerSource {
    var expectedKinds: Set<PrayerKind>
    var answers: [CivilDay: PrayerDayAvailability]

    func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability {
      answers[day] ?? .unavailable(.noPublishedData)
    }
  }

  static let zone = TimeZone(identifier: "Europe/London") ?? .gmt
  static let location = PrayerLocation(latitude: 55.95, longitude: -3.19, timeZone: zone)
  /// A Friday in British Summer Time.
  static let friday = CivilDay(year: 2026, month: 6, day: 19)
  static let saturday = CivilDay(year: 2026, month: 6, day: 20)

  /// An instant on `day` at a local time in summer (UTC+1).
  static func at(_ day: CivilDay, _ hour: Int, _ minute: Int, nextDay: Bool = false) -> Date {
    let base = (nextDay ? day.adding(days: 1) : day).start(in: zone)
    return base.addingTimeInterval(TimeInterval(hour * 3_600 + minute * 60))
  }

  static func events(on day: CivilDay, iqama: Date? = nil) -> [PrayerEvent] {
    [
      PrayerEvent(scheduleDay: day, kind: .fajr, time: at(day, 2, 42), iqama: iqama),
      PrayerEvent(scheduleDay: day, kind: .dhuhr, time: at(day, 13, 16)),
      PrayerEvent(scheduleDay: day, kind: .asr, time: at(day, 17, 33)),
      PrayerEvent(scheduleDay: day, kind: .maghrib, time: at(day, 22, 2)),
      PrayerEvent(scheduleDay: day, kind: .isha, time: at(day, 0, 16, nextDay: true)),
    ]
  }

  static let fiveKinds: Set<PrayerKind> = [.fajr, .dhuhr, .asr, .maghrib, .isha]

  static func schedule(
    _ answer: PrayerDayAvailability, on day: CivilDay = friday,
    expectedKinds: Set<PrayerKind> = fiveKinds, iqama: IqamaRules? = nil
  ) -> PrayerSchedule {
    PrayerSchedule(
      source: FixedSource(expectedKinds: expectedKinds, answers: [day: answer]),
      location: location, iqama: iqama)
  }

  static func available(_ events: [PrayerEvent], day: CivilDay = friday) -> PrayerDayAvailability {
    .available(PrayerDay(day: day, timeZone: zone, events: events), coverage: .complete)
  }

  @Test func aValidDayPassesThrough() {
    let day = Self.schedule(Self.available(Self.events(on: Self.friday))).day(Self.friday)
    #expect(day == Self.available(Self.events(on: Self.friday)))
    #expect(day.day?[.isha]?.time == Self.at(Self.friday, 0, 16, nextDay: true))
  }

  @Test func unavailabilityPassesThroughWithItsReason() {
    let schedule = Self.schedule(.unavailable(.calculationUnavailable))
    #expect(schedule.day(Self.friday) == .unavailable(.calculationUnavailable))
  }

  @Test func noExpectedKindsMakesEveryDayInvalid() {
    let schedule = Self.schedule(
      Self.available(Self.events(on: Self.friday)), expectedKinds: [])
    #expect(schedule.day(Self.friday) == .unavailable(.invalidData))
    #expect(schedule.day(Self.saturday) == .unavailable(.invalidData))
  }

  @Test(arguments: [
    "wrong day", "wrong zone", "no events", "event of another day", "unexpected kind",
    "duplicate kind", "out of order", "equal instants", "before the day",
    "at the start of the day after next", "Jumuah on Saturday", "Jumuah on Asr",
    "complete with a kind missing", "partial naming a present kind", "partial with nothing",
  ])
  func contractViolationsMakeTheDayInvalid(_ violation: String) {
    let day = Self.friday
    var events = Self.events(on: day)
    var answerDay = day
    var zone = Self.zone
    var coverage = DayCoverage.complete
    switch violation {
    case "wrong day": answerDay = Self.saturday
    case "wrong zone": zone = TimeZone(identifier: "Europe/Dublin") ?? .gmt
    case "no events": events = []
    case "event of another day": events[1].scheduleDay = Self.saturday
    case "unexpected kind":
      events.insert(
        PrayerEvent(scheduleDay: day, kind: .sunrise, time: Self.at(day, 4, 26)), at: 1)
    case "duplicate kind": events[2].kind = .dhuhr
    case "out of order": events.swapAt(1, 2)
    case "equal instants": events[2].time = events[1].time
    case "before the day": events[0].time = day.start(in: Self.zone).addingTimeInterval(-60)
    case "at the start of the day after next":
      events[4].time = day.adding(days: 2).start(in: Self.zone)
    case "Jumuah on Saturday":
      events = Self.events(on: Self.saturday)
      events[1].observance = .jumuah
      answerDay = Self.saturday
    case "Jumuah on Asr": events[2].observance = .jumuah
    case "complete with a kind missing": events.removeLast()
    case "partial naming a present kind":
      events.removeLast()
      coverage = .partial(missing: [.maghrib: .noPublishedData])
    case "partial with nothing": coverage = .partial(missing: [:])
    default: Issue.record("unknown violation \(violation)")
    }
    let requested = violation == "Jumuah on Saturday" ? Self.saturday : day
    // Set the events directly: PrayerDay's initializer would sort them.
    var prayerDay = PrayerDay(day: answerDay, timeZone: zone, events: [])
    prayerDay.events = events
    let schedule = Self.schedule(.available(prayerDay, coverage: coverage), on: requested)
    #expect(schedule.day(requested) == .unavailable(.invalidData), "\(violation)")
  }

  @Test func anInvalidRequestedDayIsInvalid() {
    let day = CivilDay(year: 2026, month: 2, day: 30)
    let schedule = Self.schedule(Self.available(Self.events(on: day), day: day), on: day)
    #expect(schedule.day(day) == .unavailable(.invalidData))
  }

  @Test func declaredJumuahOnFridayDhuhrIsKept() {
    var events = Self.events(on: Self.friday)
    events[1].observance = .jumuah
    let schedule = Self.schedule(Self.available(events))
    #expect(schedule.day(Self.friday).day?[.dhuhr]?.observance == .jumuah)
  }

  @Test func aPartialDayNamingExactlyItsMissingKindsIsKept() {
    var events = Self.events(on: Self.friday)
    events.removeLast()
    let answer = PrayerDayAvailability.available(
      PrayerDay(day: Self.friday, timeZone: Self.zone, events: events),
      coverage: .partial(missing: [.isha: .calculationUnavailable]))
    #expect(Self.schedule(answer).day(Self.friday) == answer)
  }

  @Test func anIqamaOutsideItsSpanIsDroppedAndTheDayKept() {
    let early = Self.at(Self.friday, 2, 30)
    let late = Self.friday.adding(days: 2).start(in: Self.zone)
    for iqama in [early, late] {
      let schedule = Self.schedule(Self.available(Self.events(on: Self.friday, iqama: iqama)))
      let fajr = schedule.day(Self.friday).day?[.fajr]
      #expect(fajr != nil)
      #expect(fajr?.iqama == nil)
    }
  }

  @Test func iqamaRulesApplyToCustomSources() {
    var events = Self.events(on: Self.friday, iqama: Self.at(Self.friday, 3, 0))
    events[1].observance = .jumuah
    let rules = IqamaRules(
      rules: [
        .fajr: .after(minutes: 20), .dhuhr: .after(minutes: 10),
        .isha: .at(
          WallClockTime(hour: 0, minute: 30, dayOffset: 1)),
      ],
      jumuah: nil)
    let day = Self.schedule(Self.available(events), iqama: rules).day(Self.friday).day
    // The published Fajr iqama wins; Jumu'ah has no rule, so the Dhuhr rule doesn't apply.
    #expect(day?[.fajr]?.iqama == Self.at(Self.friday, 3, 0))
    #expect(day?[.dhuhr]?.iqama == nil)
    #expect(day?[.asr]?.iqama == nil)
    #expect(day?[.isha]?.iqama == Self.at(Self.friday, 0, 30, nextDay: true))
  }

  @Test func overlappingCustomDaysKeepTheirEventsAndReportTheOverlap() throws {
    var friday = Self.events(on: Self.friday)
    var saturday = Self.events(on: Self.saturday)
    friday[4].time = Self.at(Self.friday, 2, 45, nextDay: true)  // Isha after Saturday's Fajr
    saturday[0].time = Self.at(Self.saturday, 2, 40)
    let source = FixedSource(
      expectedKinds: Self.fiveKinds,
      answers: [
        Self.friday: Self.available(friday),
        Self.saturday: Self.available(saturday, day: Self.saturday),
      ])
    let schedule = PrayerSchedule(source: source, location: Self.location)
    let result = schedule.events(
      from: Self.at(Self.saturday, 0, 0), through: Self.at(Self.saturday, 3, 0))
    #expect(result.events.map(\.kind) == [.fajr, .isha])
    let gap = try #require(result.coverage.gaps.first)
    #expect(result.coverage.gaps.count == 1)
    #expect(gap.reason == .invalidData)
    #expect(gap.day == Self.friday)
    #expect(gap.kinds == [.isha])
    #expect(gap.interval.start == Self.at(Self.saturday, 2, 40))
    #expect(gap.interval.end == Self.at(Self.friday, 2, 45, nextDay: true))

    // Inside the overlap the state asserts nothing.
    let state = schedule.state(
      at: Self.at(Self.saturday, 2, 42), through: Self.at(Self.saturday, 23, 0))
    #expect(state.prayerState == nil)
    #expect(state.changesAt == Self.at(Self.friday, 2, 45, nextDay: true))
  }
}
