import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import Testing

/// `CalculationSource` meets SalahCore's source contract and passes SalahTimes' results through
/// unchanged (RFC 0002, section 4).
@Suite struct CalculationSourceTests {
  /// Parameter sets that customize every control SalahTimes has.
  nonisolated static let customParameters: [CalculationParameters] = {
    var maghribAngle = CalculationMethod.muslimWorldLeague.parameters
    maghribAngle.maghrib = .angle(4.5)
    maghribAngle.madhab = .hanafi
    var ishaInterval = CalculationMethod.egyptian.parameters
    ishaInterval.isha = .minutesAfterMaghrib(80)
    ishaInterval.rounding = .up
    ishaInterval.adjustments = PrayerAdjustments(fajr: -3, dhuhr: 2, isha: 4)
    var unrounded = CalculationMethod.diyanet.parameters
    unrounded.rounding = .none
    unrounded.highLatitudeRule = .twilightAngle
    var shafaq = CalculationMethod.moonsightingCommittee.parameters
    shafaq.isha = .moonsightingCommittee(.abyad)
    shafaq.nightSpan = .sunsetToSunrise
    var custom = CalculationParameters(
      fajr: .angle(16.5), isha: .angle(14.5), maghrib: .angle(1), madhab: .hanafi,
      highLatitudeRule: .middleOfTheNight, methodAdjustments: PrayerAdjustments(maghrib: 2),
      adjustments: PrayerAdjustments(sunrise: -1, asr: 3), rounding: .nearest)
    custom.ramadanIsha = .interval(minutes: 120, hijriDayOffset: 0)
    return [maghribAngle, ishaInterval, unrounded, shafaq, custom]
  }()

  static let places = [Places.makkah, Places.cairo, Places.istanbul, Places.london, Places.kashgar]
  static let days = ["2026-01-15", "2026-03-01", "2026-06-21", "2026-10-25"].map(Places.day)

  @Test(arguments: customParameters.indices)
  func customizedParametersPassThroughUnchanged(_ index: Int) throws {
    let parameters = Self.customParameters[index]
    let source = CalculationSource(CalculationSettings(parameters: parameters))
    for location in Self.places {
      for day in Self.days {
        let direct = try Places.direct(day, at: location, parameters)
        let availability = source.prayerDay(day, at: location)
        let calculated = try #require(availability.day, "\(location.name ?? "") \(day)")
        #expect(availability.coverage == .complete, "\(location.name ?? "") \(day)")
        for kind in PrayerKind.allCases {
          #expect(
            calculated[kind]?.time == direct[Places.event(of: kind)].date,
            "\(location.name ?? "") \(day) \(kind)")
        }
      }
    }
  }

  @Test func aDayFollowsTheSourceContract() throws {
    let source = CalculationSource(CalculationSettings(method: .ummAlQura))
    #expect(source.expectedKinds == Set(PrayerKind.allCases))
    #expect(source.maximumLead == .seconds(12 * 3_600))
    // 2026-10-16 is a Friday: Dhuhr stays ordinary, because the source never infers Jumu'ah.
    let friday = Places.day("2026-10-16")
    let day = try #require(source.prayerDay(friday, at: Places.makkah).day)
    #expect(day.day == friday && day.isFriday)
    #expect(day.timeZone.identifier == "Asia/Riyadh")
    #expect(day.events.map(\.kind) == PrayerKind.allCases)
    #expect(day.events.allSatisfy { $0.scheduleDay == friday })
    #expect(day.events.allSatisfy { $0.observance == .ordinary && $0.iqama == nil })
    #expect(zip(day.events, day.events.dropFirst()).allSatisfy { $0.time < $1.time })
    // Pure: the same question gets the same answer.
    #expect(source.prayerDay(friday, at: Places.makkah) == .available(day, coverage: .complete))
  }

  /// The schedule accepts every calculated day as it is: no day or overlap is invalid data.
  @Test(arguments: [
    (Places.makkah, CalculationMethod.ummAlQura), (Places.london, .moonsightingCommittee),
    (Places.oslo, .tehran), (Places.rovaniemi, .ummAlQura), (Places.rovaniemi, .diyanet),
    (Places.tromso, .muslimWorldLeague), (Places.kazan, .muslimWorldLeague),
  ])
  func aYearOfDaysPassesTheSchedulesChecks(_ location: PrayerLocation, _ method: CalculationMethod)
  {
    var parameters = method.parameters
    if location == Places.kazan { parameters.highLatitudeRule = .middleOfTheNight }
    let source = CalculationSource(CalculationSettings(parameters: parameters))
    let schedule = PrayerSchedule(source: source, location: location)
    var day = Places.day("2026-01-01")
    for _ in 0..<365 {
      #expect(schedule.day(day) == source.prayerDay(day, at: location), "\(day)")
      day = day.adding(days: 1)
    }
    let zone = location.timeZone
    let year = schedule.events(
      from: Places.day("2026-01-01").start(in: zone),
      through: Places.day("2027-01-01").start(in: zone))
    #expect(!year.coverage.gaps.contains { $0.reason == .invalidData }, "\(location.name ?? "")")
  }

  // MARK: - Owning days

  /// Kazan under the middle-of-the-night rule: Fajr at 23:45 on the evening before its day.
  @Test func aFajrBeforeMidnightBelongsToTheNextDay() throws {
    var parameters = CalculationMethod.muslimWorldLeague.parameters
    parameters.highLatitudeRule = .middleOfTheNight
    let source = CalculationSource(CalculationSettings(parameters: parameters))
    let saturday = Places.day("2026-06-20")
    let sunday = Places.day("2026-06-21")
    let availability = source.prayerDay(sunday, at: Places.kazan)
    #expect(availability.coverage == .complete)
    let fajr = try #require(availability.day?[.fajr])
    #expect(fajr.time == Places.instant("2026-06-20T23:45:00+03:00"))
    #expect(fajr.time < sunday.start(in: Places.kazan.timeZone))
    // The middle of the same night ends Saturday's Isha and starts Sunday's Fajr.
    #expect(source.prayerDay(saturday, at: Places.kazan).day?[.isha]?.time == fajr.time)

    let schedule = PrayerSchedule(source: source, location: Places.kazan)
    #expect(schedule.day(sunday) == availability)
    let lateEvening = try #require(Places.instant("2026-06-20T23:50:00+03:00"))
    let state = schedule.state(
      at: lateEvening, through: Places.day("2026-06-22").start(in: Places.kazan.timeZone))
    #expect(state.prayerState?.latestPrayer?.id == fajr.id)
    #expect(state.prayerState?.next?.kind == .sunrise)
  }

  /// Kashgar runs on Beijing time, far ahead of the Sun: Isha after midnight.
  @Test func anIshaAfterMidnightBelongsToTheEveningBefore() throws {
    let source = CalculationSource(CalculationSettings(method: .muslimWorldLeague))
    let day = Places.day("2026-06-21")
    let isha = try #require(source.prayerDay(day, at: Places.kashgar).day?[.isha])
    #expect(isha.scheduleDay == day)
    #expect(isha.time == Places.instant("2026-06-22T00:19:00+08:00"))
  }

  // MARK: - Gaps

  @Test func polarDayHasOnlyDhuhrAndAsr() throws {
    let source = CalculationSource(CalculationSettings(method: .muslimWorldLeague))
    let availability = source.prayerDay(Places.day("2026-06-21"), at: Places.tromso)
    #expect(availability.day?.events.map(\.kind) == [.dhuhr, .asr])
    #expect(
      availability.coverage
        == .partial(missing: [
          .fajr: .calculationUnavailable, .sunrise: .calculationUnavailable,
          .maghrib: .calculationUnavailable, .isha: .calculationUnavailable,
        ]))
  }

  @Test func polarNightHasNoSunriseAsrOrMaghrib() throws {
    let source = CalculationSource(CalculationSettings(method: .muslimWorldLeague))
    let availability = source.prayerDay(Places.day("2026-12-21"), at: Places.tromso)
    #expect(availability.day?.events.map(\.kind) == [.fajr, .dhuhr, .isha])
    #expect(
      availability.coverage
        == .partial(missing: [
          .sunrise: .calculationUnavailable, .asr: .calculationUnavailable,
          .maghrib: .calculationUnavailable,
        ]))
  }

  /// With no high-latitude rule, Oslo's twilight never reaches 18° in June: no Fajr or Isha,
  /// and nothing borrowed from a day that has them.
  @Test func aDisabledRuleLeavesTwilightPrayersMissing() throws {
    var parameters = CalculationMethod.muslimWorldLeague.parameters
    parameters.highLatitudeRule = .disabled
    let source = CalculationSource(CalculationSettings(parameters: parameters))
    let midsummer = Places.day("2026-06-21")
    let direct = try Places.direct(midsummer, at: Places.oslo, parameters)
    #expect(direct.isha.date == nil && direct.fajr.date == nil)
    let availability = source.prayerDay(midsummer, at: Places.oslo)
    #expect(availability.day?[.isha] == nil && availability.day?[.fajr] == nil)
    #expect(
      availability.coverage
        == .partial(missing: [.fajr: .calculationUnavailable, .isha: .calculationUnavailable]))
    let april = try #require(source.prayerDay(Places.day("2026-04-01"), at: Places.oslo).day)
    #expect(april[.isha] != nil, "an April day still has Isha")
  }

  /// Tehran's Maghrib and Isha meet at Oslo in summer; the later kind is missing.
  @Test func anIshaAtMaghribsInstantIsMissing() throws {
    let parameters = CalculationMethod.tehran.parameters
    let day = Places.day("2026-06-21")
    let direct = try Places.direct(day, at: Places.oslo, parameters)
    #expect(direct.maghrib.date != nil && direct.maghrib.date == direct.isha.date)
    let availability = CalculationSource(CalculationSettings(parameters: parameters))
      .prayerDay(day, at: Places.oslo)
    #expect(availability.day?[.maghrib]?.time == direct.maghrib.date)
    #expect(availability.day?[.isha] == nil)
    #expect(availability.coverage == .partial(missing: [.isha: .calculationUnavailable]))
  }

  /// At the Arctic Circle in June, Umm al-Qura's 90-minute Isha comes after the next Fajr.
  @Test func anIshaAfterTheNextFajrIsMissing() throws {
    let parameters = CalculationMethod.ummAlQura.parameters
    let day = Places.day("2026-06-01")
    let direct = try Places.direct(day, at: Places.rovaniemi, parameters)
    let next = try Places.direct(day.adding(days: 1), at: Places.rovaniemi, parameters)
    let isha = try #require(direct.isha.date)
    #expect(isha > (try #require(next.fajr.date)))
    let source = CalculationSource(CalculationSettings(parameters: parameters))
    let availability = source.prayerDay(day, at: Places.rovaniemi)
    #expect(availability.day?[.isha] == nil)
    #expect(availability.day?[.maghrib]?.time == direct.maghrib.date)
    #expect(availability.coverage == .partial(missing: [.isha: .calculationUnavailable]))
    // The next day keeps its Fajr: the earlier day gives way.
    #expect(source.prayerDay(day.adding(days: 1), at: Places.rovaniemi).day?[.fajr] != nil)
  }

  // MARK: - Failures

  @Test func invalidCoordinatesMakeEveryDayInvalid() {
    let source = CalculationSource(CalculationSettings(method: .muslimWorldLeague))
    let nowhere = PrayerLocation(latitude: 95, longitude: 0, timeZone: .gmt)
    #expect(source.prayerDay(Places.day("2026-06-21"), at: nowhere) == .unavailable(.invalidData))
    let notANumber = PrayerLocation(latitude: .nan, longitude: 0, timeZone: .gmt)
    #expect(
      source.prayerDay(Places.day("2026-06-21"), at: notANumber) == .unavailable(.invalidData))
  }

  @Test func invalidParametersMakeEveryDayInvalid() {
    let source = CalculationSource(
      CalculationSettings(parameters: CalculationParameters(fajr: .angle(-5), isha: .angle(17))))
    #expect(
      source.prayerDay(Places.day("2026-06-21"), at: Places.makkah) == .unavailable(.invalidData))
  }

  @Test func aYearSalahTimesDoesntCalculateIsUnavailable() {
    let source = CalculationSource(CalculationSettings(method: .muslimWorldLeague))
    #expect(
      source.prayerDay(CivilDay(year: 3001, month: 1, day: 1), at: Places.makkah)
        == .unavailable(.calculationUnavailable))
    #expect(
      source.prayerDay(CivilDay(year: 999, month: 12, day: 31), at: Places.makkah)
        == .unavailable(.calculationUnavailable))
    #expect(
      source.prayerDay(CivilDay(year: 3000, month: 12, day: 31), at: Places.makkah).day != nil)
  }

  @Test func anInvalidDateIsInvalidData() {
    let source = CalculationSource(CalculationSettings(method: .muslimWorldLeague))
    #expect(
      source.prayerDay(CivilDay(year: 2026, month: 2, day: 30), at: Places.makkah)
        == .unavailable(.invalidData))
  }

  /// Samoa skipped 30 December 2011 when it crossed the date line.
  @Test func aDateTheZoneSkipsHasNoTimesOfItsOwn() throws {
    let apia = PrayerLocation(
      latitude: -13.8333, longitude: -171.7667, timeZone: Places.zone("Pacific/Apia"))
    let source = CalculationSource(CalculationSettings(method: .muslimWorldLeague))
    #expect(
      source.prayerDay(Places.day("2011-12-30"), at: apia) == .unavailable(.calculationUnavailable))
    #expect(source.prayerDay(Places.day("2011-12-29"), at: apia).coverage == .complete)
    #expect(source.prayerDay(Places.day("2011-12-31"), at: apia).coverage == .complete)
  }

  // MARK: - Ramadan

  /// Umm al-Qura's opt-in 120 minutes: only Isha moves, and only on days in Ramadan.
  @Test func theRamadanRuleMovesOnlyIshaOnRamadanDays() throws {
    let plain = CalculationSource(CalculationSettings(method: .ummAlQura))
    let optedIn = CalculationSource(
      CalculationSettings(
        method: .ummAlQura, ramadanIsha: .interval(minutes: 120, hijriDayOffset: 0)))
    // 2026-03-01 is 12 Ramadan 1447; 2026-04-15 is in Shawwal.
    let ramadan = try #require(plain.prayerDay(Places.day("2026-03-01"), at: Places.makkah).day)
    let longer = try #require(optedIn.prayerDay(Places.day("2026-03-01"), at: Places.makkah).day)
    for kind in PrayerKind.allCases where kind != .isha {
      #expect(longer[kind] == ramadan[kind], "\(kind)")
    }
    let maghrib = try #require(ramadan[.maghrib]?.time)
    #expect(ramadan[.isha]?.time == maghrib.addingTimeInterval(90 * 60))
    #expect(longer[.isha]?.time == maghrib.addingTimeInterval(120 * 60))
    #expect(
      optedIn.prayerDay(Places.day("2026-04-15"), at: Places.makkah)
        == plain.prayerDay(Places.day("2026-04-15"), at: Places.makkah))
  }

  @Test func theRamadanRuleLeavesAnAngleIshaAlone() {
    let plain = CalculationSource(CalculationSettings(method: .muslimWorldLeague))
    let optedIn = CalculationSource(
      CalculationSettings(
        method: .muslimWorldLeague, ramadanIsha: .interval(minutes: 120, hijriDayOffset: 0)))
    #expect(
      optedIn.prayerDay(Places.day("2026-03-01"), at: Places.cairo)
        == plain.prayerDay(Places.day("2026-03-01"), at: Places.cairo))
  }
}
