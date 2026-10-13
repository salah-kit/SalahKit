import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import Testing

/// `CalculationSettings` holds SalahTimes' parameters whole (RFC 0002, section 3).
@Suite struct CalculationSettingsTests {
  /// Every field changed from its method's value.
  static let customized: CalculationParameters = {
    var parameters = CalculationMethod.ummAlQura.parameters
    parameters.fajr = .angle(19.25)
    parameters.maghrib = .angle(4.5)
    parameters.isha = .minutesAfterMaghrib(75)
    parameters.madhab = .hanafi
    parameters.highLatitudeRule = .twilightAngle
    parameters.nightSpan = .sunsetToSunrise
    parameters.methodAdjustments = PrayerAdjustments(sunrise: -2, dhuhr: 3)
    parameters.adjustments = PrayerAdjustments(fajr: 2, asr: -1, isha: 5)
    parameters.rounding = .none
    parameters.ramadanIsha = .interval(minutes: 105, hijriDayOffset: 1)
    return parameters
  }()

  @Test func parametersAreKeptExactlyAsGiven() {
    let settings = CalculationSettings(parameters: Self.customized)
    #expect(settings.parameters == Self.customized)
    #expect(CalculationSource(settings).settings.parameters == Self.customized)
  }

  @Test func aMethodGivesItsParametersWithTheMadhab() {
    let settings = CalculationSettings(method: .diyanet, madhab: .hanafi)
    var expected = CalculationMethod.diyanet.parameters
    expected.madhab = .hanafi
    #expect(settings.parameters == expected)
    #expect(
      CalculationSettings(method: .karachi).parameters == CalculationMethod.karachi.parameters)
  }

  @Test(arguments: CalculationMethod.allCases)
  func everyMethodRoundTrips(_ method: CalculationMethod) throws {
    let settings = CalculationSettings(method: method, madhab: .hanafi)
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(CalculationSettings.self, from: data) == settings)
  }

  @Test func customizedSettingsRoundTripInSalahTimesJSON() throws {
    let settings = CalculationSettings(parameters: Self.customized)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(settings)
    #expect(try JSONDecoder().decode(CalculationSettings.self, from: data) == settings)

    // The parameters inside are SalahTimes' own JSON, so its documentation describes them.
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object.keys.sorted() == ["parameters"])
    let inner = try JSONSerialization.data(withJSONObject: try #require(object["parameters"]))
    #expect(try JSONDecoder().decode(CalculationParameters.self, from: inner) == Self.customized)
  }

  @Test func settingsSavedWithOnlyTheRequiredParametersDecodeWithDefaults() throws {
    let json = Data(#"{"parameters": {"fajr": {"angle": 18}, "isha": {"angle": 17}}}"#.utf8)
    let settings = try JSONDecoder().decode(CalculationSettings.self, from: json)
    #expect(settings == CalculationSettings(method: .muslimWorldLeague))
  }

  @Test func equalSettingsHashAlike() {
    let first = CalculationSettings(parameters: Self.customized)
    let second = CalculationSettings(parameters: Self.customized)
    #expect(first == second && first.hashValue == second.hashValue)
    #expect(Set([first, second, CalculationSettings(method: .egyptian)]).count == 2)
    #expect(CalculationSource(first) == CalculationSource(second))
  }

  /// The opt-in sets `ramadanIsha` and nothing else.
  @Test func theRamadanOptInChangesOnlyItsOwnField() {
    let rule = RamadanIshaRule.interval(minutes: 120, hijriDayOffset: 0)
    let plain = CalculationSettings(method: .ummAlQura)
    var optedIn = CalculationSettings(method: .ummAlQura, ramadanIsha: rule)
    #expect(optedIn.parameters.ramadanIsha == rule)
    #expect(plain.parameters.ramadanIsha == .off)
    optedIn.parameters.ramadanIsha = .off
    #expect(optedIn == plain)
  }

  @Test func suggestionsComeFromSalahTimesByCountry() {
    #expect(CalculationMethod.suggested(for: Places.istanbul) == .diyanet)
    #expect(CalculationMethod.suggested(for: Places.makkah) == .ummAlQura)
    var singapore = Places.equator
    singapore.countryCode = "sg"
    #expect(CalculationMethod.suggested(for: singapore) == .muis)
    // No source for a suggestion, or no country: no suggestion.
    #expect(CalculationMethod.suggested(for: Places.london) == nil)
    #expect(CalculationMethod.suggested(for: Places.equator) == nil)
  }
}
