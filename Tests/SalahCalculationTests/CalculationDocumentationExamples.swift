import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import Testing

/// The calculation code of README.md and of the article "A calculated prayer app with Core and
/// Calculation", compiled and run against the public API only.
///
/// `CalculationDocumentationTests` checks that every such Swift block appears here line for
/// line, so an edit to a document that isn't mirrored here fails the tests.
@Suite struct CalculationDocumentationExamples {
  @Test func readmeQuickStart() throws {
    guard let zone = TimeZone(identifier: "Europe/Istanbul") else { return }
    let istanbul = PrayerLocation(
      latitude: 41.0082, longitude: 28.9784, timeZone: zone, countryCode: "TR", name: "Istanbul")

    // Diyanet's method, which SalahTimes suggests for Turkey, with Hanafi Asr.
    let settings = CalculationSettings(
      method: CalculationMethod.suggested(for: istanbul) ?? .muslimWorldLeague, madhab: .hanafi)
    let schedule = PrayerSchedule(source: CalculationSource(settings), location: istanbul)

    let today = CivilDay(containing: Date(), in: zone)
    if case .available(let day, _) = schedule.day(today) {
      let clock = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)
      for event in day.events {
        print(event.kind, event.time.formatted(clock))
      }
    }

    var expected = CalculationMethod.diyanet.parameters
    expected.madhab = .hanafi
    #expect(settings.parameters == expected)
    #expect(schedule.day(today).coverage == .complete)
    let march = schedule.day(CivilDay(year: 2026, month: 3, day: 20))
    #expect(march.coverage == .complete)
    #expect(march.day?.events.map(\.kind) == PrayerKind.allCases)
  }

  @Test func calculatedAppArticle() throws {
    // Choose the settings
    var settings = CalculationSettings(method: .muslimWorldLeague, madhab: .hanafi)
    settings.parameters.highLatitudeRule = .seventhOfTheNight
    settings.parameters.adjustments.isha = 2

    #expect(settings.parameters.fajr == .angle(18))
    #expect(settings.parameters.madhab == .hanafi)
    #expect(settings.parameters.adjustments == PrayerAdjustments(isha: 2))

    guard let zone = TimeZone(identifier: "Asia/Riyadh") else { return }
    let location = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262, timeZone: zone, countryCode: "SA", name: "Makkah")

    let method = CalculationMethod.suggested(for: location) ?? .muslimWorldLeague  // .ummAlQura
    let makkah = CalculationSettings(
      method: method, ramadanIsha: .interval(minutes: 120, hijriDayOffset: 0))

    #expect(method == .ummAlQura)
    #expect(makkah.parameters.isha == .minutesAfterMaghrib(90))

    let saved = try JSONEncoder().encode(makkah)
    let restored = try JSONDecoder().decode(CalculationSettings.self, from: saved)

    #expect(restored == makkah)

    // Build the schedule
    let schedule = PrayerSchedule(source: CalculationSource(restored), location: location)

    // Show today and what's next
    let names = PrayerNames(locale: Locale(identifier: "en_GB"))
    let clock = Date.FormatStyle(
      date: .omitted, time: .shortened, locale: names.locale, timeZone: location.timeZone)

    func headline(at now: Date) -> String {
      switch schedule.state(at: now, through: now.addingTimeInterval(2 * 86_400)) {
      case .available(let state, _):
        guard let next = state.nextPrayer else { return "The next prayer can't be calculated" }
        let remaining = PrayerDurationFormat.string(
          next.time.timeIntervalSince(now), locale: names.locale)
        return "\(names.name(of: next)) at \(next.time.formatted(clock)), in \(remaining)"
      case .unavailable:
        return "Prayer times can't be calculated here now"
      }
    }

    // 1 March 2026 is in Ramadan, so the opted-in Isha is 120 minutes after Maghrib.
    #expect(headline(at: try instant("2026-03-01T12:00:00+03:00")) == "Dhuhr at 12:33, in 33m")
    #expect(headline(at: try instant("2026-03-01T19:00:00+03:00")) == "Isha at 20:25, in 1:25")

    // Across midnight
    func row(_ event: PrayerEvent) -> String {
      let date = CivilDay(containing: event.time, in: location.timeZone)
      var note = ""
      if date > event.scheduleDay { note = " (next day)" }
      if date < event.scheduleDay { note = " (previous evening)" }
      return "\(names.name(of: event)) \(event.time.formatted(clock))\(note)"
    }

    let ramadanDay = try #require(schedule.day(CivilDay(year: 2026, month: 3, day: 1)).day)
    #expect(ramadanDay.events.map(row).last == "Isha 20:25")

    // When a time can't be calculated
    func lines(for day: CivilDay) -> [String] {
      switch schedule.day(day) {
      case .available(let prayerDay, let coverage):
        var missing: [PrayerKind: ScheduleGapReason] = [:]
        if case .partial(let kinds) = coverage { missing = kinds }
        return PrayerKind.allCases.map { kind in
          if let event = prayerDay[kind] { return row(event) }
          let reason = missing[kind] == .invalidData ? "invalid input" : "can't be calculated"
          return "\(names.name(of: kind)): \(reason)"
        }
      case .unavailable(let reason):
        return ["No prayer times for this day (\(reason))"]
      }
    }

    #expect(lines(for: CivilDay(year: 2026, month: 3, day: 1)).count == 6)
    #expect(
      lines(for: CivilDay(year: 3001, month: 1, day: 1))
        == ["No prayer times for this day (calculationUnavailable)"])

    // Jumu'ah and iqama are your app's policy
    let mosque = PrayerSchedule(
      source: FridayJumuah(base: CalculationSource(restored)), location: location,
      iqama: IqamaRules(
        rules: [.fajr: .after(minutes: 20), .isha: .after(minutes: 15)],
        jumuah: .at(WallClockTime(hour: 12, minute: 45))))

    let friday = try #require(mosque.day(CivilDay(year: 2026, month: 3, day: 6)).day)
    #expect(friday[.dhuhr]?.observance == .jumuah)
    #expect(friday[.dhuhr].map(names.name(of:)) == "Jumuah")
    #expect(friday[.dhuhr]?.iqama == (try instant("2026-03-06T12:45:00+03:00")))
    let thursday = try #require(mosque.day(CivilDay(year: 2026, month: 3, day: 5)).day)
    #expect(thursday[.dhuhr]?.observance == .ordinary)
    #expect(thursday[.dhuhr]?.iqama == nil)
    #expect(
      thursday[.fajr]?.iqama == thursday[.fajr].map { $0.time.addingTimeInterval(20 * 60) })
  }

  /// The article's cases across midnight and at a polar day, with the article's code.
  @Test func articleCasesElsewhere() throws {
    let names = PrayerNames(locale: Locale(identifier: "en_GB"))

    // Kashgar: Isha after midnight belongs to the day before.
    var location = PrayerLocation(
      latitude: 39.4704, longitude: 75.9898, timeZone: Places.zone("Asia/Shanghai"))
    var schedule = PrayerSchedule(
      source: CalculationSource(CalculationSettings(method: .muslimWorldLeague)),
      location: location)
    var clock = Date.FormatStyle(
      date: .omitted, time: .shortened, locale: names.locale, timeZone: location.timeZone)

    func row(_ event: PrayerEvent) -> String {
      let date = CivilDay(containing: event.time, in: location.timeZone)
      var note = ""
      if date > event.scheduleDay { note = " (next day)" }
      if date < event.scheduleDay { note = " (previous evening)" }
      return "\(names.name(of: event)) \(event.time.formatted(clock))\(note)"
    }

    let kashgarDay = try #require(schedule.day(CivilDay(year: 2026, month: 6, day: 21)).day)
    let isha = try #require(kashgarDay[.isha])
    #expect(isha.time == (try instant("2026-06-22T00:19:00+08:00")))
    #expect(row(isha) == "Isha \(isha.time.formatted(clock)) (next day)")
    let afterMidnight = try instant("2026-06-22T00:05:00+08:00")
    let kashgarState = schedule.state(at: afterMidnight, through: afterMidnight + 2 * 86_400)
    #expect(kashgarState.prayerState?.nextPrayer?.id == kashgarDay[.isha]?.id)

    // Kazan, middle of the night: Fajr before midnight belongs to the day after.
    location = PrayerLocation(
      latitude: 55.7963, longitude: 49.1088, timeZone: Places.zone("Europe/Moscow"))
    var middle = CalculationMethod.muslimWorldLeague.parameters
    middle.highLatitudeRule = .middleOfTheNight
    schedule = PrayerSchedule(
      source: CalculationSource(CalculationSettings(parameters: middle)), location: location)
    clock = Date.FormatStyle(
      date: .omitted, time: .shortened, locale: names.locale, timeZone: location.timeZone)
    let kazanDay = try #require(schedule.day(CivilDay(year: 2026, month: 6, day: 21)).day)
    let fajr = try #require(kazanDay[.fajr])
    #expect(fajr.time == (try instant("2026-06-20T23:45:00+03:00")))
    #expect(row(fajr) == "Fajr 23:45 (previous evening)")

    // Tromsø on 21 June: Dhuhr and Asr only.
    location = PrayerLocation(
      latitude: 69.6492, longitude: 18.9553, timeZone: Places.zone("Europe/Oslo"))
    schedule = PrayerSchedule(
      source: CalculationSource(CalculationSettings(method: .muslimWorldLeague)),
      location: location)
    clock = Date.FormatStyle(
      date: .omitted, time: .shortened, locale: names.locale, timeZone: location.timeZone)

    func lines(for day: CivilDay) -> [String] {
      switch schedule.day(day) {
      case .available(let prayerDay, let coverage):
        var missing: [PrayerKind: ScheduleGapReason] = [:]
        if case .partial(let kinds) = coverage { missing = kinds }
        return PrayerKind.allCases.map { kind in
          if let event = prayerDay[kind] { return row(event) }
          let reason = missing[kind] == .invalidData ? "invalid input" : "can't be calculated"
          return "\(names.name(of: kind)): \(reason)"
        }
      case .unavailable(let reason):
        return ["No prayer times for this day (\(reason))"]
      }
    }

    #expect(
      lines(for: CivilDay(year: 2026, month: 6, day: 21)) == [
        "Fajr: can't be calculated", "Sunrise: can't be calculated", "Dhuhr 12:46",
        "Asr 17:58", "Maghrib: can't be calculated", "Isha: can't be calculated",
      ])
  }

  private func instant(_ text: String) throws -> Date {
    try Date(text, strategy: .iso8601)
  }
}

/// The article's Jumu'ah source.
nonisolated struct FridayJumuah: PrayerSource {
  let base: CalculationSource

  var expectedKinds: Set<PrayerKind> { base.expectedKinds }
  var maximumLead: Duration { base.maximumLead }

  func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability {
    let availability = base.prayerDay(day, at: location)
    guard day.weekday == 6, case .available(var prayerDay, let coverage) = availability else {
      return availability
    }
    prayerDay.events = prayerDay.events.map { event in
      var event = event
      if event.kind == .dhuhr { event.observance = .jumuah }
      return event
    }
    return .available(prayerDay, coverage: coverage)
  }
}
