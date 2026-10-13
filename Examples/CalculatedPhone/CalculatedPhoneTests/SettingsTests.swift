import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import Testing

@testable import CalculatedPhone

/// Choosing methods, persisting settings and reading launch arguments.
struct SettingsTests {
  // MARK: Methods

  @Test func choosingAMethodKeepsTheUsersOwnChoices() {
    var settings = AppSettings.defaults
    settings.calculation.parameters.madhab = .hanafi
    settings.calculation.parameters.highLatitudeRule = .seventhOfTheNight
    settings.calculation.parameters.adjustments.isha = 3
    settings.calculation.parameters.ramadanIsha = AppSettings.ramadanRule

    settings.choose(.preset(.muis))
    #expect(settings.method == .preset(.muis))
    var expected = CalculationMethod.muis.parameters
    expected.madhab = .hanafi
    expected.highLatitudeRule = .seventhOfTheNight
    expected.adjustments.isha = 3
    expected.ramadanIsha = AppSettings.ramadanRule
    #expect(settings.calculation.parameters == expected)
    // MUIS rounds up; the method brings its rounding.
    #expect(settings.calculation.parameters.rounding == .up)
  }

  @Test func customKeepsEveryParameter() {
    var settings = AppSettings.defaults
    let before = settings.calculation
    settings.choose(.custom)
    #expect(settings.method == .custom)
    #expect(settings.calculation == before)
  }

  @Test func aMethodsParameterSwitchesToCustom() {
    var settings = AppSettings.defaults
    settings.customize { $0.rounding = .up }
    #expect(settings.method == .custom)
    #expect(settings.calculation.parameters.rounding == .up)
  }

  @Test func methodChoiceRawValues() {
    #expect(MethodChoice(rawValue: "custom") == .custom)
    #expect(MethodChoice(rawValue: "ummAlQura") == .preset(.ummAlQura))
    #expect(MethodChoice(rawValue: "nope") == nil)
    #expect(MethodChoice.all.count == CalculationMethod.allCases.count + 1)
    #expect(MethodChoice.all.last == .custom)
  }

  @Test func suggestedMethod() {
    #expect(AppSettings.defaults.suggestedMethod == .ummAlQura)
    var settings = AppSettings.defaults
    settings.place = .invalid
    #expect(settings.suggestedMethod == nil)
  }

  // MARK: Persistence

  @Test func settingsRoundTripAsJSON() throws {
    var settings = AppSettings.defaults
    settings.place = .kazan
    settings.choose(.preset(.moonsightingCommittee))
    settings.customize {
      $0.isha = .moonsightingCommittee(.abyad)
      $0.nightSpan = .sunsetToSunrise
      $0.rounding = .none
    }
    settings.calculation.parameters.madhab = .hanafi
    settings.calculation.parameters.adjustments = PrayerAdjustments(fajr: -2, maghrib: 1)
    settings.calculation.parameters.ramadanIsha = AppSettings.ramadanRule

    let data = try settings.encoded()
    #expect(AppSettings.decoded(from: data) == settings)

    // The calculation is SalahCalculation's own JSON: {"parameters": SalahTimes' JSON}.
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let calculation = try #require(object["calculation"] as? [String: Any])
    let parameters = try #require(calculation["parameters"] as? [String: Any])
    #expect(parameters["fajr"] as? String == "moonsightingCommittee")
    #expect(parameters["madhab"] as? String == "hanafi")
    #expect(object["method"] as? String == "custom")
  }

  @Test func dataThatIsntSettingsIsIgnored() {
    #expect(AppSettings.decoded(from: Data("{}".utf8)) == nil)
    #expect(AppSettings.decoded(from: Data("not json".utf8)) == nil)
  }

  @MainActor
  @Test func theStoreSavesAndReloads() throws {
    let suite = "CalculatedPhoneTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = SettingsStore(defaults: defaults, options: LaunchOptions())
    #expect(store.settings == .defaults)
    store.update {
      $0.place = .london
      $0.calculation.parameters.madhab = .hanafi
    }
    #expect(store.savedJSON.contains("\"hanafi\""))

    let reloaded = SettingsStore(defaults: defaults, options: LaunchOptions())
    #expect(reloaded.settings.place == .london)
    #expect(reloaded.settings.calculation.parameters.madhab == .hanafi)

    var reset = LaunchOptions()
    reset.resetSettings = true
    #expect(SettingsStore(defaults: defaults, options: reset).settings == .defaults)
  }

  // MARK: Launch arguments

  @Test func launchArguments() throws {
    let options = LaunchOptions(arguments: [
      "CalculatedPhone", "-now", "2026-06-22T00:05:00+08:00", "-frozen", "-language", "ar",
      "-resetSettings", "-place", "kashgar", "-method", "muslimWorldLeague", "-madhab", "hanafi",
      "-highLatitudeRule", "middleOfTheNight", "-rounding", "up", "-fajrAngle", "16.5",
      "-ishaAngle", "15", "-ramadanIsha", "on",
    ])
    #expect(options.now == (try Date("2026-06-22T00:05:00+08:00", strategy: .iso8601)))
    #expect(options.frozen)
    #expect(options.language == "ar")
    #expect(options.resetSettings)
    #expect(options.place == .kashgar)

    var settings = AppSettings.defaults
    options.apply(to: &settings)
    #expect(settings.place == .kashgar)
    #expect(settings.method == .custom)
    var expected = CalculationMethod.muslimWorldLeague.parameters
    expected.madhab = .hanafi
    expected.highLatitudeRule = .middleOfTheNight
    expected.rounding = .up
    expected.fajr = .angle(16.5)
    expected.isha = .angle(15)
    expected.ramadanIsha = AppSettings.ramadanRule
    #expect(settings.calculation.parameters == expected)
  }

  @Test func launchCoordinates() throws {
    let options = LaunchOptions(arguments: [
      "-latitude", "39.4704", "-longitude", "75.9898", "-timeZone", "Asia/Shanghai",
      "-countryCode", "CN", "-placeName", "Kashi",
    ])
    let place = try #require(options.place)
    #expect(place.id == Place.customID)
    #expect(
      place.location
        == PrayerLocation(
          latitude: 39.4704, longitude: 75.9898,
          timeZone: try #require(TimeZone(identifier: "Asia/Shanghai")),
          countryCode: "CN", name: "Kashi"))
  }

  @Test func unreadableArgumentsAreIgnored() {
    let options = LaunchOptions(arguments: [
      "-now", "yesterday", "-place", "atlantis", "-method", "astrology", "-madhab", "maliki",
      "-fajrAngle", "nan", "-latitude", "1", "-longitude", "2", "-timeZone", "Mars/Olympus",
      "-ramadanIsha", "maybe",
    ])
    #expect(options == LaunchOptions())
    var settings = AppSettings.defaults
    options.apply(to: &settings)
    #expect(settings == .defaults)
  }

  @Test func theClock() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let launch = Date(timeIntervalSince1970: 2_000_000)
    let later = launch.addingTimeInterval(90)
    #expect(AppClock(start: start, launch: launch).now(at: later) == start.addingTimeInterval(90))
    #expect(AppClock(start: start, launch: launch, frozen: true).now(at: later) == start)
    #expect(AppClock(launch: launch, frozen: true).now(at: later) == later)
  }
}
