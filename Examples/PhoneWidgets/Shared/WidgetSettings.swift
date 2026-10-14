import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import SalahWidgets

/// The identifiers the app and the extension share.
nonisolated enum PhoneWidgetsID {
  /// The App Group both targets declare in their entitlements.
  static let appGroup = "group.io.github.salah-kit.PhoneWidgets"
  /// The widget's kind, which the app names when it asks WidgetKit for a reload.
  static let widgetKind = "io.github.salah-kit.PhoneWidgets.prayers"
  /// The `os.Logger` subsystem of both targets.
  static let logSubsystem = "io.github.salah-kit.PhoneWidgets"
}

/// The language of the widget's prayer names and wording.
nonisolated enum NamesLanguage: String, Codable, CaseIterable, Hashable, Sendable {
  case english = "en"
  case arabic = "ar"

  /// The device's language when the app or the extension has a translation for it, otherwise
  /// English: the language of the setup prompt, before the user has chosen one.
  static var device: NamesLanguage {
    Bundle.main.preferredLocalizations.first.flatMap {
      NamesLanguage(rawValue: Locale(identifier: $0).language.languageCode?.identifier ?? "")
    } ?? .english
  }
}

/// Everything the widget needs, saved by the app and read by the extension.
///
/// The extension builds its own schedule from these inputs on every timeline, so the widget keeps
/// going for as long as WidgetKit asks, without the app running.
nonisolated struct WidgetSettings: Codable, Hashable, Sendable {
  /// Where to calculate.
  var place: Place
  /// The published method the calculation starts from, shown in the app's picker.
  var method: CalculationMethod
  /// SalahCalculation's settings, passed to the calculation unchanged.
  var calculation: CalculationSettings
  /// The language of the names and the wording, whatever the device's language.
  var language: NamesLanguage

  /// Settings for a place, a method's parameters and a language.
  init(place: Place, method: CalculationMethod, language: NamesLanguage) {
    self.place = place
    self.method = method
    calculation = CalculationSettings(method: method)
    self.language = language
  }

  /// Makkah with Umm al-Qura, in English: what the app offers first.
  static let defaults = WidgetSettings(place: .makkah, method: .ummAlQura, language: .english)

  /// The methods the app offers.
  static let methods: [CalculationMethod] = [
    .ummAlQura, .muslimWorldLeague, .egyptian, .isna, .karachi,
  ]

  /// Switches to another published method, replacing the calculation's parameters with its own.
  mutating func choose(_ method: CalculationMethod) {
    self.method = method
    calculation = CalculationSettings(method: method)
  }

  /// The schedule these settings calculate.
  var schedule: PrayerSchedule {
    PrayerSchedule(source: CalculationSource(calculation), location: place.location)
  }

  /// A short, stable fingerprint of the stored value, for the diagnostics log: the 64-bit FNV-1a
  /// hash of its JSON with sorted keys, as 16 hexadecimal digits. Swift's `hashValue` changes
  /// from process to process, so it can't tell the app's value from the extension's.
  var fingerprint: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(self)) ?? Data()
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in data {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    let hex = String(hash, radix: 16)
    return String(repeating: "0", count: 16 - hex.count) + hex
  }

  /// The settings in a few words, for the diagnostics log: `makkah · ummAlQura · ar`.
  var summary: String {
    "\(place.id) · \(method.rawValue) · \(language.rawValue)"
  }
}

extension SharedValue where Value == WidgetSettings {
  /// The settings in the App Group. The app is the only writer; the extension reads them.
  ///
  /// The key carries a version: a later shape gets a new key, and a stored value that no longer
  /// decodes reads as no settings, which the widget shows as setup required.
  nonisolated static var widgetSettings: Self {
    SharedValue(appGroup: PhoneWidgetsID.appGroup, key: "settings.v1")
  }
}

/// Where the widget calculates: a preset.
///
/// The app reads no location services. A real app would get coordinates from Core Location and a
/// time zone from a geocoder; this one keeps the location an explicit input, as SalahCore does.
nonisolated struct Place: Codable, Hashable, Identifiable, Sendable {
  /// The preset's identifier, also its `-place` launch argument.
  var id: String
  var location: PrayerLocation

  static let makkah = Place(
    id: "makkah", latitude: 21.4225, longitude: 39.8262, zone: "Asia/Riyadh", country: "SA",
    name: "Makkah")
  static let london = Place(
    id: "london", latitude: 51.5074, longitude: -0.1278, zone: "Europe/London", country: "GB",
    name: "London")
  /// North of the Arctic Circle: around midsummer the Sun doesn't set, so Fajr, sunrise,
  /// Maghrib and Isha can't be calculated and the days are partial.
  static let tromso = Place(
    id: "tromso", latitude: 69.6492, longitude: 18.9553, zone: "Europe/Oslo", country: "NO",
    name: "Tromsø")
  /// A latitude beyond the pole, to show how the widget reports input SalahTimes rejects.
  static let invalid = Place(
    id: "invalid", latitude: 95, longitude: 0, zone: "UTC", country: nil,
    name: "Invalid coordinates")

  static let presets: [Place] = [makkah, london, tromso, invalid]

  /// The preset with this identifier.
  static func preset(_ id: String) -> Place? {
    presets.first { $0.id == id }
  }

  private init(
    id: String, latitude: Double, longitude: Double, zone: String, country: String?,
    name: String
  ) {
    self.id = id
    location = PrayerLocation(
      latitude: latitude, longitude: longitude,
      // Every identifier above is in every tz database; GMT only guards a broken system.
      timeZone: TimeZone(identifier: zone) ?? .gmt, countryCode: country, name: name)
  }
}
