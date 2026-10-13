import Foundation
import SalahCalculation
import SalahCore
import SalahTimes

/// The calculation method the user chose: a published one, or Custom.
nonisolated enum MethodChoice: Hashable, Sendable, RawRepresentable, Codable {
  case preset(CalculationMethod)
  case custom

  /// Every published method, then Custom.
  static let all: [MethodChoice] = CalculationMethod.allCases.map(MethodChoice.preset) + [.custom]

  /// `custom`, or the method's raw value (`ummAlQura`).
  init?(rawValue: String) {
    if rawValue == "custom" {
      self = .custom
    } else if let method = CalculationMethod(rawValue: rawValue) {
      self = .preset(method)
    } else {
      return nil
    }
  }

  var rawValue: String {
    switch self {
    case .preset(let method): method.rawValue
    case .custom: "custom"
    }
  }
}

/// Everything the user sets: the place and the calculation.
///
/// The app stores it as JSON in `UserDefaults`; `calculation` is SalahCalculation's own
/// `Codable` value, so the stored JSON holds SalahTimes' parameters whole.
///
/// A method defines Fajr, Maghrib and Isha, the night span, its own adjustments and the
/// rounding. Changing any of them switches to Custom, so the method shown is always exact. The
/// madhab, the high-latitude rule, the user's adjustments and the Ramadan rule are the user's
/// own, and stay when the method changes.
nonisolated struct AppSettings: Codable, Hashable, Sendable {
  var place: Place
  var method: MethodChoice
  var calculation: CalculationSettings

  /// Makkah with Umm al-Qura, the method SalahTimes suggests for Saudi Arabia.
  static let defaults = AppSettings(
    place: .makkah, method: .preset(.ummAlQura),
    calculation: CalculationSettings(method: .ummAlQura))

  /// The schedule these settings calculate.
  var schedule: PrayerSchedule {
    PrayerSchedule(source: CalculationSource(calculation), location: place.location)
  }

  /// SalahTimes' suggested method for the place's country, if it has one.
  var suggestedMethod: CalculationMethod? {
    CalculationMethod.suggested(for: place.location)
  }

  /// Chooses a method. A published one replaces the parameters it defines and keeps the user's
  /// own; Custom keeps every parameter as it is.
  mutating func choose(_ choice: MethodChoice) {
    method = choice
    guard case .preset(let preset) = choice else { return }
    let own = calculation.parameters
    var settings = CalculationSettings(
      method: preset, madhab: own.madhab, ramadanIsha: own.ramadanIsha)
    settings.parameters.highLatitudeRule = own.highLatitudeRule
    settings.parameters.adjustments = own.adjustments
    calculation = settings
  }

  /// Changes a parameter that methods define, and so switches to Custom.
  mutating func customize(_ change: (inout CalculationParameters) -> Void) {
    change(&calculation.parameters)
    method = .custom
  }

  /// The JSON the app stores.
  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }

  /// Decodes stored settings, or returns `nil` for data that isn't settings.
  static func decoded(from data: Data) -> AppSettings? {
    try? JSONDecoder().decode(AppSettings.self, from: data)
  }
}

/// The settings the app shows, saved to `UserDefaults` on every change.
@MainActor
@Observable
final class SettingsStore {
  /// The `UserDefaults` key of the stored JSON.
  static let key = "CalculatedPhone.settings"

  private(set) var settings: AppSettings
  /// The JSON last written, shown in Settings.
  private(set) var savedJSON = ""
  @ObservationIgnored private let defaults: UserDefaults

  /// Loads the stored settings (or the defaults), applies the launch arguments and saves the
  /// result.
  init(defaults: UserDefaults = .standard, options: LaunchOptions) {
    if options.resetSettings {
      defaults.removeObject(forKey: Self.key)
    }
    var settings = defaults.data(forKey: Self.key).flatMap(AppSettings.decoded) ?? .defaults
    options.apply(to: &settings)
    self.defaults = defaults
    self.settings = settings
    save()
  }

  /// Changes the settings and saves them.
  func update(_ change: (inout AppSettings) -> Void) {
    var settings = settings
    change(&settings)
    guard settings != self.settings else { return }
    self.settings = settings
    save()
  }

  private func save() {
    guard let data = try? settings.encoded() else { return }
    defaults.set(data, forKey: Self.key)
    savedJSON = String(decoding: data, as: UTF8.self)
  }
}
