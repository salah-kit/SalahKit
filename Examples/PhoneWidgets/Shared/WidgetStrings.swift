import Foundation
import SalahCore
import SalahTimes

/// The chosen language: wording from the String Catalog, and SalahCore's names and digits in the
/// same locale, whatever the process's language is.
///
/// The extension runs in the device's language, so it can't rely on the system choosing the
/// catalog's language: it looks wording up in the chosen language's `.lproj` folder of its own
/// bundle and names up with `PrayerNames(locale:)`, the explicit-locale catalog lookup.
nonisolated struct WidgetStrings: Sendable {
  /// The chosen language.
  let language: NamesLanguage
  /// The locale with the language's own digits (`PrayerLocale.resolved`).
  let locale: Locale
  /// Prayer names in this locale.
  let names: PrayerNames
  /// The `<language>.lproj` folder of the bundle that runs this code: the app's or the
  /// extension's.
  private let tablePath: String?

  init(language: NamesLanguage, bundle: Bundle = .main) {
    self.language = language
    locale = PrayerLocale.resolved(language.rawValue)
    names = PrayerNames(locale: locale)
    tablePath = bundle.path(forResource: language.rawValue, ofType: "lproj")
  }

  /// Whether the language is written right to left.
  var isRightToLeft: Bool {
    locale.language.characterDirection == .rightToLeft
  }

  /// A string from the String Catalog, in the chosen language.
  func callAsFunction(_ value: String.LocalizationValue) -> String {
    let bundle = tablePath.flatMap(Bundle.init(path:)) ?? .main
    return String(localized: value, bundle: bundle, locale: locale)
  }

  /// The place's name.
  func placeName(_ place: Place) -> String {
    switch place.id {
    case Place.makkah.id: self("Makkah")
    case Place.london.id: self("London")
    case Place.tromso.id: self("Tromsø")
    case Place.invalid.id: self("Invalid coordinates")
    default: place.location.name ?? place.id
    }
  }

  /// The method's name.
  func methodName(_ method: CalculationMethod) -> String {
    switch method {
    case .muslimWorldLeague: self("Muslim World League")
    case .isna: self("ISNA (North America)")
    case .egyptian: self("Egyptian General Authority of Survey")
    case .ummAlQura: self("Umm al-Qura")
    case .karachi: self("University of Islamic Sciences, Karachi")
    default: method.rawValue
    }
  }

  /// The language's name in itself, as a language picker shows it.
  static func endonym(_ language: NamesLanguage) -> String {
    switch language {
    case .english: "English"
    case .arabic: "العربية"
    }
  }

  /// A short clock time in `timeZone`, the schedule's, with the locale's digits.
  func time(_ date: Date, in timeZone: TimeZone) -> String {
    date.formatted(
      Date.FormatStyle(
        date: .omitted, time: .shortened, locale: locale, calendar: locale.calendar,
        timeZone: timeZone))
  }

  /// A day and time in `timeZone`, for the expired view and the log: "Oct 15, 15:27".
  func dayAndTime(_ date: Date, in timeZone: TimeZone) -> String {
    date.formatted(
      Date.FormatStyle(
        date: .abbreviated, time: .shortened, locale: locale, calendar: locale.calendar,
        timeZone: timeZone))
  }

  /// Names joined as the locale joins a list: "Fajr, Sunrise, and Isha".
  func list(_ kinds: [PrayerKind]) -> String {
    kinds.map { names.name(of: $0) }.formatted(.list(type: .and).locale(locale))
  }
}
