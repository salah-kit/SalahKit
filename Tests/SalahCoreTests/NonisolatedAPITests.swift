import Foundation
import SalahCore
import Testing

/// Calls the public API from nonisolated code.
///
/// CI also builds the tests with `-default-isolation MainActor` (RFC 0001, section 6.3). In that
/// build this file compiles only while every public type and member stays nonisolated, which is
/// what an app whose targets default to the main actor needs.
@Suite struct NonisolatedAPITests {
  @Test func thePublicAPIIsCallableFromNonisolatedCode() async throws {
    let summary = try await Task.detached { try exercisePublicAPI() }.value
    #expect(summary == "Jumuah 13:30 | Isha | justStarted | 4 | ٢:١٥ | 1448")
  }
}

/// A custom source. In a module that defaults to the main actor, a source must be declared
/// `nonisolated`, as here.
nonisolated struct OneDaySource: PrayerSource {
  let day: PrayerDay

  var expectedKinds: Set<PrayerKind> { Set(day.events.map(\.kind)) }

  func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability {
    day == self.day.day ? .available(self.day, coverage: .complete) : .unavailable(.noPublishedData)
  }
}

nonisolated func exercisePublicAPI() throws -> String {
  guard let zone = TimeZone(identifier: "Europe/London"), let friday = CivilDay("2026-10-16")
  else { return "" }
  let location = PrayerLocation(
    latitude: 55.95, longitude: -3.19, timeZone: zone, countryCode: "GB", name: "Edinburgh")
  _ = (friday.isValid, friday.weekday, friday.description, friday.days(to: friday.adding(days: 1)))
  _ = (friday.interval(in: zone), CivilDay(containing: friday.start(in: zone), in: zone))
  _ = (PrayerKind.allCases.filter(\.isPrayer), PrayerKind.fajr < .isha)

  guard let wall = WallClockTime("13:08") else { return "" }
  _ = (wall.description, wall.isValid, WallClockTime(hour: 0, minute: 20, dayOffset: 1))
  let row = TimetableSource.Row(
    day: friday,
    times: [
      .fajr: .local(WallClockTime(hour: 5, minute: 58)), .dhuhr: .local(wall),
      .asr: .local(WallClockTime(hour: 15, minute: 41)),
      .maghrib: .instant(friday.start(in: zone).addingTimeInterval(18 * 3_600 + 16 * 60)),
      .isha: .local(WallClockTime(hour: 19, minute: 50)),
    ],
    observances: [.dhuhr: .jumuah])
  let source = TimetableSource(
    rows: [row], expectedKinds: [.fajr, .dhuhr, .asr, .maghrib, .isha],
    wallTimeResolution: WallTimeResolution(repeated: .earlier, nonexistent: .nextValid))
  _ = (source.firstDay, source.lastDay, source.rows, source.prayerDay(friday, at: location))
  _ = try JSONDecoder().decode(TimetableSource.self, from: try JSONEncoder().encode(source))

  let rules = IqamaRules(
    rules: [.asr: .after(minutes: 10)], jumuah: .at(WallClockTime(hour: 13, minute: 30)),
    wallTimeResolution: WallTimeResolution())
  let schedule = PrayerSchedule(source: source, location: location, iqama: rules)
  _ = (schedule.source.expectedKinds, schedule.location, schedule.iqama)
  _ = PrayerSchedule.maximumQueryDays
  let availability = schedule.day(friday)
  _ = (availability.coverage, schedule.day(containing: friday.start(in: zone)))
  guard let day = availability.day, let jumuah = day[.dhuhr], let isha = day[.isha] else {
    return ""
  }
  _ = (day.isFriday, day.timeZone, jumuah.id, jumuah.scheduleDay, jumuah.observance)

  let custom = PrayerSchedule(
    source: OneDaySource(day: PrayerDay(day: friday, timeZone: zone, events: day.events)),
    location: location)
  _ = custom.day(friday)

  let names = PrayerNames(locale: Locale(identifier: "en"), overrides: [.name(.isha): "Isha"])
  let clock = Date.FormatStyle(
    date: .omitted, time: .shortened, locale: Locale(identifier: "en_GB"), timeZone: zone)
  let iqamaText = jumuah.iqama.map { $0.formatted(clock) } ?? ""
  _ = (names.locale, names.abbreviation(of: jumuah), names.abbreviation(of: .asr))
  _ = (names.name(of: PrayerKind.fajr), names.string(for: .jumuahAbbreviation))

  let policy = StatePolicy(approaching: .seconds(600), justStarted: .fixed(.seconds(900)))
  let events = schedule.events(from: friday.start(in: zone), through: isha.time)
  _ = (events.events, events.coverage.requested, events.coverage.knownIntervals)
  _ = events.coverage.gaps.map { ($0.interval, $0.day, $0.kinds, $0.reason) }
  let state = schedule.state(
    at: isha.time.addingTimeInterval(60), through: isha.time.addingTimeInterval(86_400),
    policy: policy)
  _ = (state.coverage.isComplete, state.changesAt)
  guard let prayerState = state.prayerState, let current = prayerState.justStarted else {
    return ""
  }
  _ = (prayerState.date, prayerState.previous, prayerState.latestPrayer, prayerState.next)
  _ = (prayerState.nextPrayer, prayerState.isApproaching, prayerState.changesAt)
  let status: String
  switch prayerState.status(of: current) {
  case .justStarted: status = "justStarted"
  case .passed, .next, .upcoming: status = "other"
  }

  let plan = try schedule.refreshPlan(
    from: friday.start(in: zone).addingTimeInterval(12 * 3_600), through: isha.time,
    strategy: .steps(fine: .seconds(300), coarse: .seconds(3_600), window: .seconds(900)),
    policy: policy, limit: 4)
  _ = (plan.horizon, plan.validUntil, plan.isTruncated, plan.dates, plan.entries.map(\.state))
  let failure = Result { () throws(RefreshPlanError) -> RefreshPlan in
    try schedule.refreshPlan(from: isha.time, through: isha.time)
  }
  if case .failure(let error) = failure { _ = error == .nonPositiveHorizon }

  let arabic = PrayerLocale.resolved("ar")
  _ = PrayerLocale.resolved(Locale(identifier: "ur"))
  let duration = PrayerDurationFormat.string(
    8_130, direction: .remaining, width: .compact, locale: arabic, bidiIsolated: false)
  let hijri = HijriDateFormat(
    locale: arabic, timeZone: zone, dayOffset: 0, calendar: .islamicUmmAlQura)
  _ = hijri.string(from: jumuah.time, template: "dMMMMy")
  let components = hijri.components(of: jumuah.time)
  _ = HijriDateFormat.Components(year: components.year, month: components.month, day: 1)

  return
    "\(names.name(of: jumuah)) \(iqamaText) | \(names.name(of: current)) | \(status) | "
    + "\(plan.entries.count + 1) | \(duration) | \(components.year)"
}
