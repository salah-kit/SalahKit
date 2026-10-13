import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import Testing

/// Calls SalahCalculation's public API from nonisolated code.
///
/// CI also builds the tests with `SALAHKIT_DEFAULT_ISOLATION=MainActor` (RFC 0001, section 6.3).
/// In that build this file compiles only while every public type and member stays nonisolated,
/// which a widget extension's timeline provider, for one, needs.
@Suite struct NonisolatedCalculationAPITests {
  @Test func thePublicAPIIsCallableFromNonisolatedCode() async throws {
    let summary = try await Task.detached { try exerciseCalculationAPI() }.value
    #expect(summary == "ummAlQura | 6 | 43200 | 2026-03-01/isha 20:25")
  }
}

/// A source that declares Jumu'ah on Fridays as the app's policy, wrapping a calculated source.
/// It passes the wrapped source's expected kinds and lead through.
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

nonisolated func exerciseCalculationAPI() throws -> String {
  guard let zone = TimeZone(identifier: "Asia/Riyadh") else { return "" }
  let location = PrayerLocation(
    latitude: 21.4225, longitude: 39.8262, timeZone: zone, countryCode: "SA", name: "Makkah")
  let method = CalculationMethod.suggested(for: location) ?? .muslimWorldLeague
  var settings = CalculationSettings(
    method: method, madhab: .shafi, ramadanIsha: .interval(minutes: 120, hijriDayOffset: 0))
  settings.parameters.rounding = .up
  _ = CalculationSettings(parameters: settings.parameters).hashValue
  let decoded = try JSONDecoder().decode(
    CalculationSettings.self, from: try JSONEncoder().encode(settings))

  let source = CalculationSource(decoded)
  _ = (source.settings, source.hashValue, source == CalculationSource(settings))
  let schedule = PrayerSchedule(
    source: FridayJumuah(base: source), location: location,
    iqama: IqamaRules(rules: [.isha: .after(minutes: 15)]))
  let ramadanDay = CivilDay(year: 2026, month: 3, day: 1)
  _ = source.prayerDay(ramadanDay, at: location)
  guard let isha = schedule.day(ramadanDay).day?[.isha] else { return "" }
  _ = schedule.state(at: isha.time, through: isha.time.addingTimeInterval(86_400))

  let clock = Date.FormatStyle(
    date: .omitted, time: .shortened, locale: Locale(identifier: "en_GB"), timeZone: zone)
  return
    "\(method) | \(source.expectedKinds.count) | \(Int(source.maximumLead.components.seconds))"
    + " | \(isha.scheduleDay)/\(isha.kind) \(isha.time.formatted(clock))"
}
