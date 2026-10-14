import Foundation
import SalahAlerts
import SalahCalculation
import SalahCore
import SalahTimes
import SalahWidgets

/// Everything the app's display, its alerts and the widget need, saved by the app.
///
/// The widget extension builds its own schedule from these inputs on every timeline.
nonisolated struct MenuBarSettings: Codable, Hashable, Sendable {
  /// Where to calculate.
  var place: Place
  /// The published method the calculation starts from.
  var method: CalculationMethod
  /// SalahCalculation's settings, passed to the calculation unchanged.
  var calculation: CalculationSettings
  /// The language of the names and the wording.
  var language: NamesLanguage
  /// The app's alerts.
  var alerts: AlertPreferences

  /// Settings for a place, a method's parameters and a language, with alerts off.
  init(
    place: Place, method: CalculationMethod, language: NamesLanguage,
    alerts: AlertPreferences = AlertPreferences()
  ) {
    self.place = place
    self.method = method
    calculation = CalculationSettings(method: method)
    self.language = language
    self.alerts = alerts
  }

  /// Makkah with Umm al-Qura, in English, alerts off: what the app starts with.
  static let defaults = MenuBarSettings(place: .makkah, method: .ummAlQura, language: .english)

  /// The methods the app offers.
  static let methods: [CalculationMethod] = [
    .ummAlQura, .muslimWorldLeague, .egyptian, .diyanet, .isna,
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
}

nonisolated extension SharedValue where Value == MenuBarSettings {
  /// The settings in the App Group. The app is the only writer.
  ///
  /// The key carries a version: a later shape gets a new key, and a stored value that no longer
  /// decodes reads as no settings, which the widget shows as setup required.
  static var menuBarSettings: Self {
    SharedValue(appGroup: MenuBarID.appGroup, key: "settings.v1")
  }
}

/// Which alerts the app gives, and how.
nonisolated struct AlertPreferences: Codable, Hashable, Sendable {
  /// Whether the app alerts at all. Off until the user turns alerts on; the app asks for
  /// notification permission then.
  var enabled = false
  /// The reminder before each prayer, in minutes, or `nil` for none.
  var reminderMinutes: Int? = 10
  /// The reminders the app offers, in minutes.
  static let reminderChoices = [5, 10, 15, 30]
  /// Whether the app plays its tone for alerts. Without it, notifications use the system sound.
  var playsTone = true

  /// The settings of one prayer's alerts: at its time and, if chosen, a reminder before it.
  /// Sunrise isn't a prayer, so it gets none.
  func settings(for subject: AlertSubject) -> AlertSettings? {
    guard enabled, subject.prayer.isPrayer else { return nil }
    let sound: AlertSound = playsTone ? .named(MenuBarTone.soundName) : .system
    return AlertSettings(
      atTime: true, before: reminderMinutes.map { .seconds($0 * 60) }, sound: sound,
      beforeSound: sound)
  }
}

/// The name the app's generated tone goes by in `AlertSound.named(_:)`.
nonisolated enum MenuBarTone {
  /// An `AlertSound.named` value with this name means the app plays its own tone. No file has
  /// this name: notifications for such alerts carry no sound, and the running app plays the tone.
  static let soundName = "menubar-tone"
}

/// The language of the names and the wording.
nonisolated enum NamesLanguage: String, Codable, CaseIterable, Hashable, Sendable {
  case english = "en"
  case arabic = "ar"

  /// The locale with the language's own digits.
  var locale: Locale { PrayerLocale.resolved(rawValue) }

  /// Whether the language is written right to left.
  var isRightToLeft: Bool { self == .arabic }
}

/// Where the app calculates: a preset.
///
/// The app reads no location services. A real app would get coordinates from Core Location and
/// a time zone from a geocoder; this one keeps the location an explicit input, as SalahCore
/// does.
nonisolated struct Place: Codable, Hashable, Identifiable, Sendable {
  /// The preset's identifier, also its `-place` launch argument.
  var id: String
  var location: PrayerLocation

  static let makkah = Place(
    id: "makkah", latitude: 21.4225, longitude: 39.8262, zone: "Asia/Riyadh", country: "SA",
    name: "Makkah")
  static let istanbul = Place(
    id: "istanbul", latitude: 41.0082, longitude: 28.9784, zone: "Europe/Istanbul", country: "TR",
    name: "Istanbul")
  static let london = Place(
    id: "london", latitude: 51.5074, longitude: -0.1278, zone: "Europe/London", country: "GB",
    name: "London")
  /// North of the Arctic Circle: around midsummer the Sun doesn't set, so some times can't be
  /// calculated and the days are partial.
  static let tromso = Place(
    id: "tromso", latitude: 69.6492, longitude: 18.9553, zone: "Europe/Oslo", country: "NO",
    name: "Tromsø")

  static let presets: [Place] = [makkah, istanbul, london, tromso]

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
